"""Check live game-buffer refills through the shared Sound Blaster output."""

import argparse
import json
from pathlib import Path
import subprocess

from test_audio_onset import capture_pair, read_pcm
from test_audio_pm import ROOT, RUN, make_disk, prepare_tests, sha256

REFILL_RUN = RUN / 'refill'
CODES = (16, 48, -32, 64, -16, -64, 32, -48, 48, 16, -64, 32, 64, -32, -48, -16)
CASES = (('4K', 4096, 1024, 22050), ('2BUF', 4096, 2048, 22050),
         ('8K', 8192, 2048, 22050), ('FAST', 2048, 512, 44100))


def verify_refill(signal, quiet, ring, block, rate):
    marks = json.loads(signal.with_suffix('.marks.json').read_text())
    if marks != json.loads(quiet.with_suffix('.marks.json').read_text()):
        raise ValueError('The paired runs have different command times.')
    times = {mark['id']: mark['frame'] for mark in marks}
    start, stop = times[64], times[80]
    a, b = read_pcm(signal), read_pcm(quiet)
    if len(a) != len(b):
        raise ValueError('The paired captures have different lengths.')
    delta = [(left[0]-right[0], left[1]-right[1]) for left, right in zip(a, b)]
    first = next((i for i in range(round(start), round(stop)) if abs(delta[i][0]) > 512), None)
    last = next((i for i in range(round(stop), min(round(stop)+1600, len(delta)-32))
                 if all(abs(delta[j][0]) < 16 for j in range(i, i+32))), None)
    if first is None or last is None or not 480 <= first-start <= 1088 or not 480 <= last-stop <= 1088:
        raise ValueError('A start or stop is outside the buffer interval.')
    step = (rate << 16)//44100
    blocks = ((last-first)*step >> 16)//block
    if blocks < 2*ring//block:
        raise ValueError('The capture does not contain two complete ring cycles.')
    for index in range(first+2, last-2):
        relative = index-first
        block_index = (relative*step >> 16)//block
        if ((relative-2)*step >> 16)//block != block_index or ((relative+2)*step >> 16)//block != block_index:
            continue
        expected = CODES[block_index % len(CODES)]*64
        if any(abs(value-expected) > 4 for value in delta[index]):
            raise ValueError(f'A refilled block changed or is out of order at frame {relative}.')
    return dict(ring_bytes=ring, block_bytes=block, rate=rate, complete_blocks=blocks,
                onset_ms=(first-start)/44.1, stop_ms=(last-stop)/44.1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--izarra-source', type=Path, required=True)
    args = parser.parse_args()
    REFILL_RUN.mkdir(parents=True, exist_ok=True)
    executable = prepare_tests(args.izarra_source)
    names = ['ARSHARE.COM', 'ARBAD.COM', *(prefix+name+'.COM' for name, *_ in CASES
                                         for prefix in ('AR', 'AQ'))]
    evidence = dict(passed=False, runs=[], capture_executable_sha256=sha256(executable),
                    capture_source_sha256=sha256(ROOT / 'tests/audio_capture.rs'),
                    capture_lock_sha256=sha256(RUN / 'capture/Cargo.lock'),
                    izarra_revision=subprocess.check_output(
                        ['git', '-C', str(args.izarra_source), 'rev-parse', 'HEAD'], text=True).strip(),
                    program_sha256={name: sha256(ROOT / 'build' / name) for name in names})
    report = REFILL_RUN / 'results.json'
    report.write_text(json.dumps(evidence, indent=2) + '\n')
    for alternate in (False, True):
        for case, ring, block, rate in CASES:
            name = case.lower() + ('-alt' if alternate else '')
            row = capture_pair(executable, REFILL_RUN, name, alternate=alternate, refill=case)
            evidence['runs'].append(row)
            row['checks'] = verify_refill(REFILL_RUN / (name+'.wav'),
                                           REFILL_RUN / (name+'-quiet.wav'), ring, block, rate)
            report.write_text(json.dumps(evidence, indent=2) + '\n')
            print(f'The buffer refill checks passed: {name}')
    image, wav = REFILL_RUN / 'unsafe.img', REFILL_RUN / 'unsafe.wav'
    image.write_bytes(make_disk(refill='BAD'))
    command = [str(executable), str(image), str(wav)]
    result = subprocess.run(command, capture_output=True, text=True, timeout=180)
    log = result.stdout + result.stderr
    (REFILL_RUN / 'unsafe.log').write_text(log, encoding='utf-8')
    if (not result.returncode or 'stop: TestExit { code: 1 }' not in log or
            'The unsafe refill buffer was rejected.' not in log):
        raise SystemExit('The unsafe buffer check failed. See the test log.')
    evidence['negative_control'] = dict(passed=True, command=command, disk_sha256=sha256(image),
                                        wave_sha256=sha256(wav))
    evidence['passed'] = True
    report.write_text(json.dumps(evidence, indent=2) + '\n')
    print('The unsafe buffer check passed.')


if __name__ == '__main__':
    main()
