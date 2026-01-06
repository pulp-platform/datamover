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
TESTBENCH_DEFINES += -DSTIM_READ_D2_STRIDE=${STIM_READ_D2_STRIDE}
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

TESTBENCH_DEFINES += -DSTIM_MATRIX_SIZE_M=${STIM_MATRIX_SIZE_M}
TESTBENCH_DEFINES += -DSTIM_MATRIX_SIZE_N=${STIM_MATRIX_SIZE_N}

TESTBENCH_DEFINES += -DBANDWIDTH=${BANDWIDTH}
TESTBENCH_DEFINES += -DNUM_ELEM_WORD=${NUM_ELEM_WORD}
TESTBENCH_DEFINES += -DELEM_WIDTH=${ELEM_WIDTH}
TESTBENCH_DEFINES += -DMISALIGNED_ACCESSES=${MISALIGNED_ACCESSES}


# .PHONY: clean-sim sim-script sim synopsys-script
all: sim

# Configuration help target
help:
	@echo "=========================================="
	@echo "Datamover Configuration System"
	@echo "=========================================="
	@echo ""
	@echo "Available presets:"
	@echo "  small-matrix    : 4x4 matrix (transpose)"
	@echo "  medium-matrix   : 64x64 matrix (transpose)"
	@echo "  large-matrix    : 448x448 matrix (transpose)"
	@echo "  transpose-test  : 32x32 matrix (transpose)"
	@echo "  rect-wide       : 64x256 wide rectangular matrix (transpose)"
	@echo "  rect-tall       : 256x64 tall rectangular matrix (transpose)"
	@echo "  rect-narrow     : 16x128 narrow rectangular matrix (transpose)"
	@echo "  rect-elongated  : 128x32 elongated rectangular matrix (transpose)"
	@echo "  copy-small      : 4x4 matrix (copy mode)"
	@echo "  copy-medium     : 64x64 matrix (copy mode)"
	@echo "  cim-small       : 32x128 matrix (CIM mode)"
	@echo "  cim-medium      : 64x256 matrix (CIM mode)"
	@echo "  cim-large       : 128x256 matrix (CIM mode)"
	@echo "  custom          : User-defined (config.mk default)"
	@echo ""
	@echo "Usage examples:"
	@echo "  make sim CONFIG_PRESET=small-matrix"
	@echo "  make sim CONFIG_PRESET=transpose-test TRANSP_MODE=2"
	@echo "  make sim MATRIX_SIZE_M=64 MATRIX_SIZE_N=32"
	@echo ""
	@echo "Test targets:"
	@echo "  make test-all-presets              : Test all presets (detailed reporting)"
	@echo "  make test-transpose-modes          : Test all transpose modes"
	@echo "  make test-transpose-grid           : Test all bandwidth/transpose/word width combinations"
	@echo "  make test-cim-grid                 : Test all bandwidth/CIM dimension/word width combinations"
	@echo ""
	@echo "For detailed documentation, see CONFIG_USAGE.md"
	@echo "=========================================="

# Test multiple configurations
test-all-presets:
	@echo "Testing all configuration presets..."
	@failed_tests=""; \
	for preset in small-matrix medium-matrix large-matrix transpose-test rect-wide rect-tall rect-narrow rect-elongated copy-small copy-medium cim-small cim-medium cim-large; do \
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
	for mode in 1 2 4; do \
		echo "=== Testing TRANSP_MODE=$$mode ==="; \
		if $(MAKE) sim CONFIG_PRESET=transpose-test DATAMOVER_MODE=1 TRANSP_MODE=$$mode; then \
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


test-transpose-grid:
	@echo "Testing configuration parameter combinations (grid)..."
	@failed_tests=""; \
	total_tests=0; \
	passed_tests=0; \
	for bandwidth in 256 512; do \
		for transp_mode in 1 2 4; do \
			for word_width in 16 32 64; do \
				total_tests=$$((total_tests + 1)); \
				echo "=== Testing BANDWIDTH=$$bandwidth TRANSP_MODE=$$transp_mode WORD_WIDTH=$$word_width ==="; \
				if $(MAKE) sim CONFIG_PRESET=medium-matrix BANDWIDTH=$$bandwidth DATAMOVER_MODE=1 TRANSP_MODE=$$transp_mode WORD_WIDTH=$$word_width; then \
					echo "✓ BANDWIDTH=$$bandwidth TRANSP_MODE=$$transp_mode WORD_WIDTH=$$word_width: PASSED"; \
					passed_tests=$$((passed_tests + 1)); \
				else \
					echo "✗ BANDWIDTH=$$bandwidth TRANSP_MODE=$$transp_mode WORD_WIDTH=$$word_width: FAILED"; \
					failed_tests="$$failed_tests BANDWIDTH=$$bandwidth/TRANSP_MODE=$$transp_mode/WORD_WIDTH=$$word_width"; \
				fi; \
			done; \
		done; \
	done; \
	echo ""; \
	echo "====== TEST SUMMARY ======"; \
	echo "Total tests: $$total_tests"; \
	echo "Passed: $$passed_tests"; \
	echo "Failed: $$((total_tests - passed_tests))"; \
	if [ -n "$$failed_tests" ]; then \
		echo ""; \
		echo "FAILED combinations:$$failed_tests"; \
		exit 1; \
	else \
		echo ""; \
		echo "====== SUMMARY: All bandwidth/transpose/word width combinations PASSED! ======"; \
	fi

