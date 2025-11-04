import random
import argparse
import os

# OUTPUT_DIR = "generated"

# BANDWIDTH = 128     # in bits
# WORD_WIDTH = 32     # in bits
# ELEM_WIDTH = 8      # in bits
# MEMORY_SIZE = 512   # in words

# TRANSP_MODE = 4  # 0 = none, 1 = 1 elem, 2 = 2 elem, 4 = 4 elem

# NUM_ELEM_WORD = WORD_WIDTH // ELEM_WIDTH   # e.g., 4 for 32-bit words with 8-bit elements
# BANDWIDTH_ELEMS = BANDWIDTH // ELEM_WIDTH
# BANDWIDTH_WORDS = BANDWIDTH_ELEMS // NUM_ELEM_WORD

# MATRIX_SIZE_N = 16     # in elements
# MATRIX_SIZE_M = 4      # in elements

# READ_BASE_ADDR = 0  # in bytes
# READ_D0_LENGTH = MATRIX_SIZE_N // BANDWIDTH_ELEMS  # Nof accesses with bandwidth BW per D0-transfer ("row")
# READ_D1_LENGTH = MATRIX_SIZE_M

# WRITE_BASE_ADDR = 128  # in bytes
# WRITE_D0_LENGTH = READ_D1_LENGTH
# WRITE_D1_LENGTH = READ_D0_LENGTH

