# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Check resident installation rollback and the setup sound-test guard."""

import argparse
from array import array
import json
import os
from pathlib import Path
import struct
import subprocess
import wave
import zipfile

from build import assemble, assemble_resident_host
from dos_disk import Fat16
from test_audio_pm import ROOT, CACHE, sha256
from test_dos import SHSUCD_SHA256
from test_audio_resident import prepare_resident_tests


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--izarra-source', type=Path, required=True)
    args = parser.parse_args()
    capture, base, files = prepare_resident_tests(args.izarra_source)
    assemble_resident_host()
    assemble('src/setup.asm', 'UCDDSET.EXE', exe=True)
    assemble('tests/setup_lifecycle.asm', 'INITFAIL.COM', ('EXPECT_FAILURE=1', 'INSTALL_TEST=1'))
    assemble('tests/audio_resident_state.asm', 'RESSTATE.COM', ('OWN_HOST=1',))
    assemble('tests/setup_keys.asm', 'SETKEYS.COM', ('SOUND_TEST=1',))
    files['FDCONFIG.SYS'] = files['FDCONFIG.SYS'].replace(b'FILES=40', b'LASTDRIVE=Z\r\nFILES=40')
    for name in ('UCDD.EXE', 'UCDDSET.EXE', 'INITFAIL.COM', 'RESSTATE.COM', 'SETKEYS.COM'):
        files[name] = (ROOT / 'build' / name).read_bytes()
    archive_path = CACHE / 'shcd3-7.zip'
    if sha256(archive_path) != SHSUCD_SHA256:
        raise ValueError('The SHSUCDX archive hash is incorrect.')
    with zipfile.ZipFile(archive_path) as archive:
        files['SHSUCDX.COM'] = archive.read('shsucdx.com')
    good = b'uCDD\x01\x00' + struct.pack('<H', 0x220) + bytes((7, 1, 5, 0))
    files['GOOD.CFG'] = good
    files['UCDD.CFG'] = good[:6] + struct.pack('<H', 0x240) + good[8:]
    commands = ['@ECHO OFF',
                'INITFAIL', 'IF ERRORLEVEL 1 GOTO FAIL', 'COPY GOOD.CFG UCDD.CFG >NUL',
                'UCDD -install -ems', 'IF NOT ERRORLEVEL 1 GOTO FAIL',
                'UCDD -install', 'IF ERRORLEVEL 1 GOTO FAIL', 'SHSUCDX /D:UCDD0001 /L:F',
                'IF ERRORLEVEL 246 GOTO FAIL', 'RESSTATE', 'IF ERRORLEVEL 1 GOTO FAIL',
                'SETKEYS', 'UCDDSET', 'IF ERRORLEVEL 1 GOTO FAIL',
                'RESSTATE', 'IF ERRORLEVEL 1 GOTO FAIL', 'PASS', ':FAIL', 'FAIL']
    files['AUTOEXEC.BAT'] = ('\r\n'.join(commands) + '\r\n').encode()
    base.clear()
    for name, data in files.items():
        base.add(name, data)
    run = ROOT / '.local/audio/resident-boot-own-host'
    run.mkdir(parents=True, exist_ok=True)
    image, wav = run / 'boot.img', run / 'boot.wav'
    image.write_bytes(base.image)
    evidence = dict(passed=False, cpu='386', backend='interpreter', disk_files=sorted(files),
                    program_sha256={n: sha256(ROOT/'build'/n) for n in ('UCDD.EXE', 'UCDDSET.EXE')},
                    disk_sha256=sha256(image), capture_executable_sha256=sha256(capture))
    report = run / 'results.json'
    report.write_text(json.dumps(evidence, indent=2) + '\n')
    result = subprocess.run([str(capture), str(image), str(wav)], capture_output=True, text=True,
            timeout=60, env=dict(os.environ, UCDD_TEST_CPU='386', UCDD_TEST_STEPS='60000',
                                 UCDD_TEST_DISK_EXPORT='1'))
    (run / 'boot.log').write_text(result.stdout + result.stderr)
    print(result.stdout + result.stderr)
    result.check_returncode()
    with wave.open(str(wav)) as source:
        pcm = array('h', source.readframes(source.getnframes()))
    peak = max(map(abs, pcm), default=0)
    if peak > 8:
        raise ValueError('The setup sound test used the card while resident audio was installed.')
    exported = Fat16(wav.with_suffix('.disk.img').read_bytes())
    if exported.read('UCDD.CFG') != good:
        raise ValueError('The setup program did not preserve the saved settings.')
    evidence.update(passed=True, setup_capture_peak=peak, capture_sha256=sha256(wav))
    report.write_text(json.dumps(evidence, indent=2) + '\n')
    print('Resident rollback, retry, and the setup guard passed.')


if __name__ == '__main__':
    main()
