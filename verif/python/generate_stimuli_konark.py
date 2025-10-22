import random
import argparse
import os

def generate_random_hex_32bit(size):
    """Generate random 32-bit hex values."""
    return [f"{random.randint(0, 2**32 - 1):08X}" for _ in range(size)]

def generate_counting_words_hex_32bit(size):
    """Generate counting series of 32-bit hex values (0, 1, 2, 3, ...)."""
    return [f"{i:08X}" for i in range(size)]

def generate_counting_bytes_hex_32bit(size):
    """Generate counting series of 32-bit hex values (0, 1, 2, 3, ...)."""
    return [f"{(i*4):08X}" for i in range(size)]

# def generate_counting_bytes_hex_32bit(size):
#     """Generate counting series packed as 32-bit hex values (byte-wise counting in little-endian format).
#     Example: 03020100, 07060504, 0B0A0908, ...
#     """
#     result = []
#     for i in range(size):
#         # Pack 4 consecutive bytes into a 32-bit word (little-endian)
#         byte0 = (i * 4 + 0) & 0xFF
#         byte1 = (i * 4 + 1) & 0xFF
#         byte2 = (i * 4 + 2) & 0xFF
#         byte3 = (i * 4 + 3) & 0xFF
#         # Pack as little-endian: [byte3][byte2][byte1][byte0]
#         word = (byte3 << 24) | (byte2 << 16) | (byte1 << 8) | byte0
#         result.append(f"{word:08X}")
#     return result

def generate_addresses(start, d0_stride, d0_length, d1_stride, d1_length, d2_stride, d2_length, transactions, N):
    """
    Generate addresses ensuring total transactions match, processing N words per transaction.
    Strides are adjusted with `>> 2` to align with word-based addressing.
    """
    addresses = []
    addr = start
    count = 0

    print(f"Generating addresses starting from {hex(start)} with N={N} words per transaction")
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

def update_memory(memory, write_addresses, extracted_data):
    """Update memory with extracted data using generated write addresses, processing N words at a time."""
    for addr_block, data_block in zip(write_addresses, extracted_data):
        for addr, value in zip(addr_block, data_block):
            if addr < len(memory):
                memory[addr] = value  # Write N words at a time
                print(f"Writing value {value} to address {hex(addr)}")

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
    parser.add_argument("--bandwidth_N", type=int, default=4, help="Number of words per transaction")
    parser.add_argument("--output_dir", type=str, default="output", help="Directory for storing output files")

    args = parser.parse_args()

    global MEMORY_SIZE
    MEMORY_SIZE = args.mem_size  # Set global memory size

    print(f"Memory Size: {MEMORY_SIZE} entries")

    # Step 1: Generate initial memory
    # memory = generate_random_hex_32bit(MEMORY_SIZE)
    memory = generate_counting_bytes_hex_32bit(MEMORY_SIZE)  # For debugging purposes

    # Convert byte-based to word-based ( >> 2)

    args.write_base_addr = args.write_base_addr >> 2
    args.read_base_addr = args.read_base_addr >> 2
    args.write_d0_stride = args.write_d0_stride >> 2
    args.write_d1_stride = args.write_d1_stride >> 2
    args.read_d0_stride = args.read_d0_stride >> 2
    args.read_d1_stride = args.read_d1_stride >> 2

    read_d2_length = 4
    read_d2_stride = 64 >> 2
    write_d2_length = 4
    write_d2_stride = 4352 >> 2

    # Step 2: Generate read addresses (Word-aligned)
    read_transactions = args.read_d0_length * args.read_d1_length * read_d2_length
    read_addresses = generate_addresses(args.read_base_addr, args.read_d0_stride, args.read_d0_length,
        args.read_d1_stride, args.read_d1_length, read_d2_stride, read_d2_length, read_transactions, args.bandwidth_N)

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
    write_addresses = generate_addresses(
        args.write_base_addr, args.write_d0_stride, args.write_d0_length,
        args.write_d1_stride, args.write_d1_length, write_d2_stride, write_d2_length, write_transactions, args.bandwidth_N
    )

    # Step 7: Update memory with extracted data at write addresses
    update_memory(memory, write_addresses, extracted_data)

    # Step 8: Save updated memory
    write_file(args.output_dir, "updated_memory.txt", memory)

    print(f"Files generated in '{args.output_dir}': initial_memory.txt, debug_values.txt, updated_memory.txt")

if __name__ == "__main__":
    main()
