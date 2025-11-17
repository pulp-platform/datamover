# Copyright 2023 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Configuration Presets for Datamover HWPE
# This file defines named configuration presets for common test scenarios

#########################################
# Configuration Preset System          #
#########################################

# Available presets:
# - small-matrix    : Small 4x4 matrix for quick testing (transpose)
# - medium-matrix   : Medium 64x64 matrix for moderate testing (transpose)
# - large-matrix    : Large 448x448 matrix for stress testing (transpose)
# - transpose-test  : Optimized for transpose functionality verification
# - rect-wide       : Wide rectangular matrix (64x256) (transpose)
# - rect-tall       : Tall rectangular matrix (256x64) (transpose)
# - rect-narrow     : Narrow rectangular matrix (16x128) (transpose)
# - rect-elongated  : Elongated rectangular matrix (128x32) (transpose)
# - copy-small      : Small 4x4 matrix for copy mode testing
# - copy-medium     : Medium 64x64 matrix for copy mode testing
# - cim-small       : CIM 32x128 matrix, CIM_INNER_DIM=32, 128-bit bandwidth
# - cim-medium      : CIM 64x256 matrix, CIM_INNER_DIM=64, 256-bit bandwidth
# - cim-large       : CIM 128x512 matrix, CIM_INNER_DIM=64, 512-bit bandwidth
# - custom          : User-defined configuration (default)

# Select configuration preset (can be overridden via command line)
CONFIG_PRESET ?= custom

# Preset-specific configurations
ifeq ($(CONFIG_PRESET),small-matrix)
    BANDWIDTH = 32
    WORD_WIDTH = 32
    ELEM_WIDTH = 8
    MEMORY_SIZE = 512
    MISALIGNED_ACCESSES = 0
    DATAMOVER_MODE = 1
    TRANSP_MODE = 1
    CIM_MODE = 0
    CIM_INNER_DIM = 0
    CIM_OUTER_DIM = 0
    MATRIX_SIZE_M = 4
    MATRIX_SIZE_N = 4
    CONFIG_DESC = "Small 4x4 matrix, 1-element transpose"
endif

ifeq ($(CONFIG_PRESET),medium-matrix)
    BANDWIDTH = 128
    WORD_WIDTH = 32
    ELEM_WIDTH = 8
    MEMORY_SIZE = 4096
    MISALIGNED_ACCESSES = 0
    DATAMOVER_MODE = 1
    TRANSP_MODE = 1
    CIM_MODE = 0
    CIM_INNER_DIM = 0
    CIM_OUTER_DIM = 0
    MATRIX_SIZE_M = 64
    MATRIX_SIZE_N = 64
    CONFIG_DESC = "Medium 64x64 matrix, 1-element transpose"
endif

ifeq ($(CONFIG_PRESET),large-matrix)
    BANDWIDTH = 512
    WORD_WIDTH = 32
    ELEM_WIDTH = 8
    MEMORY_SIZE = 131072
    MISALIGNED_ACCESSES = 0
    DATAMOVER_MODE = 1
    TRANSP_MODE = 1
    CIM_MODE = 0
    CIM_INNER_DIM = 0
    CIM_OUTER_DIM = 0
    MATRIX_SIZE_M = 448
    MATRIX_SIZE_N = 448
    CONFIG_DESC = "Large 448x448 matrix, 1-element transpose"
endif

ifeq ($(CONFIG_PRESET),transpose-test)
    BANDWIDTH = 256
    WORD_WIDTH = 32
    ELEM_WIDTH = 8
    MEMORY_SIZE = 16384
    MISALIGNED_ACCESSES = 0
    DATAMOVER_MODE = 1
    TRANSP_MODE = 2
    CIM_MODE = 0
    CIM_INNER_DIM = 0
    CIM_OUTER_DIM = 0
    MATRIX_SIZE_M = 32
    MATRIX_SIZE_N = 32
    CONFIG_DESC = "32x32 matrix, 2-element transpose"
endif

ifeq ($(CONFIG_PRESET),rect-wide)
    BANDWIDTH = 256
    WORD_WIDTH = 16
    ELEM_WIDTH = 8
    MEMORY_SIZE = 32768
    MISALIGNED_ACCESSES = 0
    DATAMOVER_MODE = 1
    TRANSP_MODE = 4
    CIM_MODE = 0
    CIM_INNER_DIM = 0
    CIM_OUTER_DIM = 0
    MATRIX_SIZE_M = 64
    MATRIX_SIZE_N = 256
    CONFIG_DESC = "Wide rectangular matrix 64x256, 4-element transpose"
endif

ifeq ($(CONFIG_PRESET),rect-tall)
    BANDWIDTH = 256
    WORD_WIDTH = 32
    ELEM_WIDTH = 8
    MEMORY_SIZE = 32768
    MISALIGNED_ACCESSES = 0
    DATAMOVER_MODE = 1
    TRANSP_MODE = 2
    CIM_MODE = 0
    CIM_INNER_DIM = 0
    CIM_OUTER_DIM = 0
    MATRIX_SIZE_M = 256
    MATRIX_SIZE_N = 64
    CONFIG_DESC = "Tall rectangular matrix 256x64, 2-element transpose"
