# Copyright 2023 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# This file contains the configuration parameter for
# the standalone simulation of the datamover HWPE

# Include configuration presets (optional)
-include config_presets.mk

#######################
# Datamover HW Config #
#######################

# Hardware configuration (can be overridden by presets or command line)
BANDWIDTH ?= 64   		# in bits, multiple of WORD_WIDTH
WORD_WIDTH ?= 32  		# in bits, multiple of ELEM_WIDTH
ELEM_WIDTH ?= 8   		# in bits
MEMORY_SIZE ?= 512  	# in words
MISALIGNED_ACCESSES ?= 1

DATAMOVER_MODE ?= 0     # 0 = copy, 1 = transpose, 2 = CIM data layout conversion
TRANSP_MODE ?= 1		    # 1 = 1 elem, 2 = 2 elem, 4 = 4 elem, other values: not accepted
CIM_MODE ?= 0        	  # Data layout conversion mode: 0: row-major -> A-Layout, 1: row-major -> B-Layout
CIM_INNER_DIM ?= 32    	# Inner dimension of the CIM accelerator (in elements): 64 for 64x8 CIM macro
CIM_OUTER_DIM ?= 32    	# Outer dimension of the CIM accelerator (in elements): 8x #CIM macros

# Input matrix dimensions (in elements)
MATRIX_SIZE_M ?= 8   	# Matrix height in elements
MATRIX_SIZE_N ?= 8 		# Matrix width in elements

WRITE_BASE_ADDR = $(shell echo $$(($(MATRIX_SIZE_M) * $(MATRIX_SIZE_N))))			# Element-addressed

# Derived constants from basic parameters
BANDWIDTH_REDUCTION := $(shell echo $$(($(MISALIGNED_ACCESSES) * $(WORD_WIDTH))))	# in bits
BANDWIDTH_ALIGNED := $(shell echo $$(($(BANDWIDTH) - $(BANDWIDTH_REDUCTION))))  	# in bytes
BANDWIDTH_ELEMS := $(shell echo $$(($(BANDWIDTH_ALIGNED) / $(ELEM_WIDTH))))  	# Number of elements per bandwidth
NUM_ELEM_WORD := $(shell echo $$(($(WORD_WIDTH) / $(ELEM_WIDTH))))  	# Number of elements per word
MATRIX_SIZE_TOT := $(shell echo $$(($(MATRIX_SIZE_M) * $(MATRIX_SIZE_N)))) # Total number of elements in the matrix

# ADDR and STRIDE are in bytes, LENGTH is in number of memory accesses (4*32b)
# N (bandwidth) consecutive words are read/written in one transaction

ifeq "$(strip $(DATAMOVER_MODE))" "0"	# Copy mode
$(info Copy mode enabled)
STIM_READ_BASE_ADDR ?= 0																# Element-addressed
STIM_READ_D0_LENGTH ?= $(shell echo $$(($(MATRIX_SIZE_TOT) / $(BANDWIDTH_ELEMS)))) # [Nof accesses with bandwidth BW per D0-transfer ("row")] ToDo(cdurrer): not working for misaligned matrices
STIM_READ_D0_STRIDE ?= $(BANDWIDTH_ELEMS) 							# [Elements]
STIM_READ_D1_LENGTH ?= 0 		                            # [Number of full D0-transfers ("rows")]
STIM_READ_D1_STRIDE ?= 0											          # [Elements] -> manually compute "next row" stride
STIM_READ_D2_LENGTH ?= 0																# Not used for copy mode
STIM_READ_D2_STRIDE ?= 0																# Not used for copy mode
STIM_READ_TOT_LENGTH ?= $(MATRIX_SIZE_TOT)              # [Total memory accesses]

STIM_MEM_SIZE ?= $(MEMORY_SIZE)  												# [Words]
STIM_TRANSP_MODE ?= 0
STIM_TRANSP_LEN  ?= 0

STIM_WRITE_BASE_ADDR ?= $(WRITE_BASE_ADDR)
STIM_WRITE_D0_LENGTH ?= $(STIM_READ_D0_LENGTH)
STIM_WRITE_D0_STRIDE ?= $(STIM_READ_D0_STRIDE)
STIM_WRITE_D1_LENGTH ?= $(STIM_READ_D1_LENGTH)
STIM_WRITE_D1_STRIDE ?= $(STIM_READ_D1_STRIDE)
STIM_WRITE_D2_STRIDE ?= 0
STIM_WRITE_TOT_LENGTH ?= $(STIM_READ_TOT_LENGTH)

