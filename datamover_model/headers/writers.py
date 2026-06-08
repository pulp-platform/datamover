# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors: Lionnus Kesting <lkesting@iis.ee.ethz.ch>

"""Low-level C header file writers."""

import os

import numpy as np


def hex_byte_lines(arr, per_line: int = 16) -> list:
    """Format a byte array as indented, comma-separated 0x.. lines."""
    flat = np.asarray(arr).reshape(-1).astype(np.uint8).tolist()
    lines = []
    for i in range(0, len(flat), per_line):
        chunk = flat[i:i + per_line]
        text = ", ".join(f"0x{v:02x}" for v in chunk)
        suffix = "," if i + per_line < len(flat) else ""
        lines.append(f"  {text}{suffix}")
    return lines


def write_define_header(path: str, includes, define_pairs, extra_lines=None) -> str:
    """Write a header composed of includes, #defines, and optional extra lines."""
    guard = os.path.basename(path).upper().replace(".", "_")
    with open(path, "w") as f:
        f.write(f"#ifndef {guard}\n#define {guard}\n\n")
        for inc in includes:
            f.write(f"#include \"{inc}\"\n")
        if includes:
            f.write("\n")
        for key, value in define_pairs:
            f.write(f"#define {key} {value}\n")
        if extra_lines:
            f.write("\n")
            for line in extra_lines:
                f.write(f"{line}\n")
        f.write(f"\n#endif /* {guard} */\n")
    return path
