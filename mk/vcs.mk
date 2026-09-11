# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Author: Lionnus Kesting <lkesting@iis.ee.ethz.ch>

VCS_SEPP      ?= vcs-2024.09
VCS_TAG       := $(BUILD_TAG)$(if $(filter 1,$(COV)),_cov,)
VCS_BUILD_DIR := $(SIM_DIR)/vcs/builds/$(VCS_TAG)
VCS_SIMV      := $(VCS_BUILD_DIR)/simv
VCS_VDB       := $(VCS_SIMV).vdb
VCS_COV_CFG   := $(SIM_DIR)/vcs/cov.cfg
VCS_CM        ?= line+cond+fsm+branch+assert+tgl
VLOGAN_FLAGS  ?= -full64 -sverilog -assert svaext -timescale=1ns/1fs
ifeq ($(GUI),1)
VLOGAN_FLAGS += -kdb
endif
VCS_ELAB_FLAGS := $(VLOGAN_FLAGS) -ignore initializer_driver_checks +error+50
ifeq ($(GUI),1)
VCS_ELAB_FLAGS += -debug_access+all
endif
ifeq ($(COV),1)
VCS_ELAB_FLAGS += -cm $(VCS_CM) -cm_seqnoconst -cm_noconst -cm_tgl portsonly+signalsort -cm_hier $(VCS_COV_CFG)
VCS_RUN_CM := -cm $(VCS_CM) -cm_dir $(abspath $(VCS_VDB)) -cm_name $(TEST_NAME)
endif

# A report merges one HW config, because another config is another elaboration.
COV_HW_CONFIG   ?= default
COV_BUILD_TAG    = $(shell python -c "from datamover_model.workloads.suite import build_tag, load_hw_config; print(build_tag(load_hw_config('$(COV_HW_CONFIG)')))")
COV_VDB_GLOB     = $(SIM_DIR)/vcs/builds/$(COV_BUILD_TAG)*/simv.vdb
COV_NAME        ?= $(COV_HW_CONFIG)
COV_METRIC      ?= SCORE
VCS_COV_EXPORT  := $(SIM_DIR)/vcs/cov_export
VCS_COV_DIR      = $(SIM_DIR)/vcs/cov/$(COV_NAME)
VCS_COV_DIRS    ?= $(COV_VDB_GLOB)

.PHONY: vcs-build vcs-force-build vcs-run vcs-cov-report vcs-cov-export
vcs-build: bender-checkout
	@mkdir -p $(VCS_BUILD_DIR)
	@flock -x $(VCS_BUILD_DIR)/.build.lock $(MAKE) --no-print-directory $(VCS_SIMV)

$(VCS_SIMV): $(if $(REUSE_PREBUILT_SIM),,$(RTL_DEPS))
	@echo ">>> Building RTL for build: $(VCS_TAG)"
	@mkdir -p $(VCS_BUILD_DIR)
	@printf 'WORK > DEFAULT\nDEFAULT : ./work-vcs\n' > $(VCS_BUILD_DIR)/synopsys_sim.setup
	$(BENDER_VERSION) script vcs --vlog-arg="$(VLOGAN_FLAGS)" $(VLOG_DEFS) > $(VCS_BUILD_DIR)/compile.sh
	cd $(VCS_BUILD_DIR) && $(VCS_SEPP) bash compile.sh
	cd $(VCS_BUILD_DIR) && $(VCS_SEPP) vcs $(VCS_ELAB_FLAGS) -o simv $(TOP_MODULE)

vcs-force-build:
	@rm -rf $(VCS_BUILD_DIR)
	@$(MAKE) vcs-build

# The test dir holds the stimuli that the tb reads from its cwd.
vcs-run:
	@echo "TEST_NAME = $(TEST_NAME)  (build: $(VCS_TAG))"
	@mkdir -p $(SIM_TEST_DIR)
ifeq ($(GUI),1)
	cd $(SIM_TEST_DIR) && $(VCS_SEPP) $(abspath $(VCS_SIMV)) -no_save -gui
else
	@flock -s $(VCS_BUILD_DIR)/.build.lock bash -c \
		'cd $(SIM_TEST_DIR) && $(VCS_SEPP) $(abspath $(VCS_SIMV)) -no_save $(VCS_RUN_CM) -l vcs_run.log'
endif

vcs-cov-report:
	@mkdir -p $(VCS_COV_DIR)
	@set -o pipefail; \
	dirs=$$(ls -d $(VCS_COV_DIRS) 2>/dev/null); \
	test -n "$$dirs" || { echo "ERROR: no coverage database matching $(VCS_COV_DIRS)" >&2; exit 1; }; \
	$(VCS_SEPP) urg -full64 $$(for d in $$dirs; do printf -- '-dir %s ' "$$(realpath $$d)"; done) \
		-format both -report $(VCS_COV_DIR)/urgReport -show tests 2>&1 | tee $(VCS_COV_DIR)/urg.log; \
	if grep -q UCAPI-INSTANCEMISMATCH $(VCS_COV_DIR)/urg.log; then \
		echo "ERROR: databases are from different elaborations, merge one HW config at a time" >&2; \
		exit 1; \
	fi
	@python -m datamover_model.testing.coverage $(VCS_COV_DIR)/urgReport/dashboard.txt \
		--label "$(COV_NAME)" --metric $(COV_METRIC) --json-out $(VCS_COV_DIR)/coverage.json

# Collect the databases of one suite under a unique name, for a later merge.
vcs-cov-export:
	@mkdir -p $(VCS_COV_EXPORT)
	@found=0; for vdb in $(COV_VDB_GLOB); do \
		[ -d "$$vdb" ] || continue; \
		out=$(VCS_COV_EXPORT)/$(COV_NAME)__$$(basename $$(dirname $$vdb)).vdb; \
		rm -rf "$$out" && cp -r "$$vdb" "$$out" && echo "exported $$out"; found=1; \
	done; test $$found -eq 1 || \
		echo "NOTE: no $(COV_HW_CONFIG) database under $(SIM_DIR)/vcs/builds, nothing to export"
