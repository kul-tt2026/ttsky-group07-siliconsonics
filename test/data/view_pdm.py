#!/usr/bin/env python3
"""
view_pdm.py - visualise a raw .pdm capture the way the RTL sees it.

The plots deliberately mirror the hardware chain in echo_timing.v:
square-wave I/Q correlation over 100-sample windows, |I|+|Q| envelope,
threshold and blanking gates. So what you see here is what the chip
should decide, not an idealised DSP view.

Usage:
    python view_pdm.py capture_000.pdm
    python view_pdm.py capture_000.pdm --mic 2 --save out.png
    python view_pdm.py capture_000.pdm --mics 0,1 --max-range 3
"""

import argparse
from pathlib import Path

import numpy as np
import matplotlib
import matplotlib.pyplot as plt

# --- Constants, matching the RTL ---------------------------------------
PDM_HZ = 4_000_000       # mic sample rate
F_DRIVE = 40_000         # transducer frequency
WINDOW = 100             # samples per accumulate-and-dump window
THRESHOLD = 16           # |I|+|Q| echo threshold (first_echo_timing)
BLANK = 64               # windows ignored after ping (ringdown)
SPEED_OF_SOUND = 343.0   # m/s


def load_mic(path: Path, mic_idx: int) -> np.ndarray:
    """Extract one mic's PDM bitstream. Bit N of each byte = mic N."""
    data = np.frombuffer(path.read_bytes(), dtype=np.uint8)
    # Cast to a signed type BEFORE arithmetic: on uint8, 2*0-1 wraps to 255.
    bits = ((data >> mic_idx) & 1).astype(np.int16)
    return bits


