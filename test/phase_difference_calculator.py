import cocotb
import numpy as np

from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, ReadOnly

from itertools import product

PHASE_SCALE = 2**12
PHASE_PERIOD = 2 * np.pi


def expected_phase(x: int, y: int) -> int:
    phase = np.arctan2(y, x) % PHASE_PERIOD
    return int(round(phase / PHASE_PERIOD * PHASE_SCALE)) % PHASE_SCALE


def expected_phase_difference(i1: int, q1: int, i2: int, q2: int) -> int:
    phase1 = expected_phase(i1, q1)
    phase2 = expected_phase(i2, q2)

    return (phase2 - phase1) % PHASE_SCALE


def check_result(
    i1: int,
    q1: int,
    i2: int,
    q2: int,
    output: int,
    acceptable_error: int = 10,
):
    expected = expected_phase_difference(i1, q1, i2, q2)
    error = abs(expected - output)

    # Because phase is circular, also consider the error across 0/4096.
    circular_error = min(error, PHASE_SCALE - error)

    assert circular_error <= acceptable_error, (
        f"Error too large on input vector:\n"
        f"  ({i1}, {q1}) -> phase {expected_phase(i1, q1)}\n"
        f"  ({i2}, {q2}) -> phase {expected_phase(i2, q2)}\n"
        f"expected delta: {expected}\n"
        f"output:         {output}\n"
        f"error:          {circular_error}"
    )


async def reset_dut(dut):
    dut.rst_n.value = 0

    await Timer(100, unit="ns")

    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def wait_for_phase_valid(dut, timeout_cycles=20):
    """
    Wait for delta_phase_valid and return delta_phase_out.
    """
    for cycle in range(timeout_cycles):
        await RisingEdge(dut.clk)
        await ReadOnly()

        if dut.pdc_phase_valid.value == 1:
            return dut.pdc_phase_out.value.to_unsigned()

    raise AssertionError(
        f"delta_phase_valid was not asserted within "
        f"{timeout_cycles} cycles"
    )

@cocotb.test()
async def phase_difference_test_group(dut):
    values = [
        -100, -99, -50, -10, -1, 0, 1, 10, 50, 99, 100
    ]

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

    for input_values in product(values, repeat=4):
        try:
            await phase_difference_test(dut, *input_values)
        except AssertionError:
            failed_num += 1
            dut._log.info(f'Failed phase difference for: {input_values}')

        await RisingEdge(dut.clk)

    assert failed_num == 0, (
        f"Failed {failed_num} cases for phase difference"
    )


async def phase_difference_test(dut, i1, q1, i2, q2):

    # Drive inputs
    dut.I1.value = i1
    dut.Q1.value = q1
    dut.I2.value = i2
    dut.Q2.value = q2

    # Start calculation
    dut.pdc_load_input.value = 1
    await RisingEdge(dut.clk)

    # Deassert load_input
    dut.pdc_load_input.value = 0

    # Wait for final result
    result = await wait_for_phase_valid(dut)

    # dut._log.info(
    #     f"Phase difference: "
    #     f"({i1}, {q1}) -> ({i2}, {q2}) = {result}"
    # )

    check_result(i1, q1, i2, q2, result)