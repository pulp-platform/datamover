import random
import argparse
import os
import math
from unittest import case
import numpy as np
from dataclasses import dataclass

RANDOM_STIMULI = False  # If False, stimuli are generated in a counting fashion

# HW Parameters
BANDWIDTH = 32          # in bits
WORD_WIDTH = 32         # in bits
ELEM_WIDTH = 8          # in bits
BANDWIDTH_ELEMS = BANDWIDTH // ELEM_WIDTH
WORDWIDTH_ELEMS = WORD_WIDTH // ELEM_WIDTH

# Operation Modes
DATAMOVER_MODE = 4      # 0: copy, 1: transpose, 2: CIM data layout conversion, 3: CIM layout transpose, 4: unfold
TRANSP_MODE = 1         # 1 = 1 elem, 2 = 2 elem, 4 = 4 elem, other values: not accepted
CIM_ROWTILE_SIZE = 2    # in elements (64 in Konark)
PATCH_SIZE = 4          # in elements (2x2 = 4 in MobileViT)

CHANNELS = 2
HEIGHT = 8
WIDTH = 8

@dataclass
class addrgen_ctrl_c:
    D0_LENGTH: int = HEIGHT * WIDTH
    D0_STRIDE: int = BANDWIDTH_ELEMS
    D1_LENGTH: int = 0
    D1_STRIDE: int = 0
    D2_LENGTH: int = 0
    D2_STRIDE: int = 0
    D3_LENGTH: int = 0
    D3_STRIDE: int = 0
    D4_STRIDE: int = 0
    TOT_LENGTH: int = math.ceil(HEIGHT * WIDTH / BANDWIDTH_ELEMS)
    # DIM_ENABLE: str = "0000"        # !!! REVERSE ORDER than in SystemVerilog testbench / config.mk

class addrgen_c:
    def __init__(self, start, addrgen_ctrl):
        self.addr = start
        self.addrgen_ctrl = addrgen_ctrl

        # loop indices (counters)
        self.d0 = 0
        self.d1 = 0
        self.d2 = 0
        self.d3 = 0
        self.d4 = 0

    def tick(self):
        out = int(self.addr)
        # ---- D0 ----
        self.d0 += 1
        self.addr += self.addrgen_ctrl.D0_STRIDE
        if self.d0 < self.addrgen_ctrl.D0_LENGTH:
            return out
        # wrap D0
        self.d0 = 0
        self.addr -= self.addrgen_ctrl.D0_LENGTH * self.addrgen_ctrl.D0_STRIDE
        # ---- D1 ----
        self.d1 += 1
        self.addr += self.addrgen_ctrl.D1_STRIDE
        if self.d1 < self.addrgen_ctrl.D1_LENGTH:
            return out
        self.d1 = 0
        self.addr -= self.addrgen_ctrl.D1_LENGTH * self.addrgen_ctrl.D1_STRIDE
        # ---- D2 ----
        self.d2 += 1
        self.addr += self.addrgen_ctrl.D2_STRIDE
        if self.d2 < self.addrgen_ctrl.D2_LENGTH:
            return out
        self.d2 = 0
        self.addr -= self.addrgen_ctrl.D2_LENGTH * self.addrgen_ctrl.D2_STRIDE
        # ---- D3 ----
        self.d3 += 1
        self.addr += self.addrgen_ctrl.D3_STRIDE
        if self.d3 < self.addrgen_ctrl.D3_LENGTH:
            return out
        self.d3 = 0
        self.addr -= self.addrgen_ctrl.D3_LENGTH * self.addrgen_ctrl.D3_STRIDE
        # ---- D4 ----
        self.d4 += 1
        self.addr += self.addrgen_ctrl.D4_STRIDE
        # if self.d4 < self.addrgen_ctrl.D4_LENGTH:
        #     return self.addr
        # final wrap (optional)
        # self.d4 = 0
        # self.addr = self.start
        return out

