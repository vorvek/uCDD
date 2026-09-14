# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Check Tomb's CD track and game effects in the tested output formats."""

import argparse
import json
from pathlib import Path
import wave

import numpy as np


def align_cd(pcm, source):
    anchor, window = 5*44100, 8192
    cd = source.astype(float)/4
    data = pcm[:, 0].astype(float)-pcm[:, 1]
    target = cd[anchor:anchor+window, 0]-cd[anchor:anchor+window, 1]
    size = 1 << (len(pcm)+window-1).bit_length()
    correlation = np.fft.irfft(np.fft.rfft(data, size)*np.fft.rfft(target[::-1], size), size)
    correlation = correlation[window-1:len(pcm)]
    energy = np.r_[0, np.cumsum(data*data)]
    scores = correlation/np.sqrt(np.maximum(energy[window:]-energy[:-window], 1)*sum(target*target))
    match = int(np.argmax(scores))
    start = match-anchor
    return start, float(scores[match])


def verify(pcm, source, seconds=24):
    start, score = align_cd(pcm, source)
    first, last = 44100, seconds*44100
    cd = source.astype(float)/4
    if score < 0.995 or start < 0 or start+last > len(pcm):
        raise ValueError('The CD track capture is missing.')
    residual = pcm[start+first:start+last].astype(float)-cd[first:last]
    # Guest 8-bit PCM contributes multiples of 64 at this output gain.
    game = np.rint(residual/64)*64
    error = float(np.max(abs(residual-game)))
    if error > 1:
        raise ValueError('The CD samples differ from the source.')
    rms = float(np.sqrt(np.mean(game*game)))
    if rms < 5:
        raise ValueError('The game sound is missing from the CD capture.')
    return dict(cd_start_frame=start, cd_frames=last-first, cd_maximum_error=error,
                cd_correlation=score, game_rms=rms)


def verify_pro(pcm, source, seconds=24):
    start, score = align_cd(pcm, source)
    if score < 0.8 or start < 0 or seconds < 24 or start+seconds*44100 > len(pcm):
        raise ValueError('The SB Pro CD track capture is missing.')
    cd = source.astype(float)/4
    windows = ((1, 6), (14, 18))
    error = max(float(np.max(abs(pcm[start+a*44100:start+b*44100].astype(float)-
                                cd[a*44100:b*44100]))) for a, b in windows)
    if error > 128:
        raise ValueError('The SB Pro CD samples exceed the conversion limit.')
    residual = pcm[start+6*44100:start+14*44100].astype(float)-cd[6*44100:14*44100]
    rms = float(np.sqrt(np.mean(residual*residual)))
    if rms <= 50:
        raise ValueError('The game sound is missing from the SB Pro capture.')
    return dict(cd_start_frame=start, cd_frames=9*44100, cd_windows_seconds=windows,
                cd_maximum_error=error, cd_correlation=score, game_residual_rms=rms)


def negative_controls(pcm, source, check, seconds, sbpro=False):
    start = check['cd_start_frame']
    first, last = start+44100, start+seconds*44100
    rejected = []
    for name in ('repeated-block', 'phase-jump', 'channel-swap', 'missing-game', 'missing-cd'):
        changed = pcm.copy()
        at = start+(2 if sbpro else 10)*44100
        if name == 'repeated-block':
            changed[at:at+1024] = changed[at-1024:at]
        elif name == 'phase-jump':
            changed[at:last-1024] = changed[at+1024:last]
        elif name == 'channel-swap':
            changed = changed[:, ::-1].copy()
        else:
            if sbpro and name == 'missing-game':
                first, last = start+6*44100, start+14*44100
                changed[first:last] = (source[6*44100:14*44100].astype(float)/4).astype(np.int16)
                first, last = start+44100, start+seconds*44100
            else:
                cd = source[44100:seconds*44100].astype(float)/4
                changed[first:last] = (cd if name == 'missing-game' else
                                      np.rint((changed[first:last]-cd)/64)*64).astype(np.int16)
        try:
            (verify_pro if sbpro else verify)(changed, source, seconds)
        except ValueError:
            rejected.append(name)
        else:
            raise ValueError(f'The waveform check accepted {name}.')
    return rejected


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--capture', type=Path, required=True)
    parser.add_argument('--bin', type=Path, required=True)
    parser.add_argument('--track-lba', type=int, required=True)
    parser.add_argument('--seconds', type=int, default=24)
    parser.add_argument('--sbpro', action='store_true')
    args = parser.parse_args()
    if args.track_lba < 0 or args.seconds < 7:
        parser.error('Use a valid track offset and at least seven seconds.')
    with wave.open(str(args.capture)) as wav:
        if (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) != (2, 2, 44100):
            raise ValueError('The capture format is not supported.')
        pcm = np.frombuffer(wav.readframes(wav.getnframes()), dtype='<i2').reshape(-1, 2)
    with args.bin.open('rb') as image:
        image.seek(args.track_lba*2352)
        raw = image.read(args.seconds*44100*4)
    if len(raw) != args.seconds*44100*4:
        raise ValueError('The source track is too short.')
    source = np.frombuffer(raw, dtype='<i2').reshape(-1, 2)
    check = (verify_pro if args.sbpro else verify)(pcm, source, args.seconds)
    check['negative_controls'] = negative_controls(pcm, source, check, args.seconds, args.sbpro)
    print(json.dumps(check, indent=2))


if __name__ == '__main__':
    main()
