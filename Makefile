# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

SHELL = /usr/bin/env bash
ROOT_DIR := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

BENDER_VERSION  = bender-0.31.0
MODELSIM_DIR        ?= $(ROOT_DIR)/modelsim
MODELSIM_BUILD_DIR  ?= $(MODELSIM_DIR)/build_$(TEST_NAME)

VLOG_FLAGS += -svinputport=compat
VLOG_FLAGS += -timescale 1ns/1fs
VLOG_FLAGS += +nosparse

VLOG_DEFS  += -t rtl -t datamover_standalone

BANDWIDTH           ?= 512
WORD_WIDTH          ?= 64
ELEM_WIDTH          ?= 8
MISALIGNED_ACCESSES ?= 0

-include $(MODELSIM_BUILD_DIR)/test_config.mk

SIM_DEFINES  = -DBANDWIDTH=$(BANDWIDTH)
SIM_DEFINES += -DWORD_WIDTH=$(WORD_WIDTH)
SIM_DEFINES += -DELEM_WIDTH=$(ELEM_WIDTH)
SIM_DEFINES += -DMISALIGNED_ACCESSES=$(MISALIGNED_ACCESSES)
SIM_DEFINES += -DTEST_NAME=$(TEST_NAME)

VLOG_DEFS  += $(SIM_DEFINES)

include sw/sw.mk

.PHONY: validate-pipeline-inputs
validate-pipeline-inputs:
ifndef TEST_JSON
	$(error TEST_JSON is required)
endif
ifndef TEST_NAME
	$(error TEST_NAME is required)
endif
	@test -f "$(TEST_JSON)" || (echo "ERROR: TEST_JSON file not found: $(TEST_JSON)" >&2; exit 1)

ifeq ($(NO_GUI),1)
    override VSIM_FLAGS := -c
endif
VSIM_FLAGS ?= -gui

modelsim-sim-script:
	mkdir -p $(MODELSIM_BUILD_DIR)
	@rm -f $(MODELSIM_BUILD_DIR)/compile.tcl
	$(BENDER_VERSION) script vsim --vlog-arg="$(VLOG_FLAGS)" $(VLOG_DEFS) >> $(MODELSIM_BUILD_DIR)/compile.tcl

build-sim:
	cd $(MODELSIM_DIR) && \
	$(MAKE) VSIM_FLAGS=$(VSIM_FLAGS) TEST_NAME=$(TEST_NAME) lib build

run-sim:
	cd $(MODELSIM_DIR) && \
	$(MAKE) TEST_NAME=$(TEST_NAME) VSIM_FLAGS="$(VSIM_FLAGS)" run

clean-sim:
	rm -rf $(MODELSIM_BUILD_DIR)

clean-all-sim:
	rm -rf $(MODELSIM_DIR)/build_*

.PHONY: run-sim-generate run-sim-execute run-sim-pipeline
run-sim-generate:
	@$(MAKE) validate-pipeline-inputs TEST_JSON="$(TEST_JSON)" TEST_NAME="$(TEST_NAME)"
	$(MAKE) TEST_JSON="$(TEST_JSON)" TEST_NAME="$(TEST_NAME)" clean-sim sw-gen

run-sim-execute:
ifndef TEST_NAME
	$(error TEST_NAME is required)
endif
	@test -f "$(MODELSIM_BUILD_DIR)/test_config.mk" || \
	    (echo "ERROR: missing $(MODELSIM_BUILD_DIR)/test_config.mk; run run-sim-generate first" >&2; exit 1)
	$(MAKE) TEST_NAME="$(TEST_NAME)" VSIM_FLAGS="$(VSIM_FLAGS)" modelsim-sim-script build-sim sw-compile run-sim

run-sim-pipeline:
	$(MAKE) TEST_JSON="$(TEST_JSON)" TEST_NAME="$(TEST_NAME)" run-sim-generate
	$(MAKE) TEST_NAME="$(TEST_NAME)" VSIM_FLAGS="$(VSIM_FLAGS)" run-sim-execute

.PHONY: run-test run-all-tests
run-test:
ifndef TEST_JSON
	$(error TEST_JSON is required)
endif
	python -u -m utils.run_test $(TEST_JSON) \
	    $(if $(TEST),--test=$(TEST),) \
	    $(if $(PARALLEL),--parallel=$(PARALLEL),) \
	    $(if $(TIMEOUT),--timeout=$(TIMEOUT),) \
	    $(if $(VSIM_FLAGS),--vsim-flags="$(VSIM_FLAGS)",)

TEST_JSON_GLOB ?= utils/datamover_*_tests.json
ALL_TESTS_VSIM_FLAGS ?= -c
run-all-tests:
	python -u -m utils.run_test --discover-glob="$(TEST_JSON_GLOB)" \
	    $(if $(PARALLEL),--parallel=$(PARALLEL),) \
	    $(if $(TIMEOUT),--timeout=$(TIMEOUT),) \
	    --vsim-flags="$(ALL_TESTS_VSIM_FLAGS)"

.PHONY: clean clean-all
clean: clean-all-sim
	rm -rf reports/
	rm -rf utils/__pycache__ verif/python/__pycache__

clean-all: clean
	rm -rf .bender
