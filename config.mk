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
MEMORY_SIZE = 512  # in words

TRANSP_MODE = 4  # 0 = none, 1 = 1 elem, 2 = 2 elem, 4 = 4 elem

# Derived constants from basic parameters
# BANDWIDTH_WORDS := $(shell echo $$(($(BANDWIDTH) / $(WORD_WIDTH))))  # Number of words per bandwidth
BANDWIDTH_ELEMS := $(shell echo $$(($(BANDWIDTH) / $(ELEM_WIDTH))))  # Number of elements per bandwidth
NUM_ELEM_WORD := $(shell echo $$(($(WORD_WIDTH) / $(ELEM_WIDTH))))  # Number of elements per word

#########################
# Stimuli configuration #
#########################

# Base matrix dimensions (in elements)
MATRIX_SIZE_D0 ?= 16  # Matrix width in elements
MATRIX_SIZE_D1 ?= 8   # Matrix height in elements

# Derived stride calculations
# ELEM_STRIDE_D0 := $(ELEM_WIDTH)                                    # Element-to-element stride in bits
# ROW_STRIDE_BYTES := $(shell echo $$(($(MATRIX_SIZE_D0) * $(ELEM_WIDTH) / 8)))  # Bytes per row

# ADDR and STRIDE are in bytes, LENGTH is in number of memory accesses (4*32b)
# N (bandwidth) consecutive words are read/written in one transaction
STIM_READ_BASE_ADDR ?= 0							# Element-addressed
STIM_READ_D0_LENGTH ?= $(shell echo $$(($(MATRIX_SIZE_D0) / $(BANDWIDTH_ELEMS))))  # Nof accesses with bandwidth BW per D0-transfer ("row")
STIM_READ_D0_STRIDE ?= $(BANDWIDTH_ELEMS)			# Elements
STIM_READ_D1_LENGTH ?= $(MATRIX_SIZE_D1)			# Number of full D0-transfers ("rows")
STIM_READ_D1_STRIDE ?= $(MATRIX_SIZE_D0) 			# Elements -> manually compute "next row" stride
STIM_READ_TOT_LENGTH ?= $(shell echo $$(($(STIM_READ_D0_LENGTH) * $(STIM_READ_D1_LENGTH))))  # Total memory accesses

STIM_WRITE_BASE_ADDR ?= 128							# Element-addressed
STIM_WRITE_D0_LENGTH ?= $(STIM_READ_D1_LENGTH)		# Transpose: read height becomes write width
STIM_WRITE_D0_STRIDE ?= $(BANDWIDTH_ELEMS)  		# Bytes per transposed row
STIM_WRITE_D1_LENGTH ?= $(STIM_READ_D0_LENGTH)      # Transpose: read width becomes write height
STIM_WRITE_D1_STRIDE ?= $(MATRIX_SIZE_D0)			# Elements
STIM_WRITE_TOT_LENGTH ?= $(STIM_READ_TOT_LENGTH)	# Same total length as read

STIM_MEM_SIZE ?= $(MEMORY_SIZE) #65536

STIM_TRANSP_MODE ?= $(TRANSP_MODE)       			# 3'b000 = none, 3'b001 = 1 elem, 3'b010 = 2 elem, 3'b100 = 4 elem
STIM_TRANSP_LEN  ?= 0  								# If 0: BANDWIDTH_ALIGNED / ELEM_WIDTH

# Debug: Print computed values (uncomment to see values during make)
$(info WORD_WIDTH=$(WORD_WIDTH))
$(info BANDWIDTH_ELEMS=$(BANDWIDTH_ELEMS))
$(info ROW_STRIDE_BYTES=$(ROW_STRIDE_BYTES))
$(info STIM_READ_D0_LENGTH=$(STIM_READ_D0_LENGTH))
$(info STIM_WRITE_D0_STRIDE=$(STIM_WRITE_D0_STRIDE))
