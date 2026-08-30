# from pathlib import Path

# import cocotb
# import numpy as np
# from cocotb.clock import Clock
# from cocotb.triggers import RisingEdge, Timer

# MIC_SAMPLE_FREQUENCY = 4_000_000
# SIGNAL_FREQUENCY = 40_000
# WINDOW_SIZE = 100
# SPEED_OF_SOUND = 344

# # Match Verilog echo_angle_detector parameters exactly
# THRESHOLD = 10
# MIN_WIDTH = 5
# BLANK = 64

# ANGLE_TABLE = {
#     0: 0, 1: 0, 2: 1, 3: 1, 4: 2, 5: 2, 6: 3, 7: 3,
#     8: 4, 9: 4, 10: 5, 11: 5, 12: 6, 13: 6, 14: 7, 15: 7,
#     16: 8, 17: 9, 18: 10, 19: 10, 20: 11, 21: 12, 22: 14,
#     42: 50, 43: 52, 44: 53, 45: 54, 46: 54, 47: 55, 48: 56,
#     49: 57, 50: 57, 51: 58, 52: 58, 53: 59, 54: 59, 55: 60,
#     56: 60, 57: 61, 58: 61, 59: 62, 60: 62, 61: 63, 62: 63,
#     63: 0,
# }


# def load_mic_bits(path: Path, mic_idx: int) -> list[int]:
#     data = path.read_bytes()
#     return [(byte >> mic_idx) & 0x1 for byte in data]


# def generate_reference_cos_sin(samples: int):
#     period_len = int(MIC_SAMPLE_FREQUENCY / SIGNAL_FREQUENCY)
#     r_cos = np.arange(samples)
#     r_cos = 1 - 2 * ((r_cos % period_len) >= (period_len / 2))
#     r_sin = np.roll(r_cos, int(period_len / 4))
#     return r_cos.astype(np.int16), r_sin.astype(np.int16)


# def expected_echoes(bits1: list[int], bits2: list[int]):
#     mic1 = np.array(bits1, dtype=np.int16)
#     mic2 = np.array(bits2, dtype=np.int16)
#     m1_t = 2 * mic1 - 1
#     m2_t = 2 * mic2 - 1

#     r_cos, r_sin = generate_reference_cos_sin(len(mic1))

#     I1_raw = r_cos * m1_t
#     Q1_raw = r_sin * m1_t
#     I2_raw = r_cos * m2_t
#     Q2_raw = r_sin * m2_t

#     n = WINDOW_SIZE
#     I1 = I1_raw[: len(I1_raw) - len(I1_raw) % n].reshape(-1, n).sum(axis=1)
#     Q1 = Q1_raw[: len(Q1_raw) - len(Q1_raw) % n].reshape(-1, n).sum(axis=1)
#     I2 = I2_raw[: len(I2_raw) - len(I2_raw) % n].reshape(-1, n).sum(axis=1)
#     Q2 = Q2_raw[: len(Q2_raw) - len(Q2_raw) % n].reshape(-1, n).sum(axis=1)

#     mag1 = np.abs(I1) + np.abs(Q1)
#     mag2 = np.abs(I2) + np.abs(Q2)

#     valid = (mag1 > THRESHOLD) & (mag2 > THRESHOLD)
#     valid_idx = np.flatnonzero(valid)

#     if len(valid_idx) == 0:
#         return []

#     diffs = np.diff(valid_idx)
#     breaks = np.flatnonzero(diffs > 1) + 1
#     runs = np.split(valid_idx, breaks)

#     echoes = []
#     for run in runs:
#         if len(run) < MIN_WIDTH or run[0] < BLANK:
#             continue

#         acc_I1 = int(np.sum(I1[run]))
#         acc_Q1 = int(np.sum(Q1[run]))
#         acc_I2 = int(np.sum(I2[run]))
#         acc_Q2 = int(np.sum(Q2[run]))

