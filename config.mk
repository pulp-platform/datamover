# Copyright 2023 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# This file contains the configuration parameter for
# the standalone simulation of the datamover HWPE

# Standalone testing setup OUTDATED!
# ToDo: Implement SW-based testing with a CPU core

#######################
# Datamover HW Config #
#######################

# Hardware configuration (can be overridden by presets or command line)
BANDWIDTH ?= 512   		# in bits, multiple of WORD_WIDTH (512)
WORD_WIDTH ?= 64  		# in bits, multiple of ELEM_WIDTH (64)
ELEM_WIDTH ?= 8   		# in bits (8)
MEMORY_SIZE ?= 131072	# in words
MISALIGNED_ACCESSES ?= 0

DATAMOVER_MODE ?= 1     # 0 = copy, 1 = transpose, 2 = CIM data layout conversion, 3 = CIM data layout transpose, 4 = unfold (MobileViT), 5 = fold (MobileViT), other values: not accepted
TRANSP_MODE ?= 1		    # 1 = 1 elem, 2 = 2 elem, 4 = 4 elem, other values: not accepted
CIM_MODE ?= 0        	  # Data layout conversion mode: 0: row-major -> CIM-Layout, 1: reverse (CIM-Layout -> row-major) - This parameter is not passed to the HW, only used in the HAL
ROW_TILE_SIZE ?= 64    	# Row tile size for CIM data layout (in elements): 64 for 64x8 CIM macro

# Input tensor dimensions (in elements)
NUM_CHANNELS ?= 1		  # Number of channels (ToDo: currently, this should be set to 1 except for unfold and fold modes)
TENSOR_SIZE_M ?= 64  	# Matrix height in elements
TENSOR_SIZE_N ?= 64		# Matrix width in elements

READ_BASE_ADDR = 0

# Derived constants from basic parameters
# BANDWIDTH_REDUCTION := $(shell echo $$(($(MISALIGNED_ACCESSES) * $(WORD_WIDTH))))	# in bits
# BANDWIDTH_ALIGNED   := $(shell echo $$(($(BANDWIDTH) - $(BANDWIDTH_REDUCTION))))  	# in bits
BANDWIDTH_ALIGNED   := $(BANDWIDTH)  	# in bits
BANDWIDTH_ELEMS     := $(shell echo $$(($(BANDWIDTH_ALIGNED) / $(ELEM_WIDTH))))  	# Number of elements per bandwidth
NUM_ELEM_WORD       := $(shell echo $$(($(WORD_WIDTH) / $(ELEM_WIDTH))))  	# Number of elements per word
TENSOR_SIZE_TOT     := $(shell echo $$(($(TENSOR_SIZE_M) * $(TENSOR_SIZE_N)))) # Total number of elements in the tensor
TOTAL_ELEMENTS      := $(shell echo $$(($(NUM_CHANNELS) * $(TENSOR_SIZE_TOT)))) # Total number of elements in all channels
MATRIX_MISALIGNED   := $(shell echo $$(($(TOTAL_ELEMENTS) % $(BANDWIDTH_ELEMS)))) # 1 if tensor size is not multiple of bandwidth elements
ifeq "$(strip $(MATRIX_MISALIGNED))" "0"	# Matrix size aligned
  TOTAL_ACCESSES := $(shell echo $$(($(TOTAL_ELEMENTS) / $(BANDWIDTH_ELEMS)))) # Total number of memory accesses (words) for the tensor (floor division)
else                    # Matrix size misaligned
  TOTAL_ACCESSES := $(shell echo $$(($(TOTAL_ELEMENTS) / $(BANDWIDTH_ELEMS) + 1))) # Total number of memory accesses (words) for the tensor (+1 for misaligned access)
endif
WRITE_BASE_ADDR = $(shell echo $$(($(READ_BASE_ADDR) + $(TOTAL_ELEMENTS))))			# Element-addressed

# Align tensor dimensions to bandwidth for transposition (fill elem_matrix)
TENSOR_SIZE_M_MOD := $(shell echo $$(( $(TENSOR_SIZE_M) % $(BANDWIDTH_ELEMS) )))
TENSOR_SIZE_N_MOD := $(shell echo $$(( $(TENSOR_SIZE_N) % $(BANDWIDTH_ELEMS) )))
ifeq ($(TENSOR_SIZE_M_MOD),0)
  TENSOR_SIZE_M_ALIGNED := $(TENSOR_SIZE_M)
else
  TENSOR_SIZE_M_ALIGNED := $(shell echo $$(($(TENSOR_SIZE_M) + $(BANDWIDTH_ELEMS) - $(TENSOR_SIZE_M_MOD)))) # Align M dimension to bandwidth
