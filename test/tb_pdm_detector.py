import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

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

async def run_noise_test(dut, testnumber, noise_pattern):
    await setup_dut(dut)
    
    # Log
    dut._log.info(f"Starting Test {testnumber}: Noise rejection...")

    pattern_len = noise_pattern.bit_length()

    for i in range(pattern_len):
        bit = (noise_pattern >> (pattern_len - 1 - i)) & 1
        dut.pdm_in.value = bit
        await RisingEdge(dut.clk)
        assert dut.echo_detected.value == 0, f"Error: False detection in Test {testnumber} on bit {i}!"

    dut._log.info(f"-> SUCCESS: Test {testnumber} - No false detections on noise.")

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

# NOISE TEST:
@cocotb.test()
async def test_noise_variant_1(dut):
    f"""Test 1: Send noise pattern after a tx_trigger pulse (no false detection)."""
    await run_noise_test(dut, testnumber=1, noise_pattern=0b0000_0000_0000_0000)

@cocotb.test()
async def test_noise_variant_2(dut):
    f"""Test 2: Send noise pattern after a tx_trigger pulse (no false detection)."""
    await run_noise_test(dut, testnumber=2, noise_pattern=0b1010_0100_1001_0010)

@cocotb.test()
async def test_noise_variant_3(dut):
    f"""Test 3: Send noise pattern after a tx_trigger pulse (no false detection)."""
    await run_noise_test(dut, testnumber=3, noise_pattern=0b1010_0111_1000_0010)

@cocotb.test()
async def test_noise_variant_4(dut):
    f"""Test 4: Send noise pattern after a tx_trigger pulse (no false detection)."""
    await run_noise_test(dut, testnumber=4, noise_pattern=0b0011_1100_0001_1000)


@cocotb.test()
async def test_noise_variant_5(dut):
    f"""Test 5: Send noise pattern after a tx_trigger pulse (no false detection)."""
    await run_noise_test(dut, testnumber=5, noise_pattern=0b0001_0001_0001_0001_0001_0001)

# ECHO TEST
@cocotb.test()
async def test_echo_variant_1(dut):
    """Test 1: Echo pattern over threshold: 100_1111_1111_1111_1."""
    await run_echo_test(dut, testnumber=1, echo_pattern=0b1111_0100_1111_1111_1111_1111)

@cocotb.test()
async def test_echo_variant_2(dut):
    """Test 2: Echo pattern over threshold: 1_1100_1111_1111_110."""
    await run_echo_test(dut, testnumber=2, echo_pattern=0b1001_1100_1111_1111_1100_0000)

@cocotb.test()
async def test_echo_variant_3(dut):
    """Test 3: Echo pattern over threshold: 100_1111_1111_1111_1."""
    await run_echo_test(dut, testnumber=3, echo_pattern=0b0000_0100_1111_1111_1011_1100)

@cocotb.test()
async def test_echo_variant_4(dut):
    """Test 4: Echo pattern over threshold: 11_0011_1111_1111_01."""
    await run_echo_test(dut, testnumber=4, echo_pattern=0b1100_0011_0011_1111_1111_0100_0000)

@cocotb.test()
async def test_echo_variant_5(dut):
    """Test 5: Echo pattern over threshold: 0111_1011_1111_1111."""
    await run_echo_test(dut, testnumber=4, echo_pattern=0b0111_1011_1111_1111_1111_1101_1111)