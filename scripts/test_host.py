# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Check the uCDD protected-mode monitor without a DPMI host."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import urllib.request
import zipfile
import zlib

from build import assemble, assemble_resident_host
from dos_disk import Fat16
from test_dos import ROOT, CACHE, FREEDOS_SHA256, SHSUCD_SHA256
from test_audio import JEMM_SHA256, build_capture, verify_capture
from build_audio import write_samples


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--emulator', type=Path, required=True)
    parser.add_argument('--audio', action='store_true')
    parser.add_argument('--izarra-source', type=Path)
    parser.add_argument('--no-vcpi', action='store_true')
    parser.add_argument('--load-high', action='store_true')
    parser.add_argument('--alternate', action='store_true')
    parser.add_argument('--no-delivery', action='store_true')
    parser.add_argument('--external', action='store_true')
    parser.add_argument('--client', choices=('core', 'api', 'pic', 'revoked'), default='core')
    parser.add_argument('--game', choices=('quake', 'tomb', 'u8'))
    parser.add_argument('--game-dir', type=Path)
    parser.add_argument('--game-exe', type=Path)
    parser.add_argument('--mouse-driver', type=Path)
    parser.add_argument('--cpu', choices=('386', '486', '586'), default='386')
    parser.add_argument('--cd-bin', type=Path)
    parser.add_argument('--cd-cue', type=Path)
    parser.add_argument('--resident', action='store_true')
    parser.add_argument('--legacy-host', action='store_true')
    args = parser.parse_args()
    if args.game:
        if not args.game_dir:
            parser.error('--game requires --game-dir')
        args.external = True
    if bool(args.cd_bin) != bool(args.cd_cue) or (args.cd_bin and not args.game):
        parser.error('--cd-bin and --cd-cue require a game and each other')
    if args.resident and not args.cd_bin:
        parser.error('--resident requires a CD image')
    if args.legacy_host and not args.resident:
        parser.error('--legacy-host requires --resident')
    if args.no_vcpi and (args.audio or args.load_high):
        parser.error('--no-vcpi cannot use --audio or --load-high')
    if (args.alternate or args.no_delivery) and not args.audio:
        parser.error('--alternate and --no-delivery require --audio')
    assemble('tests/host_monitor.asm', 'HOSTTEST.COM', ('NO_VCPI=1',) if args.no_vcpi else ())
    assemble('tests/setup_lifecycle.asm', 'HOSTLIFE.COM', ('CHILD_NAME="HOSTTEST.COM"',))
    if args.external:
        child = {'quake': 'QUAKE.EXE', 'tomb': 'TOMB.EXE', 'u8': 'U8.EXE'}.get(args.game, 'DCLIENT.COM')
        tail = ' -heapsize 8192 -nosound -nocdaudio -noserial -noipx -noudp -condebug' if args.game == 'quake' else ''
        assemble('tests/host_external.asm', 'HOSTEXT.COM', (f'CHILD_NAME="{child}"', f'CHILD_TAIL="{tail}"',
                 f'CHILD_RUNS={1 if args.game else 2}', f'CHILD_EXIT_CODE={1 if args.client == "revoked" else 0}'))
        client = {'core': 'dpmi', 'api': 'api', 'pic': 'pic', 'revoked': 'dpmi'}[args.client]
        assemble(f'tests/host_{client}_client.asm', 'DCLIENT.COM',
                 ('CALLBACK_REVOKED=1',) if args.client == 'revoked' else ())
    if args.load_high:
        assemble('tests/host_monitor.asm', 'HOSTHI.COM', ('HIGH_HOST=1',))
    if args.audio:
        if not args.izarra_source:
            parser.error('--audio requires --izarra-source')
        write_samples()
        assemble('tests/host_audio.asm', 'HOSTAUD.COM', ('NO_DELIVERY=1',) if args.no_delivery else ())
        assemble('tests/setup_lifecycle.asm', 'AUDLIFE.COM', ('CHILD_NAME="HOSTAUD.COM"',))
    assemble('tests/exit.asm', 'PASS.COM')
    assemble('tests/exit.asm', 'FAIL.COM', ('EXIT_CODE=1',))
    for name, expected in (('FD14-LiteUSB.zip', FREEDOS_SHA256), ('JemmB_v586.zip', JEMM_SHA256)):
        if hashlib.sha256((CACHE/name).read_bytes()).hexdigest() != expected:
            raise ValueError(f'The archive hash is incorrect: {name}')
    with zipfile.ZipFile(CACHE/'FD14-LiteUSB.zip') as archive:
        disk = Fat16(archive.read('FD14LITE.img'))
    files = {name: disk.read(name) for name in ('KERNEL.SYS', 'COMMAND.COM')}
    if not args.no_vcpi:
        with zipfile.ZipFile(CACHE/'JemmB_v586.zip') as archive:
            files['JEMMEX.EXE'] = archive.read('JEMMEX.EXE')
    for name in ('HOSTTEST.COM', 'HOSTLIFE.COM', 'PASS.COM', 'FAIL.COM'):
        files[name] = (ROOT/'build'/name).read_bytes()
    if args.audio:
        files['HOSTAUD.COM'] = (ROOT/'build/HOSTAUD.COM').read_bytes()
        files['AUDLIFE.COM'] = (ROOT/'build/AUDLIFE.COM').read_bytes()
        files['UCDD.CFG'] = b'uCDD\x01\x00\x20\x02'+bytes((7, 3, 6, 0) if args.alternate else (5, 1, 5, 0))
    if args.external:
        for name in ('HOSTEXT.COM', 'DCLIENT.COM'):
            files[name] = (ROOT/'build'/name).read_bytes()
    if args.game:
        files[child] = (args.game_exe or args.game_dir/child).read_bytes()
        if args.game == 'tomb':
            files['DOS4GW.EXE'] = (args.game_dir/'DOS4GW.EXE').read_bytes()
            files['TOMBPATH.TXT'] = b'C:\\\r\n'
        elif args.game == 'u8':
            if args.mouse_driver:
                files['MOUSE.EXE'] = args.mouse_driver.read_bytes()
            else:
                mouse = CACHE/'ctmouse.zip'
                if not mouse.exists():
                    urllib.request.urlretrieve('https://www.ibiblio.org/pub/micro/pc-stuff/freedos/'
                                               'files/repositories/1.4/base/ctmouse.zip', mouse)
                if hashlib.sha256(mouse.read_bytes()).hexdigest() != 'fd47069fb3d9559604dcaef34ca4f3705a7f2f2cff3e4b205e361b79f10a8200':
                    raise ValueError('The mouse driver archive hash is incorrect.')
                with zipfile.ZipFile(mouse) as archive:
                    files['MOUSE.EXE'] = archive.read('BIN/CTMOUSE.EXE')
    if args.cd_bin:
        if args.resident:
            if args.legacy_host:
                from test_audio_pm import HDPMI_SHA256
                host = CACHE/'SBEMU-beta6.zip'
                if hashlib.sha256(host.read_bytes()).hexdigest() != HDPMI_SHA256:
                    raise ValueError('The host archive hash is incorrect.')
                with zipfile.ZipFile(host) as archive:
                    files['HDPMI32I.EXE'] = archive.read('SBEMU/HDPMI32i.EXE')
                assemble('src/ucdd.asm', 'UCDD.EXE', ('RESIDENT_AUDIO=1',), exe=True)
            else:
                assemble_resident_host()
            files['UCDD.EXE'] = (ROOT/'build/UCDD.EXE').read_bytes()
            files['UCDD.CFG'] = b'uCDD\x01\x00\x20\x02'+bytes((7, 1, 5, 0))
        else:
            assemble('src/ucdd.asm', 'CDDATA.EXE', exe=True)
            files['UCDD.EXE'] = (ROOT/'build/CDDATA.EXE').read_bytes()
        archive_path = CACHE/'shcd3-7.zip'
        if hashlib.sha256(archive_path.read_bytes()).hexdigest() != SHSUCD_SHA256:
            raise ValueError('The SHSUCDX archive hash is incorrect.')
        with zipfile.ZipFile(archive_path) as archive:
            files['SHSUCDX.COM'] = archive.read('shsucdx.com')
        files['DISC.BIN'] = args.cd_bin.read_bytes()
        lines = args.cd_cue.read_text().splitlines()
        files['DISC.CUE'] = ('\r\n'.join('FILE "DISC.BIN" BINARY' if line.lstrip().startswith('FILE ') else line
                              for line in lines if not line.lstrip().startswith(('FLAGS ', 'PREGAP ')))+'\r\n').encode()
        if args.game == 'u8':
            assemble('tests/file_crc.asm', 'FILECRC.COM')
            files['FILECRC.COM'] = (ROOT/'build/FILECRC.COM').read_bytes()
            image = files['DISC.BIN']
            root = image[16*2352+16+156:16*2352+16+190]
            lba = struct.unpack_from('<I', root, 2)[0]
            size = struct.unpack_from('<I', root, 10)[0]
            directory = b''.join(image[n*2352+16:n*2352+2064]
                                 for n in range(lba, lba+(size+2047)//2048))
            offset = 0
            while offset < size:
                length = directory[offset]
                if not length:
                    offset = (offset//2048+1)*2048
                    continue
                record = directory[offset:offset+length]
                if record[33:33+record[32]].split(b';')[0] == b'INSTALL.BAT':
                    lba = struct.unpack_from('<I', record, 2)[0]
                    size = struct.unpack_from('<I', record, 10)[0]
                    content = b''.join(image[n*2352+16:n*2352+2064]
                                       for n in range(lba, lba+(size+2047)//2048))[:size]
                    cd_crc = zlib.crc32(content)
                    break
                offset += length
            else:
                raise ValueError('The CD test file is absent.')
    files['FDCONFIG.SYS'] = (b'DEVICE=C:\\JEMMEX.EXE NOEMS\r\nDOS=HIGH,UMB\r\nFILES=40\r\n'
                            b'SHELL=C:\\COMMAND.COM C:\\ /E:512 /P\r\n')
    if args.game == 'u8':
        files['FDCONFIG.SYS'] = files['FDCONFIG.SYS'].replace(b'FILES=40', b'FILES=64')
    if args.no_vcpi:
        files['FDCONFIG.SYS'] = files['FDCONFIG.SYS'].replace(b'DEVICE=C:\\JEMMEX.EXE NOEMS\r\n', b'').replace(b'DOS=HIGH,UMB', b'DOS=LOW')
    commands = ['@ECHO OFF', 'SET BLASTER=A220 I5 D1 H5 T6', 'HOSTLIFE', 'IF ERRORLEVEL 1 GOTO FAIL']
    if args.game == 'u8':
        commands += ['LH MOUSE', 'IF ERRORLEVEL 1 GOTO FAIL']
    if args.cd_bin:
        files['FDCONFIG.SYS'] += b'LASTDRIVE=Z\r\n'
        if args.legacy_host:
            commands += ['HDPMI32I -r', 'IF ERRORLEVEL 3 GOTO FAIL']
        commands += ['LH UCDD -install', 'IF ERRORLEVEL 1 GOTO FAIL', 'SHSUCDX /D:UCDD0001 /L:F',
                     'IF ERRORLEVEL 246 GOTO FAIL', 'UCDD -mount C:\\DISC.CUE', 'IF ERRORLEVEL 1 GOTO FAIL']
    if args.external:
        if args.game == 'u8' and args.cd_bin:
            commands += ['COPY F:\\INSTALL.BAT C:\\CDCHECK.BAT >NUL', 'IF ERRORLEVEL 1 GOTO FAIL',
                         f'FILECRC C:\\CDCHECK.BAT {cd_crc:08X}', 'IF ERRORLEVEL 1 GOTO FAIL']
        commands += [child if args.resident else 'HOSTEXT',
                     'IF ERRORLEVEL 1 GOTO FAIL']
        if args.game == 'u8' and args.cd_bin:
            commands += ['COPY F:\\INSTALL.BAT C:\\CDCHECK2.BAT >NUL', 'IF ERRORLEVEL 1 GOTO FAIL',
                         f'FILECRC C:\\CDCHECK2.BAT {cd_crc:08X}', 'IF ERRORLEVEL 1 GOTO FAIL']
    if args.load_high:
        files['HOSTHI.COM'] = (ROOT/'build/HOSTHI.COM').read_bytes()
        commands += ['LH HOSTHI', 'IF ERRORLEVEL 1 GOTO FAIL']
    if args.audio:
        commands += ['AUDLIFE', 'IF ERRORLEVEL 1 GOTO FAIL']
    commands += ['PASS', ':FAIL', 'FAIL']
    files['AUTOEXEC.BAT'] = ('\r\n'.join(commands)+'\r\n').encode()
    directories = {}
    if args.game:
        disk = disk.empty_larger(1024 if args.cd_bin and args.game != 'u8' else 128)
        if args.game == 'quake':
            directories['ID1'] = {p.name: p.read_bytes() for p in (args.game_dir/'ID1').iterdir()
                                  if p.name.upper() in ('PAK0.PAK', 'PAK1.PAK')}
            directories['ID1']['AUTOEXEC.CFG'] = b'echo UCDD_HOST_STARTED\ntoggleconsole\nquit\n'
        elif args.game == 'tomb':
            for name in ('SETTINGS.DAT', 'HMISET.CFG', 'HMIDRV.386', 'HMIDET.386'):
                files[name] = (args.game_dir/name).read_bytes()
            if args.resident:
                files['HMISET.CFG'] = files['HMISET.CFG'].replace(b'DeviceIRQ   = 7', b'DeviceIRQ   = 5')
            for path in args.game_dir.iterdir():
                if path.suffix.upper() in ('.3DF', '.SP', '.OVL') and len(path.stem) <= 8:
                    files[path.name] = path.read_bytes()
            directories['DATA'] = {p.name: p.read_bytes() for p in (args.game_dir/'DATA').iterdir() if p.is_file()}
        else:
            for path in args.game_dir.iterdir():
                if path.is_dir():
                    directories[path.name] = {p.name: p.read_bytes() for p in path.iterdir() if p.is_file()}
                elif path.suffix.upper() in ('.INI', '.DLL'):
                    files[path.name] = path.read_bytes()
    else:
        disk.clear()
    for name, data in files.items():
        disk.add(name, data)
    for directory, content in directories.items():
        disk.add_directory(directory, content)
    run = ROOT/'.local/host'
    run.mkdir(parents=True, exist_ok=True)
    name = 'audio' if args.audio else 'monitor'
    if args.external:
        name += '-external'
        if args.client != 'core':
            name += '-'+args.client
    if args.game:
        name += '-'+args.game
        if args.game_exe:
            name += '-'+hashlib.sha256(files[child]).hexdigest()[:8]
    if args.cpu != '386':
        name += '-'+args.cpu
    if args.cd_bin:
        name += '-cd'
    if args.resident:
        name += '-resident'
        if args.legacy_host:
            name += '-hdpmi'
    if args.no_vcpi:
        name += '-no-vcpi'
    if args.load_high:
        name += '-high'
    if args.alternate:
        name += '-alternate'
    if args.no_delivery:
        name += '-no-delivery'
    image = run/(name+'.img')
    if args.resident and not args.legacy_host:
        (run/(name+'.lst')).write_bytes((ROOT/'build/UCDDHOST.lst').read_bytes())
    image.write_bytes(disk.image)
    evidence = dict(passed=False, files=sorted(files), cpu=args.cpu, backend='interpreter',
                    memory_mib=int(os.environ.get('UCDD_TEST_MEMORY_MIB', '16')),
                    capture_settings={key: value for key, value in os.environ.items()
                                      if key.startswith('UCDD_TEST_')},
                    program_sha256={n: hashlib.sha256(data).hexdigest() for n, data in files.items()
                                    if n.endswith(('.COM', '.EXE'))},
                    disk_sha256=hashlib.sha256(disk.image).hexdigest(), expected_failure=args.no_delivery)
    report = run/(name+'.json')
    report.write_text(json.dumps(evidence, indent=2)+'\n')
    command = [str(args.emulator), '--cpu', args.cpu, '--interpreter', '--memory-mib', '16',
               '--headless-boot-hdd', str(image), '--cycles', '600000000' if args.cpu != '386' else '240000000']
    if args.audio or (args.external and args.izarra_source):
        capture = build_capture(args.izarra_source)
        wav = run/(name+'.wav')
        command = [str(capture), str(image), str(wav)]
    evidence['command'] = command
    evidence['emulator_sha256'] = hashlib.sha256(Path(command[0]).read_bytes()).hexdigest()
    result = subprocess.run(command, capture_output=True, text=True,
                            timeout=int(os.environ.get('UCDD_TEST_TIMEOUT', '90')),
                            env=dict(os.environ, UCDD_TEST_CPU=args.cpu, UCDD_TEST_DISK_EXPORT='1',
                                     UCDD_TEST_MEMORY_DUMP=str(run/(name+'.memory.bin'))))
    log = result.stdout+result.stderr
    (run/(name+'.log')).write_text(log)
    print(log)
    guest_passed = result.returncode == 0 and 'stop: TestExit { code: 0 }' in log
    if args.no_delivery:
        guest_passed = result.returncode != 0 and 'stop: TestExit { code: 1 }' in log
    evidence['passed'] = guest_passed
    report.write_text(json.dumps(evidence, indent=2)+'\n')
    if not evidence['passed']:
        raise SystemExit('The protected-mode test failed.')
    if args.audio:
        evidence['passed'] = False
        report.write_text(json.dumps(evidence, indent=2)+'\n')
        exported = Fat16(wav.with_suffix('.disk.img').read_bytes())
        periods, interrupts, calls, forwarded = struct.unpack('<4I', exported.read('HOSTSTAT.DAT'))
        evidence['guest'] = dict(output_periods=periods, virtual_irqs=interrupts, port_calls=calls, forwarded_irqs=forwarded)
        if args.no_delivery:
            if interrupts != 0 or periods < 340 or calls < 50:
                raise ValueError('The negative control failed for a different reason.')
        else:
            evidence['capture_checks'] = verify_capture(wav)
        evidence['capture_sha256'] = hashlib.sha256(wav.read_bytes()).hexdigest()
        evidence['passed'] = True
        report.write_text(json.dumps(evidence, indent=2)+'\n')


if __name__ == '__main__':
    main()
