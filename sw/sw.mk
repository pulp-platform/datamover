# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Author: Lionnus Kesting <lkesting@iis.ee.ethz.ch>
#
# SW build rules for datamover HWPE RISC-V testbench.

RISCV_PREFIX  ?= riscv32-unknown-elf-
RISCV_CC      := $(RISCV_PREFIX)gcc
RISCV_LD      := $(RISCV_PREFIX)gcc
RISCV_OBJDUMP := $(RISCV_PREFIX)objdump
RISCV_OBJCOPY := $(RISCV_PREFIX)objcopy

CC_OPTS  = -march=rv32imc -D__riscv__ -O2 -g
CC_OPTS += -Wextra -Wall -Wno-unused-parameter -Wno-unused-variable -Wno-unused-function
CC_OPTS += -Wno-incompatible-pointer-types -Wno-implicit-fallthrough
CC_OPTS += -fdata-sections -ffunction-sections -MMD -MP

# Override hw config params
CC_OPTS += -DDATAMOVER_BANDWIDTH=$(BANDWIDTH)
CC_OPTS += -DDATAMOVER_WORD_WIDTH=$(WORD_WIDTH)
CC_OPTS += -DDATAMOVER_ELEM_WIDTH=$(ELEM_WIDTH)
CC_OPTS += -DDATAMOVER_MISALIGNED_ACCESSES=$(MISALIGNED_ACCESSES)

# SystemRDL-generated register interface header (datamover_regif.h)
REGIF_DIR ?= $(ROOT_DIR)/rtl/ctrl/regif
CC_OPTS   += -I$(REGIF_DIR)

LD_OPTS = -march=rv32imc -D__riscv__ -MMD -MP -nostartfiles -Wl,--gc-sections -lgcc

# Build artifacts
SW_BUILD_DIR  := $(MODELSIM_BUILD_DIR)
SW_HEADER     := $(SW_BUILD_DIR)/datamover_workload.h
SW_CRT        := $(SW_BUILD_DIR)/crt0.o
SW_HAL_OBJ    := $(SW_BUILD_DIR)/hal_datamover.o
SW_OBJ        := $(SW_BUILD_DIR)/tb_datamover.o
SW_BIN        := $(SW_BUILD_DIR)/main
SW_STIM_INSTR := $(SW_BUILD_DIR)/stim_instr.txt
SW_STIM_DATA  := $(SW_BUILD_DIR)/stim_data.txt

TEST_JSON ?=
GEN_HEADERS_ARGS := --json $(TEST_JSON) --test_name $(TEST_NAME)

$(SW_BUILD_DIR):
	mkdir -p $(SW_BUILD_DIR)

# Step 1: golden model + workload header generation
$(SW_HEADER): utils/gen_workload_header.py verif/python/datamover_golden_model.py | $(SW_BUILD_DIR)
	python -m utils.gen_workload_header \
	    $(GEN_HEADERS_ARGS) \
	    $(if $(filter 1,$(NO_DEBUG)),--no-debug,) \
	    --output_dir $(SW_BUILD_DIR)

# Step 2: compile startup, HAL, and test driver
$(SW_CRT): sw/crt0.S | $(SW_BUILD_DIR)
	$(RISCV_CC) $(CC_OPTS) -c sw/crt0.S -o $(SW_CRT)

$(SW_HAL_OBJ): sw/hal_datamover.c sw/hal_datamover.h $(REGIF_DIR)/datamover_regif.h | $(SW_BUILD_DIR)
	$(RISCV_CC) $(CC_OPTS) -Isw -c sw/hal_datamover.c -o $(SW_HAL_OBJ)

$(SW_OBJ): sw/tb_datamover.c sw/hal_datamover.h sw/tinyprintf.h $(SW_HEADER) | $(SW_BUILD_DIR)
	$(RISCV_CC) $(CC_OPTS) -I$(SW_BUILD_DIR) -Isw -c sw/tb_datamover.c -o $(SW_OBJ)

# Step 3: link
$(SW_BIN): $(SW_CRT) $(SW_HAL_OBJ) $(SW_OBJ) sw/link.ld
	$(RISCV_LD) $(LD_OPTS) -o $(SW_BIN) $(SW_CRT) $(SW_HAL_OBJ) $(SW_OBJ) -Tsw/link.ld
	$(RISCV_OBJDUMP) -D $(SW_BIN) > $(SW_BIN).dump

# Step 4: convert ELF to memory hex files for $readmemh
$(SW_STIM_INSTR) $(SW_STIM_DATA): $(SW_BIN)
	$(RISCV_OBJCOPY) --srec-len 1 --output-target=srec $(SW_BIN) $(SW_BIN).s19
	sw/parse_s19.pl $(SW_BIN).s19 > $(SW_BIN).txt
	python sw/s19tomem.py $(SW_BIN).txt $(SW_STIM_INSTR) $(SW_STIM_DATA)

sw-gen: $(SW_HEADER)
sw-compile: $(SW_STIM_INSTR) $(SW_STIM_DATA)

sw-clean:
	rm -f $(SW_OBJ) $(SW_HAL_OBJ) $(SW_CRT) $(SW_BIN) $(SW_BIN).s19 $(SW_BIN).txt $(SW_BIN).dump
	rm -f $(SW_STIM_INSTR) $(SW_STIM_DATA) $(SW_HEADER)
