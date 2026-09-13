# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Check bounded BIN streaming, track boundaries, and shared stereo output."""

import argparse
import json
import os
from pathlib import Path
import struct
import subprocess
import wave

import numpy as np

from dos_disk import Fat16
from prepare_cd_stream import cue_track, descriptor
from test_audio_onset import read_pcm
from test_audio_pm import ROOT, RUN, make_disk, prepare_tests, sha256
from test_audio_stereo import verify_stereo


def image_disk(pcm, offset=2352, alternate=False, quiet=False, standalone=False, failure=None):
    disk = Fat16(make_disk(refill='4K', alternate=alternate))
    files = {name: disk.read(name) for name in disk.directory()}
    files['APSHARE.COM'] = (ROOT / 'build' / ('ACDPLAY.COM' if standalone else 'ACDSHARE.COM')).read_bytes()
    if failure == 'read':
        files['APSHARE.COM'] = (ROOT / 'build/ACDERROR.COM').read_bytes()
    client = ('ACDSTQ.COM' if quiet else 'ACDSTALL.COM') if failure == 'starve' else (
        'ACDQUIET.COM' if quiet else 'ACDPM.COM')
    files['APM.COM'] = (ROOT / 'build' / client).read_bytes()
    files['CDSTREAM.DAT'] = descriptor('AUDIO.BIN', offset, len(pcm))
    files['AUDIO.BIN'] = bytes([0x7f])*offset + pcm + bytes([0x7f])*8192
    if failure == 'short':
        files['AUDIO.BIN'] = files['AUDIO.BIN'][:offset+len(pcm)-4]
    if failure == 'missing':
        del files['AUDIO.BIN']
    if failure == 'descriptor':
        files['CDSTREAM.DAT'] = files['CDSTREAM.DAT'][:-1]
    disk.clear()
    for name, content in files.items():
        disk.add(name, content)
    return bytes(disk.image)


