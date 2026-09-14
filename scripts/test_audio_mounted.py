# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Test DOS CUE mounting, installer file copying, and unmodified Quake CD playback."""
import argparse
import io
import json
import os
from pathlib import Path
import subprocess
import struct
import wave
import zipfile
import zlib
import numpy as np
from dos_disk import Fat16
from test_audio_pm import ROOT, CACHE, make_disk, prepare_tests, sha256
from test_audio_onset import read_pcm
from test_audio_quake import pak_file


def verify_mix(path, source, sound, quiet=False):
    pcm = np.array(read_pcm(path), dtype=float)
    cd = np.frombuffer(source, dtype='<i2').reshape(-1, 2).astype(float)/4
    anchor, window = 5*44100, 4096
    delta = pcm[:, 0]-pcm[:, 1]
    target = (cd[:, 0]-cd[:, 1])[anchor:anchor+window]
    size = 1 << (len(pcm)+window-1).bit_length()
    correlation = np.fft.irfft(np.fft.rfft(delta, size)*np.fft.rfft(target[::-1], size), size)
    correlation = correlation[window-1:len(pcm)]
    energy = np.r_[0, np.cumsum(delta*delta)]
    errors = energy[window:]-energy[:-window]+sum(target*target)-2*correlation
    start = int(np.argmin(errors))-anchor
    if start < 1 or start+len(cd)+1 > len(pcm):
        raise ValueError('The complete CD track capture is missing.')
    residuals = np.array([pcm[start+d:start+d+len(cd)]-cd for d in (-1, 0, 1)])
    errors = (np.max(abs(residuals), axis=2) if quiet else
              abs(residuals[:, :, 0]-residuals[:, :, 1]))
    phase = int(np.argmin(np.max(errors[:, 512:4096], axis=1)))
    phases = np.full(len(cd), phase)
    changes, at = [], 512
    while at < len(cd):
        bad = np.flatnonzero(errors[phase, at:] > 4)
        if not len(bad):
            break
        at += int(bad[0])
        next_phase = int(np.argmin(errors[:, at]))
        if errors[next_phase, at] > 4 or changes or abs(next_phase-phase) != 1:
            raise ValueError(f'The CD samples differ at frame {at}.')
        changes.append(dict(source_frame=at, offset_frames=next_phase-1))
        phase = next_phase
        phases[at:] = phase
    residual = residuals[phases, np.arange(len(cd))]
    game = np.mean(residual, axis=1)
    with wave.open(io.BytesIO(sound)) as wav:
        if (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) != (1, 1, 11025):
            raise ValueError('The game sound format changed.')
        samples = np.frombuffer(wav.readframes(wav.getnframes()), dtype=np.uint8).astype(float)-128
    step = (11025 << 16)//44100
    reference = samples[np.arange(len(samples)*65536//step)*step >> 16].copy()
    reference -= np.mean(reference)
    size = 1 << (len(game)+len(reference)-1).bit_length()
    correlation = np.fft.irfft(np.fft.rfft(game, size)*np.fft.rfft(reference[::-1], size), size)
    correlation = correlation[len(reference)-1:len(game)]
    squares, sums = np.r_[0, np.cumsum(game*game)], np.r_[0, np.cumsum(game)]
    variance = (squares[len(reference):]-squares[:-len(reference)] -
                (sums[len(reference):]-sums[:-len(reference)])**2/len(reference))
    scores = correlation/np.sqrt(np.maximum(variance, 1)*sum(reference*reference))
    match = int(np.argmax(scores))
    gain = float(correlation[match]/sum(reference*reference))
    if quiet:
        if scores[match] > 0.5:
            raise ValueError('The muted capture contains the game sound.')
    elif scores[match] < 0.97 or not 35 < gain < 50:
        raise ValueError('The complete game sound does not match its source.')
    return dict(cd_frames=len(cd), cd_start_frame=start,
                cd_maximum_error=float(np.max(errors[phases[512:], np.arange(512, len(cd))])),
                game_correlation=float(scores[match]), game_gain=gain,
                game_match_frame=start+match, capture_phase_changes=changes,
                capture_phase_tolerance_frames=1)


def verify_controls(path, source, sound, check):
    pcm = np.array(read_pcm(path), dtype=np.int16)
    start = check['cd_start_frame']
    cd = np.frombuffer(source, dtype='<i2').reshape(-1, 2).astype(float)/4
    rejected = []
    for name in ('repeated-block', 'phase-jump', 'channel-swap', 'missing-game'):
        changed = pcm.copy()
        at = start+2*44100
        if name == 'repeated-block':
            changed[at:at+1024] = changed[at-1024:at]
        elif name == 'phase-jump':
            changed[at:-1024] = changed[at+1024:]
        elif name == 'channel-swap':
            changed = changed[:, ::-1].copy()
        else:
            changed[start:start+len(cd)] = cd.astype(np.int16)
        target = path.with_name(name+'.wav')
        with wave.open(str(target), 'wb') as wav:
            wav.setparams((2, 2, 44100, len(changed), 'NONE', 'not compressed'))
            wav.writeframes(changed.astype('<i2').tobytes())
        try:
            verify_mix(target, source, sound)
        except ValueError:
            rejected.append(name)
        else:
            raise ValueError(f'The waveform verifier accepted {name}.')
    return rejected


def quake_image(path):
    start = 12695*2352
    with path.open('rb') as source:
        raw = source.read(start)
        for lba in (12695, 35840, 46791):
            source.seek(lba*2352)
            excerpt = source.read(12*75*2352)
            if len(excerpt) != 12*75*2352:
                raise ValueError('The image is too short.')
            raw += excerpt
    image = raw
    cue = (b'FILE "QUAKE.BIN" BINARY\r\nTRACK 01 MODE1/2352\r\nINDEX 01 00:00:00\r\n'
        b'TRACK 02 AUDIO\r\nINDEX 01 02:49:20\r\nTRACK 03 AUDIO\r\nINDEX 01 03:01:20\r\n'
        b'TRACK 04 AUDIO\r\nINDEX 01 03:13:20\r\n')
    resource = b''.join(raw[i+16:i+2064] for i in range(21*2352, 12075*2352, 2352))[:24684755]
    return image, cue, resource, excerpt


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--izarra-source', type=Path, required=True)
    parser.add_argument('--quake-dir', type=Path, required=True)
    parser.add_argument('--quake-bin', type=Path, required=True)
    parser.add_argument('--copy-installer', action='store_true')
    parser.add_argument('--name', default='mounted')
    parser.add_argument('--steps', type=int, default=300000)
    parser.add_argument('--quiet', action='store_true')
    parser.add_argument('--load-high', action='store_true')
    parser.add_argument('--irq', type=int, choices=(5, 7), default=7)
    parser.add_argument('--dma8', type=int, choices=(1, 3))
    parser.add_argument('--dma16', type=int, choices=(5, 6, 7))
    parser.add_argument('--failure', choices=('starve', 'read'))
    parser.add_argument('--release', action='store_true')
    args = parser.parse_args()
    if args.release and args.failure:
        parser.error('--release cannot be used with --failure')
    executable = prepare_tests(args.izarra_source)
    run = ROOT / '.local/audio' / args.name
    run.mkdir(exist_ok=True)
    base = Fat16(make_disk(refill='4K', launcher=True, alternate=args.irq == 7))
    files = {name: base.read(name) for name in base.directory()}
    dma8 = args.dma8 if args.dma8 is not None else (3 if args.irq == 7 else 1)
    dma16 = args.dma16 if args.dma16 is not None else (6 if args.irq == 7 else 5)
    files['UCDD.CFG'] = b'uCDD\x01\x00'+struct.pack('<H', 0x220)+bytes((args.irq, dma8, dma16, 0))
    disk = base.empty_larger()
    parent_name = {'starve': 'ACDMSTAL.COM', 'read': 'ACDMERR.COM'}.get(args.failure, 'ACDMOUNT.COM')
    if args.release:
        parent_name = 'UCDDAUD.COM'
    files['APSHARE.COM'] = (ROOT/'build'/parent_name).read_bytes()
    for name in ('UCDDPM.COM', 'UCDD.EXE', 'FILECRC.COM'):
        files[name] = (ROOT/'build'/name).read_bytes()
    with zipfile.ZipFile(CACHE/'shcd3-7.zip') as archive:
        name = next(n for n in archive.namelist() if Path(n).name.lower() == 'shsucdx.com')
        files['SHSUCDX.COM'] = archive.read(name)
    raw, cue, resource, excerpt = quake_image(args.quake_bin)
    files['QUAKE.BIN'], files['QUAKE.CUE'] = raw, cue
    crc = zlib.crc32(resource)
    files['QUAKE.EXE'] = (args.quake_dir/'QUAKE.EXE').read_bytes()
    files['FDCONFIG.SYS'] = files['FDCONFIG.SYS'].replace(b'FILES=40', b'LASTDRIVE=Z\r\nFILES=40')
    if args.load_high:
        files['FDCONFIG.SYS'] = files['FDCONFIG.SYS'].replace(b'DOS=LOW', b'DOS=HIGH,UMB')
    copy_commands = ('COPY F:\\RESOURCE.1 C:\\RESCOPY.1\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
        f'FILECRC C:\\RESCOPY.1 {crc:08X}\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n') if args.copy_installer else ''
    files['AUTOEXEC.BAT'] = ('@ECHO OFF\r\nJLOAD QPIEMU.DLL\r\nHDPMI32I -r\r\n'
        'UCDD -install\r\nIF ERRORLEVEL 1 GOTO FAIL\r\nSHSUCDX /D:UCDD0001 /L:F\r\n'
        'IF ERRORLEVEL 246 GOTO FAIL\r\nUCDD -mount C:\\QUAKE.CUE\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
        + copy_commands + 'SET BLASTER=A220 I5 D1 H5 T6\r\nAPSHARE\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
        'UCDD -unmount\r\nIF ERRORLEVEL 1 GOTO FAIL\r\nPASS\r\n:FAIL\r\nFAIL\r\n').encode()
    if args.load_high:
        files['AUTOEXEC.BAT'] = files['AUTOEXEC.BAT'].replace(b'\r\nUCDD -install\r\n', b'\r\nLH UCDD -install\r\n').replace(
            b'\r\nAPSHARE\r\n', b'\r\nLH APSHARE\r\n')
    for name, data in files.items():
        disk.add(name, data)
    config = (b'ambient_level 0\nbgmvolume 1\nmap start\necho UCDD_CD_READY\n' +
              b'wait\n'*100 + b'cd info\nvolume 0.7\nstopsound\nplay misc/menu1\n' + b'wait\n'*300 +
              b'echo UCDD_CD_DONE\ntoggleconsole\nquit\n')
    if args.quiet:
        config = config.replace(b'volume 0.7', b'volume 0')
    game_files = {name: (args.quake_dir/'ID1'/name).read_bytes()
                  for name in ('PAK0.PAK', 'PAK1.PAK') if (args.quake_dir/'ID1'/name).exists()}
    game_files['AUTOEXEC.CFG'] = config
    disk.add_directory('ID1', game_files)
    image, wav = run/'quake.img', run/'quake.wav'
    image.write_bytes(disk.image)
    (run/'results.json').write_text('{"passed": false}\n')
    result = subprocess.run([str(executable), str(image), str(wav)], capture_output=True, text=True,
                            timeout=240, env=dict(os.environ, UCDD_TEST_CPU='586',
                            UCDD_TEST_STEPS=str(args.steps), UCDD_TEST_DISK_EXPORT='1'))
    (run/'quake.log').write_text(result.stdout+result.stderr)
    print(result.stdout+result.stderr)
    exported = Fat16(wav.with_suffix('.disk.img').read_bytes())
    console = exported.read('ID1/QCONSOLE.LOG')
    (run/'QCONSOLE.LOG').write_bytes(console)
    print(repr(console[-4000:]))
    if 'CDSTAT.DAT' in exported.directory():
        data = exported.read('CDSTAT.DAT')
        (run/'CDSTAT.DAT').write_bytes(data)
        print('CDSTAT.DAT', repr(data))
    if args.copy_installer and exported.read('RESCOPY.1') != resource:
        raise ValueError('The installer file copy differs from the image.')
    error = fault = child = 0
    parent = output = reads = consumed = None
    if not args.release:
        error, produced, consumed, reads, fault, child = struct.unpack('<BIIIBB', exported.read('CDSTAT.DAT')[:15])
        parent, output, allocation = struct.unpack_from('<HHH', exported.read('CDSTAT.DAT'), 15)
        if output*16+4096 > 0xa0000 or allocation*16+8192 > 0xa0000:
            raise ValueError('The physical DMA buffer is outside conventional memory.')
        if args.load_high and parent < 0xa000:
            raise ValueError('The audio parent did not load into upper memory.')
    if args.failure:
        expected_error, expected_reads = (2, 128) if args.failure == 'starve' else (1, 160)
        if (result.returncode == 0 or error != expected_error or reads != expected_reads or fault or child or
                b'UCDD_CD_DONE' not in console):
            raise ValueError('The CD failure control did not stop the source and let Quake finish.')
        (run/'results.json').write_text(json.dumps(dict(passed=True, expected_failure=args.failure,
            stream_error=error, disk_reads=reads, game_completed=True), indent=2)+'\n')
        return
    if result.returncode:
        raise SystemExit('The mounted audio test failed.')
    if error or fault or child or (not args.release and (reads <= 12*176400//4096 or consumed <= 0)):
        raise ValueError('The CD stream did not refill and loop without errors.')
    if b'Currently looping track 4' not in console or b'UCDD_CD_DONE' not in console:
        raise ValueError('Quake did not select and loop the map track.')
    sound = pak_file(game_files['PAK0.PAK'], 'sound/misc/menu1.wav')
    audio = verify_mix(wav, excerpt, sound, args.quiet)
    controls = [] if args.quiet else verify_controls(wav, excerpt, sound, audio)
    (run/'results.json').write_text(json.dumps(dict(passed=True, game_sha256=sha256(args.quake_dir/'QUAKE.EXE'),
        resource_crc32=f'{crc:08X}', resource_bytes=len(resource), installer_copied=args.copy_installer,
        cpu='586', backend='interpreter', physical_irq=args.irq, physical_dma8=dma8,
        physical_dma16=dma16, quiet=args.quiet,
        high_requested=args.load_high, parent_segment=parent, output_segment=output,
        xms_bytes=524288, disk_reads=reads, audio=audio,
        waveform_controls_rejected=controls,
        executable_sha256=sha256(executable), program_sha256={n: sha256(ROOT/'build'/n)
            for n in ('UCDD.EXE', parent_name, 'UCDDAUD.COM', 'UCDDPM.COM')},
        disk_sha256=sha256(image), capture_sha256=sha256(wav)), indent=2)+'\n')
    print(json.dumps(audio, indent=2))

if __name__ == '__main__':
    main()
