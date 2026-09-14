# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Check the integrated speaker test without external audio helpers."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import zipfile

from build import assemble
from dos_disk import Fat16
from test_audio import CACHE, ROOT, JEMM_SHA256, build_capture, verify_speaker_sequence
from test_dos import FREEDOS_SHA256


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--izarra-source', type=Path, required=True)
    parser.add_argument('--jemm', action='store_true')
    args = parser.parse_args()
    capture = build_capture(args.izarra_source)
    assemble('src/setup.asm', 'UCDDSET.EXE', exe=True)
    for name, options in (('SETLIFE.COM', ()), ('SETFAIL.COM', ('EXPECT_FAILURE=1',)),
                          ('SETRETRY.COM', ('RECOVER=1',)), ('SETHIGH.COM', ('HIGH_SETUP=1',))):
        assemble('tests/setup_lifecycle.asm', name, options)
    assemble('tests/exit.asm', 'PASS.COM')
    assemble('tests/exit.asm', 'FAIL.COM', ('EXIT_CODE=1',))
    source = CACHE / 'FD14-LiteUSB.zip'
    assert hashlib.sha256(source.read_bytes()).hexdigest() == FREEDOS_SHA256
    with zipfile.ZipFile(source) as archive:
        disk = Fat16(archive.read('FD14LITE.img'))
    kernel, command = disk.read('KERNEL.SYS'), disk.read('COMMAND.COM')
    disk.clear()
    disk.add('KERNEL.SYS', kernel)
    disk.add('COMMAND.COM', command)
    config = 'DOS=LOW\r\nFILES=40\r\nBUFFERS=10\r\nSHELL=C:\\COMMAND.COM C:\\ /E:512 /P\r\n'
    if args.jemm:
        source = CACHE / 'JemmB_v586.zip'
        assert hashlib.sha256(source.read_bytes()).hexdigest() == JEMM_SHA256
        with zipfile.ZipFile(source) as archive:
            disk.add('JEMMEX.EXE', archive.read('JEMMEX.EXE'))
        config = 'DEVICE=C:\\JEMMEX.EXE NOEMS\r\n' + config.replace('DOS=LOW', 'DOS=HIGH,UMB')
    disk.add('FDCONFIG.SYS', config.encode())
    for name in ('UCDDSET.EXE', 'SETLIFE.COM', 'SETFAIL.COM', 'SETRETRY.COM',
                 'SETHIGH.COM', 'PASS.COM', 'FAIL.COM'):
        disk.add(name, (ROOT / 'build' / name).read_bytes())
    default = b'uCDD\x01\x00' + struct.pack('<H', 0x220) + bytes((5, 1, 5, 0))
    disk.add('DEFAULT.CFG', default)
    disk.add('ALT.CFG', default[:8] + bytes((7, 3, 6, 0)))
    disk.add('BADPORT.CFG', default[:6] + struct.pack('<H', 0x240) + default[8:])
    commands = ['@ECHO OFF', 'SET BLASTER=']
    for config_name, test in (('DEFAULT', 'SETLIFE'), ('ALT', 'SETLIFE'),
                              ('BADPORT', 'SETFAIL'), ('BADPORT', 'SETRETRY')):
        commands += [f'COPY {config_name}.CFG UCDD.CFG >NUL', test,
                     'IF ERRORLEVEL 1 GOTO FAIL']
    if args.jemm:
        commands += ['COPY DEFAULT.CFG UCDD.CFG >NUL', 'SETHIGH', 'IF ERRORLEVEL 1 GOTO FAIL']
    commands += ['PASS', ':FAIL', 'FAIL']
    disk.add('AUTOEXEC.BAT', ('\r\n'.join(commands) + '\r\n').encode())
    run = ROOT / '.local/audio' / ('setup-jemm' if args.jemm else 'setup-dos')
    run.mkdir(exist_ok=True)
    image, wav = run / 'setup.img', run / 'setup.wav'
    image.write_bytes(disk.image)
    evidence = dict(passed=False, jemm=args.jemm, cpu='386', backend='interpreter',
                    program_sha256=hashlib.sha256((ROOT / 'build/UCDDSET.EXE').read_bytes()).hexdigest(),
                    disk_sha256=hashlib.sha256(disk.image).hexdigest())
    (run / 'results.json').write_text(json.dumps(evidence, indent=2) + '\n')
    result = subprocess.run([str(capture), str(image), str(wav)], capture_output=True,
                            text=True, timeout=120, env=dict(os.environ, UCDD_TEST_CPU='386',
                            UCDD_TEST_STEPS='60000'))
    (run / 'setup.log').write_text(result.stdout + result.stderr)
    print(result.stdout + result.stderr)
    result.check_returncode()
    evidence['speaker_sequence'] = verify_speaker_sequence(wav, sequences=8 if args.jemm else 6)
    evidence['capture_sha256'] = hashlib.sha256(wav.read_bytes()).hexdigest()
    evidence['passed'] = True
    (run / 'results.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print('The integrated speaker tests passed.')


if __name__ == '__main__':
    main()
