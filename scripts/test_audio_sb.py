# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Check chained legacy SB PCM and CD audio through each physical output."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import wave
import zipfile

import numpy as np

from build import ROOT, assemble, assemble_resident_host
from test_audio_resident import prepare_resident_tests
from test_audio_pm import sha256
from test_dos import make_iso, SHSUCD_SHA256


def check_audio(path):
    with wave.open(str(path)) as source:
        pcm = np.frombuffer(source.readframes(source.getnframes()), '<i2').reshape(-1, 2).astype(float)
    first = np.flatnonzero(np.max(abs(pcm), axis=1) > 200)
    if not len(first):
        raise ValueError('The capture is silent.')
    start = int(first[0])
    if start+int(2.6*44100) > len(pcm):
        raise ValueError('The capture is too short.')
    # The CD channels use different tones; mono output must retain both.
    mixed = pcm[start+int(1.3*44100):start+int(2.6*44100)].mean(axis=1)
    size = len(mixed)
    spectrum = abs(np.fft.rfft(mixed*np.hanning(size))) * 4/size
    peaks = {}
    for hz in (733, 1237, 1000):
        at = round(hz*size/44100)
        peaks[hz] = float(max(spectrum[at-8:at+9]))
        if peaks[hz] < 250:
            raise ValueError(f'The {hz} Hz source is missing.')
    # A 1 kHz square wave must remain present across every DMA block boundary.
    amplitudes = []
    for offset in range(0, len(mixed)-441, 110):
        block = mixed[offset:offset+441]
        phase = np.arange(441)*2*np.pi*1000/44100
        amplitude = abs(np.sum(block*np.exp(-1j*phase)))*2/441
        amplitudes.append(float(amplitude))
    if min(amplitudes) < 0.55*float(np.median(amplitudes)):
        raise ValueError('A chained PCM block has a silent gap.')
    return dict(source_peaks=peaks, minimum_game_amplitude=min(amplitudes),
                median_game_amplitude=float(np.median(amplitudes)))