test-transpose-grid-misaligned:
	@echo "Testing configuration parameter combinations (grid)..."
	@failed_tests=""; \
	total_tests=0; \
	passed_tests=0; \
	for bandwidth in 160 288; do \
		for transp_mode in 1 2 4; do \
			for word_width in 32; do \
				total_tests=$$((total_tests + 1)); \
				echo "=== Testing BANDWIDTH=$$bandwidth MISALIGNED_ACCESSES=1 TRANSP_MODE=$$transp_mode WORD_WIDTH=$$word_width ==="; \
				if $(MAKE) sim CONFIG_PRESET=medium-matrix BANDWIDTH=$$bandwidth MISALIGNED_ACCESSES=1 DATAMOVER_MODE=1 TRANSP_MODE=$$transp_mode WORD_WIDTH=$$word_width; then \
					echo "✓ BANDWIDTH=$$bandwidth MISALIGNED_ACCESSES=1 TRANSP_MODE=$$transp_mode WORD_WIDTH=$$word_width: PASSED"; \
					passed_tests=$$((passed_tests + 1)); \
				else \
					echo "✗ BANDWIDTH=$$bandwidth MISALIGNED_ACCESSES=1 TRANSP_MODE=$$transp_mode WORD_WIDTH=$$word_width: FAILED"; \
					failed_tests="$$failed_tests BANDWIDTH=$$bandwidth/MISALIGNED_ACCESSES=1/TRANSP_MODE=$$transp_mode/WORD_WIDTH=$$word_width"; \
				fi; \
			done; \
		done; \
	done; \
	for bandwidth in 320 576; do \
		for transp_mode in 1 2 4; do \
			for word_width in 64; do \
				total_tests=$$((total_tests + 1)); \
				echo "=== Testing BANDWIDTH=$$bandwidth MISALIGNED_ACCESSES=1 TRANSP_MODE=$$transp_mode WORD_WIDTH=$$word_width ==="; \
				if $(MAKE) sim CONFIG_PRESET=medium-matrix BANDWIDTH=$$bandwidth MISALIGNED_ACCESSES=1 DATAMOVER_MODE=1 TRANSP_MODE=$$transp_mode WORD_WIDTH=$$word_width; then \
					echo "✓ BANDWIDTH=$$bandwidth MISALIGNED_ACCESSES=1 TRANSP_MODE=$$transp_mode WORD_WIDTH=$$word_width: PASSED"; \
					passed_tests=$$((passed_tests + 1)); \
				else \
					echo "✗ BANDWIDTH=$$bandwidth MISALIGNED_ACCESSES=1 TRANSP_MODE=$$transp_mode WORD_WIDTH=$$word_width: FAILED"; \
					failed_tests="$$failed_tests BANDWIDTH=$$bandwidth/MISALIGNED_ACCESSES=1/TRANSP_MODE=$$transp_mode/WORD_WIDTH=$$word_width"; \
				fi; \
			done; \
		done; \
	done; \
	echo ""; \
	echo "====== TEST SUMMARY ======"; \
	echo "Total tests: $$total_tests"; \
	echo "Passed: $$passed_tests"; \
	echo "Failed: $$((total_tests - passed_tests))"; \
	if [ -n "$$failed_tests" ]; then \
		echo ""; \
		echo "FAILED combinations:$$failed_tests"; \
		exit 1; \
	else \
		echo ""; \
		echo "====== SUMMARY: All bandwidth/transpose/word width combinations PASSED! ======"; \
	fi

