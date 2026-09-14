# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Run DPMI lifecycle regressions with exact VCPI page recovery."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

from build import ROOT
from dos_disk import Fat16
from test_audio import build_capture


CASES = {
    'core': ('dpmi', (), (), 0),
    'api': ('api', (), (), 0),
    'pic': ('pic', (), (), 0),
    'nested': ('pic', ('LOCKED_NESTING=1',), (), 0),
    'rollback': ('dpmi', (), ('DPMI_LOCK_FAIL_SECOND=1',), 1),
    'metadata-rollback': ('dpmi', (), ('DPMI_MEMORY_FAIL=1',), 1),
    'callback-revoked': ('dpmi', ('CALLBACK_REVOKED=1',), (), 1),
    'callback-fault': ('dpmi', ('CALLBACK_UD2=1',), (), 1),
    'callback-exit': ('dpmi', ('CALLBACK_EXIT=1',), (), 0),
    'private-raw': ('dpmi', ('BAD_RAW_GATE=1',), (), 1),
    'private-reflect': ('dpmi', ('BAD_REFLECT_GATE=1',), (), 1),
    'raw-code': ('dpmi', ('BAD_RAW_CODE=1',), (), 1),
    'raw-stack': ('dpmi', ('BAD_RAW_STACK=1',), (), 1),
    'raw-data': ('dpmi', ('BAD_RAW_DATA=1',), (), 1),
    'irq-code': ('pic', ('BAD_IRQ_CODE=1',), (), 1),
    'irq-stack': ('pic', ('BAD_IRQ_STACK=1',), (), 1),
    'irq-cursor': ('pic', ('BAD_IRQ_CURSOR=1',), (), 1),
    'ivt-exit': ('api', ('LEAK_VECTORS=1',), (), 0),
    'ivt-fault': ('api', ('LEAK_VECTORS=1', 'FAULT_EXIT=1'), (), 1),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emulator', type=Path, required=True)
    parser.add_argument('--izarra-source', type=Path, required=True)
    parser.add_argument('--case', action='append', choices=CASES)
    parser.add_argument('--base-image', type=Path,
                        help='Reuse a core --external test_host.py disk.')
    parser.add_argument('--timeout', type=int, default=90)
    args = parser.parse_args()
    nasm = shutil.which('nasm')
    if not nasm:
        parser.error('NASM is required.')
    run = ROOT/'.local/host/audit'
    run.mkdir(parents=True, exist_ok=True)
    env = {key: value for key, value in os.environ.items()
           if not key.startswith('UCDD_TEST_')}
    if args.base_image:
        image = args.base_image.resolve()
    else:
        subprocess.run([sys.executable, str(ROOT/'scripts/test_host.py'),
                        '--emulator', str(args.emulator.resolve()), '--external',
                        '--izarra-source', str(args.izarra_source.resolve())],
                       cwd=ROOT, env=env, check=True)
        image = ROOT/'.local/host/monitor-external.img'
    capture = build_capture(args.izarra_source.resolve())
    disk = Fat16(image.read_bytes())
    files = {name: disk.read(name) for name in disk.directory()}
    if not {'HOSTEXT.COM', 'DCLIENT.COM', 'AUTOEXEC.BAT'} <= files.keys():
        parser.error('The base disk is not a core external-host test disk.')
    source_hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                     for path in sorted((ROOT/'src/host').glob('*.asm'))}
    failures = []
    for name in args.case or CASES:
        source, child_defines, host_defines, status = CASES[name]
        prefix = run/name
        binaries = {}
        for label, asm, defines in (
                ('HOSTEXT.COM', 'tests/host_external.asm',
                 (*host_defines, 'CHILD_RUNS=2', f'CHILD_EXIT_CODE={status}')),
                ('DCLIENT.COM', f'tests/host_{source}_client.asm', child_defines)):
            output = prefix.with_suffix('.'+label.lower())
            subprocess.run([nasm, '-f', 'bin', '-I', str(ROOT/'src')+'/',
                            *('-D'+value for value in defines), str(ROOT/asm),
                            '-o', str(output)], check=True)
            binaries[label] = output.read_bytes()
        disk.clear()
        for key, value in files.items():
            disk.add(key, binaries.get(key, value))
        disk_path = prefix.with_suffix('.img')
        disk_path.write_bytes(disk.image)
        command = [str(capture), str(disk_path), str(prefix.with_suffix('.wav'))]
        result = subprocess.run(command, capture_output=True, text=True,
                                timeout=args.timeout, env=dict(
                                    env, UCDD_TEST_CPU='386', UCDD_TEST_DISK_EXPORT='1',
                                    UCDD_TEST_MEMORY_DUMP=str(prefix.with_suffix('.memory.bin'))))
        log = result.stdout+result.stderr
        prefix.with_suffix('.log').write_text(log)
        passed = result.returncode == 0 and 'stop: TestExit { code: 0 }' in log
        report = dict(passed=passed, cpu='386', backend='interpreter', child_runs=2,
                      expected_child_exit=status, checks_exact_page_recovery=True,
                      source_sha256=source_hashes, command=command,
                      emulator_sha256=hashlib.sha256(capture.read_bytes()).hexdigest(),
                      program_sha256={key: hashlib.sha256(value).hexdigest()
                                      for key, value in binaries.items()},
                      disk_sha256=hashlib.sha256(disk.image).hexdigest())
        prefix.with_suffix('.json').write_text(json.dumps(report, indent=2)+'\n')
        print(f'{name}: {"PASS" if passed else "FAIL"}', flush=True)
        if not passed:
            failures.append(name)
    if failures:
        raise SystemExit('The host tests failed: '+', '.join(failures))


if __name__ == '__main__':
    main()
