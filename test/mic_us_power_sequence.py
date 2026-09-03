"""
Test for the SPH0641LU4H-1 power-up sequence in ultrasonic_mic_powerup_sequence.

Checks that mic_clk runs in Standard Performance Mode (1.024-2.475 MHz) for
at least 50 ms, then switches to Ultrasonic Mode (3.072-4.8 MHz) and stays
there.

Speed: mic_clk edges are counted by a small counter in tb.v
(mic_clk_edges). Python reads it once per millisecond, so the simulator
runs uninterrupted between samples instead of waking Python on every
40 MHz clock edge. Roughly 10x faster than the RisingEdge(dut.clk) loop
this replaced.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# Datasheet clock ranges (SPH0641LU4H-1 rev B)
NORMAL_MIN_HZ = 1_024_000
NORMAL_MAX_HZ = 2_475_000
US_MIN_HZ     = 3_072_000
US_MAX_HZ     = 4_800_000

# Datasheet timing: power-up 50 ms max, mode change 10 ms max
MIN_NORMAL_MS = 50
STABLE_US_MS  = 10
TIMEOUT_MS    = 200


@cocotb.test()
async def test_mic_us_power_sequence(dut):
    clock = Clock(dut.clk, 25, unit="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await Timer(100, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    mode = "OFF"
    mode_start_ms = 0
    ms = 0
    prev_edges = int(dut.mic_clk_edges.value)

    while ms < TIMEOUT_MS:
        # One simulator callback per millisecond, not per clock edge.
        await Timer(1, unit="ms")
        ms += 1

        cur_edges = int(dut.mic_clk_edges.value)
        freq = (cur_edges - prev_edges) * 1000   # edges per ms -> Hz
        prev_edges = cur_edges

        dut._log.info(f"ms {ms:3d}: mic_clk = {freq:8d} Hz  mode = {mode}")

        if mode == "OFF":
            if NORMAL_MIN_HZ <= freq <= NORMAL_MAX_HZ:
                mode = "Normal"
                mode_start_ms = ms

        elif mode == "Normal":
            if US_MIN_HZ <= freq <= US_MAX_HZ:
                normal_dur = ms - mode_start_ms
                assert normal_dur >= MIN_NORMAL_MS, (
                    f"Normal mode only {normal_dur} ms, expected >= {MIN_NORMAL_MS} ms"
                )
                mode = "US"
                mode_start_ms = ms
                dut._log.info(f"  -> Ultrasonic after {normal_dur} ms in Normal")
            else:
                assert NORMAL_MIN_HZ <= freq <= NORMAL_MAX_HZ, (
                    f"mic_clk left Standard range without entering Ultrasonic: {freq} Hz"
                )

        elif mode == "US":
            assert US_MIN_HZ <= freq <= US_MAX_HZ, (
                f"mic_clk left Ultrasonic range: {freq} Hz"
            )
            if ms - mode_start_ms >= STABLE_US_MS:
                dut._log.info(f"Ultrasonic stable for {STABLE_US_MS} ms - PASS")
                return

    assert False, f"Timeout: mic_clk never reached Ultrasonic Mode in {TIMEOUT_MS} ms"