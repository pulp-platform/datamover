import random
import argparse
import os

def generate_random_hex_32bit(size):
    """Generate random 32-bit hex values."""
    return [f"{random.randint(0, 2**32 - 1):08X}" for _ in range(size)]

def generate_addresses(start, d0_stride, d0_length, d1_stride, d1_length, transactions, N):
    """
    Generate addresses ensuring total transactions match, processing N words per transaction.
    Strides are adjusted with `>> 2` to align with word-based addressing.
    """
    addresses = []
    addr = start
    count = 0

    for d1 in range(d1_length):
        addr_d1 = addr + d1 * d1_stride
        for d0 in range(d0_length):
            addr_d0 = addr_d1 + d0 * d0_stride
            if addr_d0 + N <= MEMORY_SIZE:  # Ensure full block fits
                addresses.append([addr_d0 + i for i in range(N)])  # Read/Write N words
                count += 1
            if count == transactions:  # Stop when enough transactions are generated
                return addresses

    return addresses

def update_memory(memory, write_addresses, extracted_data):
    """Update memory with extracted data using generated write addresses, processing N words at a time."""
    for addr_block, data_block in zip(write_addresses, extracted_data):
        for addr, value in zip(addr_block, data_block):
            if addr < len(memory):
                memory[addr] = value  # Write N words at a time

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

    # Step 1: Generate initial memory
    memory = generate_random_hex_32bit(MEMORY_SIZE)

    # Convert byte-based to word-based ( >> 2)

    args.write_base_addr = args.write_base_addr >> 2
    args.read_base_addr = args.read_base_addr >> 2
    args.write_d0_stride = args.write_d0_stride >> 2
    args.write_d1_stride = args.write_d1_stride >> 2
    args.read_d0_stride = args.read_d0_stride >> 2
    args.read_d1_stride = args.read_d1_stride >> 2

    # Step 2: Generate read addresses (Word-aligned)
    read_transactions = args.read_d0_length * args.read_d1_length
    read_addresses = generate_addresses(
        args.read_base_addr, args.read_d0_stride, args.read_d0_length,
        args.read_d1_stride, args.read_d1_length, read_transactions, args.bandwidth_N
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
    write_addresses = generate_addresses(
        args.write_base_addr, args.write_d0_stride, args.write_d0_length,
        args.write_d1_stride, args.write_d1_length, write_transactions, args.bandwidth_N
    )

    # Step 7: Update memory with extracted data at write addresses
    update_memory(memory, write_addresses, extracted_data)

    # Step 8: Save updated memory
    write_file(args.output_dir, "updated_memory.txt", memory)

    print(f"Files generated in '{args.output_dir}': initial_memory.txt, debug_values.txt, updated_memory.txt")

if __name__ == "__main__":
    main()
