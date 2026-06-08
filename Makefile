# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

SHELL = /usr/bin/env bash
ROOT_DIR := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

BENDER_VERSION  = bender-0.31.0
MODELSIM_DIR        ?= $(ROOT_DIR)/modelsim

VLOG_FLAGS += -svinputport=compat
VLOG_FLAGS += -timescale 1ns/1fs
VLOG_FLAGS += +nosparse

VLOG_DEFS  += -t rtl -t datamover_standalone

# HW config + workload defaults + auto TEST_NAME + build-once machinery
# (build-sim / run-sim / BUILD_TAG / SIM_DEFINES live here).
include mk/config.mk

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

# build-sim / force-build-sim / run-sim live in mk/config.mk (build-once per BUILD_TAG).

clean-sim:
	rm -rf $(MODELSIM_TEST_DIR)

clean-all-sim:
	rm -rf $(MODELSIM_DIR)/builds $(MODELSIM_DIR)/tests

.PHONY: run-sim-generate run-sim-execute run-sim-pipeline
run-sim-generate:
	@$(MAKE) validate-pipeline-inputs TEST_JSON="$(TEST_JSON)" TEST_NAME="$(TEST_NAME)"
	$(MAKE) TEST_JSON="$(TEST_JSON)" TEST_NAME="$(TEST_NAME)" clean-sim sw-gen

run-sim-execute:
ifndef TEST_NAME
	$(error TEST_NAME is required)
endif
	@test -f "$(MODELSIM_TEST_DIR)/test_config.mk" || \
	    (echo "ERROR: missing $(MODELSIM_TEST_DIR)/test_config.mk; run run-sim-generate first" >&2; exit 1)
	$(MAKE) TEST_NAME="$(TEST_NAME)" VSIM_FLAGS="$(VSIM_FLAGS)" build-sim sw-compile run-sim

run-sim-pipeline:
	$(MAKE) TEST_JSON="$(TEST_JSON)" TEST_NAME="$(TEST_NAME)" run-sim-generate
	$(MAKE) TEST_NAME="$(TEST_NAME)" VSIM_FLAGS="$(VSIM_FLAGS)" run-sim-execute

.PHONY: run-test run-all-tests
# Select a single test with TEST=<name> (or TEST_NAME=<name>, same thing).
RUN_TEST := $(or $(TEST),$(TEST_NAME))
# GUI (the default) runs the single test directly via run-sim-pipeline so the
# Questa window opens; headless (NO_GUI=1 -> VSIM_FLAGS=-c) goes through the runner.
run-test:
ifndef TEST_JSON
	$(error TEST_JSON is required)
endif
ifeq ($(VSIM_FLAGS),-gui)
	@test -n "$(RUN_TEST)" || { echo "ERROR: GUI mode needs a single test: pass TEST_NAME=<name> (or NO_GUI=1 for headless)" >&2; exit 1; }
	$(MAKE) run-sim-pipeline TEST_JSON="$(TEST_JSON)" TEST_NAME="$(RUN_TEST)" VSIM_FLAGS=-gui
else
	python -u -m datamover_model.testing.runner $(TEST_JSON) \
	    $(if $(RUN_TEST),--test=$(RUN_TEST),) \
	    $(if $(ONLY),--only="$(ONLY)",) \
	    $(if $(SKIP),--skip="$(SKIP)",) \
	    $(if $(PARALLEL),--parallel=$(PARALLEL),) \
	    $(if $(TIMEOUT),--timeout=$(TIMEOUT),) \
	    --vsim-flags="$(VSIM_FLAGS)"
endif

