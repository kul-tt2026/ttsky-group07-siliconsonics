"""UART tuning registers: defaults, write, read back, and the effect on detection.

The detection constants are the ones that make the chip useless if the real
board does not match the bench: too high a threshold detects nothing, too low
a blank reports the transducer ringing down as a target.
"""

from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from uart_test import (UartSniffer, uart_send, set_ui_bit, feed_pdm, load_bits,
                       model_first_echo, CLK_NS, WINDOW, MEAS_MS, LOCKOUT_MS,
                       UI_RX, UI_SINGLE_MIC)

DEFAULTS = "V07054010\n"       # threshold 07, min_width 05, blank 40, ping 10 (16 half periods)


async def send_str(dut, text):
    for ch in text:
        await uart_send(dut, ord(ch))


async def reset(dut):
    dut.ena.value = 1
    dut.ui_in.value = 1 << UI_RX
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await Timer(500, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_config_registers(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await reset(dut)
    uart = UartSniffer(dut)
    ctl = dut.user_project.main_inst.controller

    # ---- defaults ----
    await uart_send(dut, ord("V"))
    line = await uart.expect_line(5)
    assert line == DEFAULTS, f"default config {line!r}, expected {DEFAULTS!r}"

    # ---- write every register and read it back ----
    await send_str(dut, "C020")          # threshold = 0x20
    line = await uart.expect_line(5)
    assert line == "V20054010\n", f"after threshold write: {line!r}"

    for cmd in ("C10C", "C280", "C304"):          # min_width, blank, ping
        await send_str(dut, cmd)
        await uart.expect_line(5)                  # each write is acknowledged
    uart.buf.clear()

    await uart_send(dut, ord("V"))
    line = await uart.expect_line(5)
    assert line == "V200C8004\n", f"after all writes: {line!r}"
    assert int(ctl.cfg_threshold.value) == 0x20
    assert int(ctl.cfg_min_width.value) == 0x0C
    assert int(ctl.cfg_blank.value) == 0x80
    assert int(ctl.cfg_halfcycles.value) == 4

    # ---- a bad hex digit aborts, it must not be taken as a command ----
    await send_str(dut, "C0Z")
    await Timer(2, unit="ms")
    uart.buf.clear()
    await uart_send(dut, ord("V"))
    line = await uart.expect_line(5)
    assert line == "V200C8004\n", f"aborted command changed config: {line!r}"

    # ---- reset restores the defaults ----
    await reset(dut)
    uart.buf.clear()
    await uart_send(dut, ord("V"))
    line = await uart.expect_line(5)
    assert line == DEFAULTS, f"reset did not restore defaults: {line!r}"


@cocotb.test()
async def test_threshold_changes_detection(dut):
    """The same capture must be detected with the default threshold and
    rejected once the threshold is raised above the echo."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await reset(dut)
    uart = UartSniffer(dut)

    while int(dut.user_project.main_inst.mic_ready.value) == 0:
        await Timer(1, unit="ms")

    cap = Path(__file__).resolve().parent / "data" / "2026-07-29_example-synthetic" / "raw" / "capture_001.pdm"
    b1 = load_bits(cap, 0)
    silent = [0] * len(b1)
    exp_win, _ = model_first_echo(b1, b1)
    n_feed = (exp_win + 40) * WINDOW

    set_ui_bit(dut, UI_SINGLE_MIC, 1)
    await Timer(1, unit="ns")

    async def ping_and_feed():
        await RisingEdge(dut.user_project.main_inst.start_pulse)
        await RisingEdge(dut.clk)
        await feed_pdm(dut, b1, silent, n_feed)

    feeder = cocotb.start_soon(ping_and_feed())
    await uart_send(dut, ord("P"))
    line = await uart.expect_line(MEAS_MS + 10)
    await feeder
    assert line.startswith("D"), f"default threshold should detect, got {line!r}"

    await Timer(LOCKOUT_MS + 5, unit="ms")
    uart.buf.clear()

    await send_str(dut, "C0FF")          # threshold above any possible echo
    line = await uart.expect_line(5)
    assert line.startswith("VFF"), f"threshold write failed: {line!r}"

    feeder = cocotb.start_soon(ping_and_feed())
    await uart_send(dut, ord("P"))
    line = await uart.expect_line(MEAS_MS + 10)
    await feeder
    assert line == "N\n", f"raised threshold should reject, got {line!r}"
