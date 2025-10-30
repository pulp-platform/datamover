import random
import argparse
import os

def generate_random_hex_32bit(size):
    """Generate random WORD_SIZE_BITS hex values."""
    def ceildiv(a, b):
        return -(a // -b)
    hex_length = ceildiv(WORD_SIZE_BITS, 4)  # Each hex digit represents 4 bits
    return [f"{random.randint(0, 2**WORD_SIZE_BITS - 1):0{hex_length}X}" for _ in range(size)]

def generate_counting_hex_32bit(size):
    """Generate counting series of 32-bit hex values (0, 1, 2, 3, ...)."""
    return [f"{(i*4):08X}" for i in range(size)]

def generate_counting_hex_8bit(size):
    """
    Generate counting series of 32-bit hex values with 8-bit increments.
    Each 32-bit word contains 4 consecutive 8-bit values in little-endian format.
    Example: 03020100, 07060504, 0B0A0908, 0F0E0D0C, ...
    """
    result = []
    for i in range(size):
        # Each word contains 4 consecutive bytes
        base = i * 4
        byte0 = (base + 0) & 0xFF
        byte1 = (base + 1) & 0xFF
        byte2 = (base + 2) & 0xFF
        byte3 = (base + 3) & 0xFF

        # Pack in little-endian format: byte3|byte2|byte1|byte0
        word = (byte3 << 24) | (byte2 << 16) | (byte1 << 8) | byte0
        result.append(f"{word:08X}")

    return result

def generate_addresses_2d(start, d0_stride, d0_length, d1_stride, d1_length, transactions, N):
    """
    Generate addresses ensuring total transactions match, processing N words per transaction.
    Strides are already adjusted with `>> elem_offset_bit` to align with word-based addressing.
    """
    addresses = []
    addr = start
    count = 0

    print(f"Generating addresses (2D) starting from {hex(4*start)} [Byte Address] with N={N} words per transaction")
    print(f"d0_stride: {d0_stride}, d0_length: {d0_length}, d1_stride: {d1_stride}, d1_length: {d1_length}")

    for d1 in range(d1_length):
        addr_d1 = addr + d1 * d1_stride
        print(f"Generating addresses for d1={d1} at {hex(4*addr_d1)} [Byte Address]")
        for d0 in range(d0_length):
            addr_d0 = addr_d1 + d0 * d0_stride      # ToDo(cdurrer): shouldnt this be addr_d1* + d0 * d0_stride?
            if addr_d0 + N <= MEMORY_SIZE:  # Ensure full block fits
                block = [addr_d0 + i for i in range(N)]
                print(f"  Appending address block: {', '.join(hex(4*a) for a in block)} [Byte Addresses]")
                addresses.append([addr_d0 + i for i in range(N)])  # Read/Write N words
                count += 1
            else:
                print(f"  Warning: Address block starting at {hex(4*addr_d0)} exceeds memory size. Skipping. [Byte Address]")
            if count == transactions:  # Stop when enough transactions are generated
                print(f"Transaction limit reached! Generated total of {count} transactions.")
                return addresses

    return addresses

def generate_addresses_3d(start, d0_stride, d0_length, d1_stride, d1_length, d2_stride, d2_length, transactions, N):
    """
    Generate addresses ensuring total transactions match, processing N words per transaction.
    Strides are adjusted with `>> 2` to align with word-based addressing.
    """
    addresses = []
    addr = start
    count = 0

    print(f"Generating addresses (3D) starting from {hex(start)} with N={N} words per transaction")
    print(f"d0_stride: {d0_stride}, d0_length: {d0_length}, d1_stride: {d1_stride}, d1_length: {d1_length}, d2_stride: {d2_stride}, d2_length: {d2_length}")

    for d2 in range(d2_length):
        addr_d2 = addr + d2 * d2_stride
        # print(f"Generating addresses for d2={d2} at {hex(addr_d2)}")
        print(f"Generating addresses for d2={d2} at {hex(4*addr_d2)} [Byte Address]")
        for d1 in range(d1_length):
            addr_d1 = addr_d2 + d1 * d1_stride
            # print(f"Generating addresses for d1={d1} at {hex(addr_d1)}")
            print(f"  Generating addresses for d1={d1} at {hex(4*addr_d1)} [Byte Address]")
            for d0 in range(d0_length):
                addr_d0 = addr_d1 + d0 * d0_stride      # ToDo(cdurrer): shouldnt this be addr_d1* + d0 * d0_stride?
                if addr_d0 + N <= MEMORY_SIZE:  # Ensure full block fits
                    block = [addr_d0 + i for i in range(N)]
                    # print(f"Appending address block: {', '.join(hex(a) for a in block)}")
                    print(f"    Appending address block: {', '.join(hex(4*a) for a in block)} [Byte Addresses]")
                    addresses.append([addr_d0 + i for i in range(N)])  # Read/Write N words
                    count += 1
                else:
                    # print(f"Warning: Address block starting at {hex(addr_d0)} exceeds memory size. Skipping.")
                    print(f"    Warning: Address block starting at {hex(4*addr_d0)} exceeds memory size. Skipping. [Byte Address]")
                if count == transactions:  # Stop when enough transactions are generated
                    print(f"Transaction limit reached! Generated total of {count} transactions.")
                    return addresses

    return addresses

def generate_addresses_transpose_read(read_start, d0_length, d1_length, transp_len, transactions, transp_mode, N):
    """
    Generate addresses for transposed access patterns.
    Strides are already adjusted with `>> elem_offset_bit` to align with word-based addressing.
    """
    read_addresses = []
    count = 0

    print(f"Generating read addresses (Transpose Mode {transp_mode})")
    print(f"d0_length: {d0_length}, d1_length: {d1_length}, N={N} words per transaction")

    for d1 in range(d1_length):
        # addr_d1 = addr + d1 * d0_length*transp_mode  # In transpose, d1 stride is d0_length
        # print(f"Generating addresses for d1={d1} at {hex(4*addr_d1)} [Byte Address]")
        for d0 in range(d0_length):
            # addr_d0 = addr_d1 + d0  # In transpose, d0 stride is 1
            read_addr = read_start + d1*(d0_length*N) + d0
            if (read_addr + N <= MEMORY_SIZE):  # Ensure full block fits
                read_block = [read_addr + i for i in range(N)]
                read_addresses.append(read_block)

                # Debug prints showing the actual appended address blocks
                read_byte_addrs = [hex(4*addr) for addr in read_block]
                print(f"  Appending read address block: {', '.join(read_byte_addrs)} [Byte Addresses]")

                count += 1
            else:
                print(f"  Warning: Read/Write address block starting at {hex(4*read_addr)} exceeds memory size. Skipping. [Byte Address]")
            if count == transactions:  # Stop when enough transactions are generated
                print(f"Transaction limit reached! Generated total of {count} transactions.")
                return read_addresses
    return read_addresses

def generate_addresses_transpose_write(write_start, d0_length, d1_length, transp_len, transactions, transp_mode, N):
    """
    Generate addresses for transposed access patterns.
    Strides are already adjusted with `>> elem_offset_bit` to align with word-based addressing.
    """
    write_addresses = []
    count = 0

    print(f"Generating write addresses (Transpose Mode {transp_mode})")
    print(f"d0_length: {d0_length}, d1_length: {d1_length}, N={N} words per transaction")

    for d1 in range(d1_length):
        # addr_d1 = addr + d1 * d0_length*transp_mode  # In transpose, d1 stride is d0_length
        # print(f"Generating addresses for d1={d1} at {hex(4*addr_d1)} [Byte Address]")
        for d0 in range(d0_length):
            # addr_d0 = addr_d1 + d0  # In transpose, d0 stride is 1
            write_addr = write_start + d0*(d1_length*N) + (d1*N)
            if (write_addr + N <= MEMORY_SIZE):  # Ensure full block fits
                write_block = [write_addr + i for i in range(N)]
                write_addresses.append(write_block)

                # Debug prints showing the actual appended address blocks
                write_byte_addrs = [hex(4*addr) for addr in write_block]
                print(f"  Appending write address block: {', '.join(write_byte_addrs)} [Byte Addresses]")

                count += 1
            else:
                print(f"  Warning: Read/Write address block starting at {hex(4*write_addr)} exceeds memory size. Skipping. [Byte Address]")
            if count == transactions:  # Stop when enough transactions are generated
                print(f"Transaction limit reached! Generated total of {count} transactions.")
                return write_addresses
    return write_addresses


def update_memory(memory, write_addresses, extracted_data):
    """Update memory with extracted data using generated write addresses, processing N words at a time."""
    for addr_block, data_block in zip(write_addresses, extracted_data):
        for addr, value in zip(addr_block, data_block):
            if addr < len(memory):
                memory[addr] = value  # Write N words at a time
                print(f"Writing value {value} to address {hex(4*addr)}")

def write_file(output_dir, filename, content):
    """Write list content to a file."""
    os.makedirs(output_dir, exist_ok=True)  # Ensure directory exists
    filepath = os.path.join(output_dir, filename)
    with open(filepath, "w") as file:
        file.write("\n".join(content) + "\n")

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

    global MEMORY_SIZE
    global WORD_SIZE_BITS
    MEMORY_SIZE = args.mem_size  # Set global memory size
    WORD_SIZE_BITS = args.num_elem_word * args.elem_width  # Set global word size in bits

    # num_elem_word must be power of two and greater than zero
    if args.num_elem_word & (args.num_elem_word - 1) != 0 or args.num_elem_word <= 0:
        raise ValueError("num_elem_word must be a power of two and greater than zero.")
    # bandwidth width must be a multiple of word size
    if args.bandwidth_bits % WORD_SIZE_BITS != 0:
        raise ValueError("bandwidth_bits must be a multiple of the word size (num_elem_word * elem_width).")
    # no transposition currently supported
    # if args.transp_mode != 0:
    #     raise NotImplementedError("Transposition modes other than 'none' are not currently supported.")

    bandwidth_N = args.bandwidth_bits // WORD_SIZE_BITS

    print(f"Memory Size: {MEMORY_SIZE} entries")

    # Step 1: Generate initial memory
    # memory = generate_random_hex_32bit(MEMORY_SIZE)  # For testing
    # memory = generate_counting_hex_32bit(MEMORY_SIZE)  # For debugging
    memory = generate_counting_hex_8bit(MEMORY_SIZE)  # For debugging with 8-bit elements

    # Convert addresses from element-addressing (e.g., byte-addressing) to word-addressing
    elem_offset_bit = (args.num_elem_word).bit_length() - 1

    args.write_base_addr = args.write_base_addr >> elem_offset_bit
    args.read_base_addr = args.read_base_addr >> elem_offset_bit
    args.write_d0_stride = args.write_d0_stride >> elem_offset_bit
    args.write_d1_stride = args.write_d1_stride >> elem_offset_bit
    args.read_d0_stride = args.read_d0_stride >> elem_offset_bit
    args.read_d1_stride = args.read_d1_stride >> elem_offset_bit

    if (args.transp_mode == 0):

        # Step 2: Generate read addresses (Word-aligned)
        read_transactions = args.read_d0_length * args.read_d1_length
        read_addresses = generate_addresses_2d(
            args.read_base_addr, args.read_d0_stride, args.read_d0_length,
            args.read_d1_stride, args.read_d1_length, read_transactions, bandwidth_N
        )

        # Step 3: Extract memory values based on read addresses
        extracted_data = [[memory[addr] for addr in block] for block in read_addresses if all(addr < MEMORY_SIZE for addr in block)]

        # Step 4: Save initial memory
        write_file(args.output_dir, "initial_memory.txt", memory)

        # Step 5: Save debug info (addresses read and values extracted)
        debug_info = [
            f"Read Block: {', '.join(hex(addr) for addr in block)} -> Data: {', '.join(memory[addr] for addr in block)}"
            for block in read_addresses if all(addr < MEMORY_SIZE for addr in block)
        ]
        write_file(args.output_dir, "debug_values.txt", debug_info)

        # Step 6: Generate write addresses (Word-aligned)
        write_transactions = read_transactions
        write_addresses = generate_addresses_2d(args.write_base_addr, args.write_d0_stride, args.write_d0_length, args.write_d1_stride, args.write_d1_length, write_transactions, bandwidth_N)

    else:       # Transpose mode
        print(f"Transposition mode {args.transp_mode} selected.")
        if (args.transp_len == 0):
            args.transp_len = args.bandwidth_bits // args.elem_width

        # Step 2: Generate read addresses (Word-aligned)
        read_transactions = args.read_d0_length * args.read_d1_length
        read_addresses = generate_addresses_transpose_read(args.read_base_addr, args.read_d0_length, args.read_d1_length, args.transp_len, read_transactions, args.transp_mode, bandwidth_N)
        write_addresses = generate_addresses_transpose_write(args.write_base_addr, args.write_d0_length, args.write_d1_length, args.transp_len, read_transactions, args.transp_mode, bandwidth_N)

        # Step 3: Extract memory values based on read addresses
        extracted_data = [[memory[addr] for addr in block] for block in read_addresses if all(addr < MEMORY_SIZE for addr in block)]

        # Step 4: Save initial memory
        write_file(args.output_dir, "initial_memory.txt", memory)

    # Step 7: Update memory with extracted data at write addresses
    update_memory(memory, write_addresses, extracted_data)

    # Step 8: Save updated memory
    write_file(args.output_dir, "updated_memory.txt", memory)

    print(f"Files generated in '{args.output_dir}': initial_memory.txt, debug_values.txt, updated_memory.txt")

if __name__ == "__main__":
    main()
