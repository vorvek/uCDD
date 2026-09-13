"""Build the DOS programs with NASM."""

from pathlib import Path
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / 'build'


def assemble(source, name, defines=(), exe=False):
    BUILD.mkdir(exist_ok=True)
    nasm = shutil.which('nasm')
    if not nasm:
        raise SystemExit('NASM is required.')
    output = BUILD / name
    subprocess.run([nasm, '-f', 'bin', '-I', str(ROOT / 'src') + '/',
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
    for source, name in [('src/driver.asm', 'UCDDRV.EXE'), ('src/helper.asm', 'UCDD.EXE'),
                         ('src/setup.asm', 'UCDDSET.EXE')]:
        assemble(source, name, exe=True)
    assemble('tests/probe.asm', 'PROBE.COM')
    assemble('tests/packets.asm', 'PACKETS.COM')
    assemble('tests/file_crc.asm', 'FILECRC.COM')
    assemble('tests/exit.asm', 'PASS.COM')
    assemble('tests/exit.asm', 'FAIL.COM', ('EXIT_CODE=1',))


if __name__ == '__main__':
    main()
