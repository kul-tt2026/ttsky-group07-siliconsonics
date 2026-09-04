"""
End-to-end test of the measurement controller and UART protocol, driven
through the real chip pins (tt_um_siliconsonics).

Runs with shortened timers so it finishes in reasonable time - see the
CONTROLLER_PARAMS note in the Makefile. The mic power-up sequence is NOT
shortened (it lives in a module we don't touch), so the test waits the
real 110 ms for mic_ready.

Scenario:
  1. Reset. Query status before the mic is ready -> expect "SW\\n".
  2. Try to ping before the mic is ready -> expect "B\\n", no burst.
  3. Wait for mic_ready. Query -> "SR\\n".
  4. 'P' with real wall-capture PDM on both mics -> transducer bursts,
     "Dwww aa\\n" arrives with the window and angle the model predicts.
  5. 'P' again immediately -> "B\\n" (lockout).
  6. 'A' -> "AR\\n", then a ping fires by itself; with silent mics -> "N\\n".
     Wait one more auto period -> another ping, another "N\\n".
  7. 'S' -> "SR\\n"; wait an auto period -> no ping.
  8. Pin-driven ping (ui_in[0] rising edge) -> burst.

A second test covers single-microphone boards (ui_in[6] high): only
mic1 is driven, the range must still be reported and the bearing reads 0.
"""

from pathlib import Path

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First

# Must match the parameters the Makefile passes to the DUT for this test
CLKS_PER_BIT = 347
CLK_NS       = 25
BIT_NS       = CLKS_PER_BIT * CLK_NS      # 8675 ns per UART bit
AUTO_MS      = 30                          # shortened from 1000 by the Makefile -P override
LOCKOUT_MS   = 20                          # shortened from 400 by the Makefile -P override
MEAS_MS      = 102.4                       # real value (matches the demodulator)

# Pin map
UI_START = 0
UI_MIC1  = 1
UI_MIC2  = 2
UI_MUX   = 3
UI_RX    = 4
UI_AUTO  = 5
UI_SINGLE_MIC = 6
UI_RST_MIC = 7

UIO_TX      = 4
UIO_DRIVE_A = 5


# ---------------------------------------------------------------------------
# UART helpers (bit-banged from Python, 8N1 LSB first)
# ---------------------------------------------------------------------------
def set_ui_bit(dut, bit, val):
    cur = int(dut.ui_in.value)
    cur = (cur | (1 << bit)) if val else (cur & ~(1 << bit))
    dut.ui_in.value = cur


async def uart_send(dut, byte: int):
    set_ui_bit(dut, UI_RX, 0)                 # start
    await Timer(BIT_NS, unit="ns")
    for i in range(8):
        set_ui_bit(dut, UI_RX, (byte >> i) & 1)
        await Timer(BIT_NS, unit="ns")
    set_ui_bit(dut, UI_RX, 1)                 # stop
    await Timer(BIT_NS, unit="ns")


class UartSniffer:
    """Background task that decodes bytes on uio_out[UIO_TX]."""

    def __init__(self, dut):
        self.dut = dut
        self.buf = bytearray()
        self.task = cocotb.start_soon(self._run())

    def _tx(self):
        return (int(self.dut.uio_out.value) >> UIO_TX) & 1

    async def _run(self):
        while True:
            # wait for start bit
            while self._tx() == 1:
                await FallingEdge(self.dut.clk)
            await Timer(BIT_NS * 1.5, unit="ns")   # middle of bit 0
            val = 0
            for i in range(8):
                val |= self._tx() << i
                await Timer(BIT_NS, unit="ns")
            # now in the stop bit; consume it so we don't re-trigger on data
            await Timer(BIT_NS * 0.5, unit="ns")
            self.buf.append(val)

    async def expect_line(self, timeout_ms: float) -> str:
        """Wait until a '\\n'-terminated line is available and return it."""
        deadline = timeout_ms * 1_000_000
        elapsed = 0
        while b"\n" not in self.buf:
            await Timer(50_000, unit="ns")
            elapsed += 50_000
            assert elapsed < deadline, (
                f"No UART line within {timeout_ms} ms; buffer so far: {bytes(self.buf)!r}"
            )
        idx = self.buf.index(b"\n")
        line = self.buf[: idx + 1].decode()
        del self.buf[: idx + 1]
        return line

    async def expect_silence(self, ms: float):
        await Timer(int(ms * 1_000_000), unit="ns")
        assert len(self.buf) == 0, f"Unexpected UART output: {bytes(self.buf)!r}"


