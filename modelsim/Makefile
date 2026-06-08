# Copyright 2023-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

.PHONY: lib build run

QUESTA_SEPP ?= questa-2023.4
TEST_NAME   ?= default
BUILDPATH   ?= builds/default
TESTPATH    ?= tests/$(TEST_NAME)
VOPT        ?= $(QUESTA_SEPP) vopt
VSIM        ?= $(QUESTA_SEPP) vsim
VLIB        ?= $(QUESTA_SEPP) vlib
VMAP        ?= $(QUESTA_SEPP) vmap
VSIM_FLAGS  ?= -gui
TOP_MODULE  ?= tb_datamover

# Compile RTL once into BUILDPATH/work and vopt the top (shared by every test).
lib:
	cd $(BUILDPATH) && $(VLIB) work && $(VMAP) work "$$(pwd)/work"

build:
	cd $(BUILDPATH) && $(VSIM) -c -do 'source compile.tcl; quit'
	cd $(BUILDPATH) && $(VOPT) +acc=r +nosparse -o vopt_$(TOP_MODULE) -work work $(TOP_MODULE)

# Run a test in its own dir, mapping work to the shared build. The tb reads
# ./stim_instr.txt / ./stim_data.txt from this cwd.
run:
	@echo "TEST_NAME = $(TEST_NAME)  (build: $(BUILDPATH))"
	@ABS_BUILD=$$(readlink -f $(BUILDPATH)) && \
		mkdir -p $(TESTPATH) && \
		cd $(TESTPATH) && \
		$(VMAP) -c >/dev/null && \
		$(VMAP) work "$$ABS_BUILD/work" >/dev/null && \
		$(VSIM) $(VSIM_FLAGS) -do "set TOP_MODULE {$(TOP_MODULE)}; source ../../run_sim.tcl"
