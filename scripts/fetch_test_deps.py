# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Download the pinned FreeDOS and SHSUCD test dependencies."""

import hashlib
from pathlib import Path
import urllib.request

from test_dos import FREEDOS_SHA256, SHSUCD_SHA256

DESTINATION = Path(__file__).resolve().parent.parent / '.local' / 'downloads'
DEPENDENCIES = [
    ('FD14-LiteUSB.zip', FREEDOS_SHA256,
     'https://www.ibiblio.org/pub/micro/pc-stuff/freedos/files/distributions/1.4/FD14-LiteUSB.zip'),
    ('shcd3-7.zip', SHSUCD_SHA256,
     'http://adoxa.altervista.org/shsucdx/shcd3-7.zip'),
]


def main():
    DESTINATION.mkdir(parents=True, exist_ok=True)
    for name, expected, url in DEPENDENCIES:
        path = DESTINATION / name
        if path.exists():
            data = path.read_bytes()
        else:
            with urllib.request.urlopen(url, timeout=60) as response:
                data = response.read()
        if hashlib.sha256(data).hexdigest() != expected:
            raise SystemExit(f'The archive hash is incorrect: {name}')
        if not path.exists():
            path.write_bytes(data)
        print(f'Archive verified: {name}')


if __name__ == '__main__':
    main()