class BurstCounter:
    """Counts rising edges on transducer_drive_a in the background."""

    def __init__(self, dut):
        self.dut = dut
        self.edges = 0
        self.task = cocotb.start_soon(self._run())

    async def _run(self):
        prev = 0
        while True:
            await RisingEdge(self.dut.clk)
            cur = (int(self.dut.uio_out.value) >> UIO_DRIVE_A) & 1
            if cur and not prev:
                self.edges += 1
            prev = cur

    def take(self):
        n = self.edges
        self.edges = 0
        return n


# ---------------------------------------------------------------------------
# PDM data + reference model (same as angle_module_test)
# ---------------------------------------------------------------------------
MIC_FS = 4_000_000
F_SIG = 40_000
WINDOW = 100
THRESHOLD = 7
MIN_WIDTH = 5
BLANK = 64


def load_bits(path: Path, mic: int):
    data = np.frombuffer(path.read_bytes(), dtype=np.uint8)
    return ((data >> mic) & 1).astype(np.int16)


def model_first_echo(b1, b2):
    """Return (start_window_hw, angle) for the first echo, hardware numbering."""
    import sys
    sys.path.append("../")
    from python_scripts.phase_to_angle_table import calculate_angle

    period = MIC_FS // F_SIG
    n = min(len(b1), len(b2))
    cos = 1 - 2 * ((np.arange(n) % period) >= period / 2)
    sin = np.roll(cos, period // 4)
    m1 = 2 * b1[:n] - 1
    m2 = 2 * b2[:n] - 1
    usable = n - n % WINDOW

    def win(x):
        return x[:usable].reshape(-1, WINDOW).sum(axis=1)

    I1, Q1 = win(cos * m1), win(sin * m1)
    I2, Q2 = win(cos * m2), win(sin * m2)
    valid = ((np.abs(I1) + np.abs(Q1)) > THRESHOLD) & ((np.abs(I2) + np.abs(Q2)) > THRESHOLD)
    idx = np.flatnonzero(valid)
    runs = np.split(idx, np.flatnonzero(np.diff(idx) > 1) + 1)
    for run in runs:
        if len(run) < MIN_WIDTH or run[0] < BLANK:
            continue
        # phase = atan2(I, Q): I carries sin(phi), Q carries cos(phi)
        p1 = np.arctan2(I1[run].sum(), Q1[run].sum()) % (2 * np.pi)
        p2 = np.arctan2(I2[run].sum(), Q2[run].sum()) % (2 * np.pi)
        d = (int(round(p2 / (2 * np.pi) * 4096)) - int(round(p1 / (2 * np.pi) * 4096))) & 0xFFF
        ang = calculate_angle((d >> 6) << 6)
        return int(run[0]) + 1, (0 if ang is None else int(ang))   # +1: hw counter is 1-based
    return None, None


async def feed_pdm(dut, b1, b2, n_samples):
    """Drive both mic pins for n_samples samples (10 clocks each)."""
    for i in range(n_samples):
        cur = int(dut.ui_in.value) & ~((1 << UI_MIC1) | (1 << UI_MIC2))
        cur |= (int(b1[i]) << UI_MIC1) | (int(b2[i]) << UI_MIC2)
        dut.ui_in.value = cur
        await Timer(10 * CLK_NS, unit="ns")
    cur = int(dut.ui_in.value) & ~((1 << UI_MIC1) | (1 << UI_MIC2))
    dut.ui_in.value = cur


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_uart_measurement_protocol(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())

    dut.ena.value = 1
    dut.ui_in.value = 1 << UI_RX          # rx idle high, everything else low
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await Timer(500, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    uart = UartSniffer(dut)
    bursts = BurstCounter(dut)

    # ---- 1. status before mic ready ----
    dut._log.info("[1] query before mic ready")
    await uart_send(dut, ord("?"))
    line = await uart.expect_line(5)
    assert line == "SW\n", f"expected 'SW\\n', got {line!r}"

    # ---- 2. ping refused before mic ready ----
    dut._log.info("[2] ping refused while mic warming up")
    await uart_send(dut, ord("P"))
    line = await uart.expect_line(5)
    assert line == "B\n", f"expected 'B\\n', got {line!r}"
    await Timer(1, unit="ms")
    assert bursts.take() == 0, "transducer fired before mic was ready"

    # ---- 3. wait for mic_ready (real 110 ms) ----
    dut._log.info("[3] waiting for mic power-up sequence")
    while int(dut.user_project.main_inst.mic_ready.value) == 0:
        await Timer(1, unit="ms")
    await uart_send(dut, ord("?"))
    line = await uart.expect_line(5)
    assert line == "SR\n", f"expected 'SR\\n', got {line!r}"

    # ---- 4. single ping with a real echo ----
    dut._log.info("[4] 'P' with wall capture on both mics")
    cap = Path(__file__).resolve().parent / "data" / "2026-07-29_example-synthetic" / "raw" / "capture_001.pdm"
    b1 = load_bits(cap, 0)
    b2 = load_bits(cap, 1)
    exp_win, exp_ang = model_first_echo(b1, b2)
    assert exp_win is not None, "model found no echo in the capture"
    dut._log.info(f"    model expects first echo: window {exp_win}, angle {exp_ang}")

    # Feed the capture starting exactly at the ping, the same way
    # angle_module_test does, so window numbering lines up with the model.
    n_feed = (exp_win + 40) * WINDOW

    async def feed_on_ping():
        await RisingEdge(dut.user_project.main_inst.start_pulse)
        await RisingEdge(dut.clk)
        await feed_pdm(dut, b1, b2, n_feed)

    feeder = cocotb.start_soon(feed_on_ping())
    await uart_send(dut, ord("P"))
    line = await uart.expect_line(MEAS_MS + 10)
    await feeder
    assert line.startswith("D") and line.endswith("\n") and len(line) == 8, f"bad detect line {line!r}"
    got_win = int(line[1:4], 16)
    got_ang = int(line[5:7], 16)
    dut._log.info(f"    chip reported: window {got_win}, angle {got_ang}")
    assert got_win == exp_win, f"window: expected {exp_win}, got {got_win}"
    assert got_ang == exp_ang, f"angle: expected {exp_ang}, got {got_ang}"
    assert bursts.take() == 8, "expected an 8-period burst"

    # sticky result_ready visible on the status nibble
    set_ui_bit(dut, UI_MUX, 1)
    await Timer(1, unit="us")
    status_nibble = int(dut.uio_out.value) & 0xF
    assert status_nibble & 0b0001, "result_ready not set after detection"
    assert status_nibble & 0b0100, "mic_ready not reflected in status"
    set_ui_bit(dut, UI_MUX, 0)

    # ---- 5. lockout ----
    dut._log.info("[5] immediate second 'P' -> lockout")
    await uart_send(dut, ord("P"))
    line = await uart.expect_line(5)
    assert line == "B\n", f"expected 'B\\n' (lockout), got {line!r}"

    # the rest of the measurement window still has to run out; with the
    # mics now silent nothing else should be reported
    await Timer(int(MEAS_MS) + 5, unit="ms")
    await uart.expect_silence(1)

    # ---- 6. auto mode ----
    dut._log.info("[6] 'A' -> auto mode, silent mics -> 'N' each period")
    await uart_send(dut, ord("A"))
    line = await uart.expect_line(5)
    assert line == "AR\n", f"expected 'AR\\n', got {line!r}"

    # first auto ping fires immediately on enable
    line = await uart.expect_line(MEAS_MS + AUTO_MS)
    assert line == "N\n", f"expected 'N\\n' after silent measurement, got {line!r}"
    n1 = bursts.take()
    assert n1 == 8, f"auto ping 1: expected 8 drive edges, got {n1}"

    line = await uart.expect_line(MEAS_MS + AUTO_MS)
    assert line == "N\n", f"expected second 'N\\n', got {line!r}"
    n2 = bursts.take()
    assert n2 == 8, f"auto ping 2: expected 8 drive edges, got {n2}"

    # ---- 7. stop ----
    dut._log.info("[7] 'S' -> auto off, no more pings")
    await uart_send(dut, ord("S"))
    line = await uart.expect_line(5)
    assert line == "SR\n", f"expected 'SR\\n', got {line!r}"
    # drain a possible in-flight measurement, then confirm quiet
    await Timer(int(MEAS_MS) + AUTO_MS + 5, unit="ms")
    uart.buf.clear()
    bursts.take()
    await uart.expect_silence(AUTO_MS + 5)
    assert bursts.take() == 0, "ping fired after auto mode was switched off"

    # ---- 8. pin-driven ping ----
    dut._log.info("[8] ui_in[0] rising edge -> ping")
    set_ui_bit(dut, UI_START, 1)
    await Timer(1, unit="ms")
    set_ui_bit(dut, UI_START, 0)
    await Timer(1, unit="ms")
    assert bursts.take() == 8, "pin-triggered ping did not fire"
    # holding the pin high must NOT retrigger: still only one burst
    line = await uart.expect_line(MEAS_MS + 5)
    assert line == "N\n"

    dut._log.info("ALL PROTOCOL CHECKS PASSED")


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_single_mic_mode(dut):
    """Only mic1 is fitted. With ui_in[6] high the chip must still report the
    range; with it low the same board detects nothing, because the detector
    needs signal on both mics."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())

    dut.ena.value = 1
    dut.ui_in.value = 1 << UI_RX
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await Timer(500, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    uart = UartSniffer(dut)

    while int(dut.user_project.main_inst.mic_ready.value) == 0:
        await Timer(1, unit="ms")

    cap = Path(__file__).resolve().parent / "data" / "2026-07-29_example-synthetic" / "raw" / "capture_001.pdm"
    b1 = load_bits(cap, 0)
    silent = [0] * len(b1)
    exp_win, _ = model_first_echo(b1, b1)
    assert exp_win is not None, "model found no echo in the capture"
    n_feed = (exp_win + 40) * WINDOW

    async def ping_and_feed():
        await RisingEdge(dut.user_project.main_inst.start_pulse)
        await RisingEdge(dut.clk)
        await feed_pdm(dut, b1, silent, n_feed)

    # ---- single_mic = 1: mic2 pin idle, range still reported, angle 0 ----
    set_ui_bit(dut, UI_SINGLE_MIC, 1)
    await Timer(1, unit="ns")          # let the write land before the next read-modify-write
    feeder = cocotb.start_soon(ping_and_feed())
    await uart_send(dut, ord("P"))
    line = await uart.expect_line(MEAS_MS + 10)
    await feeder
    assert line.startswith("D") and len(line) == 8, f"bad detect line {line!r}"
    assert int(line[1:4], 16) == exp_win, f"window: expected {exp_win}, got {line[1:4]}"
    assert int(line[5:7], 16) == 0, f"single-mic bearing must be 0, got {line[5:7]}"

    await Timer(LOCKOUT_MS + 5, unit="ms")
    uart.buf.clear()

    # ---- single_mic = 0: the same one-mic board detects nothing ----
    set_ui_bit(dut, UI_SINGLE_MIC, 0)
    await Timer(1, unit="ns")
    feeder = cocotb.start_soon(ping_and_feed())
    await uart_send(dut, ord("P"))
    line = await uart.expect_line(MEAS_MS + 10)
    await feeder
    assert line == "N\n", f"expected 'N\\n' with mic2 unconnected, got {line!r}"