def datamover_execute(input_memory, input_channels, input_height, input_width, addrgen_in_ctrl, addrgen_out_ctrl):
    nof_input_tiles = math.ceil(addrgen_in_ctrl.TOT_LENGTH / BANDWIDTH_ELEMS)
    elem_matrix = np.zeros((BANDWIDTH_ELEMS, BANDWIDTH_ELEMS), dtype=input_memory.dtype)
    output_memory = np.zeros_like(input_memory)
    addrgen_in = addrgen_c(0, addrgen_in_ctrl)
    addrgen_out = addrgen_c(0, addrgen_out_ctrl)

    for input_tile_idx in range(nof_input_tiles):
        # Fill the element matrix (internal buffer)
        for i in range(BANDWIDTH_ELEMS):
            in_addr = addrgen_in.tick()
            # print(f"Reading input address: {in_addr}")
            elem_matrix[i, :] = input_memory[in_addr:in_addr + BANDWIDTH_ELEMS]
        print(f"elem_matrix (tile {input_tile_idx}):\n{elem_matrix}\n")
        # Write out the element matrix to output memory (rearranged as needed)
        for i in range(BANDWIDTH_ELEMS):
            out_addr = addrgen_out.tick()
            if DATAMOVER_MODE==0 or DATAMOVER_MODE==2:
                output_memory[out_addr:out_addr + BANDWIDTH_ELEMS] = elem_matrix[i, :]
            elif DATAMOVER_MODE==1:
                if TRANSP_MODE==1:
                    output_memory[out_addr:out_addr + BANDWIDTH_ELEMS] = elem_matrix[:, i]
                else:
                    print(f"Unsupported TRANSP_MODE {TRANSP_MODE} in datamover_execute")
            elif DATAMOVER_MODE==4:     # ToDo(cdurrer)
                for x in range(BANDWIDTH_ELEMS):
                    for y in range(BANDWIDTH_ELEMS):
                        output_memory[out_addr + x * BANDWIDTH_ELEMS + y] = elem_matrix[x, y]
            else:
                print(f"Unsupported DATAMOVER_MODE {DATAMOVER_MODE} in datamover_execute")
    return output_memory

def cim_copy_config(input_channels, input_height, input_width):
    total_elems = input_channels * input_height * input_width
    total_accesses = math.ceil(total_elems / BANDWIDTH_ELEMS)
    addrgen_in_ctrl = addrgen_ctrl_c(
        D0_LENGTH=total_accesses,
        D0_STRIDE=BANDWIDTH_ELEMS,
        D1_LENGTH=0,
        D1_STRIDE=0,
        D2_LENGTH=0,
        D2_STRIDE=0,
        D3_LENGTH=0,
        D3_STRIDE=0,
        D4_STRIDE=0,
        TOT_LENGTH=total_accesses,
        # DIM_ENABLE="0000",
    )
    addrgen_out_ctrl = addrgen_ctrl_c(
        D0_LENGTH=total_accesses,
        D0_STRIDE=BANDWIDTH_ELEMS,
        D1_LENGTH=0,
        D1_STRIDE=0,
        D2_LENGTH=0,
        D2_STRIDE=0,
        D3_LENGTH=0,
        D3_STRIDE=0,
        D4_STRIDE=0,
        TOT_LENGTH=total_accesses,
        # DIM_ENABLE="0000",
    )
    return addrgen_in_ctrl, addrgen_out_ctrl

