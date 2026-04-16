import os
import math
import numpy as np

RANDOM_STIMULI = True  # If False, stimuli are generated in a counting fashion for easier debugging

CHANNELS = 32
HEIGHT = 32
WIDTH = 32
PATCH_SIZE = 4      # MobileViT: 2x2 = 4 (square) (not tested for other patch sizes)

# data.h generation parameters
BANDWIDTH = 512
WORD_WIDTH = 64
ELEM_WIDTH = 8
MEMORY_SIZE = 131072
DATAMOVER_MODE = 5        # 0: copy, 1: transpose, 2: CIM data layout conversion, 3: CIM layout transpose, 4: unfold (MobileViT), 5: fold (MobileViT), other values: not accepted
TRANSP_MODE = 1
CIM_MODE = 0
ROW_TILE_SIZE = 64
SIZE_C = CHANNELS
SIZE_M = HEIGHT
SIZE_N = WIDTH

def data_header_format(data, elements_per_line=16):
    lines = []
    for i in range(0, len(data), elements_per_line):
        line_elements = data[i:i + elements_per_line]
        formatted_elements = [f"0x{elem:02x}" for elem in line_elements]
        if i + elements_per_line < len(data):
            line = "  " + ", ".join(formatted_elements) + ","
        else:
            line = "  " + ", ".join(formatted_elements)
        lines.append(line)
    return lines


def write_data_header_file(output_dir, input_matrix, output_matrix, config_params):
    os.makedirs(output_dir, exist_ok=True)
    filepath = os.path.join(output_dir, "data.h")

    input_flat = np.asarray(input_matrix, dtype=np.uint8).reshape(-1).tolist()
    output_flat = np.asarray(output_matrix, dtype=np.uint8).reshape(-1).tolist()

    data_h_string = [
        "#pragma once",
        "",
        "#include <stdint.h>",
        "",
        "// Configuration Parameters",
        f"#define BANDWIDTH {config_params['bandwidth']}",
        f"#define WORD_WIDTH {config_params['word_width']}",
        f"#define ELEM_WIDTH {config_params['elem_width']}",
        f"#define MEMORY_SIZE {config_params['memory_size']}",
        f"#define DATAMOVER_MODE {config_params['datamover_mode']}",
        f"#define TRANSP_MODE {config_params['transp_mode']}",
        f"#define CIM_MODE {config_params['cim_mode']}",
        f"#define ROW_TILE_SIZE {config_params['row_tile_size']}",
        f"#define SIZE_C {config_params['size_c']}",
        f"#define SIZE_M {config_params['size_m']}",
        f"#define SIZE_N {config_params['size_n']}",
        "",
        "PI_L1 uint8_t golden_in [SIZE_C*SIZE_M*SIZE_N] = {",       # PI_L1 only for GVSoC (siracusa)
    ]
    data_h_string.extend(data_header_format(input_flat))
    data_h_string.extend([
        "};",
        "",
        "PI_L1 uint8_t golden_out [SIZE_C*SIZE_M*SIZE_N] = {",      # PI_L1 only for GVSoC (siracusa)
    ])
    data_h_string.extend(data_header_format(output_flat))
    data_h_string.extend([
        "};",
        "",
    ])

    with open(filepath, "w", encoding="utf-8") as file:
        file.write("\n".join(data_h_string))

    return filepath


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

def fold(tensor, patch_size, num_channels, height, width):  # Parameters: output tensor dimensions (CHW)
    # Input tensor shape: (PATCH_SIZE, NUM_PATCHES, CHANNELS) -- calculated from output dimensions
    # Output tensor shape: (CHANNELS, HEIGHT, WIDTH) -- num_channels, height, width are the folded dimensions
    patch_sidelength = int(math.sqrt(patch_size))
    # size_n = (height * width) // patch_size
    assert (height % patch_sidelength == 0) and (width % patch_sidelength == 0), "Height and Width must be divisible by patch sidelength"
    num_patches_h = height // patch_sidelength
    num_patches_w = width // patch_sidelength
    tensor_folded = np.zeros((num_channels, height, width), dtype=tensor.dtype)
    for p in range(patch_size):
        for h in range(num_patches_h):
            for w in range(num_patches_w):
                n = h * num_patches_w + w
                h_idx = h * patch_sidelength + (p // patch_sidelength)
                w_idx = w * patch_sidelength + (p % patch_sidelength)
                tensor_folded[:, h_idx, w_idx] = tensor[p, n, :]
    return tensor_folded

def main():
    # Check configuration
    required_elements = 3 * CHANNELS * HEIGHT * WIDTH
    assert required_elements <= MEMORY_SIZE, (
        f"MEMORY_SIZE ({MEMORY_SIZE}) is too small: requires at least "
        f"3*CHANNELS*HEIGHT*WIDTH = {required_elements} elements"
    )

    # Create a tensor of size (CHANNELS, HEIGHT, WIDTH) with random or counting values
    if RANDOM_STIMULI:
        input_tensor = np.random.randint(0, 256, (CHANNELS, HEIGHT, WIDTH), dtype=np.uint8)
    else:
        input_tensor = np.arange(CHANNELS * HEIGHT * WIDTH, dtype=np.uint8).reshape((CHANNELS, HEIGHT, WIDTH))
    print("Input Tensor:")
    print(input_tensor)
    if DATAMOVER_MODE==0:
        output_tensor = input_tensor.copy()
    elif DATAMOVER_MODE==1:
        output_tensor = np.transpose(input_tensor, (0, 2, 1))
    # elif DATAMOVER_MODE==2:
    #     output_tensor = cim_layout(input_tensor, )
    # elif DATAMOVER_MODE==3:
    #     output_tensor = cim_transpose(input_tensor, )
    elif DATAMOVER_MODE==4:
        output_tensor = unfold(input_tensor, PATCH_SIZE)
    elif DATAMOVER_MODE==5:
        # For fold mode, generate the input as an unfolded tensor by first unfolding a counting tensor
        # base_tensor = np.arange(CHANNELS * HEIGHT * WIDTH, dtype=np.uint8).reshape((CHANNELS, HEIGHT, WIDTH))
        unfolded_tensor = unfold(input_tensor, PATCH_SIZE)
        input_tensor = unfolded_tensor.copy()  # Use the unfolded tensor as input for fold mode
        print("\nUnfolded Tensor (input for fold mode):")
        print(unfolded_tensor)
        output_tensor = fold(unfolded_tensor, PATCH_SIZE, CHANNELS, HEIGHT, WIDTH)
    else:
        raise ValueError(f"Unsupported DATAMOVER_MODE: {DATAMOVER_MODE}")

    print("\nOutput Tensor:")
    print(output_tensor)

    output_dir = os.path.join(os.path.dirname(__file__), "generated")
    config_params = {
        "bandwidth": BANDWIDTH,
        "word_width": WORD_WIDTH,
        "elem_width": ELEM_WIDTH,
        "memory_size": MEMORY_SIZE,
        "datamover_mode": DATAMOVER_MODE,
        "transp_mode": TRANSP_MODE,
        "cim_mode": CIM_MODE,
        "row_tile_size": ROW_TILE_SIZE,
        "size_c": SIZE_C,
        "size_m": SIZE_M,
        "size_n": SIZE_N,
    }
    header_file = write_data_header_file(output_dir, input_tensor, output_tensor, config_params)
    print(f"\nWrote golden header to: {header_file}")

if __name__ == "__main__":
    main()
