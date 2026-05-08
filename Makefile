# Copyright 2023 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Standalone testing setup OUTDATED!
# ToDo: Implement SW-based testing with a CPU core

include config.mk

SHELL = /usr/bin/env bash
ROOT_DIR := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

VENV_BIN=venv/bin/

BENDER_VERSION = bender-0.31.0
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
TESTBENCH_DEFINES  ?= -DSTIMULI_PATH=\\\"$(abspath ${STIMULI_FILE_PATH})\\\"
TESTBENCH_DEFINES  += -DGOLDEN_PATH=\\\"$(abspath ${GOLDEN_FILE_PATH})\\\"

# Propagate paramters to testbench
TESTBENCH_DEFINES += -DSTIM_READ_BASE_ADDR=${STIM_READ_BASE_ADDR}
TESTBENCH_DEFINES += -DSTIM_READ_D0_STRIDE=${STIM_READ_D0_STRIDE}
TESTBENCH_DEFINES += -DSTIM_READ_D0_LENGTH=${STIM_READ_D0_LENGTH}
TESTBENCH_DEFINES += -DSTIM_READ_D1_STRIDE=${STIM_READ_D1_STRIDE}
TESTBENCH_DEFINES += -DSTIM_READ_D1_LENGTH=${STIM_READ_D1_LENGTH}
TESTBENCH_DEFINES += -DSTIM_READ_D2_STRIDE=${STIM_READ_D2_STRIDE}
TESTBENCH_DEFINES += -DSTIM_READ_D2_LENGTH=${STIM_READ_D2_LENGTH}
TESTBENCH_DEFINES += -DSTIM_READ_D3_STRIDE=${STIM_READ_D3_STRIDE}
TESTBENCH_DEFINES += -DSTIM_READ_D3_LENGTH=${STIM_READ_D3_LENGTH}
TESTBENCH_DEFINES += -DSTIM_READ_D4_STRIDE=${STIM_READ_D4_STRIDE}
TESTBENCH_DEFINES += -DSTIM_READ_TOT_LENGTH=${STIM_READ_TOT_LENGTH}
TESTBENCH_DEFINES += -DSTIM_READ_DIM_ENABLE=${STIM_READ_DIM_ENABLE}

TESTBENCH_DEFINES += -DSTIM_WRITE_BASE_ADDR=${STIM_WRITE_BASE_ADDR}
TESTBENCH_DEFINES += -DSTIM_WRITE_D0_STRIDE=${STIM_WRITE_D0_STRIDE}
TESTBENCH_DEFINES += -DSTIM_WRITE_D0_LENGTH=${STIM_WRITE_D0_LENGTH}
TESTBENCH_DEFINES += -DSTIM_WRITE_D1_STRIDE=${STIM_WRITE_D1_STRIDE}
TESTBENCH_DEFINES += -DSTIM_WRITE_D1_LENGTH=${STIM_WRITE_D1_LENGTH}
TESTBENCH_DEFINES += -DSTIM_WRITE_D2_STRIDE=${STIM_WRITE_D2_STRIDE}
TESTBENCH_DEFINES += -DSTIM_WRITE_D2_LENGTH=${STIM_WRITE_D2_LENGTH}
TESTBENCH_DEFINES += -DSTIM_WRITE_D3_STRIDE=${STIM_WRITE_D3_STRIDE}
TESTBENCH_DEFINES += -DSTIM_WRITE_D3_LENGTH=${STIM_WRITE_D3_LENGTH}
TESTBENCH_DEFINES += -DSTIM_WRITE_D4_STRIDE=${STIM_WRITE_D4_STRIDE}
TESTBENCH_DEFINES += -DSTIM_WRITE_TOT_LENGTH=${STIM_WRITE_TOT_LENGTH}
TESTBENCH_DEFINES += -DSTIM_WRITE_DIM_ENABLE=${STIM_WRITE_DIM_ENABLE}

TESTBENCH_DEFINES += -DSTIM_MEM_SIZE=${STIM_MEM_SIZE}