endif
ifeq ($(TENSOR_SIZE_N_MOD),0)
  TENSOR_SIZE_N_ALIGNED := $(TENSOR_SIZE_N)
else
  TENSOR_SIZE_N_ALIGNED := $(shell echo $$(($(TENSOR_SIZE_N) + $(BANDWIDTH_ELEMS) - $(TENSOR_SIZE_N_MOD)))) # Align N dimension to bandwidth
endif

# ADDR and STRIDE are in bytes, LENGTH is in number of memory accesses (bandwidth)

ifeq "$(strip $(DATAMOVER_MODE))" "0"	# Copy mode
STIM_READ_BASE_ADDR ?= $(READ_BASE_ADDR)								# Element-addressed
STIM_READ_D0_LENGTH ?= $(TOTAL_ACCESSES)                # [Nof accesses with bandwidth BW per D0-transfer ("row")]
STIM_READ_D0_STRIDE ?= $(BANDWIDTH_ELEMS) 							# [Elements]
STIM_READ_D1_LENGTH ?= 0
STIM_READ_D1_STRIDE ?= 0
STIM_READ_D2_LENGTH ?= 0
STIM_READ_D2_STRIDE ?= 0
STIM_READ_D3_LENGTH ?= 0
STIM_READ_D3_STRIDE ?= 0
STIM_READ_D4_STRIDE ?= 0
STIM_READ_TOT_LENGTH ?= $(STIM_READ_D0_LENGTH)          # [Total memory accesses]
STIM_READ_DIM_ENABLE ?= "4'b0000"

STIM_MEM_SIZE ?= $(MEMORY_SIZE)  												# [Words]
STIM_TRANSP_MODE ?= 0
# STIM_TRANSP_LEN  ?= 0
STIM_TENSOR_SIZE_M ?= $(TENSOR_SIZE_M)
STIM_TENSOR_SIZE_N ?= $(TENSOR_SIZE_N)
STIM_NUM_CHANNELS ?= 1
STIM_TOTAL_ELEMENTS ?= $(TOTAL_ELEMENTS)

STIM_WRITE_BASE_ADDR ?= $(WRITE_BASE_ADDR)
STIM_WRITE_D0_LENGTH ?= $(STIM_READ_D0_LENGTH)
STIM_WRITE_D0_STRIDE ?= $(STIM_READ_D0_STRIDE)
STIM_WRITE_D1_LENGTH ?= 0
STIM_WRITE_D1_STRIDE ?= 0
STIM_WRITE_D2_LENGTH ?= 0
STIM_WRITE_D2_STRIDE ?= 0
STIM_WRITE_D3_LENGTH ?= 0
STIM_WRITE_D3_STRIDE ?= 0
STIM_WRITE_D4_STRIDE ?= 0
STIM_WRITE_TOT_LENGTH ?= $(STIM_READ_TOT_LENGTH)
STIM_WRITE_DIM_ENABLE ?= "4'b0000"

else ifeq "$(strip $(DATAMOVER_MODE))" "1"	# Transpose mode
ifneq ($(filter 1 2 4,$(strip $(TRANSP_MODE))), $(strip $(TRANSP_MODE)))
  $(error Invalid TRANSP_MODE $(TRANSP_MODE): must be 1, 2, or 4)
endif

STIM_READ_BASE_ADDR ?= $(READ_BASE_ADDR)								# Element-addressed
STIM_READ_D0_LENGTH ?= $(TENSOR_SIZE_M_ALIGNED) 												# [Nof accesses with bandwidth BW per D0-transfer ("row")]
STIM_READ_D0_STRIDE ?= $(TENSOR_SIZE_N) 												# [Elements]
STIM_READ_D1_LENGTH ?= $(shell echo $$(($(TENSOR_SIZE_N_ALIGNED) / $(BANDWIDTH_ELEMS)))) 		# [Number of full D0-transfers ("rows")]
STIM_READ_D1_STRIDE ?= $(BANDWIDTH_ELEMS) 												# [Elements] -> manually compute "next row" stride
STIM_READ_D2_LENGTH ?= 0
STIM_READ_D2_STRIDE ?= 0
STIM_READ_D3_LENGTH ?= 0
STIM_READ_D3_STRIDE ?= 0
STIM_READ_D4_STRIDE ?= 0
STIM_READ_TOT_LENGTH ?= $(shell echo $$(($(STIM_READ_D0_LENGTH) * $(STIM_READ_D1_LENGTH))))  # [Total memory accesses]
STIM_READ_DIM_ENABLE ?= "4'b0001"

