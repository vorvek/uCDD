# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Check card protocols and WSS protected interrupts through each output."""

import argparse
import json
import os
from pathlib import Path
import struct
import subprocess
import zipfile

from build import ROOT, assemble, assemble_resident_host
from dos_disk import Fat16
from test_audio_pm import sha256
from test_audio_resident import prepare_resident_tests
from test_dos import SHSUCD_SHA256


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--izarra-source', type=Path, required=True)
    parser.add_argument('--output', choices=('sb16', 'sbpro', 'wss', 'sb'), action='append')
    parser.add_argument('--load-high', action='store_true')
    args = parser.parse_args()
    capture, disk, files = prepare_resident_tests(args.izarra_source)
    assemble_resident_host()
    programs = [('audio_wss_state', 'WSSSTATE.COM'), ('audio_pro_state', 'PROSTATE.COM'),
                ('audio_sb_state', 'SBSTATE.COM'),
                ('audio_pro_mix', 'PROMIX.COM'),
                ('audio_wss_codec', 'CODEC.COM'), ('audio_wss_irq', 'WSSIRQ.COM')]
    for source, name in programs:
        assemble(f'tests/{source}.asm', name)
        files[name] = (ROOT/'build'/name).read_bytes()
    assemble('tests/setup_lifecycle.asm', 'WSSLIFE.COM', ('CHILD_NAME="WSSIRQ.COM"',))
    for name in ('UCDD.EXE', 'WSSLIFE.COM'):
        files[name] = (ROOT/'build'/name).read_bytes()
    assemble('tests/audio_resident_state.asm', 'RESSTATE.COM', ('OWN_HOST=1',))
    files['RESSTATE.COM'] = (ROOT/'build/RESSTATE.COM').read_bytes()
    archive = ROOT/'.local/downloads/shcd3-7.zip'
    if sha256(archive) != SHSUCD_SHA256:
        raise ValueError('The CD extension archive hash is incorrect.')
    with zipfile.ZipFile(archive) as source:
        files['SHSUCDX.COM'] = source.read('shsucdx.com')
    files['FDCONFIG.SYS'] = files['FDCONFIG.SYS'].replace(b'FILES=40', b'LASTDRIVE=Z\r\nFILES=40')
    if args.load_high:
        files['FDCONFIG.SYS'] = files['FDCONFIG.SYS'].replace(b'DOS=LOW', b'DOS=HIGH,UMB')
    commands = ['@ECHO OFF']
    for name in ('WSSSTATE', 'PROSTATE', 'SBSTATE', 'PROMIX', 'CODEC',
                 ('LH ' if args.load_high else '')+'UCDD -install', 'WSSLIFE', 'WSSLIFE'):
        commands += [name, 'IF ERRORLEVEL 1 GOTO FAIL']
    commands += ['SHSUCDX /D:UCDD0001 /L:F', 'IF ERRORLEVEL 246 GOTO FAIL',
                 'RESSTATE H' if args.load_high else 'RESSTATE', 'IF ERRORLEVEL 1 GOTO FAIL']
    commands += ['PASS', ':FAIL', 'FAIL']
    files['AUTOEXEC.BAT'] = ('\r\n'.join(commands)+'\r\n').encode()
    for output in args.output or ('sb16', 'sbpro', 'wss', 'sb'):
        card = ('sb16', 'sbpro', 'wss', 'sb').index(output)
        files['UCDD.CFG'] = b'uCDD\x01'+bytes([card])+struct.pack('<H', 0x530 if card == 2 else 0x220)+bytes((7, 1, 5, 0))
        disk.clear()
        for name, data in files.items():
            disk.add(name, data)
        run = ROOT/'.local/audio'/f'cards-{output}'
        if args.load_high:
            run = run.with_name(run.name+'-high')
        run.mkdir(parents=True, exist_ok=True)
        image, wav = run/'cards.img', run/'cards.wav'
        image.write_bytes(disk.image)
        evidence = dict(passed=False, output=output, cpu='386', backend='interpreter', load_high=args.load_high,
                        programs={name: sha256(ROOT/'build'/name) for name in
                                  ('UCDD.EXE', 'WSSLIFE.COM', *(n for _, n in programs))})
        report = run/'results.json'
        report.write_text(json.dumps(evidence, indent=2)+'\n')
        result = subprocess.run([str(capture), str(image), str(wav)], capture_output=True,
                                text=True, timeout=90, env=dict(os.environ,
                                UCDD_TEST_CPU='386', UCDD_TEST_STEPS='90000', UCDD_TEST_OUTPUT=output,
                                UCDD_TEST_DISK_EXPORT='1',
                                UCDD_TEST_MEMORY_DUMP=str(run/'memory.bin')))
        (run/'cards.log').write_text(result.stdout+result.stderr)
        print(result.stdout+result.stderr)
        result.check_returncode()
        state = Fat16(wav.with_suffix('.disk.img').read_bytes()).read('RESSTAT.DAT')
        _, segment, paragraphs, allocation, ring, fault, host, host_paragraphs = struct.unpack('<8H', state)
        memory = (run/'memory.bin').read_bytes()
        dma_bytes = struct.unpack_from('<H', memory, (allocation-1)*16+3)[0]*16
        if dma_bytes != (1024 if card == 3 else 2048 if card == 1 else 8192):
            raise ValueError('The DMA allocation size is incorrect.')
        evidence.update(resident_bytes=paragraphs*16, resident_segment=segment,
                        host_bytes=host_paragraphs*16, host_segment=host,
                        dma_bytes=dma_bytes, dma_allocation=allocation,
                        dma_ring=ring, fault=fault)
        evidence.update(passed=True, capture_sha256=sha256(wav))
        report.write_text(json.dumps(evidence, indent=2)+'\n')
        print(f'The card tests passed with {output} output.')


if __name__ == '__main__':
    main()
