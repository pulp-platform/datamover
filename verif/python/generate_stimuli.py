import random
import argparse
import os 

def generate_random_hex_32bit(size):
    """Generate random 32-bit hex values."""
    return [f"{random.randint(0, 2**32 - 1):08X}" for _ in range(size)]

def generate_addresses(start, d0_stride, d0_length, d1_stride, d1_length, transactions):
    """Generate addresses based on stride and length, ensuring total transactions match."""
    addresses = []
    addr = start
    count = 0

    for d1 in range(d1_length):
        addr_d1 = addr + d1 * d1_stride
        for d0 in range(d0_length):  # Ensures equal number of transactions
            addr_d0 = addr_d1 + d0 * d0_stride
            if addr_d0 < MEMORY_SIZE:  # Prevent out-of-bounds
                addresses.append(addr_d0)
                count += 1
            if count == transactions:  # Stop when threshold for number of transactions are met
                return addresses
    
    return addresses

def update_memory(memory, write_addresses, extracted_data):
    """Update memory with extracted data using generated write addresses."""
    for addr, value in zip(write_addresses, extracted_data):
        if addr < len(memory):
            memory[addr] = value

def write_file(output_dir, filename, content):
    """Write list content to a file."""
    os.makedirs(output_dir, exist_ok=True)  # Ensure directory exists, if not create one
    filepath = os.path.join(output_dir, filename)
    with open(filepath, "w") as file:
        file.write("\n".join(content) + "\n")

def main():
    # Parse command-line arguments
    parser = argparse.ArgumentParser(description="Memory Read/Write Simulation")
    parser.add_argument("--mem_size", type=int, default=0x30, help="Memory size in entries")
    parser.add_argument("--read_base_addr", type=int, default=0x00, help="Base address for read operations")
    parser.add_argument("--write_base_addr", type=int, default=0x20, help="Base address for write operations")
    parser.add_argument("--read_d0_stride", type=int, default=1, help="Stride for d0 read")
    parser.add_argument("--read_d1_stride", type=int, default=4, help="Stride for d1 read")
    parser.add_argument("--read_d0_length", type=int, default=4, help="Length for d0 read")
    parser.add_argument("--read_d1_length", type=int, default=4, help="Length for d1 read")
    parser.add_argument("--write_d0_stride", type=int, default=1, help="Stride for d0 write")
    parser.add_argument("--write_d1_stride", type=int, default=4, help="Stride for d1 write")
    parser.add_argument("--write_d0_length", type=int, default=4, help="Length for d0 write")
    parser.add_argument("--write_d1_length", type=int, default=4, help="Length for d1 write")
    parser.add_argument("--output_dir", type=str, default="output", help="Directory for storing output files")

    args = parser.parse_args()

    global MEMORY_SIZE
    MEMORY_SIZE = args.mem_size  # Set global memory size

    # Step 1: Generate initial memory
    memory = generate_random_hex_32bit(MEMORY_SIZE)

    # Step 2: Generate read addresses
    read_transactions = args.read_d0_length * args.read_d1_length
    read_addresses = generate_addresses(args.read_base_addr, args.read_d0_stride, args.read_d0_length, args.read_d1_stride, args.read_d1_length, read_transactions)

    # Step 3: Extract memory values based on read addresses
    extracted_data = [memory[addr] for addr in read_addresses if addr < MEMORY_SIZE]

    # Step 4: Save initial memory
    write_file(args.output_dir, "initial_memory.txt", memory)

    # Step 5: Save debug info (addresses read and values extracted)
    debug_info = [f"Read Addr: {hex(addr)} -> Data: {memory[addr]}" for addr in read_addresses if addr < MEMORY_SIZE]
    write_file(args.output_dir, "debug_values.txt", debug_info)

    # Step 6: Generate write addresses (same transactions count as reads)
    write_transactions = read_transactions
    write_addresses = generate_addresses(args.write_base_addr, args.write_d0_stride, args.write_d0_length, args.write_d1_stride, args.write_d1_length, write_transactions)

    # Step 7: Update memory with extracted data at write addresses
    update_memory(memory, write_addresses, extracted_data)

    # Step 8: Save updated memory
    write_file(args.output_dir, "updated_memory.txt", memory)

    print(f"Files generated: initial_memory.txt, debug_values.txt, updated_memory.txt")


if __name__ == "__main__":
    main()