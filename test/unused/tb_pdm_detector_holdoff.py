import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from helper import load_pdm_data

async def setup_dut(dut):
    """Helper function to initialize and reset the DUT."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    dut.rst_n.value = 0
    dut.tx_trigger.value = 0
    dut.pdm_in.value = 0
    await Timer(20, unit="ns")
    
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Activate the detector with a tx_trigger pulse
    dut.tx_trigger.value = 1
    await RisingEdge(dut.clk)
    dut.tx_trigger.value = 0
    await RisingEdge(dut.clk)

async def run_echo_test(dut, testnumber, echo_pattern):
    await setup_dut(dut)

    # Log
    dut._log.info(f"Starting Test {testnumber}: Send valid echo pattern...")

    echo_pattern_len = echo_pattern.bit_length()
    pulse_detected = False
    pulse_duration = 0

    for i in range(echo_pattern_len):
        bit = (echo_pattern >> (echo_pattern_len - 1 - i)) & 1
        dut.pdm_in.value = bit
        await RisingEdge(dut.clk)
        
        if dut.echo_detected.value == 1:
            pulse_detected = True
            pulse_duration += 1

    # Assert correctness
    assert pulse_detected, f"Error: No echo pulse detected in Test {testnumber}!"
    assert pulse_duration == 1, f"Error: Pulse duration in Test {testnumber} was {pulse_duration} cycles!"
    dut._log.info(f"-> SUCCESS: Test {testnumber} passed!")

@cocotb.test()
async def test_echo_variant_1(dut):
    """Test 1: Test measured echo pattern."""
    echo_pattern = load_pdm_data("captured_data.pdm")
    await run_echo_test(dut, testnumber=1, echo_pattern=echo_pattern)
