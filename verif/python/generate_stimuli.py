import random
import argparse
import os
import math

RANDOM_STIMULI = False  # If False, counting stimuli are generated in a counting fashion
WORD_ALIGNED = False     # If True, matrices are aligned to word boundaries by zero-padding

# ToDo(cdurrer): small matrices (N < BW) not working

def extract_elements_from_word(word, word_width, elem_width):
    """Extract elements from a word based on the specified widths."""
    word_int = int(word, 16)  # Convert hex string to integer
    elements = []
    for i in range(word_width // elem_width):
        # Extract each element using shift and mask
        elem_val = (word_int >> (i * elem_width)) & ((1 << elem_width) - 1)
        elements.append(elem_val)
    return elements

def convert_memory_to_vector(memory, elem_width, word_width):
    """Convert memory (list of hex words) to a flat vector of elements."""
    vector = []
    for word in memory:
        elements = extract_elements_from_word(word, word_width, elem_width)
        vector.extend(elements)
    return vector

def data_header_format(data, elements_per_line=16):
    lines = []
    for i in range(0, len(data), elements_per_line):
        line_elements = data[i:i + elements_per_line]
        formatted_elements = [f"0x{elem:02x}" for elem in line_elements]
        # Add comma except for the last element
        if i + elements_per_line < len(data):
            line = "  " + ", ".join(formatted_elements) + ","
        else:
            # Last line - no trailing comma
            line = "  " + ", ".join(formatted_elements)
        lines.append(line)
    return lines

def generate_random_hex(size, word_width):
    """Generate random word_width hex values."""
    hex_length = math.ceil(word_width / 4)  # Each hex digit represents 4 bits
    return [f"{random.randint(0, 2**word_width - 1):0{hex_length}X}" for _ in range(size)]

def generate_counting_hex(size, elem_width, word_width):
    """
    Generate counting series of hex values with specified element and word widths.
    Each word contains multiple elements in little-endian format.
    """
    elems_per_word = word_width // elem_width
    result = []
    for i in range(size):
        word_val = 0
        for j in range(elems_per_word):
            elem_val = (i * elems_per_word + j) & ((1 << elem_width) - 1)
            word_val |= (elem_val << (j * elem_width))
        result.append(f"{word_val:0{word_width // 4}X}")  # Format as hex string
    return result

def pack_elements_to_word(elements, elem_width, word_width):
    """Pack multiple elements into a single word."""
    elems_per_word = word_width // elem_width
    word_val = 0
    for i, elem in enumerate(elements[:elems_per_word]):  # Take only what fits in a word
        word_val |= (elem << (i * elem_width))
    return f"{word_val:0{word_width // 4}X}"

def matrix_to_hex_words(matrix, elem_width, word_width):
    """Convert a matrix of elements to a list of hex words."""
    elems_per_word = word_width // elem_width
    hex_words = []
    matrix_flat = sum(matrix, [])
    for i in range(math.ceil(len(matrix_flat) / elems_per_word)):
        hex_word = pack_elements_to_word(matrix_flat[i*elems_per_word:i*elems_per_word+elems_per_word], elem_width, word_width)
        hex_words.append(hex_word)
    return hex_words

def matrix_to_hex_words_word_aligned(matrix, elem_width, word_width):
    """Convert a matrix of elements to a list of hex words - aligned to word boundaries by zero-padding."""
    elems_per_word = word_width // elem_width
    hex_words = []
    for row in matrix:
        # Process each row, grouping elements into words
        for i in range(0, len(row), elems_per_word):
            elements_for_word = row[i:i + elems_per_word]

            # Pad with zeros if the row doesn't fill a complete word
            while len(elements_for_word) < elems_per_word:
                elements_for_word.append(0)

            # Pack elements into a word
            hex_word = pack_elements_to_word(elements_for_word, elem_width, word_width)
            hex_words.append(hex_word)
    return hex_words

def write_file(output_dir, filename, content):
    """Write list content to a file."""
    os.makedirs(output_dir, exist_ok=True)  # Ensure directory exists
    filepath = os.path.join(output_dir, filename)
    with open(filepath, "w") as file:
        file.write("\n".join(content) + "\n")

def write_data_header_file(output_dir, input_matrix, output_matrix, config_params):
    """Write input and output matrices to a C header file with configuration parameters."""
    os.makedirs(output_dir, exist_ok=True)  # Ensure directory exists
    filepath = os.path.join(output_dir, "data.h")
    size_m = len(input_matrix)
    size_n = len(input_matrix[0]) if size_m > 0 else 0

    input_flat = [elem for row in input_matrix for elem in row]
    output_flat = [elem for row in output_matrix for elem in row]

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
        f"#define MISALIGNED_ACCESSES {config_params['misaligned_accesses']}",
        f"#define DATAMOVER_MODE {config_params['datamover_mode']}",
        f"#define TRANSP_MODE {config_params['transp_mode']}",
        f"#define CIM_MODE {config_params['cim_mode']}",
        f"#define CIM_INNER_DIM {config_params['cim_inner_dim']}",
        f"#define CIM_OUTER_DIM {config_params['cim_outer_dim']}",
        f"#define SIZE_M {config_params['matrix_size_m']}",
        f"#define SIZE_N {config_params['matrix_size_n']}",
        "",
        "uint8_t golden_in [SIZE_M*SIZE_N] = {",
    ]
    data_h_string.extend(data_header_format(input_flat))
    data_h_string.extend([
        "};",
        "",
        "uint8_t golden_out [SIZE_M*SIZE_N] = {",
    ])
    data_h_string.extend(data_header_format(output_flat))
    data_h_string.extend([
        "};",
        ""
    ])
    with open(filepath, "w") as file:
        file.write("\n".join(data_h_string))
    return

