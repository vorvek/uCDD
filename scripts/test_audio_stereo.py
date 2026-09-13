# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Check signed stereo game PCM through the shared SB16 output."""

import argparse
import json
from pathlib import Path
import subprocess

from test_audio_onset import capture_pair, read_pcm
from test_audio_pm import ROOT, RUN, prepare_tests, sha256
from test_audio_refill import CODES


def verify_stereo(signal, quiet):
    marks = json.loads(signal.with_suffix('.marks.json').read_text())
    if marks != json.loads(quiet.with_suffix('.marks.json').read_text()):
        raise ValueError('The paired runs have different command times.')
    times = {mark['id']: mark['frame'] for mark in marks}
    start, stop = times[64], times[80]
    a, b = read_pcm(signal), read_pcm(quiet)
    if len(a) != len(b):
        raise ValueError('The paired captures have different lengths.')
    delta = [(left[0]-right[0], left[1]-right[1]) for left, right in zip(a, b)]
    first = next((i for i in range(round(start), round(stop)) if abs(delta[i][0]) > 256), None)
    last = next((i for i in range(round(stop), min(round(stop)+1600, len(delta)-32))
                 if all(max(map(abs, delta[j])) < 16 for j in range(i, i+32))), None)
    if first is None or last is None or not 480 <= first-start <= 1088 or not 480 <= last-stop <= 1088:
        raise ValueError('A stereo start or stop is outside the buffer interval.')
    for i in range(first+2, last-2):
        frame = i-first
        block = frame//1024
        if (frame-2)//1024 != block or (frame+2)//1024 != block:
            continue
        expected = ((CODES[block % 16]*128+57)/4, (CODES[(block+5) % 16]*128-93)/4)
        if any(abs(value-reference) > 4 for value, reference in zip(delta[i], expected)):
            raise ValueError(f'The stereo channels or sample order changed at frame {frame}.')
    blocks = (last-first)//1024
    if blocks < 8:
        raise ValueError('The stereo capture does not contain two ring cycles.')
    return dict(rate=22050, ring_bytes=8192, block_bytes=2048, complete_blocks=blocks,
                onset_ms=(first-start)/44.1, stop_ms=(last-stop)/44.1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--izarra-source', type=Path, required=True)
    args = parser.parse_args()
    executable = prepare_tests(args.izarra_source)
    directory = RUN / 'stereo'
    directory.mkdir(parents=True, exist_ok=True)
    evidence = dict(passed=False, runs=[], capture_executable_sha256=sha256(executable),
                    capture_source_sha256=sha256(ROOT / 'tests/audio_capture.rs'),
                    capture_lock_sha256=sha256(RUN / 'capture/Cargo.lock'),
                    izarra_revision=subprocess.check_output(
                        ['git', '-C', str(args.izarra_source), 'rev-parse', 'HEAD'], text=True).strip(),
                    program_sha256={name: sha256(ROOT / 'build' / name) for name in
                                    ('ARSHARE.COM', 'ALAUNCH.COM', 'ASTEREO.COM', 'ASTQUIET.COM', 'ADMA.COM')})
    report = directory / 'results.json'
    report.write_text(json.dumps(evidence, indent=2) + '\n')
    for alternate in (False, True):
        name = 'alternate' if alternate else 'default'
        row = capture_pair(executable, directory, name, alternate=alternate, refill='STEREO', launcher=True,
                           dma_state=True)
        evidence['runs'].append(row)
        row['checks'] = verify_stereo(directory / (name+'.wav'), directory / (name+'-quiet.wav'))
        report.write_text(json.dumps(evidence, indent=2) + '\n')
        print(f'The stereo client test passed: {name}')
    evidence['passed'] = True
    report.write_text(json.dumps(evidence, indent=2) + '\n')


if __name__ == '__main__':
    main()
