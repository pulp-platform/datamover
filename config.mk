# Copyright 2023 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# This file contains the configuration parameter for
# the standalone simulation of the datamover HWPE

#######################
# Datamover hw config #
#######################

BANDWIDTH ?= 128   # in bits
NUM_ELEM_WORD ?= 4 # number of element in a memory bank word (powers of 2)
ELEM_WIDTH ?= 8   # width of an element (e.g., a byte is 8 bits)

#########################
# Stimuli configuration #
#########################

# Tb stimuli config
STIM_READ_BASE_ADDR ?= 0    # element-addressed
STIM_READ_D0_LENGTH ?= 4
STIM_READ_D0_STRIDE ?= 16   # element-addressed
STIM_READ_D1_LENGTH ?= 4
STIM_READ_D1_STRIDE ?= 32   # element-addressed
STIM_READ_TOT_LENGTH ?= 16

STIM_WRITE_BASE_ADDR ?= 256 # element-addressed
STIM_WRITE_D0_LENGTH ?= 4
STIM_WRITE_D0_STRIDE ?= 64  # element-addressed
STIM_WRITE_D1_LENGTH ?= 4
STIM_WRITE_D1_STRIDE ?= 64  # element-addressed
STIM_WRITE_TOT_LENGTH ?= 16
STIM_MEM_SIZE ?= 65536      # in words

STIM_TRANSP_MODE ?= 0       # 3'b000 = none, 3'b001 = 1 elem, 3'b010 = 2 elem, 3'b100 = 4 elem