endif

ifeq ($(CONFIG_PRESET),rect-narrow)
    BANDWIDTH = 128
    WORD_WIDTH = 32
    ELEM_WIDTH = 8
    MEMORY_SIZE = 8192
    MISALIGNED_ACCESSES = 0
    DATAMOVER_MODE = 1
    TRANSP_MODE = 1
    CIM_MODE = 0
    CIM_INNER_DIM = 0
    CIM_OUTER_DIM = 0
    MATRIX_SIZE_M = 16
    MATRIX_SIZE_N = 128
    CONFIG_DESC = "Narrow rectangular matrix 16x128, 1-element transpose"
endif

ifeq ($(CONFIG_PRESET),rect-elongated)
    BANDWIDTH = 256
    WORD_WIDTH = 32
    ELEM_WIDTH = 8
    MEMORY_SIZE = 16384
    MISALIGNED_ACCESSES = 0
    DATAMOVER_MODE = 1
    TRANSP_MODE = 2
    CIM_MODE = 0
    CIM_INNER_DIM = 0
    CIM_OUTER_DIM = 0
    MATRIX_SIZE_M = 128
    MATRIX_SIZE_N = 32
    CONFIG_DESC = "Elongated rectangular matrix 128x32, 2-element transpose"
endif

ifeq ($(CONFIG_PRESET),copy-small)
    BANDWIDTH = 32
    WORD_WIDTH = 32
    ELEM_WIDTH = 8
    MEMORY_SIZE = 512
    MISALIGNED_ACCESSES = 0
    DATAMOVER_MODE = 0
    TRANSP_MODE = 0
    CIM_MODE = 0
    CIM_INNER_DIM = 0
    CIM_OUTER_DIM = 0
    MATRIX_SIZE_M = 4
    MATRIX_SIZE_N = 4
    CONFIG_DESC = "Small 4x4 matrix, copy mode"
endif

ifeq ($(CONFIG_PRESET),copy-medium)
    BANDWIDTH = 128
    WORD_WIDTH = 32
    ELEM_WIDTH = 8
    MEMORY_SIZE = 4096
    MISALIGNED_ACCESSES = 0
    DATAMOVER_MODE = 0
    TRANSP_MODE = 0
    CIM_MODE = 0
    CIM_INNER_DIM = 0
    CIM_OUTER_DIM = 0
    MATRIX_SIZE_M = 64
    MATRIX_SIZE_N = 64
    CONFIG_DESC = "Medium 64x64 matrix, copy mode"
endif

ifeq ($(CONFIG_PRESET),cim-small)
    BANDWIDTH = 128
    WORD_WIDTH = 32
    ELEM_WIDTH = 8
    MEMORY_SIZE = 8192
    MISALIGNED_ACCESSES = 0
    DATAMOVER_MODE = 2
    TRANSP_MODE = 0
    CIM_MODE = 0
    CIM_INNER_DIM = 32
    CIM_OUTER_DIM = 16
    MATRIX_SIZE_M = 32
    MATRIX_SIZE_N = 128
    CONFIG_DESC = "CIM 32x128 matrix, CIM_INNER_DIM=32, 128-bit bandwidth"
endif

ifeq ($(CONFIG_PRESET),cim-medium)
    BANDWIDTH = 256
    WORD_WIDTH = 64
    ELEM_WIDTH = 8
    MEMORY_SIZE = 16384
    MISALIGNED_ACCESSES = 0
    DATAMOVER_MODE = 2
    TRANSP_MODE = 0
    CIM_MODE = 0
    CIM_INNER_DIM = 64
    CIM_OUTER_DIM = 32
    MATRIX_SIZE_M = 64
    MATRIX_SIZE_N = 256
    CONFIG_DESC = "CIM 64x256 matrix, CIM_INNER_DIM=64, 256-bit bandwidth"
endif

ifeq ($(CONFIG_PRESET),cim-large)
    BANDWIDTH = 512
    WORD_WIDTH = 64
    ELEM_WIDTH = 8
    MEMORY_SIZE = 65536
    MISALIGNED_ACCESSES = 0
    DATAMOVER_MODE = 2
    TRANSP_MODE = 0
    CIM_MODE = 0
    CIM_INNER_DIM = 64
    CIM_OUTER_DIM = 64
    MATRIX_SIZE_M = 128
    MATRIX_SIZE_N = 256
    CONFIG_DESC = "CIM 128x512 matrix, CIM_INNER_DIM=64, 512-bit bandwidth"
endif

ifeq ($(CONFIG_PRESET),custom)
    # Use values from config.mk or command line overrides
    CONFIG_DESC = "Custom user-defined configuration (config.mk)"
endif

# Print current configuration info
$(info ========================================)
$(info Configuration Preset (CONFIG_PRESET): $(CONFIG_PRESET))
$(info Description: $(CONFIG_DESC))
$(info ========================================)