TEST_JSON_GLOB ?= tests/*.json
ALL_TESTS_VSIM_FLAGS ?= -c
run-all-tests:
	python -u -m datamover_model.testing.runner --discover-glob="$(TEST_JSON_GLOB)" \
	    $(if $(ONLY),--only="$(ONLY)",) \
	    $(if $(SKIP),--skip="$(SKIP)",) \
	    $(if $(PARALLEL),--parallel=$(PARALLEL),) \
	    $(if $(TIMEOUT),--timeout=$(TIMEOUT),) \
	    --vsim-flags="$(ALL_TESTS_VSIM_FLAGS)"

# ============================================================================
# Quick test targets (CLI mode, no JSON). HW from HW_CONFIG (configs/hw_configs.json).
# Usage:
#   riscv make test-copy SIZE_M=64 SIZE_N=64 NO_GUI=1
#   riscv make test-transpose SIZE_M=64 SIZE_N=128 TRANSP_MODE=2
#   riscv make test-cim-layout SIZE_M=64 SIZE_N=128 ROW_TILE_SIZE=64
#   riscv make test-cim-layout-reverse SIZE_M=64 SIZE_N=128 ROW_TILE_SIZE=64
#   riscv make test-cim-layout-transpose SIZE_M=64 SIZE_N=128 ROW_TILE_SIZE=64
#   riscv make test-unfold SIZE_C=64 SIZE_M=16 SIZE_N=16
#   riscv make test-fold   SIZE_C=64 SIZE_M=16 SIZE_N=16
#   add HW_CONFIG=bw128_w32, COUNT=1, NO_GUI=1 as needed
# ============================================================================
.PHONY: test-copy test-transpose test-cim-layout test-cim-layout-reverse \
        test-cim-layout-transpose test-unfold test-fold _quick-test

test-copy:                 ; @$(MAKE) DATAMOVER_MODE=0 _quick-test
test-transpose:            ; @$(MAKE) DATAMOVER_MODE=1 _quick-test
test-cim-layout:           ; @$(MAKE) DATAMOVER_MODE=2 CIM_MODE=0 _quick-test
test-cim-layout-reverse:   ; @$(MAKE) DATAMOVER_MODE=2 CIM_MODE=1 _quick-test
test-cim-layout-transpose: ; @$(MAKE) DATAMOVER_MODE=3 _quick-test
test-unfold:               ; @$(MAKE) DATAMOVER_MODE=4 _quick-test
test-fold:                 ; @$(MAKE) DATAMOVER_MODE=5 _quick-test

_quick-test:
	@echo "Test: $(TEST_NAME)  [HW_CONFIG=$(HW_CONFIG): BW=$(BANDWIDTH) WW=$(WORD_WIDTH) EW=$(ELEM_WIDTH) MA=$(MISALIGNED_ACCESSES)]"
	$(MAKE) TEST_NAME="$(TEST_NAME)" clean-sim sw-gen
	$(MAKE) TEST_NAME="$(TEST_NAME)" run-sim-execute

# ============================================================================
# Backend
# ============================================================================
DESIGN ?= datamover_top_wrap
export DESIGN

NONFREE_REMOTE ?= git@iis-git.ee.ethz.ch:lkesting/surya-cim-nonfree.git
NONFREE_COMMIT ?= lkesting/datamover
NONFREE_DIR     = $(ROOT_DIR)/nonfree

.PHONY: nonfree clean-nonfree
nonfree:
	@if [ -d $(NONFREE_DIR)/.git ]; then \
		echo "ERROR: $(NONFREE_DIR) is already initialized. Run 'make clean-nonfree' first if you really want to reset it."; \
		exit 1; \
	fi
	mkdir -p $(NONFREE_DIR) && \
	cd $(NONFREE_DIR) && \
	git init && \
	git remote add origin $(NONFREE_REMOTE) && \
	git fetch origin && \
	git checkout $(NONFREE_COMMIT) -f

clean-nonfree:
	@echo "This will DELETE the entire nonfree directory: $(NONFREE_DIR)"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || (echo "Aborted."; exit 1)
	rm -rf $(NONFREE_DIR)

-include $(NONFREE_DIR)/Makefile
# ============================================================================

.PHONY: clean clean-all
clean: clean-all-sim
	rm -rf reports/
	find datamover_model -name __pycache__ -type d -exec rm -rf {} +

clean-all: clean
	rm -rf .bender
	@echo "NOTE: nonfree directory is not removed. Use 'make clean-nonfree' to remove it."