def make_references(n: int):
    """Square-wave sin/cos at F_DRIVE, exactly as ref_sig generates them."""
    period = int(PDM_HZ / F_DRIVE)          # 100 samples per 40 kHz period
    cos = np.arange(n)
    cos = 1 - 2 * ((cos % period) >= (period / 2))
    sin = np.roll(cos, period // 4)          # 90 deg = 25 samples
    return cos.astype(np.int16), sin.astype(np.int16)


def demodulate(bits: np.ndarray):
    """Windowed I/Q, matching windowed_iq_demodulator."""
    signal = 2 * bits - 1                    # PDM 0/1 -> -1/+1
    cos, sin = make_references(len(signal))

    usable = len(signal) - len(signal) % WINDOW
    I = (cos * signal)[:usable].reshape(-1, WINDOW).sum(axis=1)
    Q = (sin * signal)[:usable].reshape(-1, WINDOW).sum(axis=1)
    return I, Q


def window_to_range(w):
    """Window index -> one-way distance in metres."""
    return w * WINDOW / PDM_HZ * SPEED_OF_SOUND / 2


def first_echo(mag: np.ndarray):
    """Replicates first_echo_timing: first window past BLANK over THRESHOLD."""
    idx = np.arange(len(mag))
    hits = np.flatnonzero((mag >= THRESHOLD) & (idx >= BLANK))
    return int(hits[0]) if len(hits) else None


def echo_peak(mag: np.ndarray, start: int):
    """Walk forward from start until the signal drops back under threshold."""
    end = start
    while end + 1 < len(mag) and mag[end + 1] >= THRESHOLD:
        end += 1
    return start + int(np.argmax(mag[start:end + 1])), end


def plot_capture(path: Path, mic_idx: int, max_range: float, save: Path | None):
    bits = load_mic(path, mic_idx)
    I, Q = demodulate(bits)
    mag = np.abs(I) + np.abs(Q)

    windows = np.arange(len(mag))
    ranges = window_to_range(windows)

    # Limit the x-axis to something readable
    limit = np.searchsorted(ranges, max_range)
    limit = min(limit, len(mag))

    detect = first_echo(mag)
    peak = end = None
    if detect is not None:
        peak, end = echo_peak(mag, detect)

    fig, axes = plt.subplots(3, 1, figsize=(13, 9), height_ratios=[2, 1.4, 1.4])
    fig.suptitle(
        f"{path.name}  -  mic {mic_idx}  "
        f"({len(bits)/PDM_HZ*1000:.0f} ms, {len(mag)} windows)",
        fontsize=12,
    )

    # ---- 1. Envelope with the hardware's decision gates ----------------
    ax = axes[0]
    ax.plot(ranges[:limit], mag[:limit], lw=1.0, color="#2b6cb0",
            label="|I| + |Q|")
    ax.axhline(THRESHOLD, color="#c53030", ls="--", lw=1,
               label=f"threshold = {THRESHOLD}")
    ax.axvspan(0, window_to_range(BLANK), color="#cbd5e0", alpha=0.5,
               label=f"blanked ({BLANK} windows)")

    if detect is not None:
        ax.axvline(ranges[detect], color="#dd6b20", lw=1.2,
                   label=f"RTL trigger: w{detect} = {ranges[detect]:.3f} m")
        ax.axvline(ranges[peak], color="#38a169", lw=1.2,
                   label=f"echo peak: w{peak} = {ranges[peak]:.3f} m")

    ax.set_ylabel("|I| + |Q|")
    ax.set_xlim(0, max_range)
    ax.legend(fontsize=8, loc="upper right")
    ax.grid(alpha=0.3)

    # ---- 2. Signed I and Q --------------------------------------------
    ax = axes[1]
    ax.plot(ranges[:limit], I[:limit], lw=0.9, color="#2f855a", label="I")
    ax.plot(ranges[:limit], Q[:limit], lw=0.9, color="#975a16", label="Q")
    ax.axhline(0, color="black", lw=0.5)
    ax.set_ylabel("I / Q")
    ax.set_xlim(0, max_range)
    ax.legend(fontsize=8, loc="upper right")
    ax.grid(alpha=0.3)

    # ---- 3. Raw PDM density around the echo ---------------------------
    ax = axes[2]
    if detect is not None:
        lo = max(0, (detect - 6) * WINDOW)
        hi = min(len(bits), (end + 6) * WINDOW)
    else:
        lo, hi = 0, min(len(bits), 60 * WINDOW)

    seg = bits[lo:hi]
    # Short moving average turns the bitstream back into a visible waveform
    kernel = 8
    density = np.convolve(seg.astype(float), np.ones(kernel) / kernel, mode="same")
    t_us = (np.arange(lo, hi) / PDM_HZ) * 1e6

    ax.plot(t_us, density - 0.5, lw=0.6, color="#4a5568")
    ax.set_ylabel(f"PDM density\n({kernel}-tap avg)")
    ax.set_xlabel("time (us)   |   top two axes: one-way range (m)")
    ax.grid(alpha=0.3)

    plt.tight_layout(rect=[0, 0, 1, 0.97])

    # ---- Console summary ----------------------------------------------
    noise = mag[BLANK:detect - 4] if detect and detect > BLANK + 4 else mag[BLANK:]
    print(f"{path.name}  mic {mic_idx}")
    print(f"  windows        : {len(mag)}")
    print(f"  noise (post-blank): max {noise.max()}, mean {noise.mean():.1f}")
    if detect is not None:
        print(f"  RTL trigger    : window {detect}  ->  {ranges[detect]:.3f} m")
        print(f"  echo peak      : window {peak}  ->  {ranges[peak]:.3f} m  (mag {mag[peak]})")
        print(f"  echo width     : {end - detect + 1} windows")
    else:
        print("  no echo crossed the threshold")

    if save:
        fig.savefig(save, dpi=130)
        print(f"  saved          : {save}")
    else:
        plt.show()


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("capture", type=Path, help="path to a .pdm file")
    p.add_argument("--mic", type=int, default=0,
                   help="which bit/mic to plot (default 0)")
    p.add_argument("--max-range", type=float, default=3.0,
                   help="x-axis limit in metres (default 3)")
    p.add_argument("--save", type=Path, default=None,
                   help="write a PNG instead of opening a window")
    args = p.parse_args()

    if args.save:
        matplotlib.use("Agg")

    plot_capture(args.capture, args.mic, args.max_range, args.save)


if __name__ == "__main__":
    main()
