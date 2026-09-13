"""Run an unmodified, user-supplied DOS Quake installation through the audio launcher."""

import argparse
import io
import json
import os
from pathlib import Path
import struct
import subprocess
import wave

import numpy as np

from dos_disk import Fat16
from test_audio_onset import read_pcm
from test_audio_pm import ROOT, RUN, make_disk, prepare_tests, sha256


def pak_file(pak, name):
    if pak[:4] != b'PACK':
        raise ValueError('The PAK file is not valid.')
    offset, size = struct.unpack_from('<II', pak, 4)
    if size % 64 or offset + size > len(pak):
        raise ValueError('The PAK directory is not valid.')
    for entry in range(offset, offset + size, 64):
        if pak[entry:entry+56].split(b'\0')[0] == name.encode('ascii'):
            start, length = struct.unpack_from('<II', pak, entry+56)
            if start + length > len(pak):
                raise ValueError('The PAK member is not valid.')
            return pak[start:start+length]
    raise ValueError(f'The PAK member is missing: {name}')


def quake_disk(game, pak, alternate=False, quiet=False):
    source = Fat16(make_disk(refill='4K', launcher=True, alternate=alternate))
    files = {name: source.read(name) for name in source.directory()}
    files['APM.COM'] = (ROOT / 'build/AQUAKE.COM').read_bytes()
    files['APSHARE.COM'] = (ROOT / 'build/AQSHARE.COM').read_bytes()
    files['QUAKE.EXE'] = game
    files['AUTOEXEC.BAT'] = files['AUTOEXEC.BAT'].replace(
        b'APSHARE\r\n', b'SET BLASTER=A220 I5 D1 T6\r\nAPSHARE\r\n', 1)
    config = (b'ambient_level 0\nmap start\necho UCDD_QUAKE_READY\n' + b'wait\n'*10 +
              (b'volume 0\n' if quiet else b'volume 0.7\n') +
              b'stopsound\nplay misc/menu1\n' + b'wait\n'*100 +
              b'echo UCDD_QUAKE_DONE\ntoggleconsole\nquit\n')
    disk = Fat16(source.image)
    disk.clear()
    for name, content in files.items():
        disk.add(name, content)
    disk.add_directory('ID1', {'PAK0.PAK': pak, 'AUTOEXEC.CFG': config})
    if disk.read('ID1/PAK0.PAK') != pak or disk.read('QUAKE.EXE') != game:
        raise ValueError('The game file copy failed.')
    return bytes(disk.image)


def separate_cd(path):
    pcm = np.array(read_pcm(path), dtype=float)
    active = np.flatnonzero(np.max(np.abs(pcm), axis=1) > 100)
    if not len(active):
        raise ValueError('The CD signal is missing.')
    active = int(active[0])
    cd = np.array(list(struct.iter_unpack('<hh', (ROOT / 'build/CDTEST.PCM').read_bytes())), dtype=float)/4
    difference = cd[:, 0] - cd[:, 1]
    window = 256
    spectrum = np.fft.rfft(difference)
    energy = np.fft.irfft(np.fft.rfft(difference**2)*np.conj(
        np.fft.rfft(np.r_[np.ones(window), np.zeros(4096-window)])))
    game, errors, phases, changes = [], [], [], []
    last_phase = None
    for index in range(0, len(pcm)-active-window, window):
        block = pcm[active+index:active+index+window]
        # Subtraction cancels mono game audio and locates the independent CD channels.
        delta = block[:, 0] - block[:, 1]
        correlation = np.fft.irfft(spectrum*np.conj(np.fft.rfft(delta, 4096)))
        offset = int(np.argmin(energy-2*correlation))
        residual = block - cd[(np.arange(window)+offset) % 4096]
        error = float(np.sqrt(np.mean((residual[:, 0]-residual[:, 1])**2)))
        phase = (offset-index) % 4096
        errors.append(error)
        phases.append(phase)
        game.extend(np.mean(residual, axis=1) if error < 4 else np.zeros(window))
        if error < 4 and index >= window:
            if last_phase is not None and phase != last_phase:
                changes.append(dict(seconds=(active+index)/44100,
                                    phase_change_frames=(phase-last_phase) % 4096))
            last_phase = phase
    game = np.array(game)
    return active, game, errors, phases, changes


def verify_cd_continuity(errors, changes):
    valid = [i for i, error in enumerate(errors) if i and error < 4]
    if len(valid) < 2 or changes or max(errors[valid[0]:valid[-1]+1]) >= 4:
        raise ValueError('The CD signal is not continuous.')


