from pathlib import Path

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


def check_result(x: int, y: int, output: float, acceptable_error: float = 0.1):
    assert np.abs(np.arctan(y/x) - output) < acceptable_error, (
        f'Error too large on input vector ({x}, {y}): \nexpected value: {np.arctan(y/x)}\n output: {output}\n error: {np.arctan(y/x) - output}'
    )

@cocotb.test()
@cocotb.parametrize(("x", range(-10, 10)), ("y", range(-10, 10)))
async def atan2_cordic_test(dut, x: int=1, y: int=1):
    #dut._log.info(f"")
    
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

    dut.atan2_x_in.value = x
    dut.atan2_y_in.value = y
    dut.atan2_load_input.value = 0b1
    await RisingEdge(dut.clk)
    dut.atan2_load_input.value = 0b0

    await RisingEdge(dut.atan2_angle_valid)

    formatted_result = dut.atan2_angle_out.value.to_signed() / (2 ** 7)

    check_result(x, y, formatted_result)