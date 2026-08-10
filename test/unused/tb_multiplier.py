import cocotb
from cocotb.triggers import Timer

async def run_multiplier_test(dut, testnumber, data_in_1_bin, data_in_2_bin):
    # Set the inputs on the hardware
    dut.data_in_1.value = data_in_1_bin
    dut.data_in_2.value = data_in_2_bin
    
    # Wait a tiny bit for combinatorial propagation
    await Timer(1, unit="ns")
    
    actual_value = dut.data_out.value.integer
    
    data_in_1_dec = int(data_in_1_bin)
    data_in_2_dec = int(data_in_2_bin)
    expected_value = data_in_1_dec * data_in_2_dec

    # Log
    dut._log.info(f"--- Test {testnumber} ---")
    dut._log.info(f"Input 1 (Binary):  {bin(data_in_1_bin)}")
    dut._log.info(f"Input 1 (Decimal): {data_in_1_dec}")
    dut._log.info(f"Input 2 (Binary):  {bin(data_in_2_bin)}")
    dut._log.info(f"Input 2 (Decimal): {data_in_2_dec}")
    dut._log.info(f"Expected (Dec):    {expected_value} | Got (Dec): {actual_value}")
    
    # Assert correctness
    assert actual_value == expected_value, f"Error in Test {testnumber}: Expected {expected_value}, but got {actual_value}!"
    dut._log.info(f"-> SUCCESS: Test {testnumber} passed!\n")

@cocotb.test()
async def test_multiplier_binary_1(dut):
    """Test 1: Multiply"""
    data_in_1 = 0b0000_0000_0110_0100
    data_in_2 = 0b0000_0000_0000_0000
    await run_multiplier_test(dut, testnumber=1, data_in_1_bin=data_in_1, data_in_2_bin=data_in_2)

@cocotb.test()
async def test_multiplier_binary_2(dut):
    """Test 2: Multiply"""
    data_in_1 = 0b0000_0000_0000_0001
    data_in_2 = 0b0000_0000_0000_0001
    await run_multiplier_test(dut, testnumber=2, data_in_1_bin=data_in_1, data_in_2_bin=data_in_2)

@cocotb.test()
async def test_multiplier_binary_3(dut):
    """Test 3: Multiply"""
    data_in_1 = 0b0000_0000_0000_0000
    data_in_2 = 0b0000_0000_0000_0101
    await run_multiplier_test(dut, testnumber=3, data_in_1_bin=data_in_1, data_in_2_bin=data_in_2)

@cocotb.test()
async def test_multiplier_binary_4(dut):
    """Test 4: Multiply"""
    data_in_1 = 0b0000_0000_0110_0100
    data_in_2 = 0b0000_0000_0000_0101
    await run_multiplier_test(dut, testnumber=4, data_in_1_bin=data_in_1, data_in_2_bin=data_in_2)

@cocotb.test()
async def test_multiplier_binary_5(dut):
    """Test 5: Multiply"""
    data_in_1 = 0b1111_1111_1111_1111
    data_in_2 = 0b1111_1111_1111_1111
    await run_multiplier_test(dut, testnumber=5, data_in_1_bin=data_in_1, data_in_2_bin=data_in_2)