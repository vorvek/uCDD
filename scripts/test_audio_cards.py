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
    parser.add_argument('--umb-kib', type=int)
    parser.add_argument('--umb-extra-kib', type=int, default=0)
    parser.add_argument('--ems', action='store_true')
    parser.add_argument('--without-ems-code', action='store_true')
    args = parser.parse_args()
    if args.umb_kib is not None and not args.load_high:
        parser.error('--umb-kib requires --load-high')
    if args.umb_extra_kib and args.umb_kib is None:
        parser.error('--umb-extra-kib requires --umb-kib')
    if args.ems and args.without_ems_code:
        parser.error('--ems cannot be used with --without-ems-code')
    capture, disk, files = prepare_resident_tests(args.izarra_source)
    if args.ems:
        files['FDCONFIG.SYS'] = files['FDCONFIG.SYS'].replace(
            b'JEMMEX.EXE NOEMS', b'JEMMEX.EXE FRAME=E000')
    assemble_resident_host(('NO_EMS_QUEUE=1',) if args.without_ems_code else ())
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
    if args.umb_kib is not None:
        if args.umb_kib < 1 or args.umb_kib > 255:
            parser.error('--umb-kib must be from 1 to 255')
        if args.umb_extra_kib < 0 or args.umb_extra_kib > 255:
            parser.error('--umb-extra-kib must be from 0 to 255')
        assemble('tests/umb_keep.asm', 'UMBKEEP.COM',
                 (f'UMB_FREE_KIB={args.umb_kib}', f'UMB_EXTRA_KIB={args.umb_extra_kib}'))
        files['UMBKEEP.COM'] = (ROOT/'build/UMBKEEP.COM').read_bytes()
    archive = ROOT/'.local/downloads/shcd3-7.zip'
    if sha256(archive) != SHSUCD_SHA256:
        raise ValueError('The CD extension archive hash is incorrect.')
    with zipfile.ZipFile(archive) as source:
        files['SHSUCDX.COM'] = source.read('shsucdx.com')
    files['FDCONFIG.SYS'] = files['FDCONFIG.SYS'].replace(b'FILES=40', b'LASTDRIVE=Z\r\nFILES=40')
    if args.load_high:
        files['FDCONFIG.SYS'] = files['FDCONFIG.SYS'].replace(b'DOS=LOW', b'DOS=HIGH,UMB')
    commands = ['@ECHO OFF']
    for name in ('WSSSTATE', 'PROSTATE', 'SBSTATE', 'PROMIX', 'CODEC'):
        commands += [name, 'IF ERRORLEVEL 1 GOTO FAIL']
    if args.umb_kib is not None:
        commands += ['UMBKEEP', 'IF ERRORLEVEL 1 GOTO FAIL']
    install = ('LH ' if args.load_high else '')+'UCDD -install'
    if args.ems:
        install += ' -ems'
    commands += [install, 'IF ERRORLEVEL 1 GOTO FAIL']
    commands += ['SHSUCDX /D:UCDD0001 /L:F', 'IF ERRORLEVEL 246 GOTO FAIL',
                 'RESSTATE H' if args.load_high else 'RESSTATE', 'IF ERRORLEVEL 1 GOTO FAIL']
    for name in ('WSSLIFE', 'WSSLIFE'):
        commands += [name, 'IF ERRORLEVEL 1 GOTO FAIL']
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
        if args.umb_kib is not None:
            run = run.with_name(run.name+f'-umb{args.umb_kib}-{args.umb_extra_kib}')
        if args.ems:
            run = run.with_name(run.name+'-ems')
        if args.without_ems_code:
            run = run.with_name(run.name+'-no-ems-code')
        run.mkdir(parents=True, exist_ok=True)
        image, wav = run/'cards.img', run/'cards.wav'
        image.write_bytes(disk.image)
        evidence = dict(passed=False, output=output, cpu='386', backend='interpreter', load_high=args.load_high,
                        umb_kib=args.umb_kib,
                        umb_extra_kib=args.umb_extra_kib,
                        memory='ems' if args.ems else 'xms',
                        ems_compiled=not args.without_ems_code,
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
        (_, segment, paragraphs, allocation, ring, fault, owner,
         half_allocation, half_segment, work_allocation, work_segment, memory_mode,
         host_stack, host, host_paragraphs, dma_paragraphs, half_paragraphs,
         work_paragraphs, stack_paragraphs) = struct.unpack('<19H', state)
        dma_bytes = dma_paragraphs*16
        if dma_bytes != (1024 if card == 3 else 2048 if card == 1 else 8192):
            raise ValueError('The DMA allocation size is incorrect.')
        if memory_mode != int(args.ems):
            raise ValueError('The queue memory mode is incorrect.')
        if (half_paragraphs*16, work_paragraphs*16) != (2128, 6144):
            raise ValueError('A CD buffer allocation size is incorrect.')
        if stack_paragraphs*16 != 2048:
            raise ValueError('The host stack allocation size is incorrect.')
        blocks = {owner, allocation, half_allocation, work_allocation, host, host_stack}
        block_bytes = {owner: paragraphs*16, allocation: dma_bytes,
                       half_allocation: half_paragraphs*16,
                       work_allocation: work_paragraphs*16,
                       host: host_paragraphs*16, host_stack: stack_paragraphs*16}
        if segment != owner+16:
            blocks.add(segment)
            block_bytes[owner] = 256
            block_bytes[segment] = paragraphs*16
        if args.load_high and args.umb_kib is None and min(segment, host, host_stack, half_segment,
                                                           work_segment) < 0xa000:
            raise ValueError('A resident block did not load in upper memory.')
        if args.umb_kib == 29 and args.umb_extra_kib == 7:
            if min(segment, host, host_stack, half_segment) < 0xa000 or work_segment >= 0xa000:
                raise ValueError('The constrained UMB layout is incorrect.')
        conventional_blocks = {block for block in blocks if block < 0xa000}
        conventional_bytes = sum(block_bytes[block] for block in conventional_blocks)
        total_bytes = sum(block_bytes.values())
        evidence.update(resident_bytes=paragraphs*16, resident_segment=segment,
                        host_bytes=host_paragraphs*16, host_segment=host,
                        host_stack_bytes=stack_paragraphs*16, host_stack_segment=host_stack,
                        resident_owner=owner,
                        half_bytes=half_paragraphs*16, half_segment=half_segment,
                        work_bytes=work_paragraphs*16, work_segment=work_segment,
                        dma_bytes=dma_bytes, dma_allocation=allocation,
                        dma_ring=ring, total_resident_bytes=total_bytes,
                        total_mcb_bytes=len(blocks)*16,
                        total_memory_cost=total_bytes+len(blocks)*16,
                        conventional_resident_bytes=conventional_bytes,
                        conventional_mcb_bytes=len(conventional_blocks)*16,
                        conventional_memory_cost=conventional_bytes+len(conventional_blocks)*16,
                        fault=fault)
        evidence.update(passed=True, capture_sha256=sha256(wav))
        report.write_text(json.dumps(evidence, indent=2)+'\n')
        print(f'The card tests passed with {output} output.')


if __name__ == '__main__':
    main()
