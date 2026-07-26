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

.PHONY: bender-checkout
bender-checkout:
	@mkdir -p $(ROOT_DIR)/.bender
	@flock $(ROOT_DIR)/.bender/.checkout.lock $(BENDER_VERSION) checkout

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

# ============================================================================
# JSON-based test runner targets
# ============================================================================

# GUI=1 -> -gui else -c; test-* default GUI, suites default headless
STANDALONE_VSIM_FLAGS := $(if $(filter 0,$(GUI)),-c,-gui)
SUITE_VSIM_FLAGS      := $(if $(filter 1,$(GUI)),$(if $(strip $(TEST)),-gui,-c),-c)

# JSON-based test runner.
# Usage:
#   make tests                                          # all suites in tests/*.json (headless)
#   make tests TEST_JSON=tests/cim.json                 # one suite (headless)
#   make tests TEST_JSON=tests/cim.json TEST=NAME GUI=1 # one test, in the GUI
#   make tests ONLY='COPY_*' SKIP='*BROKEN*'            # filter across all suites
#   make tests PARALLEL=8 TIMEOUT=600
TEST_JSON_GLOB ?= tests/*.json
PARALLEL ?= 8
VSIM_FLAGS ?= $(STANDALONE_VSIM_FLAGS)

.PHONY: tests run-test run-all-tests
tests: bender-checkout
ifeq ($(SUITE_VSIM_FLAGS),-gui)
	@$(MAKE) run-sim-pipeline TEST_JSON="$(TEST_JSON)" TEST_NAME="$(TEST)" VSIM_FLAGS=-gui
else
	@python -u -m datamover_model.testing.runner \
		$(if $(TEST_JSON),$(TEST_JSON),--discover-glob="$(TEST_JSON_GLOB)") \
		$(if $(TEST),--test=$(TEST),) \
		$(if $(ONLY),--only="$(ONLY)",) \
		$(if $(SKIP),--skip="$(SKIP)",) \
		--parallel=$(PARALLEL) \
		$(if $(TIMEOUT),--timeout=$(TIMEOUT),) \
		--vsim-flags="$(SUITE_VSIM_FLAGS)"
endif

run-test run-all-tests: tests

# ============================================================================
# Quick test targets (CLI mode, no JSON). HW from HW_CONFIG (configs/hw_configs.json).
# Usage:
#   riscv make test-copy SIZE_M=64 SIZE_N=64 GUI=0
#   riscv make test-transpose SIZE_M=64 SIZE_N=128 TRANSP_MODE=2
#   riscv make test-cim-layout SIZE_M=64 SIZE_N=128 ROW_TILE_SIZE=64
#   riscv make test-cim-layout-reverse SIZE_M=64 SIZE_N=128 ROW_TILE_SIZE=64
#   riscv make test-cim-layout-transpose SIZE_M=64 SIZE_N=128 ROW_TILE_SIZE=64
#   riscv make test-unfold SIZE_C=64 SIZE_M=16 SIZE_N=16
#   riscv make test-fold   SIZE_C=64 SIZE_M=16 SIZE_N=16
#   add HW_CONFIG=bw128_w32, COUNT=1, GUI=0 as needed
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

REGIF_RDL     := rtl/ctrl/datamover_regif.rdl
REGIF_RTL_DIR := rtl/ctrl/regif
REGIF_SW_HDR  := sw/datamover_regif.h
REGIF_PEAKRDL ?= uv run peakrdl

.PHONY: regif
regif:
	@mkdir -p $(REGIF_RTL_DIR)
	$(REGIF_PEAKRDL) regblock $(REGIF_RDL) -o $(REGIF_RTL_DIR)/ --cpuif passthrough --default-reset arst_n --hwif-report --addr-width 32
	$(REGIF_PEAKRDL) html     $(REGIF_RDL) -o $(REGIF_RTL_DIR)/html/
	$(REGIF_PEAKRDL) c-header  $(REGIF_RDL) -o $(REGIF_SW_HDR)
	sed -i 's/ __attribute__ ((__packed__))//g' $(REGIF_SW_HDR)
	sed -i 's/typedef[[:space:]]\+struct\b/typedef struct packed/g' $(REGIF_RTL_DIR)/datamover_regif_pkg.sv

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
