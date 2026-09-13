# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Check protected-mode port trapping and physical IRQ ownership."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import urllib.request
import zipfile

from build import assemble
from build_audio import build_audio
from dos_disk import Fat16
from test_audio import (CACHE, JEMM_SHA256, JEMM_URL, ROOT, RUN, build_capture,
                        verify_capture)
from test_dos import FREEDOS_SHA256

HDPMI_URL = 'https://github.com/crazii/SBEMU/releases/download/Release_1.0.0-beta.6/SBEMU.zip'
HDPMI_SHA256 = '85602c7fba69b354892a1b82710e5a0f073e85572e1b8faa9461d31988faeb3c'
PM_RUN = RUN / 'protected'


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def make_disk(negative=False, alternate=False, virtual_irq=False, rollover=False,
              onset=False, quiet=False, refill=None, launcher=False, dma_state=False):
    with zipfile.ZipFile(CACHE / 'FD14-LiteUSB.zip') as archive:
        disk = Fat16(archive.read('FD14LITE.img'))
    kernel, command = disk.read('KERNEL.SYS'), disk.read('COMMAND.COM')
    disk.clear()
    disk.add('KERNEL.SYS', kernel)
    disk.add('COMMAND.COM', command)
    with zipfile.ZipFile(CACHE / 'JemmB_v586.zip') as archive:
        for name in ('JEMMEX.EXE', 'JLOAD.EXE', 'QPIEMU.DLL'):
            disk.add(name, archive.read(name))
    with zipfile.ZipFile(CACHE / 'SBEMU-beta6.zip') as archive:
        disk.add('HDPMI32I.EXE', archive.read('SBEMU/HDPMI32i.EXE'))
    for name in ('APSHARE.COM', 'ASHARE.COM', 'ACLIENT.COM', 'AISTATE.COM', 'PASS.COM', 'FAIL.COM'):
        source = 'AISHARE.COM' if virtual_irq and name == 'APSHARE.COM' else name
        if rollover and name == 'APSHARE.COM':
            source = 'AIWRAP.COM'
        if onset and name == 'APSHARE.COM':
            source = 'AOSHARE.COM'
        if refill and name == 'APSHARE.COM':
            source = 'ARSHARE.COM'
        disk.add(name, (ROOT / 'build' / source).read_bytes())
    client = ('AIPMNEG.COM' if negative else 'AIPM.COM') if virtual_irq else (
        'APMNEG.COM' if negative else 'APM.COM')
    if onset:
        client = 'AOQUIET.COM' if quiet else 'AOPM.COM'
    if refill:
        client = ('AQ' if quiet else 'AR') + refill + '.COM'
    if launcher:
        client = 'ALAUNCH.COM'
        external = ('AEXTLQ.COM' if quiet else 'AEXTLEG.COM') if refill == 'LEGACY' else (
            'AEXTQUI.COM' if quiet else 'AEXT.COM')
        if refill == 'STEREO':
            external = 'ASTQUIET.COM' if quiet else 'ASTEREO.COM'
        disk.add('GAME.COM', (ROOT / 'build' / external).read_bytes())
    disk.add('APM.COM', (ROOT / 'build' / client).read_bytes())
    if alternate:
        disk.add('UCDD.CFG', b'uCDD\x01\x00' + struct.pack('<H', 0x220) + bytes([7, 3, 6, 0]))
    if dma_state:
        disk.add('ADMA.COM', (ROOT / 'build/ADMA.COM').read_bytes())
    disk.add('FDCONFIG.SYS', (
        'DEVICE=C:\\JEMMEX.EXE NOEMS\r\nDOS=LOW\r\nFILES=40\r\nBUFFERS=10\r\n'
        'SHELL=C:\\COMMAND.COM C:\\ /E:512 /P\r\n').encode())
    repeat = '' if negative or onset or refill else (
        'APSHARE\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
        'ASHARE\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n')
    disk.add('AUTOEXEC.BAT', (
        '@ECHO OFF\r\n' + ('ADMA\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n' if dma_state else '') +
        'JLOAD QPIEMU.DLL\r\nHDPMI32I -r\r\n'
        'AISTATE\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
        'APSHARE\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n' + repeat +
        'PASS\r\n:FAIL\r\nFAIL\r\n').encode())
    return bytes(disk.image)


