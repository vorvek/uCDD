# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""CUE selection must not include the next track or an unsupported layout."""

from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from prepare_cd_stream import cue_track, descriptor


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / 'disc.bin').write_bytes(bytes(2352*100))
        self.cue = self.root / 'disc.cue'
        self.text = ('FILE "disc.bin" BINARY\nTRACK 01 MODE1/2352\nINDEX 01 00:00:00\n'
                     'TRACK 02 AUDIO\nINDEX 00 00:00:08\nINDEX 01 00:00:10\n'
                     'TRACK 03 AUDIO\nINDEX 00 00:01:05\nINDEX 01 00:01:20\n')

    def select(self, text=None, number=2):
        self.cue.write_text(self.text if text is None else text, encoding='utf-8')
        return cue_track(self.cue, number)

    def test_track_boundaries(self):
        self.assertEqual(self.select()[1:], (10*2352, 70*2352))
        self.assertEqual(self.select(number=3)[1:], (95*2352, 5*2352))

    def test_metadata_and_binary_unchanged(self):
        before = (self.root / 'disc.bin').read_bytes()
        self.select('REM A note\nTITLE "Disc title"\n'+self.text)
        self.assertEqual((self.root / 'disc.bin').read_bytes(), before)

    def test_rejected_layouts(self):
        replacements = [('TRACK 02', 'TRACK 04'), ('INDEX 01 00:00:10', ''),
                        ('INDEX 01 00:00:10', 'INDEX 01 00:00:75'),
                        ('INDEX 01 00:00:10', 'INDEX 01 00:60:10'),
                        ('INDEX 00 00:00:08', 'INDEX 00 00:00:11'),
                        ('INDEX 01 00:01:20', 'INDEX 01 00:02:00'),
                        ('INDEX 01 00:00:10', 'INDEX 01 00:00:10\nINDEX 00 00:00:09'),
                        ('INDEX 01 00:00:10', 'INDEX 01 00:00:10\nINDEX 01 00:00:10'),
                        ('TRACK 02 AUDIO', 'TRACK 02 MODE1/2048'),
                        ('TRACK 02 AUDIO', 'FILE "disc.bin" BINARY\nTRACK 02 AUDIO'),
                        ('TRACK 02 AUDIO', 'TRACK 02 AUDIO\nFLAGS PRE'),
                        ('TRACK 02 AUDIO', 'TRACK 02 AUDIO\nPREGAP 00:02:00')]
        for old, new in replacements:
            with self.subTest(new=new), self.assertRaises(ValueError):
                self.select(self.text.replace(old, new))
        for number in (0, 1, 4):
            with self.subTest(number=number), self.assertRaises(ValueError):
                self.select(number=number)

    def test_incomplete_sector(self):
        with (self.root / 'disc.bin').open('ab') as stream:
            stream.write(b'x')
        with self.assertRaises(ValueError):
            self.select()

    def test_descriptor(self):
        value = descriptor(r'C:\IMAGES\DISC.BIN', 2352, 4704)
        self.assertEqual(len(value), 140)
        self.assertEqual(struct.unpack_from('<4sII', value), (b'CDS1', 2352, 4704))
        self.assertEqual(value[12:].split(b'\0')[0], b'C:\\IMAGES\\DISC.BIN')
        for path, offset, length in [('AUDIO.BIN', 0, 0), ('AUDIO.BIN', 1, 4),
                                     ('AUDIO.BIN', 0, 3), ('AUDIO.BIN', 2**31-4, 4),
                                     ('long file name.bin', 0, 4), (r'A:\DISC.BIN', 0, 4),
                                     (r'\\SERVER\DISC.BIN', 0, 4)]:
            with self.subTest(path=path, offset=offset, length=length), self.assertRaises(ValueError):
                descriptor(path, offset, length)


if __name__ == '__main__':
    unittest.main()