#         p1 = np.arctan2(acc_Q1, acc_I1)
#         p2 = np.arctan2(acc_Q2, acc_I2)
#         if p1 < 0:
#             p1 += 2 * np.pi
#         if p2 < 0:
#             p2 += 2 * np.pi

#         p1_4096 = int(round(p1 / (2 * np.pi) * 4096)) & 0xFFF
#         p2_4096 = int(round(p2 / (2 * np.pi) * 4096)) & 0xFFF

#         delta_phase = (p2_4096 - p1_4096) & 0xFFF
#         idx = delta_phase >> 6
#         angle_raw = ANGLE_TABLE.get(idx)

#         echoes.append(
#             {
#                 "start": int(run[0]),
#                 "end": int(run[-1]),
#                 "peak": int(run[0] + len(run) // 2),
#                 "range_m": float(
#                     (run[0] + len(run) // 2)
#                     * WINDOW_SIZE
#                     / MIC_SAMPLE_FREQUENCY
#                     * SPEED_OF_SOUND
#                     / 2
#                 ),
#                 "delta_phase": int(delta_phase),
#                 "angle_raw": angle_raw,
#             }
#         )
#     return echoes


# def get_dut_signal(dut, name: str):
#     """Try direct access, then fall back to hierarchical instance."""
#     try:
#         return getattr(dut, name)
#     except AttributeError:
#         try:
#             return getattr(dut.echo_angle_detector_test, name)
#         except AttributeError:
#             return None


# # -------------------------------------------------------------------------
# # Helper: peek at internal signals for debug
# # -------------------------------------------------------------------------
# async def debug_probe(dut, log):
#     sig_state = get_dut_signal(dut, "state")
#     sig_sig1 = get_dut_signal(dut, "sig1")
#     sig_sig2 = get_dut_signal(dut, "sig2")
#     sig_wc = get_dut_signal(dut, "window_counter")
#     sig_acc = get_dut_signal(dut, "accum_cnt")
#     sig_av = get_dut_signal(dut, "angle_valid")

#     if sig_state is None:
#         log.warning("Cannot probe internal signals (hierarchy mismatch or optimized away)")
#         return

#     for _ in range(20):
#         await RisingEdge(dut.clk)
#         log.info(
#             f"state={int(sig_state.value)} wc={int(sig_wc.value) if sig_wc else '?'}"
#             f" sig1={int(sig_sig1.value) if sig_sig1 else '?'} sig2={int(sig_sig2.value) if sig_sig2 else '?'}"
#             f" accum={int(sig_acc.value) if sig_acc else '?'} av={int(sig_av.value) if sig_av else '?'}"
#         )


# # -------------------------------------------------------------------------
# # Test: synthetic scene (0.6 m @ +15°, 1.4 m @ -10°)
# # -------------------------------------------------------------------------
# @cocotb.test()
# async def test_echo_angle_synthetic(dut):
#     data_path = (
#         Path(__file__).resolve().parent
#         / "data"
#         / "2026-07-29_example-synthetic"
#         / "raw"
#         / "capture_001.pdm"
#     )

#     bits1 = load_mic_bits(data_path, 0)
#     bits2 = load_mic_bits(data_path, 1)
#     expected = expected_echoes(bits1, bits2)

#     dut._log.info(f"Python model predicts {len(expected)} echo(s)")
#     for e in expected:
#         dut._log.info(
#             f"  peak@{e['peak']:3d} | {e['range_m']:.2f} m | "
#             f"delta={e['delta_phase']:4d} | angle_raw={e['angle_raw']}"
#         )

#     # 40 MHz clock
#     clock = Clock(dut.clk, 25, unit="ns")
#     cocotb.start_soon(clock.start())

#     # Reset
#     dut.rst_n.value = 0
#     dut.ui_in.value = 0
#     dut.ena.value = 1
#     dut.uio_in.value = 0
#     await Timer(200, unit="ns")
#     dut.rst_n.value = 1
#     await RisingEdge(dut.clk)