else ifeq "$(strip $(DATAMOVER_MODE))" "1"	# Transpose mode
$(info Transpose mode $(TRANSP_MODE) enabled)
ifneq ($(filter 1 2 4,$(strip $(TRANSP_MODE))), $(strip $(TRANSP_MODE)))
  $(error Invalid TRANSP_MODE $(TRANSP_MODE): must be 1, 2, or 4)
endif

STIM_READ_BASE_ADDR ?= 0																# Element-addressed
STIM_READ_D0_LENGTH ?= $(MATRIX_SIZE_M) 												# [Nof accesses with bandwidth BW per D0-transfer ("row")]
STIM_READ_D0_STRIDE ?= $(MATRIX_SIZE_N) 												# [Elements]
STIM_READ_D1_LENGTH ?= $(shell echo $$(($(MATRIX_SIZE_N) / $(BANDWIDTH_ELEMS)))) 		# [Number of full D0-transfers ("rows")]
STIM_READ_D1_STRIDE ?= $(BANDWIDTH_ELEMS) 												# [Elements] -> manually compute "next row" stride
STIM_READ_D2_LENGTH ?= 0																# Not used for read
STIM_READ_D2_STRIDE ?= 0																# Not used for read
STIM_READ_TOT_LENGTH ?= $(shell echo $$(($(STIM_READ_D0_LENGTH) * $(STIM_READ_D1_LENGTH))))  # [Total memory accesses]

STIM_MEM_SIZE ?= $(MEMORY_SIZE)  														# [Words]
STIM_TRANSP_MODE ?= $(TRANSP_MODE)       												# 1 = 1 elem, 2 = 2 elem, 4 = 4 elem, other values: not accepted
STIM_TRANSP_LEN  ?= 0  																	# If 0: BANDWIDTH_ALIGNED / ELEM_WIDTH

STIM_WRITE_BASE_ADDR ?= $(WRITE_BASE_ADDR)												# Element-addressed
STIM_WRITE_D0_LENGTH ?= $(shell echo $$(($(BANDWIDTH_ELEMS) / $(TRANSP_MODE))))			# Transpose tile width corresponds to bandwidth
STIM_WRITE_D0_STRIDE ?= $(shell echo $$(($(MATRIX_SIZE_M) * $(TRANSP_MODE)))) 			# Transpose: Input matrix height corresponds to output matrix width
STIM_WRITE_D1_LENGTH ?= $(shell echo $$(($(STIM_WRITE_D0_STRIDE) / $(BANDWIDTH_ELEMS))))# Transpose: Input matrix height corresponds to output matrix width
STIM_WRITE_D1_STRIDE ?= $(BANDWIDTH_ELEMS)												# Transpose tile height corresponds to bandwidth
STIM_WRITE_D2_STRIDE ?= $(shell echo $$(($(MATRIX_SIZE_M) * $(BANDWIDTH_ELEMS))))		# D2 length is controlled by total length
STIM_WRITE_TOT_LENGTH ?= $(STIM_READ_TOT_LENGTH)										# Same total length as read

else ifeq "$(strip $(DATAMOVER_MODE))" "2"	# CIM data layout conversion mode
$(info CIM data layout conversion mode $(CIM_MODE) enabled)
ifneq ($(filter 0 1,$(strip $(CIM_MODE))), $(strip $(CIM_MODE)))
  $(error "Invalid CIM_MODE $(CIM_MODE): must be 0 or 1")
endif
STIM_READ_BASE_ADDR ?= 0																# Element-addressed
STIM_READ_D0_LENGTH ?= $(shell echo $$(($(CIM_INNER_DIM) / $(BANDWIDTH_ELEMS)))) 		# [Nof accesses with bandwidth BW per D0-transfer ("row")]
STIM_READ_D0_STRIDE ?= $(BANDWIDTH_ELEMS) 												# [Elements]
STIM_READ_D1_LENGTH ?= $(MATRIX_SIZE_M)
STIM_READ_D1_STRIDE ?= $(MATRIX_SIZE_N)
STIM_READ_D2_LENGTH ?= $(shell echo $$(($(MATRIX_SIZE_N) / $(CIM_INNER_DIM))))
STIM_READ_D2_STRIDE ?= $(CIM_INNER_DIM)
PARTIAL_MULT = $(shell echo $$(($(STIM_READ_D0_LENGTH) * $(STIM_READ_D1_LENGTH))))
STIM_READ_TOT_LENGTH ?= $(shell echo $$(($(PARTIAL_MULT) * $(STIM_READ_D2_LENGTH))))  	# [Total memory accesses]

