# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Test MDM parsing, media changes and keyboard IRQs in interpreted 386 DOS."""

import argparse
import hashlib
import json
import re
from pathlib import Path
import subprocess
import zipfile

from build import ROOT, assemble, assemble_resident_host
from dos_disk import Fat16
from test_dos import CACHE, FREEDOS_SHA256, SHSUCD_SHA256, make_iso
from test_audio import JEMM_SHA256


def fixture(audio=False, high=False, xms=True, hardware_keys=False, ems=False):
    for name, digest in [('FD14-LiteUSB.zip', FREEDOS_SHA256),
                         ('shcd3-7.zip', SHSUCD_SHA256), ('JemmB_v586.zip', JEMM_SHA256)]:
        if hashlib.sha256((CACHE/name).read_bytes()).hexdigest() != digest:
            raise ValueError(f'Incorrect dependency hash: {name}')
    with zipfile.ZipFile(CACHE/'FD14-LiteUSB.zip') as archive:
        disk = Fat16(archive.read('FD14LITE.img'))
    kernel, command = disk.read('KERNEL.SYS'), disk.read('COMMAND.COM')
    disk.clear()
    disk.add('KERNEL.SYS', kernel)
    disk.add('COMMAND.COM', command)
    with zipfile.ZipFile(CACHE/'JemmB_v586.zip') as archive:
        disk.add('JEMMEX.EXE', archive.read('JEMMEX.EXE'))
    with zipfile.ZipFile(CACHE/'shcd3-7.zip') as archive:
        disk.add('SHSUCDX.COM', archive.read('shsucdx.com'))
    config = ('DEVICE=C:\\JEMMEX.EXE NOEMS\r\n' if xms else '')
    config += ('DOS=HIGH,UMB' if high else 'DOS=LOW')+'\r\nFILES=40\r\nLASTDRIVE=Z\r\n'
    config += 'SHELL=C:\\COMMAND.COM C:\\ /E:512 /P\r\n'
    if ems:
        config = config.replace('NOEMS', 'FRAME=E000')
    disk.add('FDCONFIG.SYS', config.encode())
    if audio:
        assemble_resident_host()
    else:
        assemble('src/ucdd.asm', 'UCDD.EXE', exe=True, listing=True)
    listing = (ROOT/'build/UCDD.lst').read_text()
    def address(label):
        return int(re.search(r'\s[0-9A-F]{8}\s', listing.split(label+':', 1)[1])[0], 16)
    defines = () if hardware_keys else (f'KEY_SCAN={address("mdm_scan")}',
        f'KEY_RETF={int(re.search(r"([0-9A-F]{8}) CB\s+<1>\s+retf", listing)[1], 16)}')
    assemble('tests/mdm_keys.asm', 'MDMKEY.COM', defines)
    assemble('tests/mdm_memory.asm', 'MDMMEM.COM')
    assemble('tests/mdm_lock.asm', 'MDMLOCK.COM')
    for name in ('UCDD.EXE', 'UCDDSET.EXE', 'MDMKEY.COM', 'MDMMEM.COM', 'MDMLOCK.COM', 'PROBE.COM', 'FILECRC.COM', 'PASS.COM', 'FAIL.COM'):
        disk.add(name, (ROOT/'build'/name).read_bytes())
    disk.add('UCDD.CFG', b'uCDD\x01\x00\x20\x02\x07\x01\x05\x00')
    for n in range(1, 11):
        disk.add(f'DISC{n}.ISO', make_iso(f'DISC{n}'))
    raw = b''.join(bytes(16)+make_iso('RAW')[i:i+2048]+bytes(288)
                   for i in range(0, 22*2048, 2048))
    disk.add('RAW.BIN', raw+bytes(2352*150))
    disk.add('RAW.CUE', b'FILE "RAW.BIN" BINARY\r\nTRACK 01 MODE1/2352\r\nINDEX 01 00:00:00\r\nTRACK 02 AUDIO\r\nINDEX 01 00:00:22\r\n')
    disk.add('LIST.MDM', ('\r\n'.join(f'DISC{n}.ISO' for n in range(1, 11))+'\r\nIGNORED.BAD\r\n').encode())
    disk.add('MIX.MDM', b' DISC1.ISO \nRAW.CUE\nRAW.BIN')
    disk.add('BAD.MDM', b'DISC1.ISO\nMISSING.ISO\n')
    disk.add('NEST.MDM', b'LIST.MDM\n')
    disk.add('EMPTY.MDM', b'\r\n \r\n')
    disk.add('LONG.MDM', b'A'*128+b'.ISO\n')
    disk.add('ZERO.MDM', b'DISC1.ISO\0\n')
    disk.add_directory('LISTS', {'REL.MDM': b'..\\DISC1.ISO\n..\\RAW.CUE'})
    commands = ['@ECHO OFF']
    checks = []
    def check(command, ok=True):
        checks.append((command, ok))
    check(('LH ' if high else '')+'C:\\UCDD.EXE -install'+('' if audio else ' -units 2')+(' -ems' if ems else ''))
    check('SHSUCDX /D:UCDD0001 /L:F')
    check('UCDD -mount DISC2.ISO -drive F')
    if xms:
        check('MDMMEM')
    for name in ('BAD', 'NEST', 'EMPTY', 'LONG', 'ZERO'):
        check(f'UCDD -mount {name}.MDM -drive F', False)
        check('PROBE F:\\DISC2.TXT')
    if xms:
        check('MDMMEM CHECK')
    if not xms:
        check('UCDD -mount LIST.MDM -drive F', False)
        check('PROBE F:\\DISC2.TXT')
    else:
        check('UCDD -mount LIST.MDM -drive F')
        check('PROBE F:\\DISC1.TXT')
        check('MDMKEY 2 N')
        check('PROBE F:\\DISC1.TXT')
        check('MDMLOCK 1')
        check('MDMKEY 2')
        check('PROBE F:\\DISC1.TXT')
        check('UCDD -unmount LIST.MDM', False)
        check('MDMLOCK 0')
        check('PROBE F:\\DISC2.TXT')
        check('MDMKEY 1 R')
        check('PROBE F:\\DISC1.TXT')
        check('MDMKEY 2' if hardware_keys else 'MDMKEY 2 P')
        check('PROBE F:\\DISC2.TXT')
        check('MDMKEY 1 A')
        check('PROBE F:\\DISC2.TXT')
        check('MDMKEY 1 C')
        check('PROBE F:\\DISC2.TXT')
        check('UCDD -mount MIX.MDM -drive F', False)
        if not audio:
            check('UCDD -mount MIX.MDM -drive G', False)
        for n in (*range(2, 11), 1, 7, 2):
            check(f'MDMKEY {n%10}')
            check(f'PROBE F:\\DISC{n}.TXT')
        check('UCDD -unmount MIX.MDM', False)
        check('PROBE F:\\DISC2.TXT')
        check('UCDD -unmount LIST.MDM')
        check('PROBE !F:\\DISC2.TXT')
        for _ in range(8):
            check('UCDD -mount MIX.MDM')
            check('MDMKEY 2')
            check('PROBE F:\\RAW.TXT')
            check('MDMKEY 3')
            check('PROBE F:\\RAW.TXT')
            check('MDMKEY 0')
            check('PROBE F:\\RAW.TXT')
            check('UCDD -unmount MIX.MDM')
        check('UCDD -mount LIST.MDM')
        check('UCDD -mount DISC2.ISO -drive F')
        check('MDMKEY 1')
        check('PROBE F:\\DISC2.TXT')
        check('UCDD -unmount -drive F')
        check('UCDD -mount LIST.MDM -drive F')
        check('UCDD -unmount LIST.MDM -drive F')
        check('UCDD -mount LISTS\\REL.MDM')
        check('MDMKEY 2 R')
        check('PROBE F:\\RAW.TXT')
        check('UCDD -unmount LISTS\\REL.MDM')
        check('MDMMEM CHECK')
    for n, (command, ok) in enumerate(checks):
        commands += [f'ECHO Test {n}: {command}', command,
                     f'IF {"" if ok else "NOT "}ERRORLEVEL {246 if command.startswith("SHSUCDX") else 1} GOTO FAIL']
    commands += ['ECHO MDM TEST PASS', 'PASS', ':FAIL', 'ECHO MDM TEST FAIL', 'FAIL']
    disk.add('AUTOEXEC.BAT', ('\r\n'.join(commands)+'\r\n').encode())
    return disk


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emulator', type=Path, required=True)
    parser.add_argument('--audio', action='store_true')
    parser.add_argument('--load-high', action='store_true')
    parser.add_argument('--no-xms', action='store_true')
    parser.add_argument('--ems', action='store_true')
    args = parser.parse_args()
    if args.audio and args.no_xms:
        parser.error('--audio requires XMS')
    if args.ems and not args.audio:
        parser.error('--ems requires --audio')
    out = ROOT/'.local/mdm'/('audio' if args.audio else 'data')
    out = out/(('no-xms' if args.no_xms else 'high' if args.load_high else 'low')+('-ems' if args.ems else ''))
    out.mkdir(parents=True, exist_ok=True)
    disk = fixture(args.audio, args.load_high, not args.no_xms, ems=args.ems)
    path = out/'test.img'
    path.write_bytes(disk.image)
    invocation = [str(args.emulator.resolve()), '--cpu', '386', '--interpreter',
                  '--memory-mib', '16', '--headless-boot-hdd', str(path), '--cycles', '1500000000']
    result = subprocess.run(invocation, capture_output=True, text=True, timeout=180)
    log = result.stdout+result.stderr
    (out/'guest.log').write_text(log)
    passed = result.returncode == 0 and 'TestExit { code: 0 }' in log
    (out/'result.json').write_text(json.dumps({'command': invocation, 'passed': passed,
        'driver_sha256': hashlib.sha256((ROOT/'build/UCDD.EXE').read_bytes()).hexdigest(),
        'disk_sha256': hashlib.sha256(disk.image).hexdigest()}, indent=2))
    print(log[-5000:])
    if not passed:
        raise SystemExit('The MDM test failed.')


if __name__ == '__main__':
    main()