TESTBENCH_DEFINES += -DSTIM_TRANSP_MODE=${STIM_TRANSP_MODE}
# TESTBENCH_DEFINES += -DSTIM_TRANSP_LEN=${STIM_TRANSP_LEN}

TESTBENCH_DEFINES += -DSTIM_TENSOR_SIZE_M=${STIM_TENSOR_SIZE_M}
TESTBENCH_DEFINES += -DSTIM_TENSOR_SIZE_N=${STIM_TENSOR_SIZE_N}

TESTBENCH_DEFINES += -DSTIM_NUM_CHANNELS=${STIM_NUM_CHANNELS}
TESTBENCH_DEFINES += -DSTIM_TOTAL_ELEMENTS=${STIM_TOTAL_ELEMENTS}

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
	@echo "  small-tensor    : 4x4 tensor (transpose)"
	@echo "  medium-tensor   : 64x64 tensor (transpose)"
	@echo "  large-tensor    : 448x448 tensor (transpose)"
	@echo "  transpose-test  : 32x32 tensor (transpose)"
	@echo "  rect-wide       : 64x256 wide rectangular tensor (transpose)"
	@echo "  rect-tall       : 256x64 tall rectangular tensor (transpose)"
	@echo "  rect-narrow     : 16x128 narrow rectangular tensor (transpose)"
	@echo "  rect-elongated  : 128x32 elongated rectangular tensor (transpose)"
	@echo "  copy-small      : 4x4 tensor (copy mode)"
	@echo "  copy-medium     : 64x64 tensor (copy mode)"
	@echo "  cim-small       : 32x128 tensor (CIM mode)"
	@echo "  cim-medium      : 64x256 tensor (CIM mode)"
	@echo "  cim-large       : 128x256 tensor (CIM mode)"
	@echo "  custom          : User-defined (config.mk default)"
	@echo ""
	@echo "Usage examples:"
	@echo "  make sim CONFIG_PRESET=small-tensor"
	@echo "  make sim CONFIG_PRESET=transpose-test TRANSP_MODE=2"
	@echo "  make sim TENSOR_SIZE_M=64 TENSOR_SIZE_N=32"
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
	for preset in small-tensor medium-tensor large-tensor transpose-test rect-wide rect-tall rect-narrow rect-elongated copy-small copy-medium cim-small cim-medium cim-large; do \
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
				if $(MAKE) sim CONFIG_PRESET=medium-tensor BANDWIDTH=$$bandwidth DATAMOVER_MODE=1 TRANSP_MODE=$$transp_mode WORD_WIDTH=$$word_width; then \
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
				if $(MAKE) sim CONFIG_PRESET=medium-tensor BANDWIDTH=$$bandwidth MISALIGNED_ACCESSES=1 DATAMOVER_MODE=1 TRANSP_MODE=$$transp_mode WORD_WIDTH=$$word_width; then \
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
				if $(MAKE) sim CONFIG_PRESET=medium-tensor BANDWIDTH=$$bandwidth MISALIGNED_ACCESSES=1 DATAMOVER_MODE=1 TRANSP_MODE=$$transp_mode WORD_WIDTH=$$word_width; then \
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
			for row_tile_size in 32 64; do \
				total_tests=$$((total_tests + 1)); \
				echo "=== Testing BANDWIDTH=$$bandwidth WORD_WIDTH=$$word_width ROW_TILE_SIZE=$$row_tile_size ==="; \
				if $(MAKE) sim CONFIG_PRESET=cim-large DATAMOVER_MODE=2 CIM_MODE=0 BANDWIDTH=$$bandwidth WORD_WIDTH=$$word_width ROW_TILE_SIZE=$$row_tile_size; then \
					echo "✓ BANDWIDTH=$$bandwidth WORD_WIDTH=$$word_width ROW_TILE_SIZE=$$row_tile_size: PASSED"; \
					passed_tests=$$((passed_tests + 1)); \
				else \
					echo "✗ BANDWIDTH=$$bandwidth WORD_WIDTH=$$word_width ROW_TILE_SIZE=$$row_tile_size: FAILED"; \
					failed_tests="$$failed_tests BANDWIDTH=$$bandwidth/WORD_WIDTH=$$word_width/ROW_TILE_SIZE=$$row_tile_size"; \
				fi; \
			done; \
		done; \
	done; \
	for bandwidth in 512; do \
		for word_width in 32 64; do \
			for row_tile_size in 64; do \
				total_tests=$$((total_tests + 1)); \
				echo "=== Testing BANDWIDTH=$$bandwidth WORD_WIDTH=$$word_width ROW_TILE_SIZE=$$row_tile_size ==="; \
				if $(MAKE) sim CONFIG_PRESET=cim-large DATAMOVER_MODE=2 CIM_MODE=0 BANDWIDTH=$$bandwidth WORD_WIDTH=$$word_width ROW_TILE_SIZE=$$row_tile_size; then \
					echo "✓ BANDWIDTH=$$bandwidth WORD_WIDTH=$$word_width ROW_TILE_SIZE=$$row_tile_size: PASSED"; \
					passed_tests=$$((passed_tests + 1)); \
				else \
					echo "✗ BANDWIDTH=$$bandwidth WORD_WIDTH=$$word_width ROW_TILE_SIZE=$$row_tile_size: FAILED"; \
					failed_tests="$$failed_tests BANDWIDTH=$$bandwidth/WORD_WIDTH=$$word_width/ROW_TILE_SIZE=$$row_tile_size"; \
				fi; \
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

