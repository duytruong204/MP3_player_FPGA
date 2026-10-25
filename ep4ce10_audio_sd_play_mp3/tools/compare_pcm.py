#!/usr/bin/env python3
"""Compare the PCM captured from the RTL simulation (or SignalTap) with the
golden WAV of the same song.

  hw  : text file, one "left right" pair per line, signed decimal, sampled by
        the DAC serialiser (tb/out/pcm_hw.txt).  Rate = the WM8978 LRC rate,
        11.2903 MHz / 256 = 44102.8 Hz.
  ref : 16-bit stereo PCM WAV (default ../clean_46875.wav, made at 46875 Hz
        for the golden project).  It is resampled to the hw rate with the same
        windowed-sinc resampler as the golden tool, then aligned in time with a
        cross-correlation and compared (SNR, gain, L/R order).

Usage: compare_pcm.py [hw.txt] [ref.wav] [--rate 44102.8] [--min-snr 12] [--gain 1.0]
Exit code 0 = match, 1 = mismatch.
"""
import argparse
import importlib.util
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
GOLD_TOOL = os.path.join(HERE, "..", "..", "ep4ce10_audio_sd_play_wav", "tools", "resample_wav.py")


def load_golden_tool():
    spec = importlib.util.spec_from_file_location("resample_wav", GOLD_TOOL)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def xcorr_lag(a, b, maxlag):
    """lag such that b[n + lag] ~ a[n]; both mono float arrays.  The signals
    are differentiated first so that the (strong) low-frequency content does
    not smear the correlation peak."""
    a = np.diff(a)
    b = np.diff(b)
    n = 1
    while n < len(a) + len(b):
        n *= 2
    fa = np.fft.rfft(a, n)
    fb = np.fft.rfft(b, n)
    c = np.fft.irfft(fb * np.conj(fa), n)
    lags = np.concatenate([np.arange(0, maxlag + 1), np.arange(-maxlag, 0)])
    idx = np.concatenate([np.arange(0, maxlag + 1), np.arange(n - maxlag, n)])
    return int(lags[np.argmax(c[idx])])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("hw", nargs="?", default=os.path.join(HERE, "..", "tb", "out", "pcm_hw.txt"))
    ap.add_argument("ref", nargs="?", default=os.path.join(HERE, "..", "clean_46875.wav"))
    ap.add_argument("--rate", type=float, default=50e6 * 7 / 31 / 256)
    ap.add_argument("--content-rate", type=float, default=44100.0,
                    help="sample rate of the decoded MP3 (the hw plays these samples at --rate)")
    ap.add_argument("--min-snr", type=float, default=12.0,
                    help="dB.  MAC_MP3 is a 16-bit fixed-point decoder: 11..40 dB per granule vs. a float decoder "
                         "is normal, ~23 dB overall at the quiet start of clean.mp3")
    ap.add_argument("--gain", type=float, default=1.0,
                    help="expected hw/ref gain (1.0 with pcm_out_ctrl GAIN_SHIFT=1, 0.5 with GAIN_SHIFT=0)")
    ap.add_argument("--skip", type=float, default=0.3, help="seconds of hw output to ignore at the start")
    a = ap.parse_args()

    hw = np.loadtxt(a.hw, dtype=np.int64)
    if hw.ndim != 2 or hw.shape[1] != 2:
        raise SystemExit("hw file must have two columns")
    hw = hw.astype(np.float64)
    rw = load_golden_tool()
    ref46, src_rate = rw.read_wav(a.ref)
    print("hw  : %d frames @ %.2f Hz (%.3f s)" % (len(hw), a.rate, len(hw) / a.rate))
    print("ref : %d frames @ %d Hz (%.3f s)" % (len(ref46), src_rate, len(ref46) / src_rate))

    # reference part that can possibly overlap the hw capture (first hw.len + 2 s)
    nref = int((len(hw) / a.rate + 2.0) * src_rate)
    ref = rw.resample(ref46[:nref], src_rate, int(round(a.content_rate)))
    ref = ref.astype(np.float64)

    skip = int(a.skip * a.rate)
    mono_hw = hw[skip:].sum(axis=1)
    mono_ref = ref.sum(axis=1)
    lag = xcorr_lag(mono_hw, mono_ref, int(2.0 * a.rate)) - skip   # relative to hw[0]
    print("alignment: hw[n] == ref[n %+d]  (hw is %.2f ms %s)" % (lag, abs(lag) / a.rate * 1000, "late" if lag < 0 else "early"))
    start = skip
    n = min(len(hw) - start, len(ref) - (start + lag))
    h = hw[start:start + n]
    r = ref[start + lag:start + lag + n]
    # per-channel least-squares gain
    ok = True
    for ch, name in ((0, "left "), (1, "right")):
        g = (h[:, ch] @ r[:, ch]) / max(r[:, ch] @ r[:, ch], 1e-9)
        err = h[:, ch] - g * r[:, ch]
        snr = 10 * np.log10((r[:, ch] @ r[:, ch] * g * g + 1e-9) / (err @ err + 1e-9))
        print("%s: gain %.4f  SNR %.1f dB  rms hw %.1f  rms ref %.1f" %
              (name, g, snr, np.sqrt((h[:, ch] ** 2).mean()), np.sqrt((r[:, ch] ** 2).mean())))
        if np.corrcoef(h[:, ch], r[:, ch])[0, 1] < 0.97:
            ok = False
        if snr < a.min_snr or not 0.9 * a.gain < g < 1.1 * a.gain:
            ok = False
    # channel order check: left of hw against right of ref should be worse
    sw = (h[:, 0] @ r[:, 1]) / max(np.sqrt((h[:, 0] @ h[:, 0]) * (r[:, 1] @ r[:, 1])), 1e-9)
    st = (h[:, 0] @ r[:, 0]) / max(np.sqrt((h[:, 0] @ h[:, 0]) * (r[:, 0] @ r[:, 0])), 1e-9)
    print("channel check: corr(hw L, ref L) = %.4f   corr(hw L, ref R) = %.4f" % (st, sw))
    print("RESULT:", "MATCH" if ok else "MISMATCH")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
