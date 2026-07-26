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
ROW_TILE_SIZE  ?= 64
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
              --CIM_MODE $(CIM_MODE) --ROW_TILE_SIZE $(ROW_TILE_SIZE) \
              --SIZE_C $(SIZE_C) --SIZE_M $(SIZE_M) --SIZE_N $(SIZE_N) --COUNT $(COUNT) \
              --HW_CONFIG $(HW_CONFIG)
TEST_NAME := $(or $(TEST_NAME),$(shell python -m datamover_model.workloads.name $(_NAME_ARGS)))

MODELSIM_TEST_DIR := $(MODELSIM_DIR)/tests/$(TEST_NAME)

# JSON-mode per-test HW params (written by sw-gen); overrides the HW_CONFIG defaults.
-include $(MODELSIM_TEST_DIR)/test_config.mk

# ============================================================================
# Build tag + shared build dir 
# ============================================================================
BUILD_TAG := $(shell python -c "from datamover_model.workloads.suite import build_tag; print(build_tag({'BANDWIDTH':$(BANDWIDTH),'WORD_WIDTH':$(WORD_WIDTH),'ELEM_WIDTH':$(ELEM_WIDTH),'MISALIGNED_ACCESSES':$(MISALIGNED_ACCESSES)}, '$(strip $(STALL))'))")
MODELSIM_BUILDS_DIR := $(MODELSIM_DIR)/builds/$(BUILD_TAG)
BUILD_SENTINEL      := $(MODELSIM_BUILDS_DIR)/.built

TOP_MODULE ?= tb_datamover

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

BUILD_FINGERPRINT := $(strip $(VLOG_DEFS)) | $(strip $(VLOG_FLAGS))
ifneq ($(wildcard $(BUILD_SENTINEL)),)
ifneq ($(strip $(file < $(BUILD_SENTINEL))),$(strip $(BUILD_FINGERPRINT)))
$(info >>> Build flags changed for build $(BUILD_TAG); forcing rebuild)
$(shell rm -f $(BUILD_SENTINEL))
endif
endif

.PHONY: build-sim force-build-sim run-sim
build-sim: bender-checkout
	@mkdir -p $(MODELSIM_BUILDS_DIR)
	@flock -x $(MODELSIM_BUILDS_DIR)/.build.lock $(MAKE) --no-print-directory $(BUILD_SENTINEL)

force-build-sim:
	@rm -f $(BUILD_SENTINEL) $(MODELSIM_BUILDS_DIR)/compile.tcl
	@rm -rf $(MODELSIM_BUILDS_DIR)/work
	@$(MAKE) build-sim

$(BUILD_SENTINEL): $(RTL_DEPS)
	@echo ">>> Building RTL for build: $(BUILD_TAG)"
	@mkdir -p $(MODELSIM_BUILDS_DIR)
	@rm -f $(MODELSIM_BUILDS_DIR)/compile.tcl
	$(BENDER_VERSION) script vsim --vlog-arg="$(VLOG_FLAGS)" $(VLOG_DEFS) >> $(MODELSIM_BUILDS_DIR)/compile.tcl
	cd $(MODELSIM_DIR) && $(MAKE) BUILDPATH=builds/$(BUILD_TAG) TOP_MODULE=$(TOP_MODULE) lib build
	@printf '%s\n' '$(BUILD_FINGERPRINT)' > $@

run-sim:
	@mkdir -p $(MODELSIM_BUILDS_DIR)
	@flock -s $(MODELSIM_BUILDS_DIR)/.build.lock \
		$(MAKE) -C $(MODELSIM_DIR) TEST_NAME=$(TEST_NAME) BUILDPATH=builds/$(BUILD_TAG) \
		TESTPATH=tests/$(TEST_NAME) VSIM_FLAGS="$(VSIM_FLAGS)" TOP_MODULE="$(TOP_MODULE)" run