#     # Resolve output signals
#     angle_out_sig = get_dut_signal(dut, "angle_out")
#     angle_valid_sig = get_dut_signal(dut, "angle_valid")
#     echo_window_sig = get_dut_signal(dut, "echo_window")
#     echo_found_sig = get_dut_signal(dut, "echo_found")

#     assert angle_valid_sig is not None, (
#         "Cannot find angle_valid in DUT hierarchy. "
#         "If you wrapped the module, update get_dut_signal()."
#     )

#     # Snoop angle_valid pulses
#     hw_results = []

#     async def monitor():
#         prev_valid = 0
#         while True:
#             await RisingEdge(dut.clk)
#             valid = int(angle_valid_sig.value)
#             if valid and not prev_valid:
#                 hw_results.append(
#                     {
#                         "angle": int(angle_out_sig.value),
#                         "window": int(echo_window_sig.value),
#                     }
#                 )
#                 dut._log.info(
#                     f"HW angle_valid pulse: window={int(echo_window_sig.value)} "
#                     f"angle={int(angle_out_sig.value)}"
#                 )
#             prev_valid = valid

#     monitor_task = cocotb.start_soon(monitor())

#     # Start measurement pulse
#     dut.ui_in.value = 0b01  # start=1, mic1=0, mic2=0
#     await RisingEdge(dut.clk)
#     dut.ui_in.value = 0b00

#     # Feed both mics: ui_in[1]=mic1, ui_in[2]=mic2
#     total_samples = min(len(bits1), len(bits2))
#     dut._log.info(f"Feeding {total_samples} PDM samples...")
#     for idx in range(total_samples):
#         val = (bits1[idx] << 1) | (bits2[idx] << 2)
#         dut.ui_in.value = val
#         for _ in range(10):
#             await RisingEdge(dut.clk)

#     # Wait long enough for last echo to process (CORDIC + overhead)
#     await Timer(5000, unit="ns")
#     monitor_task.kill()

#     dut._log.info(f"Hardware reported {len(hw_results)} echo(s)")

#     # ---------------------------------------------------------------------
#     # Debug: if nothing found, dump internal state for a few windows
#     # ---------------------------------------------------------------------
#     if len(hw_results) == 0:
#         dut._log.warning("No hardware echoes detected — running debug probe")
#         await debug_probe(dut, dut._log)

#     # Strip direct-coupling spike (window < BLANK)
#     hw_real = [r for r in hw_results if r["window"] >= BLANK]
#     exp_real = [e for e in expected if e["peak"] >= BLANK]

#     assert len(hw_results) >= len(expected), (
#         f"Expected at least {len(expected)} total echoes, got {len(hw_results)}. "
#         f"If 0, check that ui_in[2] (mic2) is wired in your top-level!"
#     )

#     assert len(hw_real) >= len(exp_real), (
#         f"Expected {len(exp_real)} real echoes (>=blank), got {len(hw_real)}"
#     )

#     for i, (hw, exp) in enumerate(zip(hw_real, exp_real)):
#         dut._log.info(
#             f"Checking echo {i+1}: hw_w={hw['window']} exp_w={exp['peak']}"
#         )
#         assert hw["window"] == exp["peak"], (
#             f"Echo {i+1}: expected window {exp['peak']}, got {hw['window']}"
#         )
#         assert hw["angle"] == exp["angle_raw"], (
#             f"Echo {i+1}: expected angle_raw {exp['angle_raw']}, "
#             f"got {hw['angle']}"
#         )


# # -------------------------------------------------------------------------
# # Test: wall at 0.88 m
# # -------------------------------------------------------------------------
# @cocotb.test()
# async def test_echo_angle_wall88(dut):
#     data_path = (
#         Path(__file__).resolve().parent
#         / "data"
#         / "2026-07-29_wall-0m88"
#         / "raw"
#         / "capture_000.pdm"
#     )

#     bits1 = load_mic_bits(data_path, 0)
#     bits2 = load_mic_bits(data_path, 1)
#     expected = expected_echoes(bits1, bits2)

