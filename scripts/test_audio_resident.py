# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Test boot-loaded audio, image changes, and two direct Quake runs."""

import argparse
import json
import os
from pathlib import Path
import struct
import subprocess
import wave
import zipfile
import zlib

from build import assemble, assemble_resident_host
from dos_disk import Fat16
from test_audio_pm import ROOT, CACHE, make_disk, prepare_tests, sha256
from test_audio_mounted import quake_image, verify_mix, verify_controls
from test_audio_quake import pak_file
from test_dos import SHSUCD_SHA256
from test_dos import FREEDOS_SHA256
from test_audio import JEMM_SHA256, build_capture


def prepare_resident_tests(izarra_source):
    for name, expected in (('FD14-LiteUSB.zip', FREEDOS_SHA256), ('JemmB_v586.zip', JEMM_SHA256)):
        if sha256(CACHE/name) != expected:
            raise ValueError(f'The archive hash is incorrect: {name}')
    assemble('tests/exit.asm', 'PASS.COM')
    assemble('tests/exit.asm', 'FAIL.COM', ('EXIT_CODE=1',))
    with zipfile.ZipFile(CACHE/'FD14-LiteUSB.zip') as archive:
        disk = Fat16(archive.read('FD14LITE.img'))
    files = {name: disk.read(name) for name in ('KERNEL.SYS', 'COMMAND.COM')}
    with zipfile.ZipFile(CACHE/'JemmB_v586.zip') as archive:
        files['JEMMEX.EXE'] = archive.read('JEMMEX.EXE')
    for name in ('PASS.COM', 'FAIL.COM'):
        files[name] = (ROOT/'build'/name).read_bytes()
    files['FDCONFIG.SYS'] = (b'DEVICE=C:\\JEMMEX.EXE NOEMS\r\nDOS=LOW\r\nFILES=40\r\nBUFFERS=10\r\n'
                            b'SHELL=C:\\COMMAND.COM C:\\ /E:512 /P\r\n')
    disk.clear()
    for name, data in files.items():
        disk.add(name, data)
    return build_capture(izarra_source), disk, files


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--izarra-source', type=Path, required=True)
    parser.add_argument('--quake-dir', type=Path, required=True)
    parser.add_argument('--quake-bin', type=Path, required=True)
    parser.add_argument('--load-high', action='store_true')
    parser.add_argument('--own-host', action='store_true')
    parser.add_argument('--runs', type=int, choices=(1, 2), default=2)
    parser.add_argument('--mscdex', type=Path)
    args = parser.parse_args()
    if args.own_host:
        capture, base, files = prepare_resident_tests(args.izarra_source)
        assemble_resident_host()
    else:
        capture = prepare_tests(args.izarra_source)
        base = Fat16(make_disk())
        files = {name: base.read(name) for name in ('KERNEL.SYS', 'COMMAND.COM', 'JEMMEX.EXE',
                 'HDPMI32I.EXE', 'FDCONFIG.SYS', 'PASS.COM', 'FAIL.COM')}
        assemble('src/ucdd.asm', 'UCDD.EXE', ('RESIDENT_AUDIO=1',), exe=True)
    assemble('src/setup.asm', 'UCDDSET.EXE', exe=True)
    assemble('tests/audio_resident_state.asm', 'RESSTATE.COM', ('OWN_HOST=1',) if args.own_host else ())
    assemble('tests/mark.asm', 'MARK.COM')
    assemble('tests/file_crc.asm', 'FILECRC.COM')
    for name in ('UCDD.EXE', 'UCDDSET.EXE', 'RESSTATE.COM', 'MARK.COM', 'FILECRC.COM'):
        files[name] = (ROOT / 'build' / name).read_bytes()
    archive_path = CACHE / 'shcd3-7.zip'
    if sha256(archive_path) != SHSUCD_SHA256:
        raise ValueError('The SHSUCDX archive hash is incorrect.')
    with zipfile.ZipFile(archive_path) as archive:
        files['SHSUCDX.COM'] = archive.read('shsucdx.com')
    if args.mscdex:
        files['MSCDEX.EXE'] = args.mscdex.read_bytes()
    raw, cue, resource, excerpt = quake_image(args.quake_bin)
    files['QUAKE.BIN'], files['QUAKE.CUE'] = raw, cue
    files['BAD.ISO'] = b'This is not a disc image.'
    files['QUAKE.EXE'] = (args.quake_dir / 'QUAKE.EXE').read_bytes()
    files['UCDD.CFG'] = b'uCDD\x01\x00' + struct.pack('<H', 0x220) + bytes((7, 1, 5, 0))
    config = files['FDCONFIG.SYS'].replace(b'FILES=40', b'LASTDRIVE=Z\r\nFILES=40')
    if args.load_high:
        config = config.replace(b'DOS=LOW', b'DOS=HIGH,UMB')
    files['FDCONFIG.SYS'] = config
    state = 'RESSTATE H' if args.load_high else 'RESSTATE'
    redirector = 'MSCDEX /D:UCDD0001 /L:F' if args.mscdex else 'SHSUCDX /D:UCDD0001 /L:F'
    checks = [('HDPMI32I -r', None),
              (('LH ' if args.load_high else '') + 'UCDD -install', True),
              ('UCDD -install', False), (redirector, None),
              (state, True), ('UCDD -unmount', False), ('UCDD -mount C:\\QUAKE.CUE', True),
              ('UCDD -mount C:\\QUAKE.CUE', False), ('UCDD -mount C:\\BAD.ISO -drive F', False),
              ('COPY F:\\RESOURCE.1 C:\\RESCOPY.1', True),
              (f'FILECRC C:\\RESCOPY.1 {zlib.crc32(resource):08X}', True)]
    if args.own_host:
        checks.pop(0)
    for game in range(args.runs):
        checks += [(f'MARK {game*2+1}', True),
                   ('QUAKE.EXE -noserial -noipx -noudp -condebug', True),
                   (f'MARK {game*2+2}', True), (state, True),
                   (f'COPY ID1\\QCONSOLE.LOG GAME{game+1}.LOG', True),
                   ('UCDD -unmount', True), (state, True)]
        if game+1 < args.runs:
            checks.append(('UCDD -mount C:\\QUAKE.CUE', True))
    commands = ['@ECHO OFF', 'SET BLASTER=A220 I5 D1 H5 T6']
    for command, success in checks:
        commands.append(command)
        if command == 'HDPMI32I -r':
            commands.append('IF ERRORLEVEL 3 GOTO FAIL')
        elif command.startswith('SHSUCDX '):
            commands.append('IF ERRORLEVEL 246 GOTO FAIL')
        elif command.startswith('MSCDEX '):
            commands.append('IF ERRORLEVEL 1 GOTO FAIL')
        if success is not None:
            commands.append('IF ERRORLEVEL 1 GOTO FAIL' if success else 'IF NOT ERRORLEVEL 1 GOTO FAIL')
    commands += ['PASS', ':FAIL', 'FAIL']
    files['AUTOEXEC.BAT'] = ('\r\n'.join(commands) + '\r\n').encode()
    game_files = {name: (args.quake_dir / 'ID1' / name).read_bytes() for name in ('PAK0.PAK', 'PAK1.PAK')}
    game_files['AUTOEXEC.CFG'] = (b'ambient_level 0\nbgmvolume 1\nmap start\necho UCDD_CD_READY\n' +
            b'wait\n'*100 + b'cd info\nvolume 0.7\nstopsound\nplay misc/menu1\n' + b'wait\n'*300 +
            b'echo UCDD_CD_DONE\ntoggleconsole\nquit\n')
    disk = base.empty_larger()
    for name, data in files.items():
        disk.add(name, data)
    disk.add_directory('ID1', game_files)
    run = ROOT / '.local/audio' / ('resident-high' if args.load_high else 'resident-low')
    if args.own_host:
        run = run.with_name(run.name + '-own-host')
    if args.mscdex:
        run = run.with_name(run.name + '-mscdex')
    run.mkdir(exist_ok=True)
    image, wav = run / 'quake.img', run / 'quake.wav'
    image.write_bytes(disk.image)
    evidence = dict(passed=False, cpu='586', backend='interpreter', load_high=args.load_high,
                    redirector='MSCDEX' if args.mscdex else 'SHSUCDX',
                    program_sha256={n: sha256(ROOT/'build'/n) for n in ('UCDD.EXE', 'UCDDSET.EXE')},
                    disk_files=sorted(files), disk_sha256=sha256(image), capture_executable_sha256=sha256(capture))
    report = run / 'results.json'
    report.write_text(json.dumps(evidence, indent=2) + '\n')
    result = subprocess.run([str(capture), str(image), str(wav)], capture_output=True, text=True,
            timeout=480, env=dict(os.environ, UCDD_TEST_CPU='586', UCDD_TEST_STEPS='1200000',
                                 UCDD_TEST_DISK_EXPORT='1', UCDD_TEST_MEMORY_DUMP=str(run/'memory.bin')))
    (run / 'quake.log').write_text(result.stdout + result.stderr)
    print(result.stdout + result.stderr)
    result.check_returncode()
    exported = Fat16(wav.with_suffix('.disk.img').read_bytes())
    if exported.read('RESCOPY.1') != resource:
        raise ValueError('The installer copy differs from the image.')
    state_data = exported.read('RESSTAT.DAT')
    version, segment, paragraphs, allocation, output, fault = struct.unpack('<6H', state_data[:12])
    evidence.update(resident_bytes=paragraphs*16, resident_segment=segment,
                    dma_allocation_segment=allocation, dma_output_segment=output)
    if args.own_host:
        host_segment, host_paragraphs = struct.unpack('<2H', state_data[12:])
        evidence.update(host_segment=host_segment, host_resident_bytes=host_paragraphs*16,
                        total_resident_bytes=(paragraphs+host_paragraphs)*16+8192)
    marks = {m['id']: round(m['frame']*49716/44100) for m in json.loads(wav.with_suffix('.marks.json').read_text())}
    with wave.open(str(wav)) as source:
        params = source.getparams()
        pcm = source.readframes(source.getnframes())
    sound = pak_file(game_files['PAK0.PAK'], 'sound/misc/menu1.wav')
    evidence['games'] = []
    for game in range(args.runs):
        console = exported.read(f'GAME{game+1}.LOG')
        if b'Currently looping track 4' not in console or b'UCDD_CD_DONE' not in console:
            raise ValueError('Quake did not finish CD playback.')
        part = run / f'game{game+1}.wav'
        with wave.open(str(part), 'wb') as target:
            target.setparams(params)
            target.writeframes(pcm[marks[game*2+1]*4:marks[game*2+2]*4])
        audio = verify_mix(part, excerpt, sound)
        controls = verify_controls(part, excerpt, sound, audio)
        evidence['games'].append(dict(audio=audio, rejected_controls=controls))
    evidence.update(passed=True, capture_sha256=sha256(wav))
    report.write_text(json.dumps(evidence, indent=2) + '\n')
    print(f'{args.runs} direct Quake runs passed. Resident bytes: {paragraphs*16}.')


if __name__ == '__main__':
    main()
