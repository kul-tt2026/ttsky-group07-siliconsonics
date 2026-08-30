from pathlib import Path

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


import sys
sys.path.append("../")
from python_scripts.phase_to_angle_table import calculate_angle

MIC_SAMPLE_FREQUENCY = 4_000_000
SIGNAL_FREQUENCY = 40_000
WINDOW_SIZE = 100
SPEED_OF_SOUND = 344

THRESHOLD = 7
MIN_WIDTH = 5
BLANK = 64

ANGLE_TABLE = {}
for i in range(64):
    angle = calculate_angle(i * (2**6))
    ANGLE_TABLE[i] = 0 if angle is None else angle

def load_mic_bits(path: Path, mic_idx: int) -> list[int]:
    data = path.read_bytes()
    return [(byte >> mic_idx) & 0x1 for byte in data]


def generate_reference_cos_sin(samples: int):
    period_len = int(MIC_SAMPLE_FREQUENCY / SIGNAL_FREQUENCY)
    r_cos = np.arange(samples)
    r_cos = 1 - 2 * ((r_cos % period_len) >= (period_len / 2))
    r_sin = np.roll(r_cos, int(period_len / 4))
    return r_cos.astype(np.int16), r_sin.astype(np.int16)


def expected_echoes(bits1: list[int], bits2: list[int]):
    mic1 = np.array(bits1, dtype=np.int16)
    mic2 = np.array(bits2, dtype=np.int16)
    m1_t = 2 * mic1 - 1
    m2_t = 2 * mic2 - 1
    r_cos, r_sin = generate_reference_cos_sin(len(mic1))

    I1_raw = r_cos * m1_t
    Q1_raw = r_sin * m1_t
    I2_raw = r_cos * m2_t
    Q2_raw = r_sin * m2_t

    n = WINDOW_SIZE
    I1 = I1_raw[: len(I1_raw) - len(I1_raw) % n].reshape(-1, n).sum(axis=1)
    Q1 = Q1_raw[: len(Q1_raw) - len(Q1_raw) % n].reshape(-1, n).sum(axis=1)
    I2 = I2_raw[: len(I2_raw) - len(I2_raw) % n].reshape(-1, n).sum(axis=1)
    Q2 = Q2_raw[: len(Q2_raw) - len(Q2_raw) % n].reshape(-1, n).sum(axis=1)

    mag1 = np.abs(I1) + np.abs(Q1)
    mag2 = np.abs(I2) + np.abs(Q2)
    valid = (mag1 > THRESHOLD) & (mag2 > THRESHOLD)
    valid_idx = np.flatnonzero(valid)
    if len(valid_idx) == 0:
        return []

    diffs = np.diff(valid_idx)
    breaks = np.flatnonzero(diffs > 1) + 1
    runs = np.split(valid_idx, breaks)

    echoes = []
    for run in runs:
        if len(run) < MIN_WIDTH or run[0] < BLANK:
            continue
        acc_I1 = int(np.sum(I1[run]))
        acc_Q1 = int(np.sum(Q1[run]))
        acc_I2 = int(np.sum(I2[run]))
        acc_Q2 = int(np.sum(Q2[run]))
        p1 = np.arctan2(acc_Q1, acc_I1)
        p2 = np.arctan2(acc_Q2, acc_I2)
        if p1 < 0:
            p1 += 2 * np.pi
        if p2 < 0:
            p2 += 2 * np.pi
        p1_4096 = int(round(p1 / (2 * np.pi) * 4096)) & 0xFFF
        p2_4096 = int(round(p2 / (2 * np.pi) * 4096)) & 0xFFF
        delta_phase = (p2_4096 - p1_4096) & 0xFFF
        idx = delta_phase >> 6
        angle_raw = ANGLE_TABLE.get(idx)
        echoes.append(
            {
                "start": int(run[0]),
                "end": int(run[-1]),
                "peak": int(run[0] + len(run) // 2),
                "range_m": float(
                    (run[0] + len(run) // 2)
                    * WINDOW_SIZE
                    / MIC_SAMPLE_FREQUENCY
                    * SPEED_OF_SOUND
                    / 2
                ),
                "delta_phase": int(delta_phase),
                "angle_raw": angle_raw,
            }
        )
    return echoes


def safe_int(val):
    """Handle X/Z in cocotb values."""
    try:
        return int(val)
    except ValueError:
        return str(val)


# -------------------------------------------------------------------------
# Diagnostic test: dump internal signals every N windows
# -------------------------------------------------------------------------
@cocotb.test()
async def test_echo_angle_diagnostic(dut):
    data_path = (
        Path(__file__).resolve().parent
        / "data"
        / "2026-07-29_example-synthetic"
        / "raw"
        / "capture_001.pdm"
    )

    bits1 = load_mic_bits(data_path, 0)
    bits2 = load_mic_bits(data_path, 1)
    expected = expected_echoes(bits1, bits2)

    dut._log.info(f"Python model predicts {len(expected)} echo(s)")
    for e in expected:
        dut._log.info(
            f"  peak@{e['peak']:3d} | {e['range_m']:.2f} m | "
            f"delta={e['delta_phase']:4d} | angle_raw={e['angle_raw']}"
        )

    clock = Clock(dut.clk, 25, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.rst_n.value = 0
    dut.start_measurement_ead.value = 0
    dut.mic1_pdm_t.value = 0
    dut.mic2_pdm_t.value = 0
    dut.ena.value = 1
    await Timer(500, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Resolve hierarchical signals inside echo_angle_detector_test
    inst = dut.echo_angle_detector_test

    # Check that our wires are actually reachable
    try:
        _ = inst.state.value
        dut._log.info("Found echo_angle_detector_test.state")
    except Exception as e:
        dut._log.error(f"Cannot probe echo_angle_detector_test.state: {e}")
        return

    # Snoop outputs
    hw_results = []

    async def monitor():
        prev_valid = 0
        while True:
            await RisingEdge(dut.clk)
            try:
                valid = int(inst.angle_valid.value)
            except:
                valid = 0
            if valid and not prev_valid:
                hw_results.append(
                    {
                        "angle": safe_int(inst.angle_out.value),
                        "window": safe_int(inst.echo_window.value),
                    }
                )
                dut._log.info(
                    f"*** HW angle_valid: window={safe_int(inst.echo_window.value)} "
                    f"angle={safe_int(inst.angle_out.value)}"
                )
            prev_valid = valid

    monitor_task = cocotb.start_soon(monitor())

    # Start measurement
    dut.start_measurement_ead.value = 1
    await RisingEdge(dut.clk)
    dut.start_measurement_ead.value = 0

    # Feed both mics
    total_samples = min(len(bits1), len(bits2))
    dut._log.info(f"Feeding {total_samples} PDM samples...")

    # Diagnostic: dump state every 1000 clock cycles (100 windows)
    dump_every = 1000
    next_dump = dump_every

    for idx in range(total_samples):
        dut.mic1_pdm_t.value = bits1[idx]
        dut.mic2_pdm_t.value = bits2[idx]

        for _ in range(10):
            await RisingEdge(dut.clk)

            next_dump -= 1
            if next_dump <= 0:
                next_dump = dump_every
                dut._log.info(
                    f"[{int(dut.clk.value):>8}] "
                    f"state={safe_int(inst.state.value)} "
                    f"wc={safe_int(inst.window_counter.value)} "
                    f"sig1={safe_int(inst.sig1.value):>3} "
                    f"sig2={safe_int(inst.sig2.value):>3} "
                    f"acc={safe_int(inst.accum_cnt.value):>3} "
                    f"iq1v={safe_int(inst.iq1_valid.value)} "
                    f"iq2v={safe_int(inst.iq2_valid.value)} "
                    f"tick={safe_int(dut.tick_4mhz.value)}"
                )

    await Timer(5000, unit="ns")
    monitor_task.cancel()

    dut._log.info(f"Hardware reported {len(hw_results)} echo(s)")

    if len(hw_results) == 0:
        dut._log.error("NO ECHOES DETECTED")
        dut._log.error("Possible causes:")
        dut._log.error("  1. start_measurement_ead is not reaching the internal module")
        dut._log.error("  2. mic1_pdm_t / mic2_pdm_t are X due to driver conflict with ui_in")
        dut._log.error("  3. tick_4mhz is not toggling")
        dut._log.error("  4. sig1/sig2 never cross threshold")

    # Final dump of last known state
    dut._log.info(
        f"Final state: {safe_int(inst.state.value)} "
        f"wc={safe_int(inst.window_counter.value)} "
        f"acc={safe_int(inst.accum_cnt.value)}"
    )

    # Soft assertion so you still see the log
    assert len(hw_results) >= len(expected), (
        f"Expected {len(expected)} echoes, got {len(hw_results)}"
    )