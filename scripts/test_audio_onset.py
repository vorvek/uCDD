"""Measure sound onset and stop against guest command timestamps."""

import argparse
import json
from pathlib import Path
import struct
import subprocess
import wave

from test_audio_pm import ROOT, RUN, make_disk, prepare_tests, sha256

ONSET_RUN = RUN / 'onset'


def read_pcm(path):
    with wave.open(str(path)) as source:
        if (source.getnchannels(), source.getsampwidth(), source.getframerate()) != (2, 2, 44100):
            raise ValueError('The audio capture format is incorrect.')
        return list(struct.iter_unpack('<hh', source.readframes(source.getnframes())))


def verify_onset(signal, quiet):
    markers = json.loads(signal.with_suffix('.marks.json').read_text())
    quiet_markers = json.loads(quiet.with_suffix('.marks.json').read_text())
    if markers != quiet_markers:
        raise ValueError('The paired runs have different command times.')
    times = {item['id']: item['frame'] for item in markers}
    if any(key not in times for key in (*range(64, 70), *range(80, 86))):
        raise ValueError('A command timestamp is missing.')
    a, b = read_pcm(signal), read_pcm(quiet)
    if len(a) != len(b):
        raise ValueError('The paired captures have different lengths.')
    delta = [(left[0]-right[0], left[1]-right[1]) for left, right in zip(a, b)]
    measured = []
    for index in range(6):
        start, stop = times[64+index], times[80+index]
        begin, end = round(start), round(stop)
        first = next((i for i in range(begin, end) if abs(delta[i][0]) > 512), None)
        if first is None or not 480 <= first-start <= 1088:
            raise ValueError('The sound onset is missing or outside the buffer interval.')
        width = 128 if index % 2 else 64
        for part, expected in enumerate((4096, -4096, 2048, -2048)):
            values = delta[first+part*width+2:first+(part+1)*width-2]
            if not values or max(abs(value[channel]-expected) for value in values
                                 for channel in (0, 1)) > 4:
                raise ValueError(f'The first sound samples changed or were lost: trial {index+1}.')
        last = next((i for i in range(end, min(end+1600, len(delta)-32))
                     if all(abs(delta[j][0]) < 16 for j in range(i, i+32))), None)
        if last is None or not 480 <= last-stop <= 1088:
            raise ValueError('The sound stop is outside the buffer interval.')
        tail = delta[first+4*width+2:last-2]
        if not tail or max(abs(value[channel]-1024) for value in tail for channel in (0, 1)) > 4:
            raise ValueError('The sound changed before the stop command took effect.')
        measured.append(dict(rate=11025 if index % 2 else 22050,
                             onset_ms=(first-start)/44.1, stop_ms=(last-stop)/44.1,
                             marker_frames=width*4))
    return measured


def capture_pair(executable, directory, name, **options):
    row = dict(name=name, captures=[])
    for quiet in (False, True):
        stem = name + ('-quiet' if quiet else '')
        image, wav = (directory / (stem+suffix) for suffix in ('.img', '.wav'))
        image.write_bytes(make_disk(quiet=quiet, **options))
        command = [str(executable), str(image), str(wav)]
        result = subprocess.run(command, capture_output=True, text=True, timeout=180)
        log = result.stdout + result.stderr
        (directory / (stem+'.log')).write_text(log, encoding='utf-8')
        row['captures'].append(dict(command=command, disk_sha256=sha256(image),
                                    wave_sha256=sha256(wav),
                                    markers_sha256=sha256(wav.with_suffix('.marks.json'))))
        if result.returncode or 'stop: TestExit { code: 0 }' not in log:
            print(log)
            raise SystemExit('The audio guest test failed.')
    return row


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--izarra-source', type=Path, required=True)
    args = parser.parse_args()
    ONSET_RUN.mkdir(parents=True, exist_ok=True)
    executable = prepare_tests(args.izarra_source)
    evidence = dict(passed=False, runs=[], capture_executable_sha256=sha256(executable),
                    capture_source_sha256=sha256(ROOT / 'tests/audio_capture.rs'),
                    capture_lock_sha256=sha256(RUN / 'capture/Cargo.lock'),
                    izarra_revision=subprocess.check_output(
                        ['git', '-C', str(args.izarra_source), 'rev-parse', 'HEAD'], text=True).strip(),
                    program_sha256={name: sha256(ROOT / 'build' / name) for name in
                                    ('AOSHARE.COM', 'AOPM.COM', 'AOQUIET.COM')})
    report = ONSET_RUN / 'results.json'
    report.write_text(json.dumps(evidence, indent=2) + '\n')
    for alternate in (False, True):
        name = 'alternate' if alternate else 'default'
        row = capture_pair(executable, ONSET_RUN, name, alternate=alternate, onset=True)
        evidence['runs'].append(row)
        row['checks'] = verify_onset(ONSET_RUN / (name+'.wav'), ONSET_RUN / (name+'-quiet.wav'))
        report.write_text(json.dumps(evidence, indent=2) + '\n')
        print(f'The onset and stop checks passed: {name}')
    evidence['passed'] = True
    report.write_text(json.dumps(evidence, indent=2) + '\n')


if __name__ == '__main__':
    main()
