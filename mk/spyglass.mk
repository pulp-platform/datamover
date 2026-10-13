# Copyright 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

SG_SEPP        ?= spyglass-2024.09
LINT_DIR        = $(ROOT_DIR)/util/lint
LINT_BUILD_DIR  = $(LINT_DIR)/build
LINT_TOP       ?= datamover_top_wrap
LINT_REPORT     = $(LINT_BUILD_DIR)/$(LINT_TOP)/consolidated_reports/$(LINT_TOP)_lint_lint_rtl/moresimple.rpt
LINT_LOG        = $(LINT_BUILD_DIR)/spyglass.log
LINT_RTL        = $(shell find $(ROOT_DIR)/rtl -name '*.sv' -not -path '*/verif/*')

.PHONY: spyglass spyglass-clean

$(LINT_BUILD_DIR)/sources.f: $(ROOT_DIR)/Bender.lock $(ROOT_DIR)/Bender.yml | bender-checkout
	@mkdir -p $(@D)
	$(BENDER_VERSION) script flist-plus -t rtl -t synthesis > $@

$(LINT_REPORT): $(LINT_DIR)/spyglass.tcl $(LINT_BUILD_DIR)/sources.f $(LINT_RTL)
	cd $(LINT_BUILD_DIR) && LINT_TOP=$(LINT_TOP) $(SG_SEPP) sg_shell -tcl $< > $(LINT_LOG) 2>&1

spyglass: $(LINT_REPORT)
	$(LINT_DIR)/check_spyglass_lint.py $<

spyglass-clean:
	rm -rf $(LINT_BUILD_DIR)
