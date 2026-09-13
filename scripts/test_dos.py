"""Run guest tests on a disposable FreeDOS disk in interpreted 386 mode."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import zipfile
import zlib

from dos_disk import Fat16

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / '.local' / 'downloads'
RUN = ROOT / '.local' / 'test'
FREEDOS_SHA256 = '857dcd2ebf9d3d094320154db5fb5b830acba6fb98f981a95a0ca7ab3350338b'
SHSUCD_SHA256 = '0a91342c535280a44165f291df06c1eedfa7a7ca58b323b393ef26b809695e86'


def both16(value):
    return struct.pack('<H', value) + struct.pack('>H', value)


def both32(value):
    return struct.pack('<I', value) + struct.pack('>I', value)


def record(name, sector, size, directory=False):
    result = bytearray(33 + len(name) + (len(name) % 2 == 0))
    result[0] = len(result)
    result[2:10] = both32(sector)
    result[10:18] = both32(size)
    result[18:25] = bytes([126, 9, 13, 0, 0, 0, 0])
    result[25] = 2 if directory else 0
    result[28:32] = both16(1)
    result[32] = len(name)
    result[33:33 + len(name)] = name
    return result


def make_iso(name, sectors=22):
    image = bytearray(sectors * 2048)
    pvd = bytearray(2048)
    pvd[:7] = b'\x01CD001\x01'
    pvd[8:40] = b'UCDD TEST'.ljust(32)
    pvd[40:72] = name.encode().ljust(32)
    pvd[80:88] = both32(sectors)
    pvd[120:124] = both16(1)
    pvd[124:128] = both16(1)
    pvd[128:132] = both16(2048)
    pvd[132:140] = both32(10)
    struct.pack_into('<I', pvd, 140, 18)
    struct.pack_into('>I', pvd, 148, 19)
    pvd[156:190] = record(b'\0', 20, 2048, True)
    pvd[881] = 1
    image[16 * 2048:17 * 2048] = pvd
    image[17 * 2048:17 * 2048 + 7] = b'\xffCD001\x01'
    image[18 * 2048:18 * 2048 + 10] = b'\x01\0' + struct.pack('<IH', 20, 1) + b'\0\0'
    image[19 * 2048:19 * 2048 + 10] = b'\x01\0' + struct.pack('>IH', 20, 1) + b'\0\0'
    content = b'uCDD test file.\r\n'
    entries = record(b'\0', 20, 2048, True) + record(b'\1', 20, 2048, True)
    entries += record((name + '.TXT;1').encode(), 21, len(content))
    image[20 * 2048:20 * 2048 + len(entries)] = entries
    image[21 * 2048:21 * 2048 + len(content)] = content
    for sector in range(22, sectors):
        image[sector * 2048:(sector + 1) * 2048] = bytes([sector % 256]) * 2048
    return image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--emulator', type=Path, required=True)
    parser.add_argument('--baseline', action='store_true')
    parser.add_argument('--quake-bin', type=Path)
    parser.add_argument('--single-unit', action='store_true')
    parser.add_argument('--load-high', action='store_true')
    args = parser.parse_args()
    if args.load_high and (args.baseline or not args.single_unit):
        parser.error('--load-high requires --single-unit without --baseline')
    archive = (CACHE / 'FD14-LiteUSB.zip').read_bytes()
    if hashlib.sha256(archive).hexdigest() != FREEDOS_SHA256:
        raise SystemExit('The FreeDOS archive hash is incorrect.')
    with zipfile.ZipFile(CACHE / 'FD14-LiteUSB.zip') as source:
        disk = Fat16(source.read('FD14LITE.img'))
    kernel, command = disk.read('KERNEL.SYS'), disk.read('COMMAND.COM')
    disk.clear()
    disk.add('KERNEL.SYS', kernel)
    disk.add('COMMAND.COM', command)
    config = 'DOS=LOW\r\nFILES=40\r\nBUFFERS=10\r\nLASTDRIVE=Z\r\nSHELL=C:\\COMMAND.COM C:\\ /E:512 /P\r\n'
    if args.load_high:
        from test_audio import JEMM_SHA256
        jemm = CACHE / 'JemmB_v586.zip'
        if hashlib.sha256(jemm.read_bytes()).hexdigest() != JEMM_SHA256:
            raise SystemExit('The Jemm archive hash is incorrect.')
        with zipfile.ZipFile(jemm) as source:
            disk.add('JEMMEX.EXE', source.read('JEMMEX.EXE'))
        config = 'DEVICE=C:\\JEMMEX.EXE NOEMS\r\n' + config.replace('DOS=LOW', 'DOS=HIGH,UMB')
    disk.add('FDCONFIG.SYS', config.encode())
    for name in ('PROBE.COM', 'PACKETS.COM', 'CUEPACK.COM', 'CDSTATE.COM', 'FILECRC.COM', 'PASS.COM', 'FAIL.COM'):
        disk.add(name, (ROOT / 'build' / name).read_bytes())
    disk.add('ONE.ISO', make_iso('ONE'))
    disk.add('TWO.ISO', make_iso('TWO'))
    disk.add('BIG.ISO', make_iso('BIG', 128))
    raw = b''.join(bytes(16) + make_iso('BIG', 128)[i:i+2048] + bytes(288)
                   for i in range(0, 128*2048, 2048))
    disk.add('BIG.BIN', raw + bytes(2352*150))
    cue = 'FILE "BIG.BIN" BINARY\r\n TRACK 01 MODE1/2352\r\n INDEX 01 00:00:00\r\n TRACK 02 AUDIO\r\n INDEX 01 00:01:53\r\n'
    disk.add('BIG.CUE', cue.encode())
    disk.add('BADCUE.CUE', cue.replace('00:01:53', '00:00:01').encode())
    disk.add('PREGAP.BIN', bytes(150*2352)+raw+bytes(2352*150))
    disk.add('PREGAP.CUE', cue.replace('BIG.BIN', 'PREGAP.BIN').replace(
        '00:00:00', '00:02:00').replace('00:01:53', '00:03:53').encode())
    bad_cues = [cue.replace('TRACK 02', 'TRACK 03'), cue.replace('BINARY', 'WAVE'),
                cue.replace('00:01:53', '00:60:00'), cue.replace(' INDEX 01 00:01:53\r\n', ''),
                cue+' FLAGS DCP\r\n', cue+' PREGAP 00:02:00\r\n', cue+' FILE "BIG.BIN" BINARY\r\n']
    for number, text in enumerate(bad_cues):
        disk.add(f'BAD{number}.CUE', text.encode())
    bad_root = make_iso('BADROOT')
    bad_root[16 * 2048 + 158:16 * 2048 + 166] = both32(1000)
    disk.add('BADROOT.ISO', bad_root)
    boot_iso = make_iso('BOOT')
    boot_iso[17 * 2048:18 * 2048] = boot_iso[16 * 2048:17 * 2048]
    boot_iso[16 * 2048] = 0
    boot_iso[18 * 2048:18 * 2048+7] = b'\xffCD001\x01'
    boot_iso.extend(bytes(2048))
    boot_iso[17 * 2048+80:17 * 2048+88] = both32(23)
    boot_iso[17 * 2048+140:17 * 2048+144] = struct.pack('<I', 19)
    boot_iso[17 * 2048+148:17 * 2048+152] = struct.pack('>I', 22)
    boot_iso[19 * 2048:19 * 2048+10] = b'\x01\0' + struct.pack('<IH', 20, 1) + b'\0\0'
    boot_iso[22 * 2048:22 * 2048+10] = b'\x01\0' + struct.pack('>IH', 20, 1) + b'\0\0'
    disk.add('BOOT.ISO', boot_iso)
    same_a = make_iso('SAME')
    same_b = make_iso('SAME')
    same_b[21 * 2048:21 * 2048+17] = b'Different file.\r\n'
    disk.add('SAMEA.ISO', same_a)
    disk.add('SAMEB.ISO', same_b)
    suite_path = CACHE / 'shcd3-7.zip'
    if hashlib.sha256(suite_path.read_bytes()).hexdigest() != SHSUCD_SHA256:
        raise SystemExit('The SHSUCD archive hash is incorrect.')
    with zipfile.ZipFile(suite_path) as suite:
        names = {Path(name).name.lower(): name for name in suite.namelist()}
        for name in ('shsucdx.com', 'shsucdhd.exe'):
            disk.add(name, suite.read(names[name]))
    commands = ['@ECHO OFF', 'PROMPT $P$G', 'CDSTATE', 'IF ERRORLEVEL 1 GOTO FAIL',
                'PROBE absent', 'IF ERRORLEVEL 1 GOTO FAIL']
    if args.baseline:
        commands += ['SHSUCDHD /F:C:\\ONE.ISO', 'IF ERRORLEVEL 1 GOTO FAIL',
                     'SHSUCDX /D:SHSU-CDH /L:D', 'IF ERRORLEVEL 246 GOTO FAIL',
                     'PROBE D:\\ONE.TXT', 'IF ERRORLEVEL 1 GOTO FAIL']
    else:
        for name in ('UCDDRV.EXE', 'UCDD.EXE'):
            disk.add(name, (ROOT / 'build' / name).read_bytes())
        disk.add('BAD.ISO', b'This is not a disc image.')
        install = 'UCDDRV' if args.single_unit else 'UCDDRV -units 2'
        if args.load_high:
            install = 'LH ' + install
        commands += [install, 'IF ERRORLEVEL 1 GOTO FAIL',
                     'SHSUCDX /D:UCDD0001 /L:F', 'IF ERRORLEVEL 246 GOTO FAIL']
        full_crc = zlib.crc32(b'All uCDD drives are in use.\r\n')
        same_a_crc = zlib.crc32(b'uCDD test file.\r\n')
        same_b_crc = zlib.crc32(b'Different file.\r\n')
        checks = [
            ('UCDD -unmount', False),
            ('UCDD -mount C:\\ONE.ISO', True),
            ('PROBE F:\\ONE.TXT', True),
            ('UCDD -mount C:\\BADROOT.ISO -drive F', False),
            ('PROBE F:\\ONE.TXT', True),
            ('PROBE !G:\\ONE.TXT', True),
            ('UCDD -mount C:\\TWO.ISO', True),
            ('PROBE G:\\TWO.TXT', True),
            ('UCDD -mount C:\\ONE.ISO >C:\\FULL.TXT', False),
            (f'FILECRC C:\\FULL.TXT {full_crc:08X}', True),
            ('PROBE F:\\ONE.TXT', True),
            ('PROBE G:\\TWO.TXT', True),
            ('UCDD -mount C:\\BAD.ISO -drive F', False),
            ('PROBE F:\\ONE.TXT', True),
            ('UCDD -mount C:\\MISSING.ISO -drive F', False),
            ('PROBE F:\\ONE.TXT', True),
            ('UCDD -mount C:\\TWO.ISO -drive F', True),
            ('PROBE F:\\TWO.TXT', True),
            ('PROBE !F:\\ONE.TXT', True),
            ('UCDD -unmount', True),
            ('PROBE !F:\\TWO.TXT', True),
            ('PROBE G:\\TWO.TXT', True),
            ('UCDD -mount C:\\ONE.ISO', True),
            ('PROBE F:\\ONE.TXT', True),
            ('UCDD -unmount -drive G', True),
            ('PROBE !G:\\TWO.TXT', True),
            ('PROBE F:\\ONE.TXT', True),
            ('UCDD -mount C:\\ONE.ISO -drive C', False),
            ('UCDD -mount F:\\ONE.TXT -drive G', False),
            ('UCDD -unmount -drive F', True),
            ('UCDD -unmount', False),
            ('UCDD -mount C:\\BOOT.ISO -drive F', True),
            ('PROBE F:\\BOOT.TXT', True),
            ('UCDD -mount C:\\BIG.ISO -drive F', True),
        ]
        if args.single_unit:
            checks = [
                ('UCDD -unmount', False),
                ('UCDD -mount C:\\ONE.ISO', True),
                ('PROBE F:\\ONE.TXT', True),
                ('UCDD -mount C:\\TWO.ISO >C:\\FULL.TXT', False),
                (f'FILECRC C:\\FULL.TXT {full_crc:08X}', True),
                ('UCDD -mount C:\\BADROOT.ISO -drive F', False),
                ('PROBE F:\\ONE.TXT', True),
                ('UCDD -unmount', True),
                ('PROBE !F:\\ONE.TXT', True),
                ('UCDD -mount C:\\TWO.ISO', True),
                ('PROBE F:\\TWO.TXT', True),
                ('UCDD -mount C:\\BIG.ISO -drive F', True),
            ]
        for _ in range(24):
            checks += [('UCDD -mount C:\\BAD.ISO -drive F', False),
                       ('UCDD -mount C:\\BIG.ISO -drive F', True)]
        checks += [('UCDD -mount C:\\SAMEA.ISO -drive F', True),
                   (f'FILECRC F:\\SAME.TXT {same_a_crc:08X}', True),
                   ('UCDD -mount C:\\SAMEB.ISO -drive F', True),
                   (f'FILECRC F:\\SAME.TXT {same_b_crc:08X}', True),
                   ('UCDD -mount C:\\BIG.ISO -drive F', True),
                   ('PACKETS H' if args.load_high else 'PACKETS', True)]
        for number, (command, success) in enumerate(checks, 1):
            commands += [f'ECHO Test {number}: {command}', command,
                         'IF ERRORLEVEL 1 GOTO FAIL' if success else 'IF NOT ERRORLEVEL 1 GOTO FAIL']
        commands += ['UCDD -mount C:\\BIG.CUE -drive F', 'IF ERRORLEVEL 1 GOTO FAIL',
                     'CUEPACK', 'IF ERRORLEVEL 1 GOTO FAIL',
                     'PROBE F:\\BIG.TXT', 'IF ERRORLEVEL 1 GOTO FAIL',
                     'UCDD -mount C:\\BADCUE.CUE -drive F', 'IF NOT ERRORLEVEL 1 GOTO FAIL',
                     'PROBE F:\\BIG.TXT', 'IF ERRORLEVEL 1 GOTO FAIL',
                     'UCDD -mount C:\\PREGAP.CUE -drive F', 'IF ERRORLEVEL 1 GOTO FAIL',
                     'CUEPACK', 'IF ERRORLEVEL 1 GOTO FAIL',
                     'PROBE F:\\BIG.TXT', 'IF ERRORLEVEL 1 GOTO FAIL']
        for number in range(len(bad_cues)):
            commands += [f'UCDD -mount C:\\BAD{number}.CUE -drive F', 'IF NOT ERRORLEVEL 1 GOTO FAIL',
                         'PROBE F:\\BIG.TXT', 'IF ERRORLEVEL 1 GOTO FAIL']
    if args.quake_bin:
        if args.baseline:
            raise SystemExit('Use the Quake check with the uCDD test sequence.')
        with args.quake_bin.open('rb') as source:
            source.seek(16 * 2352 + 16)
            pvd = source.read(2048)
            if pvd[:7] != b'\x01CD001\x01':
                raise SystemExit('The Quake fixture must use MODE1/2352 sectors.')
            sectors = struct.unpack_from('<I', pvd, 80)[0]
            source.seek(0)
            raw = source.read(sectors * 2352)
        if len(raw) != sectors * 2352:
            raise SystemExit('The Quake data track is incomplete.')
        cooked = b''.join(raw[offset + 16:offset + 2064] for offset in range(0, len(raw), 2352))
        root = struct.unpack_from('<I', pvd, 158)[0] * 2048
        root_size = struct.unpack_from('<I', pvd, 166)[0]
        entries = []
        offset = root
        while offset < root + root_size:
            length = cooked[offset]
            if not length:
                offset = (offset // 2048 + 1) * 2048
                continue
            entry = cooked[offset:offset + length]
            name = entry[33:33 + entry[32]].decode('ascii').split(';')[0]
            if not entry[25] & 2:
                entries.append((struct.unpack_from('<I', entry, 10)[0], name,
                                struct.unpack_from('<I', entry, 2)[0] * 2048))
            offset += length
        size, name, offset = max(entries)
        crc = zlib.crc32(cooked[offset:offset + size])
        disk.add('QUAKE.ISO', cooked)
        commands += ['UCDD -mount C:\\QUAKE.ISO -drive F', 'IF ERRORLEVEL 1 GOTO FAIL',
                     f'FILECRC F:\\{name} {crc:08X}', 'IF ERRORLEVEL 1 GOTO FAIL']
        print(f'Quake data-only check: {name}, {size} bytes, CRC32 {crc:08X}')
    commands += ['ECHO UCDD TEST PASS', 'PASS', ':FAIL', 'ECHO UCDD TEST FAIL', 'FAIL']
    disk.add('AUTOEXEC.BAT', ('\r\n'.join(commands) + '\r\n').encode())
    RUN.mkdir(parents=True, exist_ok=True)
    name = ('baseline' if args.baseline else 'ucdd-high' if args.load_high
            else 'ucdd-single' if args.single_unit else 'ucdd')
    image = RUN / (name + '.img')
    image.write_bytes(disk.image)
    invocation = [str(args.emulator.resolve()), '--cpu', '386', '--interpreter',
                  '--memory-mib', '16', '--headless-boot-hdd', str(image),
                  '--cycles', '4000000000' if args.quake_bin else '800000000']
    result = subprocess.run(invocation, capture_output=True, text=True, timeout=180)
    log = result.stdout + result.stderr
    (RUN / (image.stem + '.log')).write_text(log, encoding='utf-8')
    evidence = {
        'command': invocation,
        'emulator_sha256': hashlib.sha256(args.emulator.read_bytes()).hexdigest(),
        'freedos_archive_sha256': FREEDOS_SHA256,
        'shsucd_archive_sha256': SHSUCD_SHA256,
        'program_sha256': {name: hashlib.sha256((ROOT / 'build' / name).read_bytes()).hexdigest()
                          for name in ('UCDDRV.EXE', 'UCDD.EXE')},
        'disk_sha256': hashlib.sha256(disk.image).hexdigest(),
        'exit_code': result.returncode,
        'guest_passed': bool(re.search(r'stop: TestExit \{ code: 0 \}', log)),
    }
    (RUN / (image.stem + '.json')).write_text(json.dumps(evidence, indent=2) + '\n')
    print(log[-6000:])
    if result.returncode or not re.search(r'stop: TestExit \{ code: 0 \}', log):
        raise SystemExit('The DOS test failed. See the test log.')
    print('The DOS test passed.')


if __name__ == '__main__':
    main()
