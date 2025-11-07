# Copyright 2023 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

include config.mk

SHELL = /usr/bin/env bash
ROOT_DIR := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

INSTALL_PREFIX        ?= install
INSTALL_DIR           = ${ROOT_DIR}/${INSTALL_PREFIX}
BENDER_INSTALL_DIR    = ${INSTALL_DIR}/bender

VENV_BIN=venv/bin/

BENDER_VERSION = 0.28.1
SIM_PATH   ?= modelsim/vsim
SYNTH_PATH  = synopsys

BENDER_TARGETS = -t rtl -t test -t datamover_test

GUI    ?= 0
target ?= sim_tb_datamover_top_wrap

VLOG_FLAGS += -svinputport=compat
VLOG_FLAGS += -timescale 1ns/1ps

STIMULI_DIR ?= ${ROOT_DIR}/verif/python/generated

STIMULI_FILE_PATH ?= ${STIMULI_DIR}/initial_memory.txt
GOLDEN_FILE_PATH ?= ${STIMULI_DIR}/updated_memory.txt
TESTBENCH_DEFINES  ?= -DSTIMULI_PATH=\\\"${STIMULI_FILE_PATH}\\\"
TESTBENCH_DEFINES  += -DGOLDEN_PATH=\\\"${GOLDEN_FILE_PATH}\\\"

# Propagate paramters to testbench
TESTBENCH_DEFINES += -DSTIM_READ_BASE_ADDR=${STIM_READ_BASE_ADDR}
TESTBENCH_DEFINES += -DSTIM_READ_D0_STRIDE=${STIM_READ_D0_STRIDE}
TESTBENCH_DEFINES += -DSTIM_READ_D0_LENGTH=${STIM_READ_D0_LENGTH}
TESTBENCH_DEFINES += -DSTIM_READ_D1_STRIDE=${STIM_READ_D1_STRIDE}
TESTBENCH_DEFINES += -DSTIM_READ_D1_LENGTH=${STIM_READ_D1_LENGTH}
TESTBENCH_DEFINES += -DSTIM_READ_TOT_LENGTH=${STIM_READ_TOT_LENGTH}

TESTBENCH_DEFINES += -DSTIM_WRITE_BASE_ADDR=${STIM_WRITE_BASE_ADDR}
TESTBENCH_DEFINES += -DSTIM_WRITE_D0_STRIDE=${STIM_WRITE_D0_STRIDE}
TESTBENCH_DEFINES += -DSTIM_WRITE_D0_LENGTH=${STIM_WRITE_D0_LENGTH}
TESTBENCH_DEFINES += -DSTIM_WRITE_D1_STRIDE=${STIM_WRITE_D1_STRIDE}
TESTBENCH_DEFINES += -DSTIM_WRITE_D1_LENGTH=${STIM_WRITE_D1_LENGTH}
TESTBENCH_DEFINES += -DSTIM_WRITE_D2_STRIDE=${STIM_WRITE_D2_STRIDE}
TESTBENCH_DEFINES += -DSTIM_WRITE_TOT_LENGTH=${STIM_WRITE_TOT_LENGTH}

TESTBENCH_DEFINES += -DSTIM_MEM_SIZE=${STIM_MEM_SIZE}

TESTBENCH_DEFINES += -DSTIM_TRANSP_MODE=${STIM_TRANSP_MODE}
TESTBENCH_DEFINES += -DSTIM_TRANSP_LEN=${STIM_TRANSP_LEN}

TESTBENCH_DEFINES += -DBANDWIDTH=${BANDWIDTH}
TESTBENCH_DEFINES += -DNUM_ELEM_WORD=${NUM_ELEM_WORD}
TESTBENCH_DEFINES += -DELEM_WIDTH=${ELEM_WIDTH}


# .PHONY: clean-sim sim-script sim synopsys-script
all: testvector sim

# Configuration help target
help-config:
	@echo "=========================================="
	@echo "Datamover Configuration System"
	@echo "=========================================="
	@echo ""
	@echo "Available presets:"
	@echo "  small-matrix    : 4x4 matrix"
	@echo "  medium-matrix   : 32x32 matrix"
	@echo "  large-matrix    : 448x448 matrix"
	@echo "  transpose-test  : 32x32 matrix"
	@echo "  rect-wide       : 64x256 wide rectangular matrix"
	@echo "  rect-tall       : 256x64 tall rectangular matrix"
	@echo "  rect-narrow     : 16x128 narrow rectangular matrix"
	@echo "  rect-elongated  : 128x32 elongated rectangular matrix"
	@echo "  custom          : User-defined (config.mk default)"
	@echo ""
	@echo "Usage examples:"
	@echo "  make sim CONFIG_PRESET=small-matrix"
	@echo "  make sim CONFIG_PRESET=transpose-test TRANSP_MODE=2"
	@echo "  make sim MATRIX_SIZE_M=64 MATRIX_SIZE_N=32"
	@echo ""
	@echo "Test targets:"
	@echo "  make test-all-presets         : Test all presets (detailed reporting)"
	@echo "  make test-transpose-modes     : Test all transpose modes"
	@echo ""
	@echo "For detailed documentation, see CONFIG_USAGE.md"
	@echo "=========================================="