def transpose_config(input_height, input_width, transp_mode):
    m_aligned = ((input_height + BANDWIDTH_ELEMS - 1) // BANDWIDTH_ELEMS) * BANDWIDTH_ELEMS
    n_aligned = ((input_width + BANDWIDTH_ELEMS - 1) // BANDWIDTH_ELEMS) * BANDWIDTH_ELEMS
    addrgen_in_ctrl = addrgen_ctrl_c(
        D0_LENGTH=m_aligned,
        D0_STRIDE=input_width,
        D1_LENGTH=n_aligned // BANDWIDTH_ELEMS,
        D1_STRIDE=BANDWIDTH_ELEMS,
        D2_LENGTH=0,
        D2_STRIDE=0,
        D3_LENGTH=0,
        D3_STRIDE=0,
        D4_STRIDE=0,
        TOT_LENGTH=m_aligned * (n_aligned // BANDWIDTH_ELEMS),
        # DIM_ENABLE="0001",
    )
    write_d0_stride = input_height * transp_mode
    addrgen_out_ctrl = addrgen_ctrl_c(
        D0_LENGTH=BANDWIDTH_ELEMS // transp_mode,
        D0_STRIDE=write_d0_stride,
        D1_LENGTH=write_d0_stride // BANDWIDTH_ELEMS,
        D1_STRIDE=BANDWIDTH_ELEMS,
        D2_LENGTH=0,
        D2_STRIDE=write_d0_stride * (BANDWIDTH_ELEMS // transp_mode),
        D3_LENGTH=0,
        D3_STRIDE=0,
        D4_STRIDE=0,
        TOT_LENGTH=m_aligned * (n_aligned // BANDWIDTH_ELEMS),
        # DIM_ENABLE="0011",
    )
    return addrgen_in_ctrl, addrgen_out_ctrl

def cim_layout_config(input_height, input_width, rowtile_size):
    addrgen_in_ctrl = addrgen_ctrl_c(
        D0_LENGTH=rowtile_size // BANDWIDTH_ELEMS,
        D0_STRIDE=BANDWIDTH_ELEMS,
        D1_LENGTH=input_height,
        D1_STRIDE=input_width,
        D2_LENGTH=input_width // rowtile_size,
        D2_STRIDE=rowtile_size,
        D3_LENGTH=0,
        D3_STRIDE=0,
        D4_STRIDE=0,
        TOT_LENGTH=(rowtile_size // BANDWIDTH_ELEMS) * input_height * (input_width // rowtile_size),
        # DIM_ENABLE="0011",
    )
    addrgen_out_ctrl = addrgen_ctrl_c(
        D0_LENGTH=(rowtile_size // BANDWIDTH_ELEMS) * input_height,
        D0_STRIDE=BANDWIDTH_ELEMS,
        D1_LENGTH=input_width // rowtile_size,
        D1_STRIDE=((rowtile_size // BANDWIDTH_ELEMS) * input_height) * BANDWIDTH_ELEMS,
        D2_LENGTH=0,
        D2_STRIDE=0,
        D3_LENGTH=0,
        D3_STRIDE=0,
        D4_STRIDE=0,
        TOT_LENGTH=(rowtile_size // BANDWIDTH_ELEMS) * input_height * (input_width // rowtile_size),
        # DIM_ENABLE="0001",
    )
    return addrgen_in_ctrl, addrgen_out_ctrl

def unfold_config(input_channels, input_height, input_width, patch_size):   # TODO(cdurrer): verify correctness
    patch_sidelength = int(math.sqrt(patch_size))
    num_patches_h = input_height // patch_sidelength
    num_patches_w = input_width // patch_sidelength
    num_patches = num_patches_h * num_patches_w
    total_elems = input_channels * input_height * input_width
    total_accesses = math.ceil(total_elems / BANDWIDTH_ELEMS)
    addrgen_in_ctrl = addrgen_ctrl_c(
        D0_LENGTH=CHANNELS,
        D0_STRIDE=HEIGHT * WIDTH,
        D1_LENGTH=HEIGHT,
        D1_STRIDE=WIDTH,
        D2_LENGTH=math.ceil(WIDTH / BANDWIDTH_ELEMS),
        D2_STRIDE=BANDWIDTH_ELEMS,
        D3_LENGTH=0,
        D3_STRIDE=0,
        D4_STRIDE=0,
        TOT_LENGTH=total_accesses,
        # DIM_ENABLE="0000",
    )
    addrgen_out_ctrl = addrgen_ctrl_c(
        D0_LENGTH=patch_size,
        D0_STRIDE=input_channels,
        D1_LENGTH=num_patches,
        D1_STRIDE=patch_size * input_channels,
        D2_LENGTH=0,
        D2_STRIDE=0,
        D3_LENGTH=0,
        D3_STRIDE=0,
        D4_STRIDE=0,
        TOT_LENGTH=total_accesses,
        # DIM_ENABLE="0011",
    )
    return addrgen_in_ctrl, addrgen_out_ctrl


def main():
    # Create a tensor of size (CHANNELS, HEIGHT, WIDTH) with random or counting values
    if RANDOM_STIMULI:
        input_tensor = np.random.randint(0, 256, (CHANNELS, HEIGHT, WIDTH), dtype=np.uint8)
    else:
        input_tensor = np.arange(CHANNELS * HEIGHT * WIDTH, dtype=np.uint8).reshape(CHANNELS, HEIGHT, WIDTH)
    print(f"Input Tensor:\n{input_tensor}\n")
    input_memory = input_tensor.flatten()
    output_memory = np.zeros_like(input_memory)
    print(f"Input Memory (flat):\n{input_memory}\n")
    if DATAMOVER_MODE==0:
        print("\nDATAMOVER_MODE 0: Copy\n")
        (addrgen_in_ctrl, addrgen_out_ctrl) = cim_copy_config(CHANNELS, HEIGHT, WIDTH)
        output_memory = datamover_execute(input_memory, CHANNELS, HEIGHT, WIDTH, addrgen_in_ctrl, addrgen_out_ctrl)
        output_matrix = output_memory.reshape(CHANNELS, HEIGHT, WIDTH)
    elif DATAMOVER_MODE==1:
        print(f"\nDATAMOVER_MODE 1: Transpose\n")
        (addrgen_in_ctrl, addrgen_out_ctrl) = transpose_config(HEIGHT, WIDTH, TRANSP_MODE)
        for channel in range(CHANNELS):
            channel_transposed_flat = datamover_execute(input_memory[channel*HEIGHT*WIDTH:(channel+1)*HEIGHT*WIDTH], 1, HEIGHT, WIDTH, addrgen_in_ctrl, addrgen_out_ctrl)
            output_memory[channel*HEIGHT*WIDTH:(channel+1)*HEIGHT*WIDTH] = channel_transposed_flat
        # output_memory = datamover_execute(input_memory, HEIGHT, WIDTH, addrgen_in_ctrl, addrgen_out_ctrl)
        output_matrix = output_memory.reshape(CHANNELS, WIDTH * TRANSP_MODE, HEIGHT // TRANSP_MODE)
    elif DATAMOVER_MODE==2:
        print(f"\nDATAMOVER_MODE 2: CIM Data Layout Conversion\n")
        (addrgen_in_ctrl, addrgen_out_ctrl) = cim_layout_config(HEIGHT, WIDTH, CIM_ROWTILE_SIZE)
        for channel in range(CHANNELS):
            channel_transposed_flat = datamover_execute(input_memory[channel*HEIGHT*WIDTH:(channel+1)*HEIGHT*WIDTH], 1, HEIGHT, WIDTH, addrgen_in_ctrl, addrgen_out_ctrl)
            output_memory[channel*HEIGHT*WIDTH:(channel+1)*HEIGHT*WIDTH] = channel_transposed_flat
        output_matrix = output_memory.reshape(CHANNELS, WIDTH // CIM_ROWTILE_SIZE, HEIGHT * CIM_ROWTILE_SIZE)
    # elif DATAMOVER_MODE==3:
    #     output_tensor = cim_transpose(input_memory, )
    elif DATAMOVER_MODE==4:
        print(f"\nDATAMOVER_MODE 4: Unfold\n")
        (addrgen_in_ctrl, addrgen_out_ctrl) = unfold_config(CHANNELS, HEIGHT, WIDTH, PATCH_SIZE)
        output_memory = datamover_execute(input_memory, CHANNELS, HEIGHT, WIDTH, addrgen_in_ctrl, addrgen_out_ctrl)
        output_matrix = output_memory.reshape(PATCH_SIZE, int((HEIGHT*WIDTH) / PATCH_SIZE), CHANNELS) # PNC format
    else:
        raise ValueError(f"Unsupported DATAMOVER_MODE: {DATAMOVER_MODE}")

    print(f"\nOutput Memory (flat):\n{output_memory}\n")
    print(f"\nOutput Matrix:\n{output_matrix}\n")

if __name__ == "__main__":
    main()