def verify_cd(path, source):
    pcm = np.array(read_pcm(path), dtype=float)
    reference = np.frombuffer(source, dtype='<i2').reshape(-1, 2).astype(float)/4
    anchor = min(44100, len(reference)//4)
    window = min(4096, len(reference)-anchor)
    target = reference[anchor:anchor+window]
    size = 1 << (len(pcm)+window-1).bit_length()
    correlation = sum(np.fft.irfft(np.fft.rfft(pcm[:, ch], size)*
                      np.fft.rfft(target[::-1, ch], size), size)[window-1:len(pcm)] for ch in (0, 1))
    energy = np.r_[0, np.cumsum(np.sum(pcm*pcm, axis=1))]
    error = energy[window:]-energy[:-window]+np.sum(target*target)-2*correlation
    start = int(np.argmin(error))-anchor
    if start < 0 or start+len(reference)+512 > len(pcm):
        raise ValueError('The complete CD capture is not available.')
    errors = np.array([np.max(np.abs(pcm[start+delta:start+delta+len(reference)]-reference), axis=1)
                       for delta in (-1, 0, 1)])
    changes, maximum, i = [], 0.0, 256
    phase = int(np.argmin(np.max(errors[:, i:i+256], axis=1)))
    initial_phase = phase-1
    while i < len(reference):
        bad = np.flatnonzero(errors[phase, i:] > 4)
        end = i+int(bad[0]) if len(bad) else len(reference)
        if end > i:
            maximum = max(maximum, float(np.max(errors[phase, i:end])))
        if end == len(reference):
            break
        next_phase = int(np.argmin(errors[:, end]))
        if errors[next_phase, end] > 4 or changes or abs(next_phase-phase) != 1:
            raise ValueError(f'The CD samples changed at source frame {end}.')
        changes.append(dict(source_frame=end, capture_offset_frames=next_phase-1))
        phase, i = next_phase, end
    tail = pcm[start+len(reference)+phase-1+4:start+len(reference)+phase-1+512]
    if np.max(np.abs(tail)) > 4:
        raise ValueError('Audio continues after the selected byte range.')
    return dict(frames=len(reference), start_frame=start, maximum_sample_error=maximum,
                capture_phase_tolerance_frames=1, initial_capture_offset_frames=initial_phase,
                phase_changes=changes, end_silence_frames=len(tail))


def run(executable, directory, name, pcm, **options):
    image, wav = directory / (name+'.img'), directory / (name+'.wav')
    image.write_bytes(image_disk(pcm, **options))
    command = [str(executable), str(image), str(wav)]
    result = subprocess.run(command, env=dict(os.environ, UCDD_TEST_CPU='386', UCDD_TEST_DISK_EXPORT='1'),
                            capture_output=True, text=True, timeout=180)
    log = result.stdout+result.stderr
    (directory / (name+'.log')).write_text(log, encoding='utf-8')
    stats = Fat16(wav.with_suffix('.disk.img').read_bytes()).read('CDSTAT.DAT')
    error, produced, consumed, reads, fault, child = struct.unpack('<BIIIBB', stats)
    failure = options.get('failure')
    if failure:
        message = 'The CD audio buffer is empty.' if failure == 'starve' else 'The CD image read failed.'
        expected = 2 if failure == 'starve' else 1
        if result.returncode == 0 or 'stop: TestExit { code: 1 }' not in log or message not in log or error != expected:
            raise ValueError(f'The negative control failed: {name}.')
        if failure == 'starve' and (reads != 4 or consumed != 16384 or fault or child):
            raise ValueError('The stalled stream did not stop at the queue boundary.')
        if failure == 'read' and (reads != 8 or not consumed or fault or child):
            raise ValueError('The disk read error was not tested during playback.')
    elif (result.returncode or 'stop: TestExit { code: 0 }' not in log or error or fault or child or
          reads != (len(pcm)+4095)//4096 or not len(pcm) <= consumed < len(pcm)+2048):
        raise ValueError(f'The streaming guest failed: {name}. See its log and CDSTAT.DAT.')
    return dict(name=name, passed=True, command=command, disk_sha256=sha256(image),
                capture_sha256=sha256(wav), expected_failure=failure,
                stream_error=error, produced_bytes=produced, consumed_bytes=consumed, disk_reads=reads)


def verifier_controls(directory, source, checks):
    pcm = np.array(read_pcm(directory / 'default-quiet.wav'), dtype=np.int16)
    start = checks['start_frame']
    rejected = []
    for name in ('repeated-block', 'channel-swap', 'end-leak'):
        changed = pcm.copy()
        if name == 'repeated-block':
            at = start+60000
            changed[at:at+1024] = changed[at-1024:at]
        elif name == 'channel-swap':
            changed[:, :] = changed[:, ::-1]
        else:
            at = start+len(source)//4+32
            changed[at:at+64] = 1000
        path = directory / (name+'.wav')
        with wave.open(str(path), 'wb') as output:
            output.setparams((2, 2, 44100, len(changed), 'NONE', 'not compressed'))
            output.writeframes(changed.astype('<i2').tobytes())
        try:
            verify_cd(path, source)
        except ValueError:
            rejected.append(name)
        else:
            raise ValueError(f'The waveform verifier accepted corrupt audio: {name}.')
    return rejected


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--izarra-source', type=Path, required=True)
    parser.add_argument('--cue', type=Path, help='Optional user-supplied Quake CUE/BIN image.')
    args = parser.parse_args()
    executable = prepare_tests(args.izarra_source)
    directory = RUN / 'image'
    directory.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(1977)
    pcm = rng.integers(-12000, 12000, size=(44100*5+137, 2), dtype=np.int16).astype('<i2').tobytes()
    evidence = dict(passed=False, cpu='386', backend='interpreter', queue_bytes=16384, read_bytes=4096,
                    runs=[], capture_executable_sha256=sha256(executable),
                    capture_source_sha256=sha256(ROOT / 'tests/audio_capture.rs'),
                    capture_lock_sha256=sha256(RUN / 'capture/Cargo.lock'),
                    izarra_revision=subprocess.check_output(
                        ['git', '-C', str(args.izarra_source), 'rev-parse', 'HEAD'], text=True).strip(),
                    program_sha256={name: sha256(ROOT / 'build' / name) for name in
                                    ('ACDSHARE.COM', 'ACDPLAY.COM', 'ACDPM.COM', 'ACDQUIET.COM',
                                     'ACDSTALL.COM', 'ACDSTQ.COM', 'ACDERROR.COM')})
    report = directory / 'results.json'

    def record(name, source, **options):
        row = run(executable, directory, name, source, **options)
        evidence['runs'].append(row)
        report.write_text(json.dumps(evidence, indent=2)+'\n')
        print(f'The image stream test passed: {name}', flush=True)
        return row

    report.write_text(json.dumps(evidence, indent=2)+'\n')
    for alternate in (False, True):
        name = 'alternate' if alternate else 'default'
        record(name, pcm, alternate=alternate)
        quiet = record(name+'-quiet', pcm, alternate=alternate, quiet=True)
        quiet['cd'] = verify_cd(directory / (name+'-quiet.wav'), pcm)
        quiet['game'] = verify_stereo(directory / (name+'.wav'), directory / (name+'-quiet.wav'))
        if not alternate:
            evidence['waveform_controls_rejected'] = verifier_controls(directory, pcm, quiet['cd'])
    standalone = record('standalone', pcm, standalone=True)
    standalone['cd'] = verify_cd(directory / 'standalone.wav', pcm)
    for failure in ('starve', 'read', 'short', 'missing', 'descriptor'):
        record(failure, pcm, failure=failure)
    stalled = record('starve-quiet', pcm, quiet=True, failure='starve')
    stalled['cd'] = verify_cd(directory / 'starve-quiet.wav', pcm[:16384])
    stalled['game'] = verify_stereo(directory / 'starve.wav', directory / 'starve-quiet.wav')
    if args.cue:
        path, offset, length = cue_track(args.cue, 2)
        length = min(length, 44100*5*4+137*4)
        with path.open('rb') as stream:
            stream.seek(offset)
            excerpt = stream.read(length)
        evidence['cue_sha256'] = sha256(args.cue)
        evidence['bin_sha256'] = sha256(path)
        evidence['excerpt_offset'] = offset
        evidence['excerpt_bytes'] = length
        record('cue', excerpt, offset=offset)
        quiet = record('cue-quiet', excerpt, offset=offset, quiet=True)
        quiet['cd'] = verify_cd(directory / 'cue-quiet.wav', excerpt)
        quiet['game'] = verify_stereo(directory / 'cue.wav', directory / 'cue-quiet.wav')
    evidence['passed'] = True
    report.write_text(json.dumps(evidence, indent=2)+'\n')


if __name__ == '__main__':
    main()
