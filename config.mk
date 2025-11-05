# Copyright 2023 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# This file contains the configuration parameter for
# the standalone simulation of the datamover HWPE

#######################
# Datamover hw config #
#######################

BANDWIDTH = 128   # in bits
WORD_WIDTH = 32  # in bits
ELEM_WIDTH = 8   # in bits
MEMORY_SIZE = 8192  # in words

TRANSP_MODE = 4 # 0 = none, 1 = 1 elem, 2 = 2 elem, 4 = 4 elem

# Derived constants from basic parameters
# BANDWIDTH_WORDS := $(shell echo $$(($(BANDWIDTH) / $(WORD_WIDTH))))  # Number of words per bandwidth
BANDWIDTH_ELEMS := $(shell echo $$(($(BANDWIDTH) / $(ELEM_WIDTH))))  # Number of elements per bandwidth
NUM_ELEM_WORD := $(shell echo $$(($(WORD_WIDTH) / $(ELEM_WIDTH))))  # Number of elements per word

#########################
# Stimuli configuration #
#########################

# Base matrix dimensions (in elements)
MATRIX_SIZE_M ?= 128   	# Matrix height in elements
MATRIX_SIZE_N ?= 64 	# Matrix width in elements

# Derived stride calculations
# ELEM_STRIDE_D0 := $(ELEM_WIDTH)                                    # Element-to-element stride in bits
# ROW_STRIDE_BYTES := $(shell echo $$(($(MATRIX_SIZE_N) * $(ELEM_WIDTH) / 8)))  # Bytes per row

# ADDR and STRIDE are in bytes, LENGTH is in number of memory accesses (4*32b)
# N (bandwidth) consecutive words are read/written in one transaction
STIM_READ_BASE_ADDR ?= 0																# Element-addressed
STIM_READ_D0_LENGTH ?= $(MATRIX_SIZE_M) 												# [Nof accesses with bandwidth BW per D0-transfer ("row")]
STIM_READ_D0_STRIDE ?= $(MATRIX_SIZE_N) 												# [Elements]
STIM_READ_D1_LENGTH ?= $(shell echo $$(($(MATRIX_SIZE_N) / $(BANDWIDTH_ELEMS)))) 		# [Number of full D0-transfers ("rows")]
STIM_READ_D1_STRIDE ?= $(BANDWIDTH_ELEMS) 												# [Elements] -> manually compute "next row" stride
STIM_READ_TOT_LENGTH ?= $(shell echo $$(($(STIM_READ_D0_LENGTH) * $(STIM_READ_D1_LENGTH))))  # [Total memory accesses]

STIM_WRITE_BASE_ADDR ?= $(shell echo $$(($(MATRIX_SIZE_M) * $(MATRIX_SIZE_N))))			# Element-addressed
STIM_WRITE_D0_LENGTH ?= $(shell echo $$(($(BANDWIDTH_ELEMS) / $(TRANSP_MODE))))			# Transpose tile width corresponds to bandwidth
STIM_WRITE_D0_STRIDE ?= $(shell echo $$(($(MATRIX_SIZE_M) * $(TRANSP_MODE)))) 			# Transpose: Input matrix height corresponds to output matrix width
STIM_WRITE_D1_LENGTH ?= $(shell echo $$(($(STIM_WRITE_D0_STRIDE) / $(BANDWIDTH_ELEMS))))# Transpose: Input matrix height corresponds to output matrix width
STIM_WRITE_D1_STRIDE ?= $(BANDWIDTH_ELEMS)												# Transpose tile height corresponds to bandwidth
STIM_WRITE_D2_STRIDE ?= $(shell echo $$(($(MATRIX_SIZE_M) * $(BANDWIDTH_ELEMS))))		# D2 length is controlled by total length
STIM_WRITE_TOT_LENGTH ?= $(STIM_READ_TOT_LENGTH)										# Same total length as read

STIM_MEM_SIZE ?= $(MEMORY_SIZE)  # [Words]

STIM_TRANSP_MODE ?= $(TRANSP_MODE)       			# 3'b000 = none, 3'b001 = 1 elem, 3'b010 = 2 elem, 3'b100 = 4 elem
STIM_TRANSP_LEN  ?= 0  								# If 0: BANDWIDTH_ALIGNED / ELEM_WIDTH

# Debug: Print computed values (uncomment to see values during make)
$(info BANDWIDTH_ELEMS: $(BANDWIDTH_ELEMS))
$(info WORD_WIDTH: $(WORD_WIDTH))
$(info ELEM_WIDTH: $(ELEM_WIDTH))

$(info BANDWIDTH_ELEMS: $(BANDWIDTH_ELEMS))
$(info NUM_ELEM_WORD: $(NUM_ELEM_WORD))

$(info MATRIX_SIZE_N: $(MATRIX_SIZE_N))
$(info MATRIX_SIZE_M: $(MATRIX_SIZE_M))

$(info STIM_READ_BASE_ADDR: $(STIM_READ_BASE_ADDR))
$(info STIM_READ_D0_LENGTH: $(STIM_READ_D0_LENGTH))
$(info STIM_WRITE_D0_STRIDE: $(STIM_WRITE_D0_STRIDE))
$(info STIM_READ_D1_LENGTH: $(STIM_READ_D1_LENGTH))
$(info STIM_READ_D1_STRIDE: $(STIM_READ_D1_STRIDE))
$(info STIM_READ_TOT_LENGTH: $(STIM_READ_TOT_LENGTH))

$(info STIM_WRITE_BASE_ADDR: $(STIM_WRITE_BASE_ADDR))
$(info STIM_WRITE_D0_LENGTH: $(STIM_WRITE_D0_LENGTH))
$(info STIM_WRITE_D0_STRIDE: $(STIM_WRITE_D0_STRIDE))
$(info STIM_WRITE_D1_LENGTH: $(STIM_WRITE_D1_LENGTH))
$(info STIM_WRITE_D1_STRIDE: $(STIM_WRITE_D1_STRIDE))
$(info STIM_WRITE_D2_STRIDE: $(STIM_WRITE_D2_STRIDE))
$(info STIM_WRITE_TOT_LENGTH: $(STIM_WRITE_TOT_LENGTH))

$(info STIM_TRANSP_MODE: $(STIM_TRANSP_MODE))