test-cim-grid:
	@echo "Testing CIM configuration parameter combinations (grid)..."
	@failed_tests=""; \
	total_tests=0; \
	passed_tests=0; \
	for bandwidth in 128 256; do \
		for word_width in 32 64; do \
			for cim_inner_dim in 32 64; do \
				for cim_outer_dim in 32 64; do \
					total_tests=$$((total_tests + 1)); \
					echo "=== Testing BANDWIDTH=$$bandwidth WORD_WIDTH=$$word_width CIM_INNER_DIM=$$cim_inner_dim CIM_OUTER_DIM=$$cim_outer_dim ==="; \
					if $(MAKE) sim CONFIG_PRESET=cim-large DATAMOVER_MODE=2 CIM_MODE=0 BANDWIDTH=$$bandwidth WORD_WIDTH=$$word_width CIM_INNER_DIM=$$cim_inner_dim CIM_OUTER_DIM=$$cim_outer_dim; then \
						echo "✓ BANDWIDTH=$$bandwidth WORD_WIDTH=$$word_width CIM_INNER_DIM=$$cim_inner_dim CIM_OUTER_DIM=$$cim_outer_dim: PASSED"; \
						passed_tests=$$((passed_tests + 1)); \
					else \
						echo "✗ BANDWIDTH=$$bandwidth WORD_WIDTH=$$word_width CIM_INNER_DIM=$$cim_inner_dim CIM_OUTER_DIM=$$cim_outer_dim: FAILED"; \
						failed_tests="$$failed_tests BANDWIDTH=$$bandwidth/WORD_WIDTH=$$word_width/CIM_INNER_DIM=$$cim_inner_dim/CIM_OUTER_DIM=$$cim_outer_dim"; \
					fi; \
				done; \
			done; \
		done; \
	done; \
	for bandwidth in 512; do \
		for word_width in 32 64; do \
			for cim_inner_dim in 64; do \
				for cim_outer_dim in 64; do \
					total_tests=$$((total_tests + 1)); \
					echo "=== Testing BANDWIDTH=$$bandwidth WORD_WIDTH=$$word_width CIM_INNER_DIM=$$cim_inner_dim CIM_OUTER_DIM=$$cim_outer_dim ==="; \
					if $(MAKE) sim CONFIG_PRESET=cim-large DATAMOVER_MODE=2 CIM_MODE=0 BANDWIDTH=$$bandwidth WORD_WIDTH=$$word_width CIM_INNER_DIM=$$cim_inner_dim CIM_OUTER_DIM=$$cim_outer_dim; then \
						echo "✓ BANDWIDTH=$$bandwidth WORD_WIDTH=$$word_width CIM_INNER_DIM=$$cim_inner_dim CIM_OUTER_DIM=$$cim_outer_dim: PASSED"; \
						passed_tests=$$((passed_tests + 1)); \
					else \
						echo "✗ BANDWIDTH=$$bandwidth WORD_WIDTH=$$word_width CIM_INNER_DIM=$$cim_inner_dim CIM_OUTER_DIM=$$cim_outer_dim: FAILED"; \
						failed_tests="$$failed_tests BANDWIDTH=$$bandwidth/WORD_WIDTH=$$word_width/CIM_INNER_DIM=$$cim_inner_dim/CIM_OUTER_DIM=$$cim_outer_dim"; \
					fi; \
				done; \
			done; \
		done; \
	done; \
	echo ""; \
	echo "====== CIM TEST SUMMARY ======"; \
	echo "Total tests: $$total_tests"; \
	echo "Passed: $$passed_tests"; \
	echo "Failed: $$((total_tests - passed_tests))"; \
	if [ -n "$$failed_tests" ]; then \
		echo ""; \
		echo "FAILED CIM combinations:$$failed_tests"; \
		exit 1; \
	else \
		echo ""; \
		echo "====== SUMMARY: All CIM configuration combinations PASSED! ======"; \
	fi

# ToDo: CIM tests grid


# Validate current configuration
validate-config:
	@echo "Validating current configuration..."
	@python3 verif/python/validate_config.py \
		--bandwidth $(BANDWIDTH) \
		--word_width $(WORD_WIDTH) \
		--elem_width $(ELEM_WIDTH) \
		--memory_size $(MEMORY_SIZE) \
		--misaligned_accesses $(MISALIGNED_ACCESSES) \
		--datamover_mode $(DATAMOVER_MODE) \
		--transp_mode $(TRANSP_MODE) \
		--cim_mode $(CIM_MODE) \
		--cim_inner_dim $(CIM_INNER_DIM) \
		--cim_outer_dim $(CIM_OUTER_DIM) \
		--matrix_size_m $(MATRIX_SIZE_M) \
		--matrix_size_n $(MATRIX_SIZE_N)

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

stimuli: clean-stimuli validate-config
	python -m verif.python.generate_stimuli \
	--mem_size $(STIM_MEM_SIZE) \
	--read_base_addr $(STIM_READ_BASE_ADDR) \
	--write_base_addr $(STIM_WRITE_BASE_ADDR) \
	--bandwidth_bits $(BANDWIDTH) \
	--num_elem_word $(NUM_ELEM_WORD) \
	--elem_width $(ELEM_WIDTH) \
	--misaligned_accesses $(MISALIGNED_ACCESSES) \
	--datamover_mode $(DATAMOVER_MODE) \
	--transp_mode $(STIM_TRANSP_MODE) \
	--cim_mode $(CIM_MODE) \
	--cim_inner_dim $(CIM_INNER_DIM) \
	--cim_outer_dim $(CIM_OUTER_DIM) \
	--matrix_size_m $(MATRIX_SIZE_M) \
	--matrix_size_n $(MATRIX_SIZE_N) \
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

.PHONY: all help test-all-presets test-transpose-modes test-transpose-grid test-cim-grid validate-config clean-sim sim-script sim clean-stimuli stimuli bender check-bender
