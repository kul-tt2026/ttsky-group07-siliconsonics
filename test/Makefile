# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# ==============================================================================
# CONFIGURATION FOR CURRENT TEST
# Modify these variables when switching to a new module or testbench:
# PROJECT_SOURCES
# TOPLEVEL
# COCOTB_TEST_MODULES
# ==============================================================================

# Defaults
SIM             ?= icarus
FST             ?= -fst # Use more efficient FST format
TOPLEVEL_LANG   ?= verilog
SRC_DIR          = $(PWD)/../src

PROJECT_SOURCES = \
    project.v \
    main.v \
    data_mux.v \
    clk_div_10.v \
    ref_sig.v \
    correlator.v \
    windowed_iq_demodulator.v \
    echo_angle_detector.v \
    transducer_ping_generator.v \
    mic_clock_sequence.v \
    atan2_cordic_16b.v \
    phase_difference_to_angle.v \
    uart_tx.v \
    uart_rx.v \
    byte_fifo.v \
    measurement_controller.v

ifneq ($(GATES),yes)

# RTL simulation:
SIM_BUILD        = sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))

else

# Gate level simulation:
SIM_BUILD        = sim_build/gl
PDK_PATH        := $(shell find $(PDK_ROOT) -maxdepth 5 -type d -name $(PDK) 2>/dev/null | head -1)
COMPILE_ARGS    += -DGL_TEST
COMPILE_ARGS    += -DFUNCTIONAL
COMPILE_ARGS    += -DUSE_POWER_PINS
COMPILE_ARGS    += -DSIM
COMPILE_ARGS    += -DUNIT_DELAY=\#1
VERILOG_SOURCES += $(PDK_PATH)/libs.ref/sky130_fd_sc_hd/verilog/primitives.v
VERILOG_SOURCES += $(PDK_PATH)/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v

# This gets copied in by the GDS action workflow
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v

endif

# uart_test would take ~25 min with the real 1 s auto period and 400 ms
# lockout; shorten both for simulation. uart_test.py's AUTO_MS / LOCKOUT_MS
# must match these (30 ms / 20 ms).
ifneq ($(GATES),yes)
COMPILE_ARGS    += -Ptb.user_project.main_inst.AUTO_PERIOD_TICKS=120000
COMPILE_ARGS    += -Ptb.user_project.main_inst.LOCKOUT_TICKS=80000
endif

# Include the testbench sources:
VERILOG_SOURCES += $(PWD)/tb.v
TOPLEVEL         = tb

# ==============================================================================
# Test modules to run, separated by commas and without the .py suffix.
#
# WARNING: mic_us_power_sequence simulates the full 110 ms power-up sequence.
#          It takes ~3 minutes, so keep it last.
#
# Removed and why:
#   phase_difference_calculator - module no longer in src/ (not instantiated
#                                 by main.v; echo_angle_detector sequences the
#                                 CORDIC itself)
#   tb_echo_timing              - tested first_echo_timing, which the chip no
#                                 longer uses. main.v uses echo_angle_detector,
#                                 which needs BOTH mics; that test only drives
#                                 ui_in[1] so sig2 never crosses the threshold.
# ==============================================================================

ifeq ($(GATES),yes)
# Only tests that apply to the complete design:
COCOTB_TEST_MODULES = mic_us_power_sequence
else
# Modules tested separately can be added here as well:
COCOTB_TEST_MODULES = angle_module_test,atan2_cordic,uart_test,mic_us_power_sequence
endif

# Include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim

# Extend cocotb's clean target to also remove build artifacts
.PHONY: clean
clean::
	rm -rf sim_build/ __pycache__/ results.xml tb.fst
