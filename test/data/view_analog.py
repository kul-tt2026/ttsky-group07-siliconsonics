#!/usr/bin/env python3
"""
view_analog.py - reconstruct the analog acoustic waveform from a raw .pdm
capture and plot it.

PDM is a 1-bit stream at 4 MHz whose *local density* encodes the analog
amplitude. Recovering the waveform is just: map 0/1 to -1/+1, low-pass to
throw away the shaping noise up at MHz, then decimate down to a sane rate.

Usage:
    python view_analog.py capture_000.pdm
    python view_analog.py capture_000.pdm --mic 3 --zoom 0.795 0.86
    python view_analog.py capture_000.pdm --mics 0,1 --save out.png
"""

import argparse
from pathlib import Path

import numpy as np
import matplotlib
import matplotlib.pyplot as plt
from scipy import signal as sps

PDM_HZ = 4_000_000
F_DRIVE = 40_000
SPEED_OF_SOUND = 343.0
DECIM = 8                      # 4 MHz -> 500 kHz, still 12x oversampled at 40 kHz


def load_mic(path: Path, mic_idx: int) -> np.ndarray:
    data = np.frombuffer(path.read_bytes(), dtype=np.uint8)
    # Cast before arithmetic: on uint8, 2*0-1 wraps to 255.
    return ((data >> mic_idx) & 1).astype(np.int16)


def pdm_to_analog(bits: np.ndarray, decim: int = DECIM):
    """
    PDM bitstream -> analog waveform.

    Step 1: 0/1 -> -1/+1. The average of this over any short span IS the
            analog value; everything else is quantisation noise pushed to
            high frequency by the mic's sigma-delta modulator.
    Step 2: low-pass at ~100 kHz. Keeps 40 kHz and its immediate sidebands,
            kills the MHz-region shaping noise.
    Step 3: decimate to 500 kHz so the arrays are manageable.
    """
    x = (2.0 * bits - 1.0)

    fs_out = PDM_HZ / decim
    cutoff = 100_000                       # Hz
    # decimate() applies its own anti-alias filter, but an explicit sharper
    # one first gives a much cleaner 40 kHz recovery.
    sos = sps.butter(6, cutoff, btype="low", fs=PDM_HZ, output="sos")
    x = sps.sosfiltfilt(sos, x)            # zero-phase: no group delay to correct

    x = sps.decimate(x, decim, ftype="fir", zero_phase=True)
    return x, fs_out


def bandpass(x: np.ndarray, fs: float, low=25_000, high=60_000):
    """Isolate the 40 kHz band - this is the 'clean' acoustic signal."""
    sos = sps.butter(4, [low, high], btype="band", fs=fs, output="sos")
    return sps.sosfiltfilt(sos, x)


def envelope(x: np.ndarray):
    """Analytic-signal magnitude: the outline of the burst."""
    return np.abs(sps.hilbert(x))


def t_to_range(t_s):
    return t_s * SPEED_OF_SOUND / 2


def plot(path: Path, mics, zoom, save):
    fig, axes = plt.subplots(3, 1, figsize=(13, 9))
    fig.suptitle(f"{path.name}  -  reconstructed analog waveform", fontsize=12)

    colors = ["#2b6cb0", "#c05621", "#2f855a", "#805ad5",
              "#b7791f", "#c53030", "#2c7a7b"]

    first = None
    for n, mic in enumerate(mics):
        bits = load_mic(path, mic)
        wave, fs = pdm_to_analog(bits)
        band = bandpass(wave, fs)
        env = envelope(band)

        t = np.arange(len(wave)) / fs
        rng = t_to_range(t)

        if first is None:
            first = (t, rng, fs)

        c = colors[n % len(colors)]

        # ---- 1. Full capture, envelope only (waveform is unreadable here)
        axes[0].plot(rng, env, lw=0.9, color=c, label=f"mic {mic}")

        # ---- 2. Zoomed raw waveform
        if zoom:
            lo_t, hi_t = zoom[0] * 2 / SPEED_OF_SOUND, zoom[1] * 2 / SPEED_OF_SOUND
        else:
            # auto-zoom on the strongest peak outside the ringdown
            guard = int(0.002 * fs)          # skip first 2 ms
            pk = guard + int(np.argmax(env[guard:]))
            lo_t = max(0, (pk - int(0.0004 * fs))) / fs
            hi_t = min(len(env) - 1, (pk + int(0.0004 * fs))) / fs

        m = (t >= lo_t) & (t <= hi_t)
        axes[1].plot(t[m] * 1e3, band[m], lw=1.0, color=c, label=f"mic {mic}")
        axes[1].plot(t[m] * 1e3, env[m], lw=0.9, ls="--", color=c, alpha=0.6)

        # ---- 3. The transmit ping itself (start of capture)
        m0 = t <= 0.0012
        axes[2].plot(t[m0] * 1e3, band[m0], lw=0.9, color=c, label=f"mic {mic}")

        peak_t = t[guard + int(np.argmax(env[int(0.002*fs):]))] if len(mics) else 0
        print(f"mic {mic}: peak envelope {env[int(0.002*fs):].max():.4f} "
              f"at {t_to_range(peak_t):.3f} m")

    axes[0].set_ylabel("envelope")
    axes[0].set_xlabel("one-way range (m)")
    axes[0].set_xlim(0, 3)
    axes[0].grid(alpha=0.3)
    axes[0].legend(fontsize=8)
    axes[0].set_title("full capture - 40 kHz envelope", fontsize=10, loc="left")

    axes[1].set_ylabel("amplitude")
    axes[1].set_xlabel("time (ms)")
    axes[1].grid(alpha=0.3)
    axes[1].legend(fontsize=8)
    axes[1].set_title("echo - reconstructed waveform (dashed = envelope)",
                      fontsize=10, loc="left")

    axes[2].set_ylabel("amplitude")
    axes[2].set_xlabel("time (ms)")
    axes[2].grid(alpha=0.3)
    axes[2].legend(fontsize=8)
    axes[2].set_title("transmit ping + ringdown", fontsize=10, loc="left")

    plt.tight_layout(rect=[0, 0, 1, 0.96])

    if save:
        fig.savefig(save, dpi=130)
        print(f"saved: {save}")
    else:
        plt.show()


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("capture", type=Path)
    p.add_argument("--mic", type=int, default=None, help="single mic (bit index)")
    p.add_argument("--mics", type=str, default=None,
                   help="comma-separated mics, e.g. 0,1")
    p.add_argument("--zoom", type=float, nargs=2, metavar=("LO_M", "HI_M"),
                   default=None, help="zoom window in metres for panel 2")
    p.add_argument("--save", type=Path, default=None)
    args = p.parse_args()

    if args.mics:
        mics = [int(m) for m in args.mics.split(",")]
    elif args.mic is not None:
        mics = [args.mic]
    else:
        mics = [0]

    if args.save:
        matplotlib.use("Agg")

    plot(args.capture, mics, args.zoom, args.save)


if __name__ == "__main__":
    main()
