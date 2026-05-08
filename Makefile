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

NO_DEBUG ?= 0
export NO_DEBUG

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
	@python -u -m utils.run_test $(TEST_JSON) \
		$(if $(TEST),--test=$(TEST),) \
		$(if $(PARALLEL),--parallel=$(PARALLEL),) \
		$(if $(TIMEOUT),--timeout=$(TIMEOUT),) \
		$(if $(VSIM_FLAGS),--vsim-flags="$(VSIM_FLAGS)",); \
	rc=$$?; \
	if [ $$rc -eq 0 ]; then \
		printf '\033[1;32m==== ALL TESTS PASSED ====\033[0m\n'; \
	else \
		printf '\033[1;31m==== SOME TESTS FAILED ====\033[0m\n'; \
	fi; \
	exit $$rc

TEST_JSON_GLOB ?= utils/datamover_*_tests.json
ALL_TESTS_VSIM_FLAGS ?= -c
run-all-tests:
	@python -u -m utils.run_test --discover-glob="$(TEST_JSON_GLOB)" \
		$(if $(PARALLEL),--parallel=$(PARALLEL),) \
		$(if $(TIMEOUT),--timeout=$(TIMEOUT),) \
		--vsim-flags="$(ALL_TESTS_VSIM_FLAGS)"; \
	rc=$$?; \
	if [ $$rc -eq 0 ]; then \
		printf '\033[1;32m==== ALL TESTS PASSED ====\033[0m\n'; \
	else \
		printf '\033[1;31m==== SOME TESTS FAILED ====\033[0m\n'; \
	fi; \
	exit $$rc

clean:
	rm -rf modelsim/build_*
	rm -rf modelsim/vsim
	rm -rf reports/
	rm -rf utils/__pycache__ verif/python/__pycache__