STIM_MEM_SIZE ?= $(MEMORY_SIZE)  														# [Words]
STIM_TRANSP_MODE ?= $(TRANSP_MODE)       												# 1 = 1 elem, 2 = 2 elem, 4 = 4 elem, other values: not accepted
# STIM_TRANSP_LEN  ?= 0  																	# If 0: BANDWIDTH_ALIGNED / ELEM_WIDTH
STIM_TENSOR_SIZE_M ?= $(TENSOR_SIZE_M)    # Actual (non-aligned) tensor dimensions
STIM_TENSOR_SIZE_N ?= $(TENSOR_SIZE_N)
STIM_NUM_CHANNELS ?= 1
STIM_TOTAL_ELEMENTS ?= $(TOTAL_ELEMENTS)

STIM_WRITE_BASE_ADDR ?= $(WRITE_BASE_ADDR)												# Element-addressed
STIM_WRITE_D0_LENGTH ?= $(shell echo $$(($(BANDWIDTH_ELEMS) / $(TRANSP_MODE))))			# Transpose tile width corresponds to bandwidth
STIM_WRITE_D0_STRIDE ?= $(shell echo $$(($(TENSOR_SIZE_M) * $(TRANSP_MODE)))) 			# Transpose: Input tensor height corresponds to output tensor width
STIM_WRITE_D1_LENGTH ?= $(shell echo $$(($(STIM_WRITE_D0_STRIDE) / $(BANDWIDTH_ELEMS))))# Transpose: Input tensor height corresponds to output tensor width
STIM_WRITE_D1_STRIDE ?= $(BANDWIDTH_ELEMS)												# Transpose tile height corresponds to bandwidth
STIM_WRITE_D2_LENGTH ?= 0
STIM_WRITE_D2_STRIDE ?= $(shell echo $$(($(STIM_WRITE_D0_STRIDE) * $(STIM_WRITE_D0_LENGTH))))		# D2 length is controlled by total length
STIM_WRITE_D3_LENGTH ?= 0
STIM_WRITE_D3_STRIDE ?= 0
STIM_WRITE_D4_STRIDE ?= 0
STIM_WRITE_TOT_LENGTH ?= $(STIM_READ_TOT_LENGTH)
STIM_WRITE_DIM_ENABLE ?= "4'b0011"

else ifeq "$(strip $(DATAMOVER_MODE))" "2"	# CIM data layout conversion mode
ifneq ($(filter 0 1, $(strip $(CIM_MODE))), $(strip $(CIM_MODE)))
  $(error "Invalid CIM_MODE $(CIM_MODE): must be 0 or 1")
endif
STIM_READ_BASE_ADDR ?= $(READ_BASE_ADDR)								# Element-addressed
STIM_READ_D0_LENGTH ?= $(shell echo $$(($(ROW_TILE_SIZE) / $(BANDWIDTH_ELEMS)))) 		# [Nof accesses with bandwidth BW per D0-transfer ("row")]
STIM_READ_D0_STRIDE ?= $(BANDWIDTH_ELEMS) 												# [Elements]
STIM_READ_D1_LENGTH ?= $(TENSOR_SIZE_M)
STIM_READ_D1_STRIDE ?= $(TENSOR_SIZE_N)
STIM_READ_D2_LENGTH ?= $(shell echo $$(($(TENSOR_SIZE_N) / $(ROW_TILE_SIZE))))      # Redundant (handled by TOT_LEN)
STIM_READ_D2_STRIDE ?= $(ROW_TILE_SIZE)
STIM_READ_D3_LENGTH ?= 0
STIM_READ_D3_STRIDE ?= 0
STIM_READ_D4_STRIDE ?= 0
PARTIAL_MULT = $(shell echo $$(($(STIM_READ_D0_LENGTH) * $(STIM_READ_D1_LENGTH))))
STIM_READ_TOT_LENGTH ?= $(shell echo $$(($(PARTIAL_MULT) * $(STIM_READ_D2_LENGTH))))  	# [Total memory accesses]
STIM_READ_DIM_ENABLE ?= "4'b0011"

STIM_MEM_SIZE ?= $(MEMORY_SIZE)  														# [Words]
STIM_TRANSP_MODE ?= 0
# STIM_TRANSP_LEN  ?= 0
STIM_TENSOR_SIZE_M ?= $(TENSOR_SIZE_M)
STIM_TENSOR_SIZE_N ?= $(TENSOR_SIZE_N)
STIM_NUM_CHANNELS ?= 1
STIM_TOTAL_ELEMENTS ?= $(TOTAL_ELEMENTS)

