"""Pin-only end-to-end test: reset, ping, feed an echo, read the range back.

Touches nothing but the chip's own pins, so it runs unchanged against the
gate-level netlist (GATES=yes), where the internal hierarchy other tests
reach into does not exist.
"""

from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, with_timeout

from uart_test import load_bits, model_first_echo, CLK_NS, WINDOW

UI_START, UI_MIC1, UI_MUX, UI_RX, UI_SINGLE_MIC = 0, 1, 3, 4, 6
DRIVE_B = 6


def data_out(dut):
    return (int(dut.uio_out.value) & 0xF) << 8 | int(dut.uo_out.value)


async def set_pins(dut, **bits):
    cur = int(dut.ui_in.value)
    for name, val in bits.items():
        bit = {"start": UI_START, "mic1": UI_MIC1, "mux": UI_MUX,
               "rx": UI_RX, "single": UI_SINGLE_MIC}[name]
        cur = (cur | (1 << bit)) if val else (cur & ~(1 << bit))
    dut.ui_in.value = cur
    await Timer(1, unit="ns")


@cocotb.test()
async def test_range_over_pins(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())

    dut.ena.value = 1
    dut.ui_in.value = 1 << UI_RX
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await Timer(500, unit="ns")
    dut.rst_n.value = 1
    for _ in range(20):          # let the netlist settle before reading pins
        await RisingEdge(dut.clk)

    assert int(dut.uio_oe.value) == 0xFF, (
        f"all 8 uio pins must drive out, uio_oe = {int(dut.uio_oe.value):#04x}"
    )

    # Status word: [8] result_ready, [9] busy, [10] mic_ready, [11] auto_mode
    await set_pins(dut, mux=1, single=1)
    assert data_out(dut) & (1 << 8) == 0, "result_ready set before any measurement"

    for _ in range(200):                       # mic power-up is ~110 ms
        if data_out(dut) & (1 << 10):
            break
        await Timer(1, unit="ms")
    assert data_out(dut) & (1 << 10), "mic_ready never came up"

    cap = Path(__file__).resolve().parent / "data" / "2026-07-29_example-synthetic" / "raw" / "capture_001.pdm"
    bits = load_bits(cap, 0)
    expected, _ = model_first_echo(bits, bits)
    assert expected is not None
    dut._log.info(f"expecting window {expected}")

    await set_pins(dut, start=1)
    async def wait_for_burst():
        while not (int(dut.uio_out.value) >> DRIVE_B) & 1:
            await RisingEdge(dut.clk)
    await with_timeout(wait_for_burst(), 5, "ms")   # the ping has started
    await set_pins(dut, start=0)

    base = int(dut.ui_in.value) & ~(1 << UI_MIC1)
    for i in range((expected + 40) * WINDOW):
        dut.ui_in.value = base | (int(bits[i]) << UI_MIC1)
        await Timer(10 * CLK_NS, unit="ns")
    dut.ui_in.value = base
    await Timer(500, unit="us")            # let the echo close and the CORDIC run

    assert data_out(dut) & (1 << 8), "result_ready not set after the echo"
    assert data_out(dut) & 0x3F == 0, "single-mic bearing must read 0"

    await set_pins(dut, mux=0)
    window = data_out(dut)
    dut._log.info(f"window on the pins: {window}")
    assert abs(window - expected) <= 1, f"expected window {expected}, pins show {window}"