def check_controls(path):
    with wave.open(str(path)) as source:
        pcm = np.frombuffer(source.readframes(source.getnframes()), '<i2').reshape(-1, 2).copy()
    start = int(np.flatnonzero(np.max(abs(pcm.astype(float)), axis=1) > 200)[0])
    t = np.arange(len(pcm))/44100
    rejected = []
    for name in ('block-gap', 'missing-game', 'missing-cd'):
        changed = pcm.copy()
        if name == 'block-gap':
            changed[start+2*44100:start+2*44100+882] = 0
        else:
            tone = (np.sin(2*np.pi*733*t)+np.sin(2*np.pi*1237*t) if name == 'missing-game'
                    else np.sign(np.sin(2*np.pi*1000*t)))
            changed[:] = (tone*2000).astype('<i2')[:, None]
        target = path.with_name(name+'.wav')
        with wave.open(str(target), 'wb') as output:
            output.setparams((2, 2, 44100, len(changed), 'NONE', 'not compressed'))
            output.writeframes(changed.astype('<i2').tobytes())
        try:
            check_audio(target)
        except ValueError:
            rejected.append(name)
        else:
            raise ValueError(f'The waveform check accepted {name}.')
    return rejected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--izarra-source', type=Path, required=True)
    parser.add_argument('--output', choices=('sb16', 'sbpro', 'wss', 'sb'), action='append')
    parser.add_argument('--cpu', choices=('386', '486', '586'), default='386')
    parser.add_argument('--irq', type=int, choices=(5, 7), default=7)
    parser.add_argument('--dma8', type=int, choices=(1, 3), default=1)
    parser.add_argument('--dma16', type=int, choices=(5, 6, 7), default=5)
    parser.add_argument('--mscdex', type=Path,
                        help='Use a private MSCDEX executable instead of SHSUCDX.')
    parser.add_argument('--himem', type=Path,
                        help='Use this HIMEM.SYS with --emm386.')
    parser.add_argument('--emm386', type=Path,
                        help='Use this EMM386.EXE with --himem.')
    parser.add_argument('--max386', type=Path,
                        help='Use this 386MAX.SYS instead of JEMMEX.')
    parser.add_argument('--max386-profile', type=Path,
                        help='Use this profile with --max386.')
    args = parser.parse_args()
    if bool(args.himem) != bool(args.emm386):
        parser.error('--himem and --emm386 must be used together.')
    if args.max386 and (args.himem or args.emm386):
        parser.error('--max386 cannot be combined with --himem or --emm386.')
    if bool(args.max386_profile) != bool(args.max386):
        parser.error('--max386 and --max386-profile must be used together.')
    external_manager = bool(args.emm386 or args.max386)
    capture, disk, files = prepare_resident_tests(args.izarra_source)
    assemble_resident_host()
    options = ('SHARED_IRQ5=1',) if args.irq == 5 else ()
    assemble('tests/audio_sb_irq.asm', 'SBIRQ.COM', options)
    assemble('tests/audio_sb_irq.asm', 'SBRM.COM', (*options, 'REAL_CLIENT=1'))
    assemble('tests/audio_card_resources.asm', 'CARDSET.COM')
    assemble('tests/setup_lifecycle.asm', 'SBLIFE.COM', ('CHILD_NAME="SBIRQ.COM"',))
    assemble('tests/setup_lifecycle.asm', 'RMLIFE.COM', ('CHILD_NAME="SBRM.COM"',))
    assemble('tests/audio_resident_state.asm', 'RESSTATE.COM', ('OWN_HOST=1',))
    for name in ('UCDD.EXE', 'SBIRQ.COM', 'SBRM.COM', 'RESSTATE.COM', 'CARDSET.COM', 'SBLIFE.COM', 'RMLIFE.COM'):
        files[name] = (ROOT/'build'/name).read_bytes()
    archive = ROOT/'.local/downloads/shcd3-7.zip'
    if sha256(archive) != SHSUCD_SHA256:
        raise ValueError('The CD extension archive hash is incorrect.')
    with zipfile.ZipFile(archive) as source:
        files['SHSUCDX.COM'] = source.read('shsucdx.com')
    if args.mscdex:
        files['MSCDEX.EXE'] = args.mscdex.read_bytes()
    if args.emm386:
        files['HIMEM.SYS'] = args.himem.read_bytes()
        files['EMM386.EXE'] = args.emm386.read_bytes()
        files['FDCONFIG.SYS'] = files['FDCONFIG.SYS'].replace(
            b'DEVICE=C:\\JEMMEX.EXE NOEMS',
            b'DEVICE=C:\\HIMEM.SYS /TESTMEM:OFF\r\nDEVICE=C:\\EMM386.EXE NOEMS')
    elif args.max386:
        files['386MAX.SYS'] = args.max386.read_bytes()
        files['386MAX.PRO'] = args.max386_profile.read_bytes()
        files['FDCONFIG.SYS'] = files['FDCONFIG.SYS'].replace(
            b'DEVICE=C:\\JEMMEX.EXE NOEMS',
            b'DEVICE=C:\\386MAX.SYS PRO=C:\\386MAX.PRO EMS=0')
    data = make_iso('SBTEST')
    raw = b''.join(bytes(16)+data[i:i+2048]+bytes(288) for i in range(0, len(data), 2048))
    t = np.arange(8*44100)/44100
    pcm = np.stack((np.sin(t*2*np.pi*733), np.sin(t*2*np.pi*1237)), axis=1)*10000
    files['SBTEST.BIN'] = raw+pcm.astype('<i2').tobytes()
    files['SBTEST.CUE'] = (b'FILE "SBTEST.BIN" BINARY\r\nTRACK 01 MODE1/2352\r\nINDEX 01 00:00:00\r\n'
                           b'TRACK 02 AUDIO\r\nINDEX 01 00:00:22\r\n')
    if not external_manager:
        files['FDCONFIG.SYS'] = files['FDCONFIG.SYS'].replace(b'DOS=LOW', b'DOS=HIGH,UMB')
    files['FDCONFIG.SYS'] = files['FDCONFIG.SYS'].replace(
        b'FILES=40', b'LASTDRIVE=Z\r\nFILES=40')
    for output in args.output or ('sb16', 'sbpro', 'wss', 'sb'):
        if output == 'wss' and args.irq == 5:
            continue
        card = ('sb16', 'sbpro', 'wss', 'sb').index(output)
        files['UCDD.CFG'] = b'uCDD\x01'+bytes([card])+struct.pack('<H', 0x530 if card == 2 else 0x220)+bytes((args.irq, args.dma8, args.dma16, 0))
        for client in ('SBIRQ', 'SBRM'):
            redirector = ('MSCDEX /D:UCDD0001 /L:F' if args.mscdex else
                          'SHSUCDX /D:UCDD0001 /L:F')
            commands = ['@ECHO OFF', ('UCDD -install' if external_manager else 'LH UCDD -install'),
                        'IF ERRORLEVEL 1 GOTO FAIL',
                        redirector,
                        ('IF ERRORLEVEL 1 GOTO FAIL' if args.mscdex else
                         'IF ERRORLEVEL 246 GOTO FAIL'),
                        'UCDD -mount C:\\SBTEST.CUE', 'IF ERRORLEVEL 1 GOTO FAIL',
                        'SBLIFE' if client == 'SBIRQ' else 'RMLIFE',
                        'IF ERRORLEVEL 1 GOTO FAIL',
                        ('RESSTATE' if external_manager else 'RESSTATE H'),
                        'IF ERRORLEVEL 1 GOTO FAIL',
                        'PASS', ':FAIL', 'FAIL']
            if args.irq == 5:
                commands.insert(1, 'CARDSET')
            files['AUTOEXEC.BAT'] = ('\r\n'.join(commands)+'\r\n').encode()
            disk.clear()
            for name, data in files.items():
                disk.add(name, data)
            run = ROOT/'.local/audio'/f'legacy-{output}-{client.lower()}-{args.cpu}'
            if args.mscdex:
                run = run.with_name(run.name+'-mscdex')
            if args.emm386:
                run = run.with_name(run.name+'-emm386')
            elif args.max386:
                run = run.with_name(run.name+'-386max')
            if args.irq == 5:
                run = run.with_name(run.name+'-irq5')
            if (args.dma8, args.dma16) != (1, 5):
                run = run.with_name(run.name+f'-dma{args.dma8}-{args.dma16}')
            run.mkdir(parents=True, exist_ok=True)
            image, wav = run/'test.img', run/'test.wav'
            image.write_bytes(disk.image)
            evidence = dict(passed=False, cpu=args.cpu, backend='interpreter', output=output,
                            client=client, irq=args.irq, dma8=args.dma8, dma16=args.dma16,
                            driver_sha256=hashlib.sha256(files['UCDD.EXE']).hexdigest())
            (run/'results.json').write_text(json.dumps(evidence, indent=2)+'\n')
            result = subprocess.run([str(capture), str(image), str(wav)], capture_output=True,
                                    text=True, encoding='cp437', errors='replace', timeout=90,
                                    env=dict(os.environ, UCDD_TEST_CPU=args.cpu,
                                    UCDD_TEST_STEPS='90000', UCDD_TEST_OUTPUT=output,
                                    UCDD_TEST_MEMORY_DUMP=str(run/'memory.bin')))
            (run/'test.log').write_text(result.stdout+result.stderr, encoding='utf-8')
            terminal_encoding = sys.stdout.encoding or 'utf-8'
            print((result.stdout+result.stderr).encode(
                terminal_encoding, errors='replace').decode(terminal_encoding), end='')
            result.check_returncode()
            evidence.update(check_audio(wav), rejected_controls=check_controls(wav), passed=True)
            (run/'results.json').write_text(json.dumps(evidence, indent=2)+'\n')
            print(f'The legacy SB test passed with {output} output and {client}.')


if __name__ == '__main__':
    main()
