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
    (BUILD / 'ONSET.PCM').write_bytes(bytes([192]*32 + [64]*32 + [160]*32 + [96]*32 + [144]*3968))
    (BUILD / 'QUIET.PCM').write_bytes(bytes([128]*4096))
    assemble('tests/audio_trap.asm', 'ATRAP.COM')
    assemble('tests/audio_share.asm', 'ASHARE.COM')
    assemble('tests/audio_share.asm', 'UCDDTST.COM', ('OUTPUT_TEST=1',))
    assemble('tests/audio_client.asm', 'ACLIENT.COM')
    assemble('tests/audio_share.asm', 'APSHARE.COM', ('PM_CLIENT=1',))
    assemble('tests/audio_pm.asm', 'APM.COM')
    assemble('tests/audio_pm.asm', 'APMNEG.COM', ('NO_ROUTE=1',))
    assemble('tests/audio_share.asm', 'AISHARE.COM', ('PM_CLIENT=1', 'VIRTUAL_IRQ=1', 'OUTPUT_SHIFT=9'))
    assemble('tests/audio_pm.asm', 'AIPM.COM', ('VIRTUAL_IRQ=1', 'OUTPUT_SHIFT=9'))
    assemble('tests/audio_pm.asm', 'AIPMNEG.COM', ('VIRTUAL_IRQ=1', 'OUTPUT_SHIFT=9', 'NO_DELIVERY=1'))
    assemble('tests/audio_irq_state.asm', 'AISTATE.COM')
    assemble('tests/audio_share.asm', 'AIWRAP.COM',
             ('PM_CLIENT=1', 'VIRTUAL_IRQ=1', 'OUTPUT_SHIFT=9', 'PERIOD_SEED=65520'))
    onset = ('VIRTUAL_IRQ=1', 'OUTPUT_SHIFT=9', 'ONSET_TEST=1')
    assemble('tests/audio_share.asm', 'AOSHARE.COM', (*onset, 'PM_CLIENT=1'))
    assemble('tests/audio_pm.asm', 'AOPM.COM', onset)
    assemble('tests/audio_pm.asm', 'AOQUIET.COM', (*onset, 'ONSET_SILENT=1'))
    refill = ('VIRTUAL_IRQ=1', 'OUTPUT_SHIFT=9', 'STREAM_TEST=1')
    assemble('tests/audio_share.asm', 'ARSHARE.COM', (*refill, 'PM_CLIENT=1'))
    assemble('tests/audio_launch.asm', 'ALAUNCH.COM')
    assemble('tests/audio_pm.asm', 'AEXT.COM', (*refill, 'EXTERNAL_BRIDGE=1',
             'CLIENT_RING_BYTES=4096', 'CLIENT_BLOCK_BYTES=1024', 'CLIENT_RATE=22050'))
    assemble('tests/audio_pm.asm', 'AEXTQUI.COM', (*refill, 'EXTERNAL_BRIDGE=1', 'STREAM_SILENT=1',
             'CLIENT_RING_BYTES=4096', 'CLIENT_BLOCK_BYTES=1024', 'CLIENT_RATE=22050'))
    for name, extra in (('AEXTLEG.COM', ()), ('AEXTLQ.COM', ('STREAM_SILENT=1',))):
        assemble('tests/audio_pm.asm', name, (*refill, 'EXTERNAL_BRIDGE=1', 'LEGACY_DSP=1',
                 'CLIENT_RING_BYTES=4096', 'CLIENT_BLOCK_BYTES=1024', 'CLIENT_RATE=10000', *extra))
    assemble('tests/audio_launch.asm', 'AQUAKE.COM', ('QUAKE_TEST=1',))
    assemble('tests/audio_pm.asm', 'APOLL.COM', (*refill, 'EXTERNAL_BRIDGE=1', 'POLL_TEST=1',
             'CLIENT_RING_BYTES=4096', 'CLIENT_BLOCK_BYTES=1024', 'CLIENT_RATE=22050'))
    assemble('tests/audio_share.asm', 'AQSHARE.COM',
             ('PM_CLIENT=1', 'VIRTUAL_IRQ=1', 'OUTPUT_SHIFT=9', 'QUAKE_TEST=1'))
    for name, ring, block, rate in (('4K', 4096, 1024, 22050), ('2BUF', 4096, 2048, 22050),
                                    ('8K', 8192, 2048, 22050),
                                    ('FAST', 2048, 512, 44100), ('BAD', 1024, 512, 44100)):
        options = (*refill, f'CLIENT_RING_BYTES={ring}', f'CLIENT_BLOCK_BYTES={block}',
                   f'CLIENT_RATE={rate}', *(('EXPECT_REJECT=1',) if name == 'BAD' else ()))
        assemble('tests/audio_pm.asm', f'AR{name}.COM', options)
        if name != 'BAD':
            assemble('tests/audio_pm.asm', f'AQ{name}.COM', (*options, 'STREAM_SILENT=1'))


if __name__ == '__main__':
    build_audio()
