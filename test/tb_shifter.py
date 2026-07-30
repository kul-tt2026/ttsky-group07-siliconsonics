import cocotb
from cocotb.triggers import Timer

async def run_shifter_test(dut, testnumber, data_in_bin, shift_val):
    # Set the inputs on the hardware
    dut.data_in.value = data_in_bin
    dut.shift_amt.value = shift_val
    
    # Wait a tiny bit for combinatorial propagation
    await Timer(1, unit="ns")
    
    # Output from hardware
    actual_out = dut.data_out.value

    # Output from software
    expected_val = data_in_bin >> shift_val

    # Logs
    dut._log.info(f"--- Test {testnumber} ---")
    dut._log.info(f"Data In (bin):     {data_in_bin:032b}")
    dut._log.info(f"Shift Amount:      {shift_val}")
    dut._log.info(f"Expected (bin):    {actual_out.to_unsigned():032b}")
    dut._log.info(f"Got      (bin):    {actual_out.to_unsigned():032b}")
    
    # Assert correctness
    assert actual_out == expected_val, f"Error in Test {testnumber}: Expected {expected_val}, but got {actual_out}!"
    dut._log.info(f"-> SUCCESS: Test {testnumber} passed!\n")

@cocotb.test()
async def test_shifter_1(dut):
    """Test 1: Shift"""
    await run_shifter_test(dut, testnumber=1, data_in_bin=0b0000_0000_0000_0000_0000_0000_0110_0100, shift_val=0)

@cocotb.test()
async def test_shifter_2(dut):
    """Test 2: Shift"""
    await run_shifter_test(dut, testnumber=2, data_in_bin=0b0000_0000_0000_0000_0000_0000_0110_0100, shift_val=2)

@cocotb.test()
async def test_shifter_3(dut):
    """Test 3: Shift"""
    await run_shifter_test(dut, testnumber=3, data_in_bin=0b1111_0000_0000_0000_0000_0000_0110_0100, shift_val=4)

@cocotb.test()
async def test_shifter_4(dut):
    """Test 4: Shift"""
    await run_shifter_test(dut, testnumber=4, data_in_bin=0b1111_0000_1111_0000_1111_0000_1111_0000, shift_val=8)

@cocotb.test()
async def test_shifter_5(dut):
    """Test 5: Shift"""
    await run_shifter_test(dut, testnumber=5, data_in_bin=0b0000_0000_1111_0000_0000_0000_0000_0001, shift_val=1)