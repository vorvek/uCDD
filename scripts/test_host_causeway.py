# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Prepare isolated Daggerfall extender tests from locally supplied files."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import time
import zipfile
import zlib

from dos_disk import Fat16
from test_dos import CACHE, FREEDOS_SHA256, ROOT, SHSUCD_SHA256
from test_audio import JEMM_SHA256


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def archive_file(name, expected, member):
    path = CACHE / name
    if digest(path) != expected:
        raise ValueError(f'The archive hash is incorrect: {name}')
    with zipfile.ZipFile(path) as archive:
        return archive.read(member)


def add_tree(disk, name, path, parent=0, overrides=None):
    overrides = overrides or {}
    children = sorted(path.iterdir(), key=lambda item: item.name.upper())
    children = [item for item in children if item.name.upper() != 'FALL_BAK.EXE']
    size = ((len(children)+2)*32 + disk.cluster_bytes-1)//disk.cluster_bytes*disk.cluster_bytes
    slot = next(offset for offset in range(disk.root, disk.root+disk.entries*32, 32)
                if disk.image[offset] == 0)
    cluster = disk.next_cluster
    disk.add(name, bytes(size), 0x10)
    entry = bytearray(disk.image[slot:slot+32])
    struct.pack_into('<I', entry, 28, 0)
    disk.image[slot:slot+32] = bytes(32)
    start = disk.data+(cluster-2)*disk.cluster_bytes
    for index, (label, target) in enumerate(((b'.          ', cluster), (b'..         ', parent))):
        dot = bytearray(32)
        dot[:11], dot[11] = label, 0x10
        struct.pack_into('<H', dot, 26, target)
        disk.image[start+index*32:start+(index+1)*32] = dot
    for index, child in enumerate(children, 2):
        if child.is_dir():
            item = add_tree(disk, child.name, child, cluster)
        else:
            disk.add(child.name, overrides.get(child.name.upper(), child.read_bytes()))
            item = disk.image[slot:slot+32]
            disk.image[slot:slot+32] = bytes(32)
        disk.image[start+index*32:start+(index+1)*32] = item
    return entry


