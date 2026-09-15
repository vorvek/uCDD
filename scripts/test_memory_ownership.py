# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Check DPMI mapping and failed resident-install ownership in the interpreter."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess

from build import ROOT
from dos_disk import Fat16


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def assemble(nasm, output, source, name, defines=(), includes=()):
    path = output/name
    subprocess.run([nasm, '-f', 'bin', *('-I'+str(p)+'/' for p in includes),
                    '-I'+str(ROOT/'src')+'/', *('-D'+value for value in defines),
                    '-l', str(path.with_suffix('.lst')), str(ROOT/source), '-o', str(path)],
                   check=True)
    return path


def prepare_detach(nasm, output, files, case):
    overlay = output/'source-overlay'
    (overlay/'audio').mkdir(parents=True, exist_ok=True)
    source = (ROOT/'src/audio/resident_init.asm').read_text()
    old = '    call own_host_install\n'
    if source.count(old) != 1:
        raise ValueError('The internal-host failure injection point changed.')
    (overlay/'audio/resident_init.asm').write_text(source.replace(old, '    stc\n'))
    if case != 'detach-clean':
        source = (ROOT/'src/audio/trap.asm').read_text()
        old = 'trap_remove:\n'
        if source.count(old) != 1:
            raise ValueError('The trap-removal failure injection point changed.')
        (overlay/'audio/trap.asm').write_text(source.replace(old, old+'    stc\n    ret\n'))
    path = assemble(nasm, output, 'src/ucdd.asm', 'UCDD.EXE',
                    ('RESIDENT_AUDIO=1', 'OWN_HOST=1', 'OWN_HOST_SIZE=1', 'OWN_HOST_OFFSET=65536'),
                    (overlay,))
    payload = path.read_bytes()
    stack_top = (len(payload)+15)//16*16+1024
    size = 32+len(payload)
    header = struct.pack('<14H', 0x5a4d, size % 512, (size+511)//512,
                         0, 2, 64, 64, 0, stack_top, 0, 0, 0, 28, 0)
    path.write_bytes(header.ljust(32, b'\0')+payload)
    files[path.name] = path.read_bytes()
    if case == 'detach-clean':
        path = assemble(nasm, output, 'tests/setup_lifecycle.asm', 'DETACH.COM',
                        ('EXPECT_FAILURE=1', 'INSTALL_TEST=1'))
    else:
        listing = (output/'UCDD.lst').read_text().splitlines()
        offsets = []
        for label in ('host_mux', 'resident_psp', 'audio_detach_failed', 'sb_running',
                      'output_allocation', 'cd_half_allocation', 'cd_work_allocation',
                      'cd_xms_handle'):
            index = next(i for i, line in enumerate(listing)
                         if re.search(r'\b'+label+r'(?:\s+d[bw]|:)', line))
            match = next(re.search(r'^\s*\d+\s+([0-9A-F]{8})\s', line)
                         for line in listing[index:]
                         if re.search(r'^\s*\d+\s+([0-9A-F]{8})\s', line))
            offsets.append(f'%define audit_{label} 0{match[1]}h')
        (output/'resident_offsets.inc').write_text('\n'.join(offsets)+'\n')
        path = assemble(nasm, output, 'tests/resident_detach.asm', 'DETACH.COM',
                        (f'EXPECT_HIGH={int(case == "detach-high")}',), (output,))
    files[path.name] = path.read_bytes()
    path = assemble(nasm, output, 'tests/umb_keep.asm', 'UMBKEEP.COM',
                    (f'UMB_FREE_KIB={0 if case == "detach-low" else 29}',
                     f'UMB_EXTRA_KIB={0 if case == "detach-low" else 12}'))
    files[path.name] = path.read_bytes()
    files['UCDD.CFG'] = b'uCDD\x01\x00\x20\x02'+bytes((7, 1, 5, 0))
    files['FDCONFIG.SYS'] = files['FDCONFIG.SYS'].replace(b'DOS=LOW', b'DOS=HIGH,UMB')
    files['AUTOEXEC.BAT'] = (b'@ECHO OFF\r\nUMBKEEP\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
                             b'DETACH\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
                             b'PASS\r\n:FAIL\r\nFAIL\r\n')
    return ['UCDD.EXE', 'DETACH.COM', 'UMBKEEP.COM']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture', type=Path, required=True)
    parser.add_argument('--base-image', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--case', choices=('unmap', 'detach-high', 'detach-low', 'detach-clean'),
                        default='unmap')
    args = parser.parse_args()
    nasm = shutil.which('nasm')
    if not nasm:
        parser.error('NASM is required.')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    disk = Fat16(args.base_image.read_bytes())
    files = {name: disk.read(name) for name in disk.directory()}
    if args.case == 'unmap':
        programs = ['HOSTEXT.COM', 'DCLIENT.COM']
        for name, source, defines in (
                ('HOSTEXT.COM', 'tests/host_external.asm', ('CHILD_RUNS=2',)),
                ('DCLIENT.COM', 'tests/host_api_client.asm', ())):
            path = assemble(nasm, output, source, name, defines)
            files[name] = path.read_bytes()
        files['AUTOEXEC.BAT'] = (b'@ECHO OFF\r\nHOSTEXT\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
                                 b'PASS\r\n:FAIL\r\nFAIL\r\n')
        checks = ['unmap-zero', 'unmap-fff', 'low-vector', 'exact-page-recovery']
    else:
        programs = prepare_detach(nasm, output, files, args.case)
        checks = (['clean-rollback'] if args.case == 'detach-clean' else
                  ['hooked-code-mcb', 'buffer-mcbs', 'queue-handle', 'stopped-output', 'live-callback'])
    disk.clear()
    for name, data in files.items():
        disk.add(name, data)
    disk_path = output/'boot.img'
    disk_path.write_bytes(disk.image)
    evidence = dict(passed=False, case=args.case, cpu='386', backend='interpreter',
                    child_runs=2 if args.case == 'unmap' else 1, checks=checks,
                    capture_sha256=sha256(args.capture), disk_sha256=sha256(disk_path),
                    programs={name: sha256(output/name) for name in programs},
                    source_sha256={str(path.relative_to(ROOT)): sha256(path)
                                   for path in sorted((ROOT/'src').rglob('*')) if path.is_file()},
                    overlay_sha256={str(path.relative_to(output)): sha256(path)
                                    for path in sorted((output/'source-overlay').rglob('*'))
                                    if path.is_file()})
    report = output/'results.json'
    report.write_text(json.dumps(evidence, indent=2)+'\n')
    env = {key: value for key, value in os.environ.items() if not key.startswith('UCDD_TEST_')}
    result = subprocess.run([str(args.capture.resolve()), str(disk_path), str(output/'boot.wav')],
                            capture_output=True, text=True, timeout=90,
                            env=dict(env, UCDD_TEST_CPU='386', UCDD_TEST_DISK_EXPORT='1',
                                     UCDD_TEST_MEMORY_DUMP=str(output/'memory.bin')))
    log = result.stdout+result.stderr
    (output/'boot.log').write_text(log)
    print(log)
    evidence['passed'] = result.returncode == 0 and 'stop: TestExit { code: 0 }' in log
    report.write_text(json.dumps(evidence, indent=2)+'\n')
    if not evidence['passed']:
        raise SystemExit('FAIL: memory ownership regression.')
    print('PASS: memory ownership regression.')


if __name__ == '__main__':
    main()