STIM_MEM_SIZE ?= $(MEMORY_SIZE)  														# [Words]
STIM_TRANSP_MODE ?= 0
STIM_TRANSP_LEN  ?= 0

STIM_WRITE_BASE_ADDR ?= $(WRITE_BASE_ADDR)												# Element-addressed
STIM_WRITE_D0_LENGTH ?= $(shell echo $$(($(STIM_READ_D0_LENGTH) * $(MATRIX_SIZE_M))))
STIM_WRITE_D0_STRIDE ?= $(BANDWIDTH_ELEMS)
STIM_WRITE_D1_LENGTH ?= $(shell echo $$(($(MATRIX_SIZE_N) / $(CIM_INNER_DIM))))
STIM_WRITE_D1_STRIDE ?= $(shell echo $$(($(STIM_WRITE_D0_LENGTH) * $(BANDWIDTH_ELEMS))))
STIM_WRITE_D2_STRIDE ?= 0
STIM_WRITE_TOT_LENGTH ?= $(STIM_READ_TOT_LENGTH)										# Same total length as read

else
$(error "Invalid DATAMOVER_MODE $(DATAMOVER_MODE): must be 0 (copy), 1 (transpose), or 2 (CIM data layout conversion)")
endif

# Debug: Print computed values (uncomment to see values during make)
$(info ========================================)
$(info Hardware Configuration:)
$(info   BANDWIDTH: $(BANDWIDTH) bits)
$(info   MISALIGNED_ACCESSES: $(MISALIGNED_ACCESSES))
$(info   BANDWIDTH_ALIGNED: $(BANDWIDTH_ALIGNED) bits)
$(info   WORD_WIDTH: $(WORD_WIDTH) bits)
$(info   ELEM_WIDTH: $(ELEM_WIDTH) bits)
$(info   BANDWIDTH_ELEMS: $(BANDWIDTH_ELEMS))
$(info   NUM_ELEM_WORD: $(NUM_ELEM_WORD))
$(info   DATAMOVER_MODE: $(DATAMOVER_MODE))
$(info   TRANSP_MODE: $(TRANSP_MODE))
$(info   CIM_MODE: $(CIM_MODE))
$(info   CIM_INNER_DIM: $(CIM_INNER_DIM) elements)
$(info   CIM_OUTER_DIM: $(CIM_OUTER_DIM) elements)
$(info )
$(info Matrix Configuration:)
$(info   MATRIX_SIZE: $(MATRIX_SIZE_M) x $(MATRIX_SIZE_N))
$(info   MEMORY_SIZE: $(MEMORY_SIZE) words)
$(info )
$(info Read Configuration:)
$(info   BASE_ADDR: $(STIM_READ_BASE_ADDR))
$(info   D0_LENGTH: $(STIM_READ_D0_LENGTH), D0_STRIDE: $(STIM_READ_D0_STRIDE))
$(info   D1_LENGTH: $(STIM_READ_D1_LENGTH), D1_STRIDE: $(STIM_READ_D1_STRIDE))
$(info   D2_STRIDE: $(STIM_READ_D2_STRIDE))
$(info   TOT_LENGTH: $(STIM_READ_TOT_LENGTH))
$(info )
$(info Write Configuration:)
$(info   BASE_ADDR: $(STIM_WRITE_BASE_ADDR))
$(info   D0_LENGTH: $(STIM_WRITE_D0_LENGTH), D0_STRIDE: $(STIM_WRITE_D0_STRIDE))
$(info   D1_LENGTH: $(STIM_WRITE_D1_LENGTH), D1_STRIDE: $(STIM_WRITE_D1_STRIDE))
$(info   D2_STRIDE: $(STIM_WRITE_D2_STRIDE))
$(info   TOT_LENGTH: $(STIM_WRITE_TOT_LENGTH))
$(info )
$(info Transpose Configuration:)
$(info   TRANSP_MODE: $(STIM_TRANSP_MODE))
$(info   TRANSP_LEN: $(STIM_TRANSP_LEN))
$(info ========================================)
