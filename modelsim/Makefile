# Copyright 2023-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

.PHONY: lib build run all
all: lib build run

QUESTA_SEPP ?= questa-2023.4
TEST_NAME   ?= default
buildpath   ?= build_$(TEST_NAME)
VOPT        ?= $(QUESTA_SEPP) vopt
VSIM        ?= $(QUESTA_SEPP) vsim
VLIB        ?= $(QUESTA_SEPP) vlib
VMAP        ?= $(QUESTA_SEPP) vmap
VSIM_FLAGS  ?= -gui
DEBUG       ?= ON

lib:
	cd $(buildpath) && $(VLIB) work && $(VMAP) work work

build:
	cd $(buildpath) && $(VSIM) -c -do 'source compile.tcl; quit'

run:
	@echo "TEST_NAME = $(TEST_NAME)"
	cd $(buildpath) && $(VSIM) $(VSIM_FLAGS) -do "source ../run_sim.tcl"
