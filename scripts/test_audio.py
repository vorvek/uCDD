# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Run audio experiments on a disposable FreeDOS disk."""

import argparse
import hashlib
import json
import math
import os
import shutil
from pathlib import Path
import subprocess
import struct
import urllib.request
import wave
import zipfile
import zlib

from build import assemble
from build_audio import build_audio
from dos_disk import Fat16
from test_dos import FREEDOS_SHA256

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / '.local' / 'downloads'
RUN = ROOT / '.local' / 'audio'
JEMM_URL = 'https://github.com/Baron-von-Riedesel/Jemm/releases/download/v5.86/JemmB_v586.zip'
JEMM_SHA256 = '94838a1836f94d95dcf84d250f7968dfca2eb6b5cfa7ac664d6e01f22f0d296e'


def build_capture(izarra_source):
    crate = RUN / 'capture'
    crate.mkdir(parents=True, exist_ok=True)
    manifest = ['[package]', 'name = "ucdd-audio-capture"', 'version = "0.1.0"',
                'edition = "2024"', '[[bin]]', 'name = "ucdd-audio-capture"',
                f'path = {json.dumps((ROOT / "tests/audio_capture.rs").as_posix())}',
                '[dependencies]']
    for name in ('izarravm-core', 'izarravm-machine', 'izarravm-firmware'):
        path = (izarra_source.resolve() / 'crates' / name).as_posix()
        manifest.append(f'{name} = {{ path = {json.dumps(path)}, default-features = false }}')
    (crate / 'Cargo.toml').write_text('\n'.join(manifest) + '\n')
    subprocess.run(['cargo', 'build', '--release', '--manifest-path', str(crate / 'Cargo.toml')],
                   check=True)
    executable = crate / 'target' / 'release' / ('ucdd-audio-capture.exe' if os.name == 'nt'
                                                else 'ucdd-audio-capture')
    digest = hashlib.sha256(executable.read_bytes()).hexdigest()[:16]
    snapshot = crate / f'capture-{digest}{executable.suffix}'
    if not snapshot.exists():
        shutil.copy2(executable, snapshot)
    return snapshot


def verify_capture(path, extra_windows=()):
    with wave.open(str(path)) as source:
        if (source.getnchannels(), source.getsampwidth(), source.getframerate()) != (2, 2, 44100):
            raise ValueError('The audio capture format is incorrect.')
        frames = list(struct.iter_unpack('<hh', source.readframes(source.getnframes())))
    active = next((i for i, pair in enumerate(frames) if max(map(abs, pair)) > 100), None)
    if active is None or active + int(4.0 * 44100) >= len(frames):
        raise ValueError('The audio capture is too short or silent.')

    def amplitude(center, channel, frequency):
        start = active + round((center - 0.15) * 44100)
        count = 13230
        real = imag = weight_sum = 0.0
        for i in range(count):
            weight = 0.5 - 0.5 * math.cos(2 * math.pi * i / (count - 1))
            angle = 2 * math.pi * frequency * i / 44100
            value = frames[start + i][channel] * weight
            real += value * math.cos(angle)
            imag += value * math.sin(angle)
            weight_sum += weight
        return 2 * math.hypot(real, imag) / weight_sum

    measured = []
    for center, game_hz in ((0.65, 22050 / 64), (1.65, None),
                            (2.75, 11025 / 64), (3.75, 22050 / 64), *extra_windows):
        row = dict(seconds=center, game_hz=game_hz)
        for channel, cd_hz in enumerate((44100 * 37 / 4096, 44100 * 61 / 4096)):
            cd = amplitude(center, channel, cd_hz)
            if not 2500 < cd < 3500:
                raise ValueError('The CD signal is missing or its level changed.')
            game = amplitude(center, channel, game_hz or 22050 / 64)
            if (game_hz and not 1500 < game < 2400) or (not game_hz and game > 50):
                raise ValueError('The game signal has an incorrect rate or reset state.')
            other_cd = amplitude(center, channel, 44100 * (61 if channel == 0 else 37) / 4096)
            if other_cd > 50:
                raise ValueError('The CD channels are not separate.')
            row[str(channel)] = dict(cd_amplitude=cd, game_amplitude=game)
        measured.append(row)
    return measured


