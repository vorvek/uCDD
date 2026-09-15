# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Check XMS buffer addresses after installation into fragmented upper memory."""

import argparse
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import zipfile

from build import assemble, assemble_resident_host
from dos_disk import Fat16
from test_audio_resident import prepare_resident_tests
from test_audio_pm import ROOT, CACHE, sha256
from test_dos import SHSUCD_SHA256


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--izarra-source', type=Path, required=True)
    args = parser.parse_args()
    capture, disk, files = prepare_resident_tests(args.izarra_source)
    files['FDCONFIG.SYS'] = files['FDCONFIG.SYS'].replace(b'DOS=LOW', b'DOS=HIGH,UMB')
    files['FDCONFIG.SYS'] += b'LASTDRIVE=Z\r\n'
    assemble_resident_host()
    assemble('tests/umb_keep.asm', 'UMBKEEP.COM', ('UMB_FREE_KIB=29', 'UMB_EXTRA_KIB=12'))
    assemble('tests/audio_resident_dump.asm', 'CDDIAG.COM')
    for name in ('UCDD.EXE', 'UMBKEEP.COM', 'CDDIAG.COM'):
        files[name] = (ROOT/'build'/name).read_bytes()
    archive = CACHE/'shcd3-7.zip'
    if sha256(archive) != SHSUCD_SHA256:
        raise ValueError('The SHSUCDX archive hash is incorrect.')
    with zipfile.ZipFile(archive) as source:
        files['SHSUCDX.COM'] = source.read('shsucdx.com')
    files['UCDD.CFG'] = b'uCDD\x01\x00'+struct.pack('<H', 0x220)+bytes((7, 1, 5, 0))
    files['AUTOEXEC.BAT'] = (
        b'@ECHO OFF\r\nUMBKEEP\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
        b'LH UCDD -install\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
        b'SHSUCDX /D:UCDD0001 /L:F\r\nCDDIAG STATE.BIN\r\n'
        b'IF ERRORLEVEL 1 GOTO FAIL\r\nPASS\r\n:FAIL\r\nFAIL\r\n')
    disk.clear()
    for name, data in files.items():
        disk.add(name, data)
    run = ROOT/'.local/audio/buffer-relocation'
    run.mkdir(parents=True, exist_ok=True)
    image = run/'boot.img'
    image.write_bytes(disk.image)
    evidence = dict(passed=False, cpu='386', backend='interpreter',
                    driver_sha256=sha256(ROOT/'build/UCDD.EXE'),
                    disk_sha256=sha256(image), capture_sha256=sha256(capture))
    report = run/'results.json'
    report.write_text(json.dumps(evidence, indent=2)+'\n')
    env = {k: v for k, v in os.environ.items() if not k.startswith('UCDD_TEST_')}
    result = subprocess.run([str(capture), str(image), str(run/'boot.wav')],
                            capture_output=True, text=True, timeout=60,
                            env=dict(env, UCDD_TEST_CPU='386', UCDD_TEST_DISK_EXPORT='1'))
    (run/'boot.log').write_text(result.stdout+result.stderr)
    print(result.stdout+result.stderr)
    result.check_returncode()
    data = Fat16((run/'boot.disk.img').read_bytes()).read('STATE.BIN')
    (run/'STATE.BIN').write_bytes(data)
    if data[:6] != b'UCDS\x01\x00' or len(data) != 34+struct.unpack_from('<H', data, 6)[0]:
        raise ValueError('The resident snapshot is not valid.')
    resident_segment = struct.unpack_from('<H', data, 10)[0]
    listing = (ROOT/'build/UCDD.lst').read_text().splitlines()

    def word(label, delta=0):
        line = next(line for line in listing if re.search(r'\b'+label+r' dw\b', line))
        offset = int(re.search(r'\b([0-9A-F]{8})\b', line)[1], 16)
        return struct.unpack_from('<H', data, 34+offset+delta)[0]

    actual = dict(resident_segment=resident_segment,
                  half_segment=word('cd_half_segment'),
                  xms_read_segment=word('cd_read_address', 2),
                  work_segment=word('cd_work_segment'),
                  xms_write_segment=word('cd_write_address', 2))
    evidence.update(actual)
    evidence['passed'] = (resident_segment >= 0xa000 and actual['half_segment'] >= 0xa000
                          and actual['half_segment'] == actual['xms_read_segment']
                          and actual['work_segment'] == actual['xms_write_segment'])
    report.write_text(json.dumps(evidence, indent=2)+'\n')
    print(json.dumps(actual, indent=2))
    if not evidence['passed']:
        raise SystemExit('FAIL: relocated CD buffers and XMS move addresses do not match.')
    print('PASS: upper-memory CD buffers and XMS move addresses match.')


if __name__ == '__main__':
    main()
