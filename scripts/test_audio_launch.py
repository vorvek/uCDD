"""Check the audio bridge with an independent protected-mode child."""

import argparse
import json
from pathlib import Path
import subprocess

from test_audio_onset import capture_pair
from test_audio_refill import verify_refill
from test_audio_pm import ROOT, RUN, prepare_tests, sha256


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--izarra-source', type=Path, required=True)
    args = parser.parse_args()
    directory = RUN / 'launcher'
    directory.mkdir(parents=True, exist_ok=True)
    executable = prepare_tests(args.izarra_source)
    evidence = dict(passed=False, runs=[], capture_executable_sha256=sha256(executable),
                    capture_source_sha256=sha256(ROOT / 'tests/audio_capture.rs'),
                    capture_lock_sha256=sha256(RUN / 'capture/Cargo.lock'),
                    izarra_revision=subprocess.check_output(
                        ['git', '-C', str(args.izarra_source), 'rev-parse', 'HEAD'], text=True).strip(),
                    program_sha256={name: sha256(ROOT / 'build' / name) for name in
                                    ('ARSHARE.COM', 'ALAUNCH.COM', 'AEXT.COM', 'AEXTQUI.COM', 'AEXTLEG.COM', 'AEXTLQ.COM')})
    report = directory / 'results.json'
    report.write_text(json.dumps(evidence, indent=2) + '\n')
    for alternate in (False, True):
        for legacy in (False, True):
            name = ('legacy' if legacy else 'default') + ('-alt' if alternate else '')
            row = capture_pair(executable, directory, name, alternate=alternate,
                               refill='LEGACY' if legacy else '4K', launcher=True)
            evidence['runs'].append(row)
            row['checks'] = verify_refill(directory / (name+'.wav'), directory / (name+'-quiet.wav'),
                                         4096, 1024, 10000 if legacy else 22050)
            report.write_text(json.dumps(evidence, indent=2) + '\n')
            print(f'The external client test passed: {name}')
    evidence['passed'] = True
    report.write_text(json.dumps(evidence, indent=2) + '\n')


if __name__ == '__main__':
    main()
