import random
import argparse
import os
import math
from unittest import case
import numpy as np

RANDOM_STIMULI = False  # If False, stimuli are generated in a counting fashion

CIM_MODE = 4        # 0: copy, 1: transpose, 2: CIM data layout conversion, 3: CIM layout transpose, 4: unfold

CHANNELS = 2
HEIGHT = 4
WIDTH = 4
PATCH_SIZE = 4

def unfold(tensor, patch_size):
    # Input tensor shape: (CHANNELS, HEIGHT, WIDTH)
    # Output tensor shape: (PATCH_SIZE, NUM_PATCHES, CHANNELS)
    channels, height, width = tensor.shape
    patch_sidelength = int(math.sqrt(patch_size))
    assert (height % patch_sidelength == 0) and (width % patch_sidelength == 0), "Height and Width must be divisible by patch sidelength"
    num_patches_h = height // patch_sidelength
    num_patches_w = width // patch_sidelength
    num_patches = num_patches_h * num_patches_w
    tensor_unfolded = np.zeros((patch_size, num_patches, channels), dtype=tensor.dtype)
    for p in range(patch_size):
        for h in range(num_patches_h):
            for w in range(num_patches_w):
                n = h * num_patches_w + w
                h_idx = h * patch_sidelength + (p // patch_sidelength)
                w_idx = w * patch_sidelength + (p % patch_sidelength)
                tensor_unfolded[p, n, :] = tensor[:, h_idx, w_idx]
    return tensor_unfolded

def main():
    # Create a tensor of size (CHANNELS, HEIGHT, WIDTH) with random or counting values
    if RANDOM_STIMULI:
        input_tensor = np.random.randint(0, 256, (CHANNELS, HEIGHT, WIDTH), dtype=np.uint8)
    else:
        input_tensor = np.arange(CHANNELS * HEIGHT * WIDTH, dtype=np.uint8).reshape((CHANNELS, HEIGHT, WIDTH))
    print("Input Tensor:")
    print(input_tensor)
    if CIM_MODE==0:
        output_tensor = input_tensor.copy()
    elif CIM_MODE==1:
        output_tensor = np.transpose(input_tensor, (0, 2, 1))
    # elif CIM_MODE==2:
    #     output_tensor = cim_layout(input_tensor, )
    # elif CIM_MODE==3:
    #     output_tensor = cim_transpose(input_tensor, )
    elif CIM_MODE==4:
        output_tensor = unfold(input_tensor, PATCH_SIZE)
    else:
        raise ValueError(f"Unsupported CIM_MODE: {CIM_MODE}")

    print("\nOutput Tensor:")
    print(output_tensor)

if __name__ == "__main__":
    main()
