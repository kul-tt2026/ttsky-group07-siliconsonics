from pathlib import Path

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

def adjusted_arctan(x, y):
    if x != 0:
        return np.arctan(y/x)

    return np.pi / 2 * (np.sign(y))

# def check_result(x: int, y: int, output: float, acceptable_error: float = 0.1):
#     assert np.abs(adjusted_arctan(x, y) - output) < acceptable_error, (
#         f'Error too large on input vector ({x}, {y}): \nexpected value: {adjusted_arctan(x, y)}\n output: {output}\n error: {adjusted_arctan(x, y) - output}'
#     )

def check_result(x: int, y: int, output: float, acceptable_error: float = 10):
    expected_value = (np.arctan2(y, x) % (2 * np.pi)) / (2 * np.pi) * (2**12)

    assert np.abs(expected_value - output) < acceptable_error, (
        f'Error too large on input vector ({x}, {y}): \nexpected value: {expected_value}\n output: {output}\n error: {expected_value - output}'
    )

@cocotb.test()
async def atan2_cordic_test_group(dut):
    x_range = range(-100, 100)
    y_range = range(-100, 100)

    failed_num = 0

    # Clock (25 ns period = 40 MHz)
    clock = Clock(dut.clk, 25, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.rst_n.value = 0
    dut.atan2_x_in.value = 0
    dut.atan2_y_in.value = 0
    dut.atan2_load_input.value = 0
    await Timer(100, unit="ns")

    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    for x in x_range:
        for y in y_range:
            try:
                await atan2_cordic_test(dut, x, y)
            except:
                failed_num += 1
                dut._log.info(f'Failed atan2 for: {x}, {y}')

    assert failed_num == 0, (
        f"Failed {failed_num} cases for atan2"
    )


async def atan2_cordic_test(dut, x: int=1, y: int=1):
    #dut._log.info(f"")

    dut.atan2_x_in.value = x
    dut.atan2_y_in.value = y
    dut.atan2_load_input.value = 0b1
    await RisingEdge(dut.clk)
    dut.atan2_load_input.value = 0b0

    formatted_result = None

    for i in range(9):
        await RisingEdge(dut.clk)

        #dut._log.info(f'Iteration {i}: {dut.atan2_angle_out.value}, read as: {dut.atan2_angle_out.value.integer}')

        if dut.atan2_angle_valid.value == 1:
            formatted_result = dut.atan2_angle_out.value.to_unsigned()
            break

    assert formatted_result is not None, (
        f'No angle returned within 8 cycles'
    )

    #await RisingEdge(dut.atan2_angle_valid)

    #formatted_result = dut.atan2_angle_out.value.to_signed() / (2 ** 7)

    check_result(x, y, formatted_result)



@cocotb.test()
async def atan2_16_cordic_test_group(dut):
    x_range = range(-5000, 5000)
    y_range = range(-5000, 5000)

    failed_num = 0

    # Clock (25 ns period = 40 MHz)
    clock = Clock(dut.clk, 25, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.rst_n.value = 0
    dut.atan2_x_in_16.value = 0
    dut.atan2_y_in_16.value = 0
    dut.atan2_load_input_16.value = 0
    await Timer(100, unit="ns")

    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    for x in x_range:
        for y in y_range:
            try:
                await atan2_16_cordic_test(dut, x, y)
            except:
                failed_num += 1
                dut._log.info(f'Failed atan2 16 for: {x}, {y}')

    assert failed_num == 0, (
        f"Failed {failed_num} cases for atan2 16"
    )


async def atan2_16_cordic_test(dut, x: int=1, y: int=1):
    #dut._log.info(f"")

    dut.atan2_x_in_16.value = x
    dut.atan2_y_in_16.value = y
    dut.atan2_load_input_16.value = 0b1
    await RisingEdge(dut.clk)
    dut.atan2_load_input_16.value = 0b0

    formatted_result = None

    for i in range(9):
        await RisingEdge(dut.clk)

        #dut._log.info(f'Iteration {i}: {dut.atan2_angle_out.value}, read as: {dut.atan2_angle_out.value.integer}')

        if dut.atan2_angle_valid_16.value == 1:
            formatted_result = dut.atan2_angle_out_16.value.to_unsigned()
            break

    assert formatted_result is not None, (
        f'No angle returned within 8 cycles by atan2 16'
    )

    #await RisingEdge(dut.atan2_angle_valid)

    #formatted_result = dut.atan2_angle_out.value.to_signed() / (2 ** 7)

    check_result(x, y, formatted_result)