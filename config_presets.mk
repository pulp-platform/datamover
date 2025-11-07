# Copyright 2023 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Configuration Presets for Datamover HWPE
# This file defines named configuration presets for common test scenarios

#########################################
# Configuration Preset System          #
#########################################

# Available presets:
# - small-matrix    : Small 4x4 matrix for quick testing
# - medium-matrix   : Medium 32x32 matrix for moderate testing
# - large-matrix    : Large 448x448 matrix for stress testing
# - transpose-test  : Optimized for transpose functionality verification
# - rect-wide       : Wide rectangular matrix (64x256)
# - rect-tall       : Tall rectangular matrix (256x64)
# - rect-narrow     : Narrow rectangular matrix (16x128)
# - rect-elongated  : Elongated rectangular matrix (128x32)
# - custom          : User-defined configuration (default)

# Select configuration preset (can be overridden via command line)
CONFIG_PRESET ?= custom

# Preset-specific configurations
ifeq ($(CONFIG_PRESET),small-matrix)
    BANDWIDTH = 32
    WORD_WIDTH = 32
    ELEM_WIDTH = 8
    MEMORY_SIZE = 512
    TRANSP_MODE = 1
    MATRIX_SIZE_M = 4
    MATRIX_SIZE_N = 4
    CONFIG_DESC = "Small 4x4 matrix, 1-element transpose"
endif

ifeq ($(CONFIG_PRESET),medium-matrix)
    BANDWIDTH = 64
    WORD_WIDTH = 32
    ELEM_WIDTH = 8
    MEMORY_SIZE = 1024
    TRANSP_MODE = 1
    MATRIX_SIZE_M = 32
    MATRIX_SIZE_N = 32
    CONFIG_DESC = "Medium 32x32 matrix, 1-element transpose"
endif

ifeq ($(CONFIG_PRESET),large-matrix)
    BANDWIDTH = 512
    WORD_WIDTH = 32
    ELEM_WIDTH = 8
    MEMORY_SIZE = 131072
    TRANSP_MODE = 1
    MATRIX_SIZE_M = 448
    MATRIX_SIZE_N = 448
    CONFIG_DESC = "Large 448x448 matrix, 1-element transpose"
endif

ifeq ($(CONFIG_PRESET),transpose-test)
    BANDWIDTH = 256
    WORD_WIDTH = 32
    ELEM_WIDTH = 8
    MEMORY_SIZE = 16384
    TRANSP_MODE = 2
    MATRIX_SIZE_M = 32
    MATRIX_SIZE_N = 32
    CONFIG_DESC = "32x32 matrix, 2-element transpose"
endif

ifeq ($(CONFIG_PRESET),rect-wide)
    BANDWIDTH = 256
    WORD_WIDTH = 32
    ELEM_WIDTH = 8
    MEMORY_SIZE = 32768
    TRANSP_MODE = 1
    MATRIX_SIZE_M = 64
    MATRIX_SIZE_N = 256
    CONFIG_DESC = "Wide rectangular matrix 64x256, 1-element transpose"
endif

ifeq ($(CONFIG_PRESET),rect-tall)
    BANDWIDTH = 256
    WORD_WIDTH = 32
    ELEM_WIDTH = 8
    MEMORY_SIZE = 32768
    TRANSP_MODE = 2
    MATRIX_SIZE_M = 256
    MATRIX_SIZE_N = 64
    CONFIG_DESC = "Tall rectangular matrix 256x64, 2-element transpose"
endif

ifeq ($(CONFIG_PRESET),rect-narrow)
    BANDWIDTH = 128
    WORD_WIDTH = 32
    ELEM_WIDTH = 8
    MEMORY_SIZE = 8192
    TRANSP_MODE = 1
    MATRIX_SIZE_M = 16
    MATRIX_SIZE_N = 128
    CONFIG_DESC = "Narrow rectangular matrix 16x128, 1-element transpose"
endif

ifeq ($(CONFIG_PRESET),rect-elongated)
    BANDWIDTH = 256
    WORD_WIDTH = 32
    ELEM_WIDTH = 8
    MEMORY_SIZE = 16384
    TRANSP_MODE = 2
    MATRIX_SIZE_M = 128
    MATRIX_SIZE_N = 32
    CONFIG_DESC = "Elongated rectangular matrix 128x32, 2-element transpose"
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