def verify_speaker_sequence(path, sequences=2):
    with wave.open(str(path)) as source:
        frames = list(struct.iter_unpack('<hh', source.readframes(source.getnframes())))
    runs = []
    for start in range(0, len(frames)-441, 441):
        block = frames[start:start+441]
        energy = [sum(pair[ch]**2 for pair in block)/441 for ch in (0, 1)]
        peak = [max(abs(pair[ch]) for pair in block) for ch in (0, 1)]
        channel = 1 if energy[0] > 1000000 and peak[1] < 8 else (
            2 if energy[1] > 1000000 and peak[0] < 8 else 0)
        if runs and runs[-1]['channel'] == channel:
            runs[-1]['end'] = start+441
        else:
            runs.append(dict(channel=channel, start=start, end=start+441))
    tones = [row for row in runs if row['channel'] and row['end']-row['start'] > 4410]
    if [row['channel'] for row in tones] != [1, 2]*sequences:
        raise ValueError('Each sound test must play the left speaker, then the right speaker.')
    for row in tones:
        if not 1.08 <= (row['end']-row['start'])/44100 <= 1.14:
            raise ValueError('The speaker test duration is incorrect.')
    for left, right in zip(tones[::2], tones[1::2]):
        if not 0.35 <= (right['start']-left['end'])/44100 <= 0.40:
            raise ValueError('The speaker tests need a short pause between channels.')
        gap = frames[left['end']+441:right['start']-441]
        if not gap or max(abs(value) for pair in gap for value in pair) >= 8:
            raise ValueError('Both speakers must be silent during the pause.')
    return tones


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--emulator', type=Path, required=True)
    parser.add_argument('--izarra-source', type=Path)
    args = parser.parse_args()
    RUN.mkdir(parents=True, exist_ok=True)
    archive = CACHE / 'JemmB_v586.zip'
    if not archive.exists():
        urllib.request.urlretrieve(JEMM_URL, archive)
    for path, expected in ((archive, JEMM_SHA256),
                           (CACHE / 'FD14-LiteUSB.zip', FREEDOS_SHA256)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise SystemExit(f'The archive hash is incorrect: {path.name}')
    build_audio()
    assemble('src/setup.asm', 'UCDDSET.EXE', ('SETUP_SNAPSHOT=1',), exe=True)
    assemble('tests/setup_keys.asm', 'SETKEYS.COM')
    assemble('tests/setup_keys.asm', 'TESTKEYS.COM', ('SOUND_TEST=1',))
    assemble('tests/setup_keys.asm', 'SAVEKEYS.COM', ('SAVE_ONLY=1',))
    assemble('tests/file_crc.asm', 'FILECRC.COM')
    assemble('tests/exit.asm', 'PASS.COM')
    assemble('tests/exit.asm', 'FAIL.COM', ('EXIT_CODE=1',))
    with zipfile.ZipFile(CACHE / 'FD14-LiteUSB.zip') as source:
        disk = Fat16(source.read('FD14LITE.img'))
    kernel, command = disk.read('KERNEL.SYS'), disk.read('COMMAND.COM')
    disk.clear()
    disk.add('KERNEL.SYS', kernel)
    disk.add('COMMAND.COM', command)
    with zipfile.ZipFile(archive) as source:
        for name in ('JEMMEX.EXE', 'JLOAD.EXE', 'QPIEMU.DLL'):
            disk.add(name, source.read(name))
    for name in ('ATRAP.COM', 'ASHARE.COM', 'ACLIENT.COM', 'UCDDSET.EXE', 'UCDDTST.COM',
                 'SETKEYS.COM', 'TESTKEYS.COM', 'SAVEKEYS.COM', 'FILECRC.COM', 'PASS.COM', 'FAIL.COM'):
        disk.add(name, (ROOT / 'build' / name).read_bytes())
    default_config = b'uCDD\x01\x00' + struct.pack('<H', 0x220) + bytes([5, 1, 5, 0])
    changed_config = b'uCDD\x01\x01' + struct.pack('<H', 0x240) + bytes([7, 3, 5, 0])
    suggested_config = changed_config[:10] + bytes([6, 0])
    disk.add('DEFAULT.CFG', default_config)
    disk.add('ALT.CFG', default_config[:8] + bytes([7, 3, 6, 0]))
    disk.add('BADPORT.CFG', default_config[:6] + struct.pack('<H', 0x240) + default_config[8:])
    disk.add('INVALID.CFG', b'This is not a uCDD configuration file.')
    disk.add('FDCONFIG.SYS', (
        'DEVICE=C:\\JEMMEX.EXE NOEMS\r\nDOS=LOW\r\nFILES=40\r\nBUFFERS=10\r\n'
        'SHELL=C:\\COMMAND.COM C:\\ /E:512 /P\r\n').encode())
    disk.add('AUTOEXEC.BAT', (
        '@ECHO OFF\r\nJLOAD QPIEMU.DLL\r\nATRAP\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
        'ASHARE\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
        'SETKEYS\r\nUCDDSET\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
        f'FILECRC UCDD.CFG {zlib.crc32(changed_config):08X}\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
        'UCDDTST\r\nIF NOT ERRORLEVEL 1 GOTO FAIL\r\n'
        'DEL UCDD.CFG\r\nSET BLASTER=A240 I7 D3 H6 T4\r\nSAVEKEYS\r\nUCDDSET\r\n'
        f'FILECRC UCDD.CFG {zlib.crc32(suggested_config):08X}\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
        'SET BLASTER=\r\n'
        'COPY DEFAULT.CFG UCDD.CFG >NUL\r\nTESTKEYS\r\nUCDDSET\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
        f'FILECRC UCDD.CFG {zlib.crc32(default_config):08X}\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
        'COPY ALT.CFG UCDD.CFG >NUL\r\nUCDDTST\r\nIF ERRORLEVEL 1 GOTO FAIL\r\n'
        'COPY INVALID.CFG UCDD.CFG >NUL\r\nUCDDTST\r\nIF NOT ERRORLEVEL 1 GOTO FAIL\r\n'
        'COPY BADPORT.CFG UCDD.CFG >NUL\r\nUCDDTST\r\nIF NOT ERRORLEVEL 1 GOTO FAIL\r\n'
        'PASS\r\n:FAIL\r\nFAIL\r\n').encode())
    image = RUN / 'audio.img'
    image.write_bytes(disk.image)
    command = [str(args.emulator.resolve()), '--cpu', '386', '--interpreter',
               '--memory-mib', '16', '--headless-boot-hdd', str(image),
               '--cycles', '800000000']
    env = os.environ.copy()
    env.pop('IZARRAVM_AUDIO_COST', None)
    env.pop('IZARRAVM_AUDIO_WAV', None)
    result = subprocess.run(command, capture_output=True, text=True, env=env, timeout=180)
    log = result.stdout + result.stderr
    (RUN / 'audio.log').write_text(log, encoding='utf-8')
    passed = result.returncode == 0 and 'stop: TestExit { code: 0 }' in log
    evidence = dict(command=command, guest_passed=passed,
                    passed=passed and not bool(args.izarra_source), jemm_sha256=JEMM_SHA256,
                    program_sha256={name: hashlib.sha256((ROOT / 'build' / name).read_bytes()).hexdigest()
                                    for name in ('ATRAP.COM', 'ASHARE.COM', 'ACLIENT.COM', 'UCDDTST.COM')},
                    disk_sha256=hashlib.sha256(disk.image).hexdigest(),
                    emulator_sha256=hashlib.sha256(args.emulator.read_bytes()).hexdigest())
    (RUN / 'audio.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(log[-6000:])
    if not passed:
        raise SystemExit('The audio test failed. See the test log.')
    if args.izarra_source:
        executable = build_capture(args.izarra_source)
        crate = RUN / 'capture'
        result = subprocess.run([str(executable), str(image), str(RUN / 'audio.wav'),
                                 str(RUN / 'setup.ppm')],
                                capture_output=True, text=True, timeout=180)
        (RUN / 'capture.log').write_text(result.stdout + result.stderr, encoding='utf-8')
        print(result.stdout + result.stderr)
        result.check_returncode()
        evidence['capture_checks'] = verify_capture(RUN / 'audio.wav')
        evidence['speaker_sequence'] = verify_speaker_sequence(RUN / 'audio.wav')
        evidence['passed'] = True
        evidence['capture_source_sha256'] = hashlib.sha256(
            (ROOT / 'tests/audio_capture.rs').read_bytes()).hexdigest()
        evidence['capture_lock_sha256'] = hashlib.sha256((crate / 'Cargo.lock').read_bytes()).hexdigest()
        evidence['capture_sha256'] = hashlib.sha256((RUN / 'audio.wav').read_bytes()).hexdigest()
        evidence['capture_executable_sha256'] = hashlib.sha256(executable.read_bytes()).hexdigest()
        evidence['izarra_revision'] = subprocess.check_output(
            ['git', '-C', str(args.izarra_source), 'rev-parse', 'HEAD'], text=True).strip()
        (RUN / 'audio.json').write_text(json.dumps(evidence, indent=2) + '\n')
        print('The captured audio checks passed.')
    assemble('src/setup.asm', 'UCDDSET.EXE', exe=True)


if __name__ == '__main__':
    main()