def prepare_tests(izarra_source):
    CACHE.mkdir(parents=True, exist_ok=True)
    for name, url, expected in (
            ('JemmB_v586.zip', JEMM_URL, JEMM_SHA256),
            ('SBEMU-beta6.zip', HDPMI_URL, HDPMI_SHA256),
            ('FD14-LiteUSB.zip', None, FREEDOS_SHA256)):
        archive = CACHE / name
        if not archive.exists():
            if not url:
                raise SystemExit('Run scripts/fetch_test_deps.py first.')
            urllib.request.urlretrieve(url, archive)
        if sha256(archive) != expected:
            raise SystemExit(f'The archive hash is incorrect: {name}')
    build_audio()
    assemble('tests/exit.asm', 'PASS.COM')
    assemble('tests/exit.asm', 'FAIL.COM', ('EXIT_CODE=1',))
    return build_capture(izarra_source)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--izarra-source', type=Path, required=True)
    args = parser.parse_args()
    PM_RUN.mkdir(parents=True, exist_ok=True)
    executable = prepare_tests(args.izarra_source)
    evidence = dict(passed=False, jemm_sha256=JEMM_SHA256, hdpmi_archive_sha256=HDPMI_SHA256,
                    freedos_sha256=FREEDOS_SHA256, capture_executable_sha256=sha256(executable),
                    capture_source_sha256=sha256(ROOT / 'tests/audio_capture.rs'),
                    capture_lock_sha256=sha256(RUN / 'capture/Cargo.lock'),
                    izarra_revision=subprocess.check_output(
                        ['git', '-C', str(args.izarra_source), 'rev-parse', 'HEAD'], text=True).strip(),
                    program_sha256={name: sha256(ROOT / 'build' / name) for name in
                                    ('APSHARE.COM', 'APM.COM', 'APMNEG.COM', 'ASHARE.COM', 'ACLIENT.COM',
                                     'AISHARE.COM', 'AIPM.COM', 'AIPMNEG.COM', 'AISTATE.COM', 'AIWRAP.COM')},
                    runs=[])
    report = PM_RUN / 'results.json'
    report.write_text(json.dumps(evidence, indent=2) + '\n')
    for name, negative, alternate, virtual_irq, rollover in (
            ('default', False, False, False, False), ('alternate', False, True, False, False),
            ('no-route', True, False, False, False), ('interrupts', False, False, True, False),
            ('interrupts-alt', False, True, True, False), ('no-delivery', True, False, True, False),
            ('interrupts-wrap', False, False, True, True)):
        image, wav, log_path = (PM_RUN / (name + suffix) for suffix in ('.img', '.wav', '.log'))
        image.write_bytes(make_disk(negative, alternate, virtual_irq, rollover))
        command = [str(executable), str(image), str(wav)]
        result = subprocess.run(command, capture_output=True, text=True, timeout=180)
        log = result.stdout + result.stderr
        log_path.write_text(log, encoding='utf-8')
        if negative:
            expected = ('No virtual sound interrupt was received.' if virtual_irq else
                        'Without IRQ routing, the client received the card interrupts.')
            passed = (result.returncode != 0 and 'stop: TestExit { code: 1 }' in log and
                      expected in log)
        else:
            passed = result.returncode == 0 and 'stop: TestExit { code: 0 }' in log
        row = dict(name=name, command=command, passed=passed, disk_sha256=sha256(image),
                   capture_sha256=sha256(wav), expected_failure=negative)
        evidence['runs'].append(row)
        report.write_text(json.dumps(evidence, indent=2) + '\n')
        if not passed:
            print(log)
            raise SystemExit(f'The protected audio check failed: {name}')
        if not negative:
            windows = tuple((center, 22050 / 64) for center in (4.35, 5.1, 6.0)) if virtual_irq else ()
            row['capture_checks'] = verify_capture(wav, windows)
        print(f'The protected audio check passed: {name}')
        report.write_text(json.dumps(evidence, indent=2) + '\n')
    evidence['passed'] = True
    report.write_text(json.dumps(evidence, indent=2) + '\n')


if __name__ == '__main__':
    main()
