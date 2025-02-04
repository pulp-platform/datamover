# Copyright 2023 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

SHELL = /usr/bin/env bash
ROOT_DIR := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

INSTALL_PREFIX        ?= install
INSTALL_DIR           = ${ROOT_DIR}/${INSTALL_PREFIX}
BENDER_INSTALL_DIR    = ${INSTALL_DIR}/bender

VENV_BIN=venv/bin/

BENDER_VERSION = 0.28.1
SIM_PATH   ?= modelsim/build
SYNTH_PATH  = synopsys

BENDER_TARGETS = -t rtl -t test

target ?= sim_tb_datamover_top

VLOG_FLAGS += -svinputport=compat
VLOG_FLAGS += -timescale 1ns/1ps

STIMULI_DIR ?= ${ROOT_DIR}/verif/python/generated

STIMULI_FILE_PATH ?= ${STIMULI_DIR}/initial_memory.txt
GOLDEN_FILE_PATH ?= ${STIMULI_DIR}/updated_memory.txt
TESTBENCH_DEFINES  ?= -DSTIMULI_PATH="\"${STIMULI_FILE_PATH}\""
TESTBENCH_DEFINES  += -DGOLDEN_PATH="\"${GOLDEN_FILE_PATH}\""

STIM_READ_BASE_ADDR ?= 0
STIM_READ_D0_LENGTH ?= 4
STIM_READ_D0_STRIDE ?= 4
STIM_READ_D1_LENGTH ?= 4
STIM_READ_D1_STRIDE ?= 16
STIM_READ_TOT_LENGTH ?= 16

STIM_WRITE_BASE_ADDR ?= 128
STIM_WRITE_D0_LENGTH ?= 4
STIM_WRITE_D0_STRIDE ?= 16
STIM_WRITE_D1_LENGTH ?= 4
STIM_WRITE_D1_STRIDE ?= 64
STIM_WRITE_TOT_LENGTH ?= 16
STIM_MEM_SIZE ?= 65536

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
TESTBENCH_DEFINES += -DSTIM_WRITE_TOT_LENGTH=${STIM_WRITE_TOT_LENGTH}

# .PHONY: clean-sim sim-script sim synopsys-script
all: testvector sim

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

sim: stimuli sim-script
	cd modelsim && \
	$(MAKE) $(target) buildpath=$(ROOT_DIR)/$(SIM_PATH)

stimuli: 
	python -m verif.python.generate_stimuli \
	--mem_size $(STIM_MEM_SIZE) \
	--read_base_addr $(STIM_READ_BASE_ADDR) \
	--read_d0_stride $(STIM_READ_D0_STRIDE) \
	--read_d0_length $(STIM_READ_D0_LENGTH) \
	--read_d1_stride $(STIM_READ_D1_STRIDE) \
	--read_d1_length $(STIM_READ_D1_LENGTH) \
	--write_base_addr $(STIM_WRITE_BASE_ADDR) \
	--write_d0_stride $(STIM_WRITE_D0_STRIDE) \
	--write_d0_length $(STIM_WRITE_D0_LENGTH) \
	--write_d1_stride $(STIM_WRITE_D1_STRIDE) \
	--write_d1_length $(STIM_WRITE_D1_LENGTH) \
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