# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Check configuration beside the executable and first-install sound setup."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess

from build import ROOT, assemble, assemble_resident_host
from dos_disk import Fat16
from test_audio import verify_speaker_sequence
from test_audio_resident import prepare_resident_tests


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--izarra-source', type=Path, required=True)
    args = parser.parse_args()
    capture, disk, common = prepare_resident_tests(args.izarra_source)
    assemble_resident_host()
    assemble('src/setup.asm', 'UCDDSET.EXE', exe=True)
    assemble('tests/setup_keys.asm', 'SAVEKEY.COM', ('SAVE_ONLY=1',))
    assemble('tests/setup_keys.asm', 'ESCKEY.COM', ('CANCEL_ONLY=1',))
    assemble('tests/setup_keys.asm', 'TESTKEY.COM', ('SOUND_TEST=1',))
    assemble('tests/setup_lifecycle.asm', 'FAILSAFE.COM',
             ('INSTALL_TEST=1', 'EXPECT_FAILURE=1', 'HIGH_SETUP=1',
              'CHILD_NAME="C:\\DOSDRV\\UCDD.EXE"'))
    common['FDCONFIG.SYS'] = common['FDCONFIG.SYS'].replace(b'DOS=LOW', b'DOS=HIGH,UMB')
    for name in ('SAVEKEY.COM', 'ESCKEY.COM', 'TESTKEY.COM', 'FAILSAFE.COM'):
        common[name] = (ROOT/'build'/name).read_bytes()
    programs = {name: (ROOT/'build'/name).read_bytes() for name in ('UCDD.EXE', 'UCDDSET.EXE')}
    good = b'uCDD\x01\x00'+struct.pack('<H', 0x220)+bytes((7, 1, 5, 0))
    cases = (
        ('existing-absolute', good, False, None, 'LH C:\\DOSDRV\\UCDD.EXE -install', True),
        ('existing-path', good, False, None, 'LH UCDD -install', True),
        ('first-save', None, True, 'SAVEKEY', 'LH UCDD -install', True),
        ('first-test', None, True, 'TESTKEY', 'LH UCDD -install', True),
        ('first-cancel', None, True, 'ESCKEY', 'LH UCDD -install', False),
        ('cancel-state', None, True, 'ESCKEY', 'FAILSAFE', False),
        ('missing-setup', None, False, None, 'LH UCDD -install', False),
        ('invalid-config', b'invalid', True, None, 'LH UCDD -install', False),
        ('setup-existing', good, True, 'SAVEKEY', 'C:\\DOSDRV\\UCDDSET.EXE', True),
        ('setup-new', None, True, 'SAVEKEY', 'UCDDSET', True),
    )
    reports = []
    for name, config, helper, keys, command, success in cases:
        files = dict(common)
        files['UCDD.CFG'] = b'working-directory decoy'
        app = {'UCDD.EXE': programs['UCDD.EXE']}
        if config is not None:
            app['UCDD.CFG'] = config
        if helper:
            app['UCDDSET.EXE'] = programs['UCDDSET.EXE']
        commands = ['@ECHO OFF', 'SET PATH=C:\\;C:\\DOSDRV', 'SET BLASTER=A220 I7 D1 H5 T6']
        if keys:
            commands.append(keys)
        commands += [command+' >C:\\RESULT.TXT',
                     ('IF ERRORLEVEL 1' if success or name == 'cancel-state' else
                      'IF NOT ERRORLEVEL 1')+' GOTO FAIL',
                     'CD >C:\\CWD.TXT', 'C:\\PASS', ':FAIL', 'C:\\FAIL']
        files['AUTOEXEC.BAT'] = ('\r\n'.join(commands)+'\r\n').encode()
        disk.clear()
        for filename, data in files.items():
            disk.add(filename, data)
        disk.add_directory('DOSDRV', app)
        run = ROOT/'.local/audio/config-path'/name
        run.mkdir(parents=True, exist_ok=True)
        image, wav = run/'boot.img', run/'boot.wav'
        image.write_bytes(disk.image)
        result = subprocess.run([str(capture), str(image), str(wav)], capture_output=True,
                                text=True, timeout=60, env=dict(os.environ, UCDD_TEST_CPU='386',
                                UCDD_TEST_STEPS='60000', UCDD_TEST_DISK_EXPORT='1'))
        (run/'boot.log').write_text(result.stdout+result.stderr)
        result.check_returncode()
        exported = Fat16(wav.with_suffix('.disk.img').read_bytes())
        message = exported.read('RESULT.TXT').decode('ascii')
        assert exported.read('UCDD.CFG') == files['UCDD.CFG'], name
        assert exported.read('CWD.TXT').strip() == b'C:\\', name
        if success:
            assert exported.read('DOSDRV/UCDD.CFG') == good, name
            if not name.startswith('setup-'):
                assert 'The uCDD driver is installed.' in message, name
        elif name in ('first-cancel', 'cancel-state'):
            assert 'UCDD.CFG was not saved.' in message, name
        elif name == 'missing-setup':
            assert 'UCDDSET.EXE cannot be started.' in message, name
        elif name == 'invalid-config':
            assert 'UCDD.CFG cannot be read.' in message, name
            assert exported.read('DOSDRV/UCDD.CFG') == config, name
        if not success and config is None:
            directory = exported.directory()['DOSDRV'][0]
            assert 'UCDD.CFG' not in exported.directory(directory), name
        if name == 'first-test':
            verify_speaker_sequence(wav, sequences=1)
        if name.startswith('first-'):
            assert 'Sound setup will start.' in message, name
        if name.startswith('existing-') or name == 'invalid-config':
            assert 'Sound setup will start.' not in message, name
        reports.append(dict(case=name, passed=True, message=message))
        print(name+': PASS')
    report = dict(passed=True, cpu='386', backend='interpreter', cases=reports,
                  program_sha256={n: hashlib.sha256(data).hexdigest() for n, data in programs.items()})
    (ROOT/'.local/audio/config-path/results.json').write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__':
    main()