def transpose(matrix, size_n, size_m, transp_mode):
    transposed = [[0 for _ in range(size_m * transp_mode)] for _ in range(size_n // transp_mode)]
    for d1 in range(size_m):
        for d0 in range(size_n // transp_mode):
            for i in range(transp_mode):
                # print(f"Transposing element [{d1}][{(d0*transp_mode)+i}] to [{d0}][{(d1*transp_mode)+i}]")
                transposed[d0][(d1*transp_mode)+i] = matrix[d1][(d0*transp_mode)+i]
    return transposed

def cim_layout(matrix, size_n, size_m, cim_mode, cim_inner_dim, cim_outer_dim):
    if cim_mode == 0:   # row-major -> A-Layout
        row_tile_size = cim_inner_dim
        initial_size_m = size_m
        initial_size_n = size_n
    elif cim_mode == 1:               # row-major -> B-Layout
        row_tile_size = cim_outer_dim
        initial_size_m = size_m
        initial_size_n = size_n
    elif cim_mode == 2:    # A-Layout -> row-major
        row_tile_size = cim_inner_dim
        initial_size_m = size_n // row_tile_size
        initial_size_n = size_m * row_tile_size
    elif cim_mode == 3:    # B-Layout -> row-major
        row_tile_size = cim_outer_dim
        initial_size_m = size_n // row_tile_size
        initial_size_n = size_m * row_tile_size
    else:
        raise ValueError("[GM] cim_mode must be 0 (A-Layout), 1 (B-Layout), 2 (A-Layout -> row-major), or 3 (B-Layout -> row-major).")

    print(f"initial_size_m: {initial_size_m}, initial_size_n: {initial_size_n}, row_tile_size: {row_tile_size}")
    cim_matrix = [[0 for _ in range(initial_size_m * row_tile_size)] for _ in range(initial_size_n // row_tile_size)]
    for d2 in range(initial_size_n // row_tile_size):
        for d1 in range(initial_size_m):
            cim_matrix[d2][(d1*row_tile_size):(d1*row_tile_size+row_tile_size)] = matrix[d1][d2*(row_tile_size):(d2*row_tile_size+row_tile_size)]

    # Reshape back to original dimensions for output

    print(f"CIM Matrix Size: {len(cim_matrix)} x {len(cim_matrix[0])}")

    return cim_matrix

def main():
        # Parse command-line arguments
    parser = argparse.ArgumentParser(description="Memory Read/Write Simulation with Word-Aligned Strides")
    parser.add_argument("--mem_size", type=int, default=0x30, help="Memory size in words")
    parser.add_argument("--read_base_addr", type=int, default=0x00, help="Base address for read operations")
    parser.add_argument("--write_base_addr", type=int, default=0x20, help="Base address for write operations")
    parser.add_argument("--bandwidth_bits", type=int, default=4, help="Number of bits per transaction")
    parser.add_argument("--num_elem_word", type=int, default=4, help="Number of elements in a memory bank word")
    parser.add_argument("--elem_width", type=int, default=8, help="Width of each element (in bits)")
    parser.add_argument("--misaligned_accesses", type=int, default=0, help="Enable misaligned accesses (0=disabled, 1=enabled)")
    parser.add_argument("--datamover_mode", type=int, default=0, help="Datamover mode (0=normal, 1=CIM)")
    parser.add_argument("--transp_mode", type=int, default=0, help="Transposition mode (3'b000 = none, 3'b001 = 1 elem, 3'b010 = 2 elem, 3'b100 = 4 elem)")
    parser.add_argument("--cim_mode", type=int, default=0, help="CIM mode (0=normal, 1=CIM)")
    parser.add_argument("--cim_inner_dim", type=int, default=4, help="CIM inner dimension")
    parser.add_argument("--cim_outer_dim", type=int, default=4, help="CIM outer dimension")
    parser.add_argument("--matrix_size_m", type=int, default=64, help="Matrix height in elements")
    parser.add_argument("--matrix_size_n", type=int, default=64, help="Matrix width in elements")
    parser.add_argument("--output_dir", type=str, default="output", help="Directory for storing output files")

    args = parser.parse_args()

    BANDWIDTH_ALIGNED = args.bandwidth_bits - (args.misaligned_accesses * (args.elem_width * args.num_elem_word))
    MEMORY_SIZE = args.mem_size  # Set global memory size
    BANDWIDTH_ELEMS = BANDWIDTH_ALIGNED // args.elem_width
    WORD_SIZE_BITS = args.num_elem_word * args.elem_width  # Set global word size in bits

    ELEM_WIDTH = args.elem_width
    WORD_WIDTH = args.num_elem_word * args.elem_width
    READ_BASE_ADDR = args.read_base_addr
    WRITE_BASE_ADDR = args.write_base_addr
    TRANSP_MODE = args.transp_mode
    MATRIX_SIZE_N = args.matrix_size_n
    MATRIX_SIZE_M = args.matrix_size_m
    TOT_LENGTH = (args.matrix_size_m * args.matrix_size_n) // BANDWIDTH_ELEMS

    OUTPUT_DIR = args.output_dir

    if MEMORY_SIZE < ((MATRIX_SIZE_N * MATRIX_SIZE_M * ELEM_WIDTH // WORD_WIDTH) * 2):
        raise ValueError(f"MEMORY_SIZE ({MEMORY_SIZE}) is too small for the given matrix size "
                    f"({MATRIX_SIZE_M}x{MATRIX_SIZE_N}) and element width ({ELEM_WIDTH})")
    # num_elem_word must be power of two and greater than zero
    if args.num_elem_word & (args.num_elem_word - 1) != 0 or args.num_elem_word <= 0:
        raise ValueError("[GM] num_elem_word must be a power of two and greater than zero.")
    # bandwidth width must be a multiple of word size
    if BANDWIDTH_ALIGNED % WORD_SIZE_BITS != 0:
        raise ValueError("[GM] BANDWIDTH_ALIGNED must be a multiple of the word size (num_elem_word * elem_width).")
    # # bandwidth width must be a multiple of word size
    # if ((MATRIX_SIZE_N * ELEM_WIDTH) < BANDWIDTH_ALIGNED):
    #     raise ValueError("[GM] Matrix width (N) in bits must be at least as large as BANDWIDTH_ALIGNED.")
    # read_tot_length must not exceed 12-bit register capacity (4096)

    # # BANDWIDTH_ALIGNED must be a power of 2
    # if ((BANDWIDTH_ALIGNED & (BANDWIDTH_ALIGNED - 1)) != 0) or (BANDWIDTH_ALIGNED < WORD_SIZE_BITS):
    #     raise ValueError(f"[GM] BANDWIDTH_ALIGNED ({BANDWIDTH_ALIGNED}) must be a power of 2 and greater than the WORD_SIZE ({WORD_SIZE_BITS}).")

    if ((TOT_LENGTH >= 4096) & (args.datamover_mode != 0)):
        raise ValueError("[GM] TOT_LENGTH (MxN / BW_ELEM) must be less than 4096 in transpose and CIM modes (12-bit register limit).")


    if(args.datamover_mode == 1): # transpose mode
        # transp_mode must be valid (1=1elem, 2=2elem, 4=4elem)
        if args.transp_mode not in [1, 2, 4]:
            raise ValueError("[GM] transp_mode must be 1 (1 elem), 2 (2 elem), or 4 (4 elem).")
        if (MATRIX_SIZE_N % args.transp_mode) != 0:
            raise ValueError(f"[GM] Matrix width N ({MATRIX_SIZE_N}) must be a multiple of transp_mode ({args.transp_mode}).")

    print(f"Memory Size: {MEMORY_SIZE} entries")
    print(f"Word Size: {WORD_SIZE_BITS} bits")

    # memory = generate_counting_hex(MEMORY_SIZE, ELEM_WIDTH, WORD_WIDTH)
    if RANDOM_STIMULI:
        memory = generate_random_hex(MEMORY_SIZE, WORD_SIZE_BITS)  # for testing
    else:
        memory = generate_counting_hex(MEMORY_SIZE, ELEM_WIDTH, WORD_WIDTH) # for debugging

    write_file(OUTPUT_DIR, "initial_memory.txt", memory)

    # Convert memory to flat vector
    memory_flat = convert_memory_to_vector(memory, ELEM_WIDTH, WORD_WIDTH)

    # Extract matrix (read dimensions) from memory
    input_matrix = [[0 for _ in range(MATRIX_SIZE_N)] for _ in range(MATRIX_SIZE_M)]
    for d1 in range(MATRIX_SIZE_M):
        row = []
        for d0 in range(MATRIX_SIZE_N):
            input_matrix[d1][d0] = memory_flat[(READ_BASE_ADDR + d1 * MATRIX_SIZE_N + d0)]

    # Print input matrix
    print("Input Matrix:")
    # # for i, row in enumerate(input_matrix):
    # #     print(f"Row {i}: {row}")
    # # print("\n")
    for i, row in enumerate(input_matrix):
        print(f"Row {i}: {[format(elem, 'X') for elem in row]}")

    if args.datamover_mode == 0: # Copy mode
        output_matrix = input_matrix
    elif args.datamover_mode == 1: # Transpose mode
        output_matrix = transpose(input_matrix, MATRIX_SIZE_N, MATRIX_SIZE_M, TRANSP_MODE)
    elif args.datamover_mode == 2: # CIM mode
        output_matrix = cim_layout(input_matrix, MATRIX_SIZE_N, MATRIX_SIZE_M, args.cim_mode, args.cim_inner_dim, args.cim_outer_dim)
    # elif args.datamover_mode == 2: # TEST CIM mode (TWICE: should be identical to input)
        # intermediate_matrix = cim_layout(input_matrix, MATRIX_SIZE_N, MATRIX_SIZE_M, args.cim_mode, args.cim_inner_dim, args.cim_outer_dim)
        # intermediate_size_m = len(intermediate_matrix)
        # intermediate_size_n = len(intermediate_matrix[0])
        # # Print intermediate matrix
        # print("\nIntermediate Matrix:")
        # for i, row in enumerate(intermediate_matrix):
        #     print(f"Row {i}: {[format(elem, 'X') for elem in row]}")
        # print("\n")
        # output_matrix = cim_layout(intermediate_matrix, intermediate_size_n, intermediate_size_m, args.cim_mode, args.cim_inner_dim, args.cim_outer_dim)
    elif args.datamover_mode == 3: # CIM layout transpose mode (INPUT SIZES EXPECTED IN ORIGINAL (ROW-MAJOR) LAYOUT FORM!)
        print("TRANSP_MODE = ", TRANSP_MODE)
        converted_size_m = MATRIX_SIZE_N // args.cim_inner_dim
        converted_size_n = MATRIX_SIZE_M * args.cim_inner_dim
        # Reshape input_matrix to converted_size_m x converted_size_n
        input_flat = [elem for row in input_matrix for elem in row]
        reshaped_matrix = [
            [input_flat[i * converted_size_n + j] for j in range(converted_size_n)]
            for i in range(converted_size_m)]
        print("\nReshaped Matrix:")
        for i, row in enumerate(reshaped_matrix):
            print(f"Row {i}: {[format(elem, 'X') for elem in row]}")
        print("\n")

        intermediate1_matrix = cim_layout(reshaped_matrix, converted_size_n, converted_size_m, args.cim_mode, args.cim_inner_dim, args.cim_outer_dim)
        intermediate1_size_m = len(intermediate1_matrix)
        intermediate1_size_n = len(intermediate1_matrix[0])

        print("\nIntermediate1 Matrix (CIM layout -> row-major):")
        for i, row in enumerate(intermediate1_matrix):
            print(f"Row {i}: {[format(elem, 'X') for elem in row]}")
        print("\n")
        intermediate2_matrix = transpose(intermediate1_matrix, intermediate1_size_n, intermediate1_size_m, TRANSP_MODE)
        intermediate2_size_m = len(intermediate2_matrix)
        intermediate2_size_n = len(intermediate2_matrix[0])
        print("\nIntermediate2 Matrix (row major transpose):")
        for i, row in enumerate(intermediate2_matrix):
            print(f"Row {i}: {[format(elem, 'X') for elem in row]}")
        print("\n")
        output_matrix = cim_layout(intermediate2_matrix, intermediate2_size_n, intermediate2_size_m, args.cim_mode, args.cim_inner_dim, args.cim_outer_dim)
    else:
        raise ValueError("[GM] datamover_mode must be 0 (copy), 1 (transpose), or 2 (CIM).")

    # Print output matrix
    print("\nOutput Matrix:")
    for i, row in enumerate(output_matrix):
        print(f"Row {i}: {[format(elem, 'X') for elem in row]}")
    print("\n")

    # Compare input and output matrix: equality check
    if (output_matrix == input_matrix):
        print("Output matrix matches input matrix.")

    # # Convert output matrix back to words
    if (WORD_ALIGNED):
        output_hex_words = matrix_to_hex_words_word_aligned(output_matrix, ELEM_WIDTH, WORD_WIDTH)
    else:
        output_hex_words = matrix_to_hex_words(output_matrix, ELEM_WIDTH, WORD_WIDTH)

    # print(f"\nOutput Matrix as Hex Words:")
    # for i, word in enumerate(output_hex_words):
    #     print(f"Word {i}: {word}")

    # Write back output matrix to memory at WRITE_BASE_ADDR
    for i, word in enumerate(output_hex_words):
        memory[(WRITE_BASE_ADDR // (WORD_WIDTH // 8) + i)] = word
        # print(f"Writing word {word} to memory address [Byte-address] {WRITE_BASE_ADDR + i * (WORD_WIDTH // 8)}")
        # print(f"Writing word {word} to memory address [Word-address] {WRITE_BASE_ADDR + i}")

    write_file(OUTPUT_DIR, "updated_memory.txt", memory)

    # Write data header file for C testing
    config_params = {
        'bandwidth': args.bandwidth_bits,
        'word_width': WORD_WIDTH,
        'elem_width': args.elem_width,
        'memory_size': args.mem_size,
        'misaligned_accesses': args.misaligned_accesses,
        'datamover_mode': args.datamover_mode,
        'transp_mode': args.transp_mode,
        'cim_mode': args.cim_mode,
        'cim_inner_dim': args.cim_inner_dim,
        'cim_outer_dim': args.cim_outer_dim,
        'matrix_size_m': args.matrix_size_m,
        'matrix_size_n': args.matrix_size_n
    }
    write_data_header_file(OUTPUT_DIR, input_matrix, output_matrix, config_params)

if __name__ == "__main__":
    main()