#     dut._log.info(f"Python model predicts {len(expected)} echo(s)")
#     for e in expected:
#         dut._log.info(
#             f"  peak@{e['peak']:3d} | {e['range_m']:.2f} m | angle_raw={e['angle_raw']}"
#         )

#     clock = Clock(dut.clk, 25, unit="ns")
#     cocotb.start_soon(clock.start())

#     dut.rst_n.value = 0
#     dut.ui_in.value = 0
#     dut.ena.value = 1
#     dut.uio_in.value = 0
#     await Timer(200, unit="ns")
#     dut.rst_n.value = 1
#     await RisingEdge(dut.clk)

#     angle_out_sig = get_dut_signal(dut, "angle_out")
#     angle_valid_sig = get_dut_signal(dut, "angle_valid")
#     echo_window_sig = get_dut_signal(dut, "echo_window")

#     hw_results = []

#     async def monitor():
#         prev_valid = 0
#         while True:
#             await RisingEdge(dut.clk)
#             valid = int(angle_valid_sig.value)
#             if valid and not prev_valid:
#                 hw_results.append(
#                     {
#                         "angle": int(angle_out_sig.value),
#                         "window": int(echo_window_sig.value),
#                     }
#                 )
#             prev_valid = valid

#     monitor_task = cocotb.start_soon(monitor())

#     dut.ui_in.value = 0b01
#     await RisingEdge(dut.clk)
#     dut.ui_in.value = 0b00

#     total_samples = min(len(bits1), len(bits2))
#     for idx in range(total_samples):
#         val = (bits1[idx] << 1) | (bits2[idx] << 2)
#         dut.ui_in.value = val
#         for _ in range(10):
#             await RisingEdge(dut.clk)

#     await Timer(5000, unit="ns")
#     monitor_task.kill()

#     dut._log.info(f"Hardware reported {len(hw_results)} echo(s)")

#     if len(hw_results) == 0:
#         dut._log.warning("No hardware echoes detected — running debug probe")
#         await debug_probe(dut, dut._log)

#     hw_real = [r for r in hw_results if r["window"] >= BLANK]
#     exp_real = [e for e in expected if e["peak"] >= BLANK]

#     assert len(hw_results) >= len(expected), (
#         f"Expected at least {len(expected)} echoes, got {len(hw_results)}"
#     )
#     assert len(hw_real) >= len(exp_real), (
#         f"Expected {len(exp_real)} real echoes, got {len(hw_real)}"
#     )

#     for i, (hw, exp) in enumerate(zip(hw_real, exp_real)):
#         assert hw["window"] == exp["peak"], (
#             f"Echo {i+1}: expected window {exp['peak']}, got {hw['window']}"
#         )
#         assert hw["angle"] == exp["angle_raw"], (
#             f"Echo {i+1}: expected angle_raw {exp['angle_raw']}, "
#             f"got {hw['angle']}"
#         )

from pathlib import Path

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

MIC_SAMPLE_FREQUENCY = 4_000_000
SIGNAL_FREQUENCY = 40_000
WINDOW_SIZE = 100
SPEED_OF_SOUND = 344

THRESHOLD = 10
MIN_WIDTH = 5
BLANK = 64

ANGLE_TABLE = {
    0: 0, 1: 0, 2: 1, 3: 1, 4: 2, 5: 2, 6: 3, 7: 3,
    8: 4, 9: 4, 10: 5, 11: 5, 12: 6, 13: 6, 14: 7, 15: 7,
    16: 8, 17: 9, 18: 10, 19: 10, 20: 11, 21: 12, 22: 14,
    42: 50, 43: 52, 44: 53, 45: 54, 46: 54, 47: 55, 48: 56,
    49: 57, 50: 57, 51: 58, 52: 58, 53: 59, 54: 59, 55: 60,
    56: 60, 57: 61, 58: 61, 59: 62, 60: 62, 61: 63, 62: 63,
    63: 0,
}


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