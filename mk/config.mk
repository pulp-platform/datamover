# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Author: Lionnus Kesting <lkesting@iis.ee.ethz.ch>

# ============================================================================
# Hardware configuration
# ============================================================================
# Selects a profile from configs/hw_configs.json for the CLI quick-test targets
# (test-copy, test-transpose, ...). JSON suites carry their own hw_config.
# Example: make test-transpose HW_CONFIG=bw128_w32
HW_CONFIG ?= default

define load_hw_config
$(shell python -c "import json,sys;c=json.load(open('configs/hw_configs.json'));n='$(1)';d=c.get(n);d or (print(f'ERROR: HW config {n!r} not found. Available: {list(c.keys())}',file=sys.stderr),sys.exit(1));print(' '.join(f'{k}={v}' for k,v in d.items()))")
endef

$(foreach var,$(call load_hw_config,$(HW_CONFIG)),$(eval $(var)))

ifndef BANDWIDTH
$(error BANDWIDTH not set. Check HW_CONFIG=$(HW_CONFIG) and configs/hw_configs.json)
endif

# ============================================================================
# Workload defaults (CLI quick-test mode)
# ============================================================================
DATAMOVER_MODE ?= 0
TRANSP_MODE    ?= 1
CIM_MODE       ?= 0
SIZE_C         ?= 1
SIZE_M         ?= 64
SIZE_N         ?= 64
COUNT          ?= 0

# Memory stall probability
STALL ?= 0.0
export STALL

# ============================================================================
# Test name (JSON mode passes TEST_NAME explicitly) + per-test dir
# ============================================================================
_NAME_ARGS := --DATAMOVER_MODE $(DATAMOVER_MODE) --TRANSP_MODE $(TRANSP_MODE) \
              --CIM_MODE $(CIM_MODE) \
              --SIZE_C $(SIZE_C) --SIZE_M $(SIZE_M) --SIZE_N $(SIZE_N) --COUNT $(COUNT) \
              --HW_CONFIG $(HW_CONFIG)
TEST_NAME := $(or $(TEST_NAME),$(shell python -m datamover_model.workloads.name $(_NAME_ARGS)))

SIM_DIR      := $(ROOT_DIR)/simulation
SIM_TEST_DIR := $(SIM_DIR)/tests/$(TEST_NAME)

# JSON-mode per-test HW params (written by sw-gen); overrides the HW_CONFIG defaults.
# The test dir carries them, so it cannot carry the build tag as well.
-include $(SIM_TEST_DIR)/test_config.mk

# ============================================================================
# Build tag + simulation engine
# ============================================================================
BUILD_TAG := $(shell python -c "from datamover_model.workloads.suite import build_tag; print(build_tag({'BANDWIDTH':$(BANDWIDTH),'WORD_WIDTH':$(WORD_WIDTH),'ELEM_WIDTH':$(ELEM_WIDTH),'MISALIGNED_ACCESSES':$(MISALIGNED_ACCESSES)}, '$(strip $(STALL))'))")

TOP_MODULE ?= tb_datamover

# Engine for simulation can be questa (default) or vcs (e.g. for coverage report)
ENGINE ?= questa
COV    ?= 0
export ENGINE COV

# ============================================================================
# Simulation defines
# ============================================================================
SIM_DEFINES  = -DBANDWIDTH=$(BANDWIDTH)
SIM_DEFINES += -DWORD_WIDTH=$(WORD_WIDTH)
SIM_DEFINES += -DELEM_WIDTH=$(ELEM_WIDTH)
SIM_DEFINES += -DMISALIGNED_ACCESSES=$(MISALIGNED_ACCESSES)
SIM_DEFINES += -DPROB_STALL=$(STALL)
VLOG_DEFS  += $(SIM_DEFINES)

# ============================================================================
# Build hw once, then run tests
# ============================================================================
RTL_DEPS := $(shell find rtl .bender/git/checkouts -type f \( -name '*.sv' -o -name '*.svh' -o -name '*.v' -o -name '*.vh' \) 2>/dev/null) \
            Bender.yml Bender.lock

# See mk/questa.mk and mk/vcs.mk for actual commands
.PHONY: build-sim force-build-sim run-sim
build-sim:       $(ENGINE)-build
force-build-sim: $(ENGINE)-force-build
run-sim:         $(ENGINE)-run

# ============================================================================
# Clean targets
# ============================================================================
.PHONY: clean-test clean-tests clean-builds clean-all-sim

clean-test:
	rm -rf $(SIM_TEST_DIR)

clean-tests:
	rm -rf $(SIM_DIR)/tests

clean-builds:
	rm -rf $(SIM_DIR)/questa/builds $(SIM_DIR)/vcs/builds

clean-all-sim: clean-tests clean-builds
	rm -rf $(SIM_DIR)/vcs/cov $(SIM_DIR)/vcs/cov_export
