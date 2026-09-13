"""Check CD continuity when a DPMI game polls without a sound IRQ handler."""

import argparse
import json
from pathlib import Path
import subprocess

from dos_disk import Fat16
from test_audio_pm import ROOT, RUN, make_disk, prepare_tests, sha256
from test_audio_quake import separate_cd


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--izarra-source', type=Path, required=True)
    args = parser.parse_args()
    executable = prepare_tests(args.izarra_source)
    directory = RUN / 'poll'
    directory.mkdir(parents=True, exist_ok=True)
    evidence = dict(passed=False, runs=[], capture_executable_sha256=sha256(executable),
                    capture_source_sha256=sha256(ROOT / 'tests/audio_capture.rs'),
                    capture_lock_sha256=sha256(RUN / 'capture/Cargo.lock'),
                    izarra_revision=subprocess.check_output(
                        ['git', '-C', str(args.izarra_source), 'rev-parse', 'HEAD'], text=True).strip(),
                    program_sha256={name: sha256(ROOT / 'build' / name)
                                    for name in ('ARSHARE.COM', 'ALAUNCH.COM', 'APOLL.COM')})
    report = directory / 'results.json'
    report.write_text(json.dumps(evidence, indent=2) + '\n')
    for irq, dma8, dma16 in ((5, 1, 5), (7, 1, 5), (5, 3, 6), (7, 3, 6)):
        source = Fat16(make_disk(refill='4K', launcher=True, alternate=True))
        files = {name: source.read(name) for name in source.directory()}
        files['GAME.COM'] = (ROOT / 'build/APOLL.COM').read_bytes()
        config = bytearray(files['UCDD.CFG'])
        config[8:11] = bytes([irq, dma8, dma16])
        files['UCDD.CFG'] = config
        source.clear()
        for name, content in files.items():
            source.add(name, content)
        name = f'irq{irq}-dma{dma8}{dma16}'
        image, wav = directory / (name+'.img'), directory / (name+'.wav')
        image.write_bytes(source.image)
        command = [str(executable), str(image), str(wav)]
        result = subprocess.run(command, capture_output=True, text=True, timeout=180)
        log = result.stdout + result.stderr
        (directory / (name+'.log')).write_text(log, encoding='utf-8')
        row = dict(name=name, passed=False, command=command, disk_sha256=sha256(image),
                   capture_sha256=sha256(wav))
        evidence['runs'].append(row)
        report.write_text(json.dumps(evidence, indent=2) + '\n')
        if result.returncode or 'stop: TestExit { code: 0 }' not in log:
            raise SystemExit(f'The polling client failed. See {name}.log.')
        _, _, errors, _, changes = separate_cd(wav)
        row['cd_phase_changes'] = changes
        report.write_text(json.dumps(evidence, indent=2) + '\n')
        # The emulator capture can repeat one frame; a mixer half is 512 frames.
        slips = sum(min(change['phase_change_frames'], 4096-change['phase_change_frames'])
                    for change in changes)
        if slips > 1 or sum(error < 4 for error in errors) < 200:
            raise ValueError('The CD position changed or the capture is too short.')
        row['passed'] = True
        report.write_text(json.dumps(evidence, indent=2) + '\n')
        print(f'The polling client test passed: {name}')
    evidence['passed'] = True
    report.write_text(json.dumps(evidence, indent=2) + '\n')


if __name__ == '__main__':
    main()
