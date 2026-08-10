import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, ClockCycles

@cocotb.test()
async def test_mic_us_power_sequence(dut):
    # 40 MHz system clock
    clock = Clock(dut.clk, 25, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset + idle inputs
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0        # start_measurement=0, mic1_pdm=0, restart_mic=0
    dut.uio_in.value = 0
    await Timer(100, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Background coroutine: count rising edges of mic_clk
    edge_count = 0
    prev_mic = 0

    async def monitor_mic():
        nonlocal edge_count, prev_mic
        while True:
            await RisingEdge(dut.clk)
            curr = int(dut.mic_clk.value)
            if curr == 1 and prev_mic == 0:
                edge_count += 1
            prev_mic = curr

    cocotb.start_soon(monitor_mic())

    mode = "OFF"
    mode_start_ms = 0
    ms = 0

    # Sample once per millisecond (40 000 cycles @ 40 MHz)
    while ms < 200:            # 200 ms timeout
        await ClockCycles(dut.clk, 40_000)
        ms += 1
        freq = edge_count * 1000   # edges/ms -> Hz

        dut._log.info(f"ms {ms:3d}: mic_clk freq = {freq:7d} Hz  mode = {mode}")

        if mode == "OFF":
            if 1_024_000 <= freq <= 2_475_000:
                mode = "Normal"
                mode_start_ms = ms

        elif mode == "Normal":
            if 3_072_000 <= freq <= 4_800_000:
                normal_dur = ms - mode_start_ms
                assert normal_dur >= 50, (
                    f"Normal mode only {normal_dur} ms, expected >= 50 ms"
                )
                mode = "US"
                mode_start_ms = ms
                dut._log.info(f"  -> Switched to US after {normal_dur} ms in Normal")

        elif mode == "US":
            us_dur = ms - mode_start_ms
            if us_dur >= 10:
                dut._log.info(f"US mode stable for {us_dur} ms — PASS")
                return

        edge_count = 0

    assert False, "Timeout: mic_clk never reached US mode"