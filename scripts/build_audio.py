"""Build the standalone audio experiments and sound test."""

import math
import struct

from build import BUILD, assemble


def build_audio():
    BUILD.mkdir(exist_ok=True)
    (BUILD / 'CDTEST.PCM').write_bytes(b''.join(
        struct.pack('<hh', round(12000 * math.sin(2 * math.pi * 37 * i / 4096)),
                    round(12000 * math.sin(2 * math.pi * 61 * i / 4096)))
        for i in range(4096)))
    (BUILD / 'GAMETEST.PCM').write_bytes(bytes(
        round(128 + 32 * math.sin(2 * math.pi * i / 64)) for i in range(64)))
    assemble('tests/audio_trap.asm', 'ATRAP.COM')
    assemble('tests/audio_share.asm', 'ASHARE.COM')
    assemble('tests/audio_share.asm', 'UCDDTST.COM', ('OUTPUT_TEST=1',))
    assemble('tests/audio_client.asm', 'ACLIENT.COM')
    assemble('tests/audio_share.asm', 'APSHARE.COM', ('PM_CLIENT=1',))
    assemble('tests/audio_pm.asm', 'APM.COM')
    assemble('tests/audio_pm.asm', 'APMNEG.COM', ('NO_ROUTE=1',))


if __name__ == '__main__':
    build_audio()
