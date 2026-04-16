#!/usr/bin/env python3
"""
Configuration validation script for datamover HWPE
Validates that configuration parameters are compatible and reasonable
"""

import sys
import argparse

def validate_config(bandwidth, word_width, elem_width, memory_size, num_channels,
                    datamover_mode, transp_mode, cim_mode, row_tile_size,
                    size_m, size_n):
    """Validate configuration parameters"""
    errors = []
    warnings = []

    bandwidth_aligned = bandwidth

    # Computed values
    bandwidth_elems = bandwidth_aligned // elem_width
    num_elem_word = word_width // elem_width

    # Basic parameter validation
    if bandwidth_aligned % word_width != 0:
        errors.append(f"BANDWIDTH_ALIGNED ({bandwidth_aligned}) must be divisible by WORD_WIDTH ({word_width})")

    if word_width % elem_width != 0:
        errors.append(f"WORD_WIDTH ({word_width}) must be divisible by ELEM_WIDTH ({elem_width})")

    if memory_size < (num_channels * size_n * size_m * elem_width // word_width) * 2:
        errors.append(f"MEMORY_SIZE ({memory_size}) is too small for the given matrix size "
                      f"({num_channels}x{size_m}x{size_n}) and element width ({elem_width})")

    # Mode validation (based on config.mk)
    if datamover_mode not in [0, 1, 2, 3, 4, 5]:
        errors.append(f"DATAMOVER_MODE ({datamover_mode}) must be 0 (copy), 1 (transpose), 2 (CIM data layout conversion), 3 (CIM layout transpose), 4 (unfold), or 5 (fold)")

    # if transp_mode not in [0, 1, 2, 4]:
    #     errors.append(f"TRANSP_MODE ({transp_mode}) must be 0, 1, 2, or 4")

    # # Mode consistency validation
    # if datamover_mode == 0 and transp_mode != 0:
    #     warnings.append(f"Copy mode (DATAMOVER_MODE=0) typically uses TRANSP_MODE=0, but got {transp_mode}")

    if datamover_mode == 1 and transp_mode not in [1, 2, 4]:
        errors.append(f"Transpose mode (DATAMOVER_MODE=1) requires TRANSP_MODE = [1,2,4] but got {transp_mode}")

    # CIM-specific validation
    if datamover_mode in [2, 3]:
        if cim_mode not in [0, 1]:
            errors.append(f"CIM_MODE ({cim_mode}) must be 0 (row-major -> CIM-layout) or 1 (CIM-layout -> row-major) for CIM modes")
        if row_tile_size % bandwidth_elems != 0:
            errors.append(f"ROW_TILE_SIZE ({row_tile_size}) must be a multiple of bandwidth ({bandwidth_elems})")
        # if row_tile_size > size_n:
        #     errors.append(f"ROW_TILE_SIZE ({row_tile_size}) cannot be greater than matrix width ({size_n})")

    # Memory requirements
    matrix_elements = num_channels * size_m * size_n
    matrix_words = (matrix_elements * elem_width + word_width - 1) // word_width
    total_memory_needed = matrix_words * 2  # Input + output matrices

    if total_memory_needed > memory_size:
        errors.append(f"Memory size ({memory_size} words) insufficient for matrices "
                     f"({total_memory_needed} words needed for {num_channels}x{size_m}x{size_n} input+output)")

    # Matrix dimension alignment errors
    # if size_n % bandwidth_elems != 0:
    #     errors.append(f"Matrix width ({size_n}) not aligned to bandwidth "
    #                    f"({bandwidth_elems} elements)")

    # if size_m % bandwidth_elems != 0:
    #     errors.append(f"Matrix height ({size_m}) not aligned to bandwidth "
    #                    f"({bandwidth_elems} elements)")

    # Transpose-specific validation
    if datamover_mode == 1 and transp_mode > 0:
        if bandwidth_elems % transp_mode != 0:
            errors.append(f"Bandwidth elements ({bandwidth_elems}) must be divisible "
                         f"by TRANSP_MODE ({transp_mode})")

    return errors, warnings

def main():
    parser = argparse.ArgumentParser(description="Validate datamover configuration")
    parser.add_argument("--bandwidth", type=int, required=True)
    parser.add_argument("--word_width", type=int, required=True)
    parser.add_argument("--elem_width", type=int, required=True)
    parser.add_argument("--memory_size", type=int, required=True)
    parser.add_argument("--num_channels", type=int, required=True)
    parser.add_argument("--datamover_mode", type=int, required=True)
    parser.add_argument("--transp_mode", type=int, required=True)
    parser.add_argument("--cim_mode", type=int, required=True)
    parser.add_argument("--row_tile_size", type=int, required=True)
    parser.add_argument("--size_m", type=int, required=True)
    parser.add_argument("--size_n", type=int, required=True)

    args = parser.parse_args()

    errors, warnings = validate_config(
        args.bandwidth, args.word_width, args.elem_width, args.memory_size,
        args.num_channels, args.datamover_mode, args.transp_mode, args.cim_mode,
        args.row_tile_size,
        args.size_m, args.size_n
    )

    # Print results
    if warnings:
        print("WARNINGS:")
        for warning in warnings:
            print(f"  - {warning}")
        print()

    if errors:
        print("ERRORS:")
        for error in errors:
            print(f"  - {error}")
        print()
        print("Configuration validation FAILED!")
        return 1
    else:
        print("Configuration validation PASSED!")

        # Print mode information
        mode_names = {0: "Copy", 1: "Transpose", 2: "CIM Data Layout Conversion", 3: "CIM Layout Transpose", 4: "Unfold", 5: "Fold"}
        cim_mode_names = {0: "row-major -> CIM-layout", 1: "CIM-layout -> row-major"}

        print(f"\nMode Configuration:")
        print(f"  DATAMOVER_MODE: {args.datamover_mode} ({mode_names.get(args.datamover_mode, 'Unknown')})")
        print(f"  TRANSP_MODE: {args.transp_mode}")
        print(f"  CIM_MODE: {args.cim_mode} ({cim_mode_names.get(args.cim_mode, 'Unknown')})")
        if args.datamover_mode == 2:  # CIM mode
            print(f"  ROW_TILE_SIZE: {args.row_tile_size}")

        # Print computed values
        bandwidth_elems = args.bandwidth // args.elem_width
        num_elem_word = args.word_width // args.elem_width
        matrix_words = (args.num_channels * args.size_m * args.size_n) // num_elem_word

        print(f"\nComputed values:")
        print(f"  Channels: {args.num_channels}")
        print(f"  Elements per bandwidth: {bandwidth_elems}")
        print(f"  Elements per word: {num_elem_word}")
        print(f"  Matrix memory usage: {matrix_words} words ({matrix_words * 2} total)")
        print(f"  Memory utilization: {(matrix_words * 2 * 100) // args.memory_size}% ({matrix_words*2} / {args.memory_size})")

        return 0

if __name__ == "__main__":
    sys.exit(main())