def read_iso_root(path, name):
    with path.open('rb') as stream:
        stream.seek(16*2048)
        pvd = stream.read(2048)
        if pvd[:7] != b'\x01CD001\x01':
            raise ValueError('The image must contain 2048-byte ISO sectors.')
        lba, size = struct.unpack_from('<I', pvd, 158)[0], struct.unpack_from('<I', pvd, 166)[0]
        stream.seek(lba*2048)
        directory = stream.read(size)
        offset = 0
        while offset < size:
            length = directory[offset]
            if not length:
                offset = (offset//2048+1)*2048
                continue
            record = directory[offset:offset+length]
            if record[33:33+record[32]].split(b';')[0] == name.encode():
                stream.seek(struct.unpack_from('<I', record, 2)[0]*2048)
                return stream.read(struct.unpack_from('<I', record, 10)[0])
            offset += length
    raise ValueError('The CD test file is absent.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--game-dir', type=Path, required=True)
    parser.add_argument('--iso', type=Path, required=True)
    parser.add_argument('--host', type=Path, required=True)
    parser.add_argument('--capture', type=Path)
    parser.add_argument('--mouse-driver', type=Path)
    parser.add_argument('--variant', choices=('causeway', 'dos32a'), required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cpu', choices=('386', '486'), default='386')
    parser.add_argument('--steps', type=int, default=60000)
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--keys', default='')
    parser.add_argument('--mouse-events', default='', help='step:dx:dy:buttons events, separated by commas')
    parser.add_argument('--memory-mib', type=int, default=16)
    parser.add_argument('--hide-vcpi', action='store_true')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    executable = args.game_dir / ('FALL_bak.EXE' if args.variant == 'causeway' else 'FALL.EXE')
    signature = b'CauseWay DOS Extender v3.32' if args.variant == 'causeway' else b'DOS/32A -- DOS Extender'
    if signature not in executable.read_bytes():
        raise ValueError('The executable extender signature is incorrect.')
    disk = Fat16(archive_file('FD14-LiteUSB.zip', FREEDOS_SHA256, 'FD14LITE.img'))
    files = {name: disk.read(name) for name in ('KERNEL.SYS', 'COMMAND.COM')}
    files['JEMMEX.EXE'] = archive_file('JemmB_v586.zip', JEMM_SHA256, 'JEMMEX.EXE')
    files['SHSUCDX.COM'] = archive_file('shcd3-7.zip', SHSUCD_SHA256, 'shsucdx.com')
    files['MOUSE.COM'] = args.mouse_driver.read_bytes() if args.mouse_driver else archive_file('ctmouse.zip',
        'fd47069fb3d9559604dcaef34ca4f3705a7f2f2cff3e4b205e361b79f10a8200', 'BIN/CTMOUSE.EXE')
    files['UCDD.EXE'] = args.host.read_bytes()
    files['UCDD.CFG'] = b'uCDD\x01\x00\x20\x02'+bytes((7, 1, 5, 0))
    files['FDCONFIG.SYS'] = (b'DEVICE=C:\\JEMMEX.EXE NOEMS\r\nDOS=HIGH,UMB\r\nFILES=64\r\n'
                            b'LASTDRIVE=Z\r\nSHELL=C:\\COMMAND.COM C:\\ /E:1024 /P\r\n')
    crc = zlib.crc32(read_iso_root(args.iso, 'READ.ME'))
    commands = ['@ECHO OFF', 'SET BLASTER=A220 I5 D1 H5 T6', 'SET CAUSEWAY=DPMI',
                'LH MOUSE', 'IF ERRORLEVEL 1 GOTO FAIL', 'LH UCDD -install',
                'IF ERRORLEVEL 1 GOTO FAIL', 'SHSUCDX /D:UCDD0001 /L:F',
                'IF ERRORLEVEL 246 GOTO FAIL', 'UCDD -mount C:\\DISC.ISO',
                'IF ERRORLEVEL 1 GOTO FAIL', f'FILECRC F:\\READ.ME {crc:08X}',
                'IF ERRORLEVEL 1 GOTO FAIL', 'ECHO CD_READ_OK > CDREAD.TXT']
    if args.hide_vcpi:
        commands += ['HIDEVCPI', 'IF ERRORLEVEL 1 GOTO FAIL']
    commands += ['CD DAGGER', 'FALL.EXE Z.CFG', 'IF ERRORLEVEL 1 GOTO FAIL',
                'CD \\', f'FILECRC F:\\READ.ME {crc:08X}', 'IF ERRORLEVEL 1 GOTO FAIL',
                'PASS', ':FAIL', 'C:\\FAIL']
    files['AUTOEXEC.BAT'] = ('\r\n'.join(commands)+'\r\n').encode()
    for source, name, defines in [('tests/file_crc.asm', 'FILECRC.COM', []),
                                  ('tests/exit.asm', 'PASS.COM', []),
                                  ('tests/exit.asm', 'FAIL.COM', ['-DEXIT_CODE=1']),
                                  ('tests/hide_vcpi.asm', 'HIDEVCPI.COM', [])]:
        output = args.output/name
        subprocess.run(['nasm', '-f', 'bin', *defines, str(ROOT/source), '-o', str(output)], check=True)
        files[name] = output.read_bytes()
    disk = disk.empty_larger(1024)
    for name, data in files.items():
        disk.add(name, data)
    disk.add('DISC.ISO', args.iso.read_bytes())
    cfg = (args.game_dir/'Z.CFG').read_text()
    cfg = '\r\n'.join('path c:\\dagger\\arena2\\' if line.lower().startswith('path ') else
                      'pathcd f:\\dagger\\arena2\\' if line.lower().startswith('pathcd ') else line
                      for line in cfg.splitlines()
                      if not line.lower().startswith(('texturememory ', 'objmemsize ')))+'\r\n'
    hmi = (args.game_dir/'SB16/HMISET.CFG').read_bytes().replace(b'DeviceIRQ   = 7', b'DeviceIRQ   = 5')
    entry = add_tree(disk, 'DAGGER', args.game_dir,
                     overrides={'FALL.EXE': executable.read_bytes(), 'Z.CFG': cfg.encode(), 'HMISET.CFG': hmi})
    slot = next(offset for offset in range(disk.root, disk.root+disk.entries*32, 32) if disk.image[offset] == 0)
    disk.image[slot:slot+32] = entry
    stem = args.output / f'daggerfall-{args.variant}-{args.cpu}'
    image = stem.with_suffix('.img')
    image.write_bytes(disk.image)
    evidence = dict(variant=args.variant, executable_sha256=digest(executable), iso_sha256=digest(args.iso),
                    host_sha256=digest(args.host), disk_sha256=digest(image), cpu=args.cpu,
                    backend='interpreter', memory_mib=args.memory_mib, hidden_vcpi=args.hide_vcpi,
                    cd_test_crc32=f'{crc:08X}', commands=commands,
                    config_changes=['Paths use local C: and uCDD F:.', 'Digital IRQ is 5.',
                                    'Remove collection texturememory and objmemsize overrides.'])
    stem.with_suffix('.json').write_text(json.dumps(evidence, indent=2)+'\n')
    del disk
    print(image, flush=True)
    if args.capture:
        live = args.output / f'live-{args.variant}-{args.cpu}'
        live.mkdir(exist_ok=True)
        for name in ('step.txt', 'input.txt'):
            (live/name).unlink(missing_ok=True)
        environment = dict(os.environ, UCDD_TEST_CPU=args.cpu, UCDD_TEST_STEPS=str(args.steps),
                           UCDD_TEST_MEMORY_MIB=str(args.memory_mib),
                           UCDD_TEST_DISK_EXPORT='1', UCDD_TEST_MEMORY_DUMP=str(stem.with_suffix('.memory.bin')),
                           UCDD_TEST_MEMORY_BYTES=str(args.memory_mib*1024*1024), UCDD_TEST_FRAME=str(stem.with_suffix('.ppm')),
                           UCDD_TEST_LIVE=str(live), UCDD_TEST_KEYS=args.keys)
        command = [str(args.capture), str(image), str(stem.with_suffix('.wav'))]
        mouse_events = [tuple(map(int, event.split(':'))) for event in args.mouse_events.split(',') if event]
        if any(len(event) != 4 for event in mouse_events):
            raise ValueError('Each mouse event needs four fields.')
        evidence.update(command=command, capture_sha256=digest(args.capture), steps=args.steps,
                        keys=args.keys, mouse_events=list(mouse_events), delivered_mouse_events=[])
        with stem.with_suffix('.log').open('w') as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, env=environment)
            deadline = time.monotonic()+args.timeout
            try:
                while process.poll() is None:
                    if time.monotonic() > deadline:
                        raise subprocess.TimeoutExpired(command, args.timeout)
                    try:
                        step = int((live/'step.txt').read_text())
                    except (OSError, ValueError):
                        step = -1
                    if mouse_events and step >= mouse_events[0][0] and not (live/'input.txt').exists():
                        event = mouse_events.pop(0)
                        (live/'input.txt').write_text(f'mouse {event[1]} {event[2]} {event[3]}\n')
                        evidence['delivered_mouse_events'].append([step, *event[1:]])
                    time.sleep(0.02)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
                evidence['returncode'] = process.returncode
                stem.with_suffix('.json').write_text(json.dumps(evidence, indent=2)+'\n')
        log_text = stem.with_suffix('.log').read_text(errors='replace')
        evidence['passed'] = evidence['returncode'] == 0 and 'stop: TestExit { code: 0 }' in log_text
        stem.with_suffix('.json').write_text(json.dumps(evidence, indent=2)+'\n')
        print(log_text)
        if not evidence['passed']:
            raise SystemExit(1)


if __name__ == '__main__':
    main()