def extract_elements_from_word(word, word_width, elem_width):
    """Extract elements from a word based on the specified widths."""
    word_int = int(word, 16)  # Convert hex string to integer

    elements = []
    for i in range(word_width // elem_width):
        # Extract each element using shift and mask
        elem_val = (word_int >> (i * elem_width)) & ((1 << elem_width) - 1)
        elements.append(elem_val)
    return elements

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

def transpose(matrix, size_d0, size_d1, transp_mode):
    transposed = [[0 for _ in range(size_d1 * transp_mode)] for _ in range(size_d0 // transp_mode)]
    for d1 in range(size_d1):
        for d0 in range(size_d0 // transp_mode):
            for i in range(transp_mode):
                transposed[d0][(d1*transp_mode)+i] = matrix[d1][(d0*transp_mode)+i]
    return transposed

def main():
        # Parse command-line arguments
    parser = argparse.ArgumentParser(description="Memory Read/Write Simulation with Word-Aligned Strides")
    parser.add_argument("--mem_size", type=int, default=0x30, help="Memory size in entries")
    parser.add_argument("--read_base_addr", type=int, default=0x00, help="Base address for read operations")
    parser.add_argument("--write_base_addr", type=int, default=0x20, help="Base address for write operations")
    parser.add_argument("--read_d0_stride", type=int, default=4, help="Stride for d0 read (in bytes)")
    parser.add_argument("--read_d1_stride", type=int, default=16, help="Stride for d1 read (in bytes)")
    parser.add_argument("--read_d0_length", type=int, default=4, help="Length for d0 read")
    parser.add_argument("--read_d1_length", type=int, default=4, help="Length for d1 read")
    parser.add_argument("--write_d0_stride", type=int, default=4, help="Stride for d0 write (in bytes)")
    parser.add_argument("--write_d1_stride", type=int, default=16, help="Stride for d1 write (in bytes)")
    parser.add_argument("--write_d0_length", type=int, default=4, help="Length for d0 write")
    parser.add_argument("--write_d1_length", type=int, default=4, help="Length for d1 write")
    parser.add_argument("--bandwidth_bits", type=int, default=4, help="Number of bits per transaction")
    parser.add_argument("--num_elem_word", type=int, default=4, help="Number of elements in a memory bank word")
    parser.add_argument("--elem_width", type=int, default=8, help="Width of each element (in bits)")
    parser.add_argument("--transp_mode", type=int, default=0, help="Transposition mode (3'b000 = none, 3'b001 = 1 elem, 3'b010 = 2 elem, 3'b100 = 4 elem)")
    parser.add_argument("--transp_len", type=int, default=0, help="Transposition length")
    parser.add_argument("--output_dir", type=str, default="output", help="Directory for storing output files")

    args = parser.parse_args()

    MEMORY_SIZE = args.mem_size  # Set global memory size
    BANDWIDTH_ELEMS = args.bandwidth_bits // args.elem_width
    BANDWIDTH_WORDS = BANDWIDTH_ELEMS // args.num_elem_word
    WORD_SIZE_BITS = args.num_elem_word * args.elem_width  # Set global word size in bits

    ELEM_WIDTH = args.elem_width
    WORD_WIDTH = args.num_elem_word * args.elem_width
    NUM_ELEM_WORD = args.num_elem_word
    READ_BASE_ADDR = args.read_base_addr
    READ_D0_LENGTH = args.read_d0_length
    READ_D1_LENGTH = args.read_d1_length
    WRITE_BASE_ADDR = args.write_base_addr
    TRANSP_MODE = args.transp_mode
    # MATRIX_SIZE_N = READ_D0_LENGTH * BANDWIDTH_ELEMS
    # MATRIX_SIZE_M = READ_D1_LENGTH
    MATRIX_SIZE_N = READ_D1_LENGTH * BANDWIDTH_ELEMS
    MATRIX_SIZE_M = READ_D0_LENGTH

    OUTPUT_DIR = args.output_dir

    # num_elem_word must be power of two and greater than zero
    if args.num_elem_word & (args.num_elem_word - 1) != 0 or args.num_elem_word <= 0:
        raise ValueError("num_elem_word must be a power of two and greater than zero.")
    # bandwidth width must be a multiple of word size
    if args.bandwidth_bits % WORD_SIZE_BITS != 0:
        raise ValueError("bandwidth_bits must be a multiple of the word size (num_elem_word * elem_width).")


    print(f"Memory Size: {MEMORY_SIZE} entries")
    print(f"Word Size: {WORD_SIZE_BITS} bits")

    # memory = generate_counting_hex(MEMORY_SIZE, ELEM_WIDTH, WORD_WIDTH)
    memory = generate_counting_hex(MEMORY_SIZE, ELEM_WIDTH*TRANSP_MODE, WORD_WIDTH)

    write_file(OUTPUT_DIR, "initial_memory.txt", memory)

    # Extract matrix (read dimensions) from memory
    input_matrix = []
    for d1 in range(MATRIX_SIZE_M):
        row = []
        for d0 in range(MATRIX_SIZE_N // NUM_ELEM_WORD):
            word = memory[(READ_BASE_ADDR // (WORD_WIDTH // 8) + d1 * (MATRIX_SIZE_N // NUM_ELEM_WORD) + d0)]
            word_elements = extract_elements_from_word(word, NUM_ELEM_WORD*ELEM_WIDTH, ELEM_WIDTH)
            for elem in range(NUM_ELEM_WORD):
                row.append(word_elements[elem])
        input_matrix.append(row)

    # Print input matrix
    print("Input Matrix:")
    for i, row in enumerate(input_matrix):
        print(f"Row {i}: {row}")
    print("\n")
    for i, row in enumerate(input_matrix):
        print(f"Row {i}: {[format(elem, 'X') for elem in row]}")

    # for d0 in range(d0_length):
    #     for d1 in range(d1_length):
    #         input_matrix[d0][d1] = d0*d1_length + d1
    # print("Input Matrix:")
    # for row in input_matrix:
    #     print(row)

    transposed_matrix = transpose(input_matrix, MATRIX_SIZE_N, MATRIX_SIZE_M, TRANSP_MODE)
    print("\nTransposed Matrix:")
    for i, row in enumerate(transposed_matrix):
        print(f"Row {i}: {row}")
    print("\n")
    for i, row in enumerate(transposed_matrix):
        print(f"Row {i}: {[format(elem, 'X') for elem in row]}")

    # Convert transposed matrix back to words
    transposed_hex_words = matrix_to_hex_words(transposed_matrix, ELEM_WIDTH, WORD_WIDTH)
    # print(f"\nTransposed Matrix as Hex Words:")
    # for i, word in enumerate(transposed_hex_words):
    #     print(f"Word {i}: {word}")

    # Write back transposed matrix to memory at WRITE_BASE_ADDR
    for i, word in enumerate(transposed_hex_words):
        print(f"Writing word {word} to memory address {WRITE_BASE_ADDR + i * (WORD_WIDTH // 8)}")
        memory[(WRITE_BASE_ADDR // (WORD_WIDTH // 8) + i)] = word
        # print(f"Writing word {word} to memory address {WRITE_BASE_ADDR + i}")

    write_file(OUTPUT_DIR, "updated_memory.txt", memory)

if __name__ == "__main__":
    main()
