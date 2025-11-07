#!/usr/bin/env python3
"""
Configuration validation script for datamover HWPE
Validates that configuration parameters are compatible and reasonable
"""

import sys
import argparse

def validate_config(bandwidth, word_width, elem_width, memory_size,
                    transp_mode, matrix_m, matrix_n):
    """Validate configuration parameters"""
    errors = []
    warnings = []

    # Basic parameter validation
    if bandwidth % word_width != 0:
        errors.append(f"BANDWIDTH ({bandwidth}) must be divisible by WORD_WIDTH ({word_width})")

    if word_width % elem_width != 0:
        errors.append(f"WORD_WIDTH ({word_width}) must be divisible by ELEM_WIDTH ({elem_width})")

    if transp_mode not in [0, 1, 2, 4]:
        errors.append(f"TRANSP_MODE ({transp_mode}) must be 0, 1, 2, or 4")

    # Computed values
    bandwidth_elems = bandwidth // elem_width
    num_elem_word = word_width // elem_width

    # Memory requirements
    matrix_elements = matrix_m * matrix_n
    matrix_words = (matrix_elements * elem_width + word_width - 1) // word_width
    total_memory_needed = matrix_words * 2  # Input + output matrices

    if total_memory_needed > memory_size:
        errors.append(f"Memory size ({memory_size} words) insufficient for matrices "
                     f"({total_memory_needed} words needed for {matrix_m}x{matrix_n} input+output)")

    # Matrix dimension alignment errors
    if matrix_n % bandwidth_elems != 0:
        errors.append(f"Matrix width ({matrix_n}) not aligned to bandwidth "
                       f"({bandwidth_elems} elements)")

    if matrix_m % bandwidth_elems != 0:
        errors.append(f"Matrix height ({matrix_m}) not aligned to bandwidth "
                       f"({bandwidth_elems} elements)")

    # Transpose-specific validation
    if transp_mode > 0:
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
    parser.add_argument("--transp_mode", type=int, required=True)
    parser.add_argument("--matrix_m", type=int, required=True)
    parser.add_argument("--matrix_n", type=int, required=True)

    args = parser.parse_args()

    errors, warnings = validate_config(
        args.bandwidth, args.word_width, args.elem_width, args.memory_size,
        args.transp_mode, args.matrix_m, args.matrix_n
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

        # Print computed values
        bandwidth_elems = args.bandwidth // args.elem_width
        num_elem_word = args.word_width // args.elem_width
        matrix_words = (args.matrix_m * args.matrix_n * args.elem_width + args.word_width - 1) // args.word_width

        print(f"\nComputed values:")
        print(f"  Elements per bandwidth: {bandwidth_elems}")
        print(f"  Elements per word: {num_elem_word}")
        print(f"  Matrix memory usage: {matrix_words} words ({matrix_words * 2} total)")
        print(f"  Memory utilization: {(matrix_words * 2 * 100) // args.memory_size}%")

        return 0

if __name__ == "__main__":
    sys.exit(main())
