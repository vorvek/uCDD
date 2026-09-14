# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Build the DOS programs with NASM."""

from pathlib import Path
import argparse
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / 'build'


def assemble(source, name, defines=(), exe=False, listing=False):
    BUILD.mkdir(exist_ok=True)
    nasm = shutil.which('nasm')
    if not nasm:
        raise SystemExit('NASM is required.')
    output = BUILD / name
    subprocess.run([nasm, '-f', 'bin', '-I', str(ROOT / 'src') + '/',
                    *(['-l', str(output.with_suffix('.lst'))] if listing else []),
                    *['-D' + value for value in defines], str(ROOT / source),
                    '-o', str(output)], check=True)
    if exe:
        payload = output.read_bytes()
        stack_top = (len(payload) + 15) // 16 * 16 + 1024
        if stack_top > 65534:
            raise ValueError('The program exceeds one DOS segment.')
        size = 32 + len(payload)
        header = struct.pack('<14H', 0x5a4d, size % 512, (size + 511) // 512,
                             0, 2, 64, 64, 0, stack_top, 0, 0, 0, 28, 0)
        output.write_bytes(header.ljust(32, b'\0') + payload)
    print(f'{name}: {output.stat().st_size} bytes')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--resident-audio', '--own-host', action='store_true',
                        help='Build resident audio with the internal DPMI host.')
    args = parser.parse_args()
    for source, name in [('src/ucdd.asm', 'UCDD.EXE'),
                         ('src/setup.asm', 'UCDDSET.EXE')]:
        if args.resident_audio and name == 'UCDD.EXE':
            assemble_resident_host()
        else:
            assemble(source, name, exe=True)
    (BUILD / 'UCDDRV.EXE').unlink(missing_ok=True)
    assemble('tests/probe.asm', 'PROBE.COM')
    assemble('tests/packets.asm', 'PACKETS.COM')
    assemble('tests/cue_packets.asm', 'CUEPACK.COM')
    assemble('tests/audio_cd_state.asm', 'CDSTATE.COM')
    assemble('tests/file_crc.asm', 'FILECRC.COM')
    assemble('tests/exit.asm', 'PASS.COM')
    assemble('tests/exit.asm', 'FAIL.COM', ('EXIT_CODE=1',))


def assemble_resident_host():
    assemble('src/host/resident.asm', 'UCDDHOST.BIN', listing=True)
    host = (BUILD / 'UCDDHOST.BIN').read_bytes()
    if len(host) > 65535:
        raise ValueError('The host exceeds one segment.')
    defines = ('RESIDENT_AUDIO=1', 'OWN_HOST=1', f'OWN_HOST_SIZE={len(host)}')
    assemble('src/ucdd.asm', 'UCDD.EXE', (*defines, 'OWN_HOST_OFFSET=65536'), exe=True)
    program = (BUILD / 'UCDD.EXE').read_bytes()
    if len(program) > 65536:
        raise ValueError('The driver overlaps its host overlay.')
    (BUILD / 'UCDD.EXE').write_bytes(program.ljust(65536, b'\0') + host)
    print(f'UCDD.EXE with internal host: {65536 + len(host)} bytes')


if __name__ == '__main__':
    main()
