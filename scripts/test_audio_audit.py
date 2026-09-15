# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Run isolated audio correctness regressions with the 386 interpreter."""

import argparse
import json
import os
from pathlib import Path
import subprocess

from build import ROOT
from test_audio_resident import prepare_resident_tests
from test_audio_pm import sha256


CASES = {
    'cd-range': ('tests/audio_cd_state.asm', ('CD_PLAY_RANGE=1',)),
    'shared-dma': ('tests/audio_dma_state.asm', ('SHARED_DMA_TEST=1',)),
    'dsp-timeout': ('tests/audio_dsp_timeout.asm', ()),
    'dsp-timeout-late': ('tests/audio_dsp_timeout.asm', ('DSP_FAIL_AFTER=3',)),
    'dma-snapshot': ('tests/audio_dma_snapshot.asm', ()),
    'dma-owner': ('tests/audio_dma_owner.asm', ()),
    'ems-offset': ('tests/audio_ems_atomic.asm', ()),
    'ems-length': ('tests/audio_ems_atomic.asm', ()),
    'ems-buffer': ('tests/audio_ems_atomic.asm', ()),
    'ems-direction': ('tests/audio_ems_atomic.asm', ()),
    'ems-result': ('tests/audio_ems_atomic.asm', ('EMS_ERROR_TEST=1',)),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--izarra-source', type=Path, required=True)
    parser.add_argument('--case', action='append', choices=CASES)
    args = parser.parse_args()
    capture, disk, files = prepare_resident_tests(args.izarra_source)
    run = ROOT/'.local/audio/audit-cases'
    run.mkdir(parents=True, exist_ok=True)
    files['AUTOEXEC.BAT'] = b'@ECHO OFF\r\nCHECK\r\nIF ERRORLEVEL 1 GOTO FAIL\r\nPASS\r\n:FAIL\r\nFAIL\r\n'
    files['CHECK.BIN'] = bytes(550*2352)
    env = {k: v for k, v in os.environ.items() if not k.startswith('UCDD_TEST_')}
    failed = []
    for case in args.case or CASES:
        source, defines = CASES[case]
        prefix = run/case
        binary = prefix.with_suffix('.com')
        if case == 'dma-owner':
            trap = (ROOT/'src/audio/trap.asm').read_text()
            body = trap.split('dma_unowned_write:\n', 1)[1].split('\ndma_port:', 1)[0]
            (run/'shared_dma.inc').write_text('dma_unowned_write:\n'+body+'\n')
        if case == 'dma-snapshot':
            trap = (ROOT/'src/audio/trap.asm').read_text()
            body = trap.split('emm_dma_snapshot:\n', 1)[1].split('\n%endif', 1)[0]
            (run/'snapshot.inc').write_text('emm_dma_snapshot:\n'+body+'\n')
        if case.startswith('ems-'):
            mounted = (ROOT/'src/audio/mounted.asm').read_text()
            body = 'cd_ems_write:\n'+mounted.split('cd_ems_write:\n', 1)[1].split('\n%endif', 1)[0]
            boundary = {
                'ems-offset': '    mov [cd_ems_offset], eax',
                'ems-length': '    mov [cd_ems_remaining], ax',
                'ems-buffer': '    mov [cd_ems_buffer], ax',
                'ems-direction': '    mov byte [cd_ems_direction], 0',
                'ems-result': '    popf',
            }[case]
            if boundary not in body:
                raise ValueError('The EMS test boundary is missing.')
            body = body.replace(boundary+'\n', boundary+'\n    call irq_probe\n')
            (run/'ems.inc').write_text(body+'\n')
        subprocess.run(['nasm', '-f', 'bin', '-I', str(run)+'/', '-I', str(ROOT/'src')+'/',
                        *['-D'+d for d in defines], str(ROOT/source), '-o', str(binary)], check=True)
        files['CHECK.COM'] = binary.read_bytes()
        disk.clear()
        for name, data in files.items():
            disk.add(name, data)
        image = prefix.with_suffix('.img')
        image.write_bytes(disk.image)
        result = subprocess.run([str(capture), str(image), str(prefix.with_suffix('.wav'))],
                                capture_output=True, text=True, timeout=60,
                                env=dict(env, UCDD_TEST_CPU='386'))
        log = result.stdout+result.stderr
        prefix.with_suffix('.log').write_text(log)
        passed = result.returncode == 0 and 'stop: TestExit { code: 0 }' in log
        evidence = dict(passed=passed, cpu='386', backend='interpreter',
                        binary_sha256=sha256(binary), capture_sha256=sha256(capture),
                        source_sha256={str(p.relative_to(ROOT)): sha256(p)
                                       for p in sorted((ROOT/'src').rglob('*')) if p.is_file()})
        prefix.with_suffix('.json').write_text(json.dumps(evidence, indent=2)+'\n')
        print(f'{case}: {"PASS" if passed else "FAIL"}', flush=True)
        if not passed:
            print(log)
            failed.append(case)
    if failed:
        raise SystemExit('Failed: '+', '.join(failed))


if __name__ == '__main__':
    main()