def verify_waveform(path, sound, quiet):
    active, game, errors, phases, changes = separate_cd(path)
    verify_cd_continuity(errors, changes)
    window = 256
    with wave.open(io.BytesIO(sound)) as source:
        if (source.getnchannels(), source.getsampwidth(), source.getframerate()) != (1, 1, 11025):
            raise ValueError('The reference sound format is not supported.')
        samples = np.frombuffer(source.readframes(source.getnframes()), dtype=np.uint8).astype(float)-128
    rate = 1000000//(256-((65536-256000000//11025) >> 8))
    step = (rate << 16)//44100
    reference = samples[np.arange(len(samples)*65536//step)*step >> 16].copy()
    reference -= np.mean(reference)
    if len(game) < len(reference):
        raise ValueError('The game audio capture is too short.')
    length = 1 << (len(game)+len(reference)-1).bit_length()
    correlation = np.fft.irfft(np.fft.rfft(game, length)*np.fft.rfft(reference[::-1], length), length)
    correlation = correlation[len(reference)-1:len(game)]
    squares, sums = np.r_[0, np.cumsum(game*game)], np.r_[0, np.cumsum(game)]
    variance = (squares[len(reference):]-squares[:-len(reference)] -
                (sums[len(reference):]-sums[:-len(reference)])**2/len(reference))
    scores = correlation/np.sqrt(np.maximum(variance, 1)*np.sum(reference*reference))
    match = int(np.argmax(scores))
    score = float(scores[match])
    gain = float(correlation[match]/np.sum(reference*reference))
    if quiet:
        if score > 0.5:
            raise ValueError('The muted capture contains the reference sound.')
    else:
        if score < 0.97 or not 35 < gain < 50:
            raise ValueError(f'The complete game sound does not match: correlation {score:.4f}.')
        first, last = match//window, (match+len(reference)+window-1)//window
        if max(errors[first:last]) > 2 or len(set(phases[first:last])) != 1:
            raise ValueError('The CD signal changed during the reference sound.')
    return dict(reference_correlation=score, reference_gain=gain, source_rate=rate,
                reference_seconds=len(reference)/44100, match_seconds=(active+match)/44100,
                cd_phase_changes=changes)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--izarra-source', type=Path, required=True)
    parser.add_argument('--quake-dir', type=Path, required=True)
    parser.add_argument('--cpu', choices=('486', '586'), default='586')
    args = parser.parse_args()
    game_path, pak_path = args.quake_dir / 'QUAKE.EXE', args.quake_dir / 'ID1/PAK0.PAK'
    game, pak = game_path.read_bytes(), pak_path.read_bytes()
    sound = pak_file(pak, 'sound/misc/menu1.wav')
    executable = prepare_tests(args.izarra_source)
    directory = RUN / 'quake'
    directory.mkdir(parents=True, exist_ok=True)
    evidence = dict(passed=False, runs=[], cpu=args.cpu, backend='interpreter', memory_mib=16,
                    game_sha256=sha256(game_path), pak_sha256=sha256(pak_path),
                    capture_executable_sha256=sha256(executable),
                    capture_source_sha256=sha256(ROOT / 'tests/audio_capture.rs'),
                    capture_lock_sha256=sha256(RUN / 'capture/Cargo.lock'),
                    izarra_revision=subprocess.check_output(
                        ['git', '-C', str(args.izarra_source), 'rev-parse', 'HEAD'], text=True).strip(),
                    program_sha256={name: sha256(ROOT / 'build' / name)
                                    for name in ('AQUAKE.COM', 'AQSHARE.COM')})
    report = directory / 'results.json'
    report.write_text(json.dumps(evidence, indent=2) + '\n')
    env = dict(os.environ, UCDD_TEST_CPU=args.cpu, UCDD_TEST_STEPS='300000', UCDD_TEST_DISK_EXPORT='1')
    for name, alternate, quiet in (('default', False, False), ('muted', False, True),
                                   ('alternate', True, False)):
        image, wav = directory / (name+'.img'), directory / (name+'.wav')
        image.write_bytes(quake_disk(game, pak, alternate, quiet))
        command = [str(executable), str(image), str(wav)]
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=180)
        log = result.stdout + result.stderr
        (directory / (name+'.log')).write_text(log, encoding='utf-8')
        row = dict(name=name, passed=False, command=command, disk_sha256=sha256(image),
                   capture_sha256=sha256(wav))
        evidence['runs'].append(row)
        report.write_text(json.dumps(evidence, indent=2) + '\n')
        if result.returncode or 'stop: TestExit { code: 0 }' not in log:
            raise SystemExit(f'The Quake guest failed. See {name}.log.')
        disk = Fat16(wav.with_suffix('.disk.img').read_bytes())
        console = disk.read('ID1/QCONSOLE.LOG').decode('cp437')
        (directory / (name+'.console.txt')).write_text(console, encoding='utf-8')
        if not all(text in console for text in ('Version 2 SB startup', 'Introduction',
                                                'UCDD_QUAKE_READY', 'UCDD_QUAKE_DONE')):
            raise SystemExit('The Quake test did not complete its sound sequence.')
        row['waveform'] = verify_waveform(wav, sound, quiet)
        row['passed'] = True
        report.write_text(json.dumps(evidence, indent=2) + '\n')
        print(f'The Quake audio test passed: {name}')
    evidence['passed'] = True
    report.write_text(json.dumps(evidence, indent=2) + '\n')


if __name__ == '__main__':
    main()
