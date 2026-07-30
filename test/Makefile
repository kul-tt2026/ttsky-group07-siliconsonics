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

#PROJECT_SOURCES  = project.v
PROJECT_SOURCES  = pdm_detectors.v
#PROJECT_SOURCES  = multiplier.v
#PROJECT_SOURCES  = shifter.v

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

# Include the testbench sources:
VERILOG_SOURCES += $(PWD)/tb.v
#TOPLEVEL         = tb
TOPLEVEL         = pdm_detector
#TOPLEVEL         = constant_multiplier
#TOPLEVEL         = down_shifter

# List test modules to run, separated by commas and without the .py suffix:
#COCOTB_TEST_MODULES = test
COCOTB_TEST_MODULES = tb_pdm_detector
#COCOTB_TEST_MODULES = tb_multiplier
#COCOTB_TEST_MODULES = tb_shifter

# Include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim

# Extend cocotb's clean target to also remove build artifacts
.PHONY: clean
clean::
	rm -rf sim_build/ __pycache__/ results.xml tb.fst