# Test multiple configurations
test-all-presets:
	@echo "Testing all configuration presets..."
	@failed_tests=""; \
	for preset in small-matrix medium-matrix large-matrix transpose-test rect-wide rect-tall rect-narrow rect-elongated; do \
		echo "=== Testing CONFIG_PRESET=$$preset ==="; \
		if $(MAKE) sim CONFIG_PRESET=$$preset; then \
			echo "✓ $$preset: PASSED"; \
		else \
			echo "✗ $$preset: FAILED"; \
			failed_tests="$$failed_tests $$preset"; \
		fi; \
	done; \
	if [ -n "$$failed_tests" ]; then \
		echo ""; \
		echo "====== SUMMARY: The following presets FAILED:$$failed_tests ======"; \
		exit 1; \
	else \
		echo ""; \
		echo "====== SUMMARY: All presets PASSED! ======"; \
	fi

test-transpose-modes:
	@echo "Testing all transpose modes..."
	@failed_tests=""; \
	for mode in 0 1 2 4; do \
		echo "=== Testing TRANSP_MODE=$$mode ==="; \
		if $(MAKE) sim CONFIG_PRESET=transpose-test TRANSP_MODE=$$mode; then \
			echo "✓ TRANSP_MODE=$$mode: PASSED"; \
		else \
			echo "✗ TRANSP_MODE=$$mode: FAILED"; \
			failed_tests="$$failed_tests $$mode"; \
		fi; \
	done; \
	if [ -n "$$failed_tests" ]; then \
		echo ""; \
		echo "====== SUMMARY: The following transpose modes FAILED:$$failed_tests ======"; \
		exit 1; \
	else \
		echo ""; \
		echo "====== SUMMARY: All transpose modes PASSED! ======"; \
	fi

# Validate current configuration
validate-config:
	@echo "Validating current configuration..."
	@python3 verif/python/validate_config.py \
		--bandwidth $(BANDWIDTH) \
		--word_width $(WORD_WIDTH) \
		--elem_width $(ELEM_WIDTH) \
		--memory_size $(MEMORY_SIZE) \
		--transp_mode $(TRANSP_MODE) \
		--matrix_m $(MATRIX_SIZE_M) \
		--matrix_n $(MATRIX_SIZE_N)

clean-sim:
	rm -rf $(SIM_PATH)/work
	rm -rf $(SIM_PATH)/compile.tcl
	rm -rf $(SIM_PATH)/wlft*
	rm -rf $(SIM_PATH)/transcript
	rm -rf $(SIM_PATH)/modelsim.ini
	rm -rf $(SIM_PATH)/vsim.wlf

sim-script: clean-sim
	mkdir -p $(SIM_PATH)
	$(BENDER_INSTALL_DIR)/bender script vsim $(BENDER_TARGETS) $(TESTBENCH_DEFINES) --vlog-arg="$(VLOG_FLAGS)" >> $(SIM_PATH)/compile.tcl

sim: stimuli sim-script validate-config
	cd modelsim && \
	GUI=$(GUI) $(MAKE) $(target) buildpath=$(ROOT_DIR)/$(SIM_PATH)

clean-stimuli:
	rm -rf $(STIMULI_DIR)

stimuli: clean-stimuli
	python -m verif.python.generate_stimuli_test \
	--mem_size $(STIM_MEM_SIZE) \
	--read_base_addr $(STIM_READ_BASE_ADDR) \
	--read_d0_stride $(STIM_READ_D0_STRIDE) \
	--read_d0_length $(STIM_READ_D0_LENGTH) \
	--read_d1_stride $(STIM_READ_D1_STRIDE) \
	--read_d1_length $(STIM_READ_D1_LENGTH) \
	--read_tot_length $(STIM_READ_TOT_LENGTH) \
	--write_base_addr $(STIM_WRITE_BASE_ADDR) \
	--write_d0_stride $(STIM_WRITE_D0_STRIDE) \
	--write_d0_length $(STIM_WRITE_D0_LENGTH) \
	--write_d1_stride $(STIM_WRITE_D1_STRIDE) \
	--write_d1_length $(STIM_WRITE_D1_LENGTH) \
	--write_d2_stride $(STIM_WRITE_D2_STRIDE) \
	--bandwidth_bits $(BANDWIDTH) \
	--num_elem_word $(NUM_ELEM_WORD) \
	--elem_width $(ELEM_WIDTH) \
	--transp_mode $(STIM_TRANSP_MODE) \
	--transp_len $(STIM_TRANSP_LEN) \
	--output_dir "verif/python/generated"

# Bender
bender: check-bender
	$(BENDER_INSTALL_DIR)/bender update
	$(BENDER_INSTALL_DIR)/bender vendor init

check-bender:
	@if [ -x $(BENDER_INSTALL_DIR)/bender ]; then \
		req="bender $(BENDER_VERSION)"; \
		current="$$($(BENDER_INSTALL_DIR)/bender --version)"; \
		if [ "$$(printf '%s\n' "$${req}" "$${current}" | sort -V | head -n1)" != "$${req}" ]; then \
			rm -rf $(BENDER_INSTALL_DIR); \
		fi \
	fi
	@$(MAKE) -C $(ROOT_DIR) $(BENDER_INSTALL_DIR)/bender

$(BENDER_INSTALL_DIR)/bender:
	mkdir -p $(BENDER_INSTALL_DIR) && cd $(BENDER_INSTALL_DIR) && \
	curl --proto '=https' --tlsv1.2 https://pulp-platform.github.io/bender/init -sSf | sh -s -- $(BENDER_VERSION)

.PHONY: all help-config test-all-presets test-transpose-modes validate-config clean-sim sim-script sim clean-stimuli stimuli bender check-bender