STIM_WRITE_BASE_ADDR ?= $(WRITE_BASE_ADDR)												# Element-addressed
STIM_WRITE_D0_LENGTH ?= $(shell echo $$(($(STIM_READ_D0_LENGTH) * $(TENSOR_SIZE_M))))
STIM_WRITE_D0_STRIDE ?= $(BANDWIDTH_ELEMS)
STIM_WRITE_D1_LENGTH ?= $(shell echo $$(($(TENSOR_SIZE_N) / $(ROW_TILE_SIZE))))
STIM_WRITE_D1_STRIDE ?= $(shell echo $$(($(STIM_WRITE_D0_LENGTH) * $(BANDWIDTH_ELEMS))))
STIM_WRITE_D2_LENGTH ?= 0
STIM_WRITE_D2_STRIDE ?= 0
STIM_WRITE_D3_LENGTH ?= 0
STIM_WRITE_D3_STRIDE ?= 0
STIM_WRITE_D4_STRIDE ?= 0
STIM_WRITE_TOT_LENGTH ?= $(STIM_READ_TOT_LENGTH)										# Same total length as read
STIM_WRITE_DIM_ENABLE ?= "4'b0001"

else ifeq "$(strip $(DATAMOVER_MODE))" "3"	# CIM data layout transpose mode
ifneq ($(filter 0 1, $(strip $(CIM_MODE))), $(strip $(CIM_MODE)))
  $(error "Invalid CIM_MODE $(CIM_MODE): must be 0 or 1")
endif
ifneq ($(filter 1 2 4,$(strip $(TRANSP_MODE))), $(strip $(TRANSP_MODE)))
  $(error Invalid TRANSP_MODE $(TRANSP_MODE): must be 1, 2, or 4)
endif

STIM_READ_BASE_ADDR ?= $(READ_BASE_ADDR)								# Element-addressed
STIM_READ_D0_LENGTH ?= $(TENSOR_SIZE_M)
STIM_READ_D0_STRIDE ?= $(ROW_TILE_SIZE)
STIM_READ_D1_LENGTH ?= $(shell echo $$(($(ROW_TILE_SIZE) / $(BANDWIDTH_ELEMS))))
STIM_READ_D1_STRIDE ?= $(BANDWIDTH_ELEMS)
STIM_READ_D2_LENGTH ?= 0																# Not used (controlled by TOT_LEN)
STIM_READ_D2_STRIDE ?= $(shell echo $$(($(TENSOR_SIZE_M) * $(ROW_TILE_SIZE))))
STIM_READ_D3_LENGTH ?= 0
STIM_READ_D3_STRIDE ?= 0
STIM_READ_D4_STRIDE ?= 0
STIM_READ_TOT_LENGTH ?= $(shell echo $$(($(TOTAL_ELEMENTS) / $(BANDWIDTH_ELEMS))))
STIM_READ_DIM_ENABLE ?= "4'b0011"

STIM_MEM_SIZE ?= $(MEMORY_SIZE)  														# [Words]
STIM_TRANSP_MODE ?= $(TRANSP_MODE)														# transp_mode
# STIM_TRANSP_LEN  ?= 0
STIM_TENSOR_SIZE_M ?= $(TENSOR_SIZE_M)
STIM_TENSOR_SIZE_N ?= $(TENSOR_SIZE_N)
STIM_NUM_CHANNELS ?= 1
STIM_TOTAL_ELEMENTS ?= $(TOTAL_ELEMENTS)

STIM_WRITE_BASE_ADDR ?= $(WRITE_BASE_ADDR)												# Element-addressed
STIM_WRITE_D0_LENGTH ?= $(BANDWIDTH_ELEMS)
STIM_WRITE_D0_STRIDE ?= $(ROW_TILE_SIZE)
STIM_WRITE_D1_LENGTH ?= $(shell echo $$(($(ROW_TILE_SIZE) / $(BANDWIDTH_ELEMS))))
STIM_WRITE_D1_STRIDE ?= $(BANDWIDTH_ELEMS)
STIM_WRITE_D2_LENGTH ?= 0
STIM_WRITE_D2_STRIDE ?= $(shell echo $$(($(BANDWIDTH_ELEMS) * $(ROW_TILE_SIZE))))
STIM_WRITE_D3_LENGTH ?= 0
STIM_WRITE_D3_STRIDE ?= 0
STIM_WRITE_D4_STRIDE ?= 0
STIM_WRITE_TOT_LENGTH ?= $(STIM_READ_TOT_LENGTH)										# Same total length as read
STIM_WRITE_DIM_ENABLE ?= "4'b0011"


else
$(error "Invalid DATAMOVER_MODE $(DATAMOVER_MODE): must be 0 (copy), 1 (transpose), 2 (CIM data layout conversion), or 3 (CIM data layout transpose)")
endif

