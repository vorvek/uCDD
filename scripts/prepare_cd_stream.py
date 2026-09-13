# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Select an audio track in a single-file, raw-sector CUE/BIN image."""

import argparse
from pathlib import Path
import re
import shlex
import struct


def cue_track(cue, number):
    image, tracks, current = None, [], None
    for line in cue.read_text(encoding='utf-8-sig').splitlines():
        lexer = shlex.shlex(line, posix=True)
        lexer.whitespace_split, lexer.commenters, lexer.escape = True, '', ''
        words = list(lexer)
        if not words:
            continue
        command = words[0].upper()
        if command in ('REM', 'TITLE', 'PERFORMER', 'SONGWRITER', 'CATALOG', 'ISRC'):
            continue
        if command == 'FILE' and len(words) == 3 and words[2].upper() == 'BINARY' and image is None:
            image = cue.parent / words[1].replace('\\', '/')
        elif command == 'TRACK' and len(words) == 3 and image is not None:
            if not words[1].isdigit() or int(words[1]) != len(tracks)+1 or len(tracks) == 99:
                raise ValueError('The track number is not valid.')
            if words[2].upper() not in ('AUDIO', 'MODE1/2352'):
                raise ValueError('The track format is not supported.')
            current = dict(mode=words[2].upper(), indexes={})
            tracks.append(current)
        elif command == 'INDEX' and len(words) == 3 and current is not None:
            if words[1] not in ('00', '01') or words[1] in current['indexes']:
                raise ValueError('The track index is not supported.')
            if words[1] == '00' and '01' in current['indexes']:
                raise ValueError('The track indexes are not in order.')
            if not re.fullmatch(r'\d{2}:\d{2}:\d{2}', words[2]):
                raise ValueError('The track time is not valid.')
            minute, second, frame = map(int, words[2].split(':'))
            if second >= 60 or frame >= 75:
                raise ValueError('The track time is not valid.')
            current['indexes'][words[1]] = (minute*60+second)*75+frame
        else:
            raise ValueError(f'The CUE command is not supported: {command}')
    if image is None or not tracks or not 1 <= number <= len(tracks):
        raise ValueError('The audio track is not available.')
    size = image.stat().st_size
    if not size or size >= 2**31 or size % 2352:
        raise ValueError('The BIN file size is not valid.')
    previous = -1
    for track in tracks:
        if '01' not in track['indexes']:
            raise ValueError('A track has no start index.')
        start = track['indexes']['01']
        boundary = track['indexes'].get('00', start)
        if not previous < boundary <= start < size//2352:
            raise ValueError('The track indexes are outside the image or not in order.')
        previous = start
    track = tracks[number-1]
    if track['mode'] != 'AUDIO':
        raise ValueError('The selected track does not contain audio.')
    start = track['indexes']['01']
    end = (tracks[number]['indexes'].get('00', tracks[number]['indexes']['01'])
           if number < len(tracks) else size//2352)
    return image, start*2352, (end-start)*2352


def descriptor(path, offset, length):
    if offset < 0 or length <= 0 or (offset | length) & 3 or offset+length >= 2**31:
        raise ValueError('The audio byte range is not valid.')
    path = path.replace('/', '\\')
    parts = path.split('\\')
    if re.fullmatch('[C-Zc-z]:', parts[0]):
        parts = parts[1:]
    if not parts or any(not re.fullmatch(r'[A-Za-z0-9_!#$%&\-@^`{}~]{1,8}(\.[A-Za-z0-9_!#$%&\-@^`{}~]{1,3})?',
                                        part) for part in parts):
        raise ValueError('Use a DOS 8.3 path on a local hard disk.')
    encoded = path.encode('ascii')
    if len(encoded) > 127:
        raise ValueError('The DOS path is too long.')
    return struct.pack('<4sII', b'CDS1', offset, length) + encoded.ljust(128, b'\0')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cue', type=Path, required=True)
    parser.add_argument('--track', type=int, required=True)
    parser.add_argument('--dos-path', required=True, help='Path to the original BIN file on the DOS PC.')
    parser.add_argument('--output', type=Path, required=True, help='Destination CDSTREAM.DAT file.')
    args = parser.parse_args()
    _, offset, length = cue_track(args.cue, args.track)
    args.output.write_bytes(descriptor(args.dos_path, offset, length))
    print(f'The track selection is saved. Audio length: {length/176400:.2f} seconds.')


if __name__ == '__main__':
    main()