# Validate current configuration
validate-config:
	@echo "Validating current configuration..."
	@python3 verif/python/validate_config.py \
		--bandwidth $(BANDWIDTH) \
		--word_width $(WORD_WIDTH) \
		--elem_width $(ELEM_WIDTH) \
		--memory_size $(MEMORY_SIZE) \
		--datamover_mode $(DATAMOVER_MODE) \
		--transp_mode $(TRANSP_MODE) \
		--cim_mode $(CIM_MODE) \
		--row_tile_size $(ROW_TILE_SIZE) \
		--size_m $(TENSOR_SIZE_M) \
		--size_n $(TENSOR_SIZE_N) \
		--num_channels $(NUM_CHANNELS)

clean-sim:
	rm -rf $(SIM_PATH)/work
	rm -rf $(SIM_PATH)/compile.tcl
	rm -rf $(SIM_PATH)/wlft*
	rm -rf $(SIM_PATH)/transcript
	rm -rf $(SIM_PATH)/modelsim.ini
	rm -rf $(SIM_PATH)/vsim.wlf

sim-script: clean-sim
	mkdir -p $(SIM_PATH)
	$(BENDER_VERSION) script vsim $(BENDER_TARGETS) $(TESTBENCH_DEFINES) --vlog-arg="$(VLOG_FLAGS)" >> $(SIM_PATH)/compile.tcl

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
	--datamover_mode $(DATAMOVER_MODE) \
	--transp_mode $(STIM_TRANSP_MODE) \
	--cim_mode $(CIM_MODE) \
	--row_tile_size $(ROW_TILE_SIZE) \
	--size_m $(TENSOR_SIZE_M) \
	--size_n $(TENSOR_SIZE_N) \
	--num_channels $(NUM_CHANNELS) \
	--output_dir "$(STIMULI_DIR)" \
	$(if $(filter 1,$(NO_DEBUG)),--no-debug,)

.PHONY: all validate-config clean-sim sim-script sim clean-stimuli stimuli run-test run-all-tests clean

run-test:
ifndef TEST_JSON
	$(error TEST_JSON is required. Usage: make run-test TEST_JSON=utils/datamover_transpose_tests.json)
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

clean:
	rm -rf modelsim/build_*
	rm -rf modelsim/vsim
	rm -rf reports/
	rm -rf verif/python/generated
	rm -rf utils/__pycache__ verif/python/__pycache__
