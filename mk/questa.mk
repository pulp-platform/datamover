# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Author: Lionnus Kesting <lkesting@iis.ee.ethz.ch>

QUESTA_SEPP      ?= questa-2023.4
QUESTA_DIR       := $(SIM_DIR)/questa
QUESTA_BUILD_DIR := $(QUESTA_DIR)/builds/$(BUILD_TAG)
BUILD_SENTINEL   := $(QUESTA_BUILD_DIR)/.built
RUN_SIM_TCL      := $(QUESTA_DIR)/run_sim.tcl

BUILD_FINGERPRINT := $(strip $(VLOG_DEFS)) | $(strip $(VLOG_FLAGS))
ifneq ($(wildcard $(BUILD_SENTINEL)),)
ifneq ($(strip $(file < $(BUILD_SENTINEL))),$(strip $(BUILD_FINGERPRINT)))
$(info >>> Build flags changed for build $(BUILD_TAG); forcing rebuild)
$(shell rm -f $(BUILD_SENTINEL))
endif
endif

.PHONY: questa-build questa-force-build questa-run
questa-build: bender-checkout
	@mkdir -p $(QUESTA_BUILD_DIR)
	@flock -x $(QUESTA_BUILD_DIR)/.build.lock $(MAKE) --no-print-directory $(BUILD_SENTINEL)

questa-force-build:
	@rm -f $(BUILD_SENTINEL)
	@rm -rf $(QUESTA_BUILD_DIR)/work $(QUESTA_BUILD_DIR)/compile.tcl
	@$(MAKE) questa-build

$(BUILD_SENTINEL): $(if $(REUSE_PREBUILT_SIM),,$(RTL_DEPS))
	@echo ">>> Building RTL for build: $(BUILD_TAG)"
	@mkdir -p $(QUESTA_BUILD_DIR)
	@rm -f $(QUESTA_BUILD_DIR)/work/_lock
	@rm -f $(QUESTA_BUILD_DIR)/compile.tcl
	$(BENDER_VERSION) script vsim --vlog-arg="$(VLOG_FLAGS)" $(VLOG_DEFS) >> $(QUESTA_BUILD_DIR)/compile.tcl
	cd $(QUESTA_BUILD_DIR) && $(QUESTA_SEPP) vlib work && $(QUESTA_SEPP) vmap work "$$(pwd)/work"
	cd $(QUESTA_BUILD_DIR) && $(QUESTA_SEPP) vsim -c -do 'if {[source compile.tcl] eq "1"} { quit -code 1 } else { quit }'
	cd $(QUESTA_BUILD_DIR) && $(QUESTA_SEPP) vopt +acc=r +nosparse -o vopt_$(TOP_MODULE) -work work $(TOP_MODULE)
	@printf '%s\n' '$(BUILD_FINGERPRINT)' > $@

# The test dir holds the stimuli that the tb reads from its cwd.
questa-run:
	@echo "TEST_NAME = $(TEST_NAME)  (build: $(BUILD_TAG))"
	@mkdir -p $(SIM_TEST_DIR)
	@flock -s $(QUESTA_BUILD_DIR)/.build.lock bash -c 'set -e; \
		ABS_BUILD=$$(readlink -f $(QUESTA_BUILD_DIR)); \
		cd $(SIM_TEST_DIR); \
		$(QUESTA_SEPP) vmap -c >/dev/null; \
		$(QUESTA_SEPP) vmap work "$$ABS_BUILD/work" >/dev/null; \
		$(QUESTA_SEPP) vsim $(VSIM_FLAGS) -do "set TOP_MODULE {$(TOP_MODULE)}; source $(abspath $(RUN_SIM_TCL))"'
