from pathlib import Path

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

MIC_SAMPLE_FREQUENCY = 4_000_000
SIGNAL_FREQUENCY = 40_000
WINDOW_SIZE = 100
THRESHOLD = 16
MIN_WINDOW = 64


def load_mic1_bits(path: Path) -> list[int]:
    data = path.read_bytes()
    return [(byte >> 0) & 0x1 for byte in data]


def generate_reference_cos_sin(samples: int):
    period_len = int(MIC_SAMPLE_FREQUENCY / SIGNAL_FREQUENCY)
    r_cos = np.arange(samples)
    r_cos = 1 - 2 * ((r_cos % period_len) >= (period_len / 2))
    r_sin = np.roll(r_cos, int(period_len / 4))
    return r_cos.astype(np.int16), r_sin.astype(np.int16)


def expected_window_from_data(bits: list[int]) -> int:
    mic_bits = np.array(bits, dtype=np.int16)
    mic_transformed = 2 * mic_bits - 1

    r_cos, r_sin = generate_reference_cos_sin(len(mic_bits))
    I = r_cos * mic_transformed
    Q = r_sin * mic_transformed

    I_windowed = I[: len(I) - len(I) % WINDOW_SIZE].reshape(-1, WINDOW_SIZE).sum(axis=1)
    Q_windowed = Q[: len(Q) - len(Q) % WINDOW_SIZE].reshape(-1, WINDOW_SIZE).sum(axis=1)

    sig_strength = np.abs(I_windowed) + np.abs(Q_windowed)
    matches = np.flatnonzero(
        (sig_strength >= THRESHOLD) & (np.arange(len(sig_strength)) + 1 >= MIN_WINDOW)
    )
    assert len(matches) > 0, "No non-overlapping window in the PDM capture crossed the echo threshold"
    return int(matches[0] + 1)


@cocotb.test()
async def test_echo_timing_mic1_wall88(dut):
    data_path = (
        Path(__file__).resolve().parent
        / "data"
        / "2026-07-29_wall-0m88"
        / "raw"
        / "capture_000.pdm"
    )
    bits = load_mic1_bits(data_path)
    expected_window = expected_window_from_data(bits)
    expected_distance = expected_window * 100 / 4_000_000 * 343 / 2
    dut._log.info(f"Expected window {expected_window} (~{expected_distance:.2f} m)")

    # Clock (25 ns period = 40 MHz)
    clock = Clock(dut.clk, 25, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.ena.value = 1
    dut.uio_in.value = 0
    await Timer(100, unit="ns")

    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Feed PDM bits: mic_pdm on ui_in[1], each bit held for 10 clock cycles
    samples_to_send = min(len(bits), expected_window * WINDOW_SIZE + 100)
    for idx in range(samples_to_send):
        dut.ui_in.value = bits[idx] << 1
        for _ in range(10):
            await RisingEdge(dut.clk)

    await Timer(200, unit="ns")

    # Read raw outputs
    uo_val = int(dut.uo_out.value)      # echo_window_index[7:0]
    uio_val = int(dut.uio_out.value)    # {3'b0, echo_found, index[11:8]}

    observed_window = uo_val | ((uio_val & 0x0F) << 8)
    observed_found = (uio_val >> 4) & 0x1

    assert observed_found == 1, (
        f"Expected echo_found to go high, saw {observed_found}"
    )
    assert observed_window == expected_window, (
        f"Expected echo window {expected_window}, got {observed_window}"
    )


@cocotb.test()
async def test_echo_timing_mic1_synthetic(dut):
    data_path = (
        Path(__file__).resolve().parent
        / "data"
        / "2026-07-29_example-synthetic"
        / "raw"
        / "capture_000.pdm"
    )
    bits = load_mic1_bits(data_path)
    expected_window = expected_window_from_data(bits)
    expected_distance = expected_window * 100 / 4_000_000 * 343 / 2
    dut._log.info(f"Expected window {expected_window} (~{expected_distance:.2f} m)")

    # Clock (25 ns period = 40 MHz)
    clock = Clock(dut.clk, 25, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.ena.value = 1
    dut.uio_in.value = 0
    await Timer(100, unit="ns")

    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Feed PDM bits: mic_pdm on ui_in[1], each bit held for 10 clock cycles
    samples_to_send = min(len(bits), expected_window * WINDOW_SIZE + 100)
    for idx in range(samples_to_send):
        dut.ui_in.value = bits[idx] << 1
        for _ in range(10):
            await RisingEdge(dut.clk)

    await Timer(200, unit="ns")

    # Read raw outputs
    uo_val = int(dut.uo_out.value)      # echo_window_index[7:0]
    uio_val = int(dut.uio_out.value)    # {3'b0, echo_found, index[11:8]}

    observed_window = uo_val | ((uio_val & 0x0F) << 8)
    observed_found = (uio_val >> 4) & 0x1

    assert observed_found == 1, (
        f"Expected echo_found to go high, saw {observed_found}"
    )
    assert observed_window == expected_window, (
        f"Expected echo window {expected_window}, got {observed_window}"
    )