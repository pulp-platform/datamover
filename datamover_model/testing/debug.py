# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors: Lionnus Kesting <lkesting@iis.ee.ethz.ch>

"""Human-readable tensor dumps for debugging RTL vs golden mismatches."""

import os
import shutil

import numpy as np


def _save_dec_hex(arr: np.ndarray, path: str, cols: int = 16) -> None:
    flat = arr.reshape(-1).astype(np.uint8)
    with open(path, "w") as f:
        for row in range(0, len(flat), cols):
            chunk = flat[row:row + cols]
            dec = "  ".join(f"{v:3d}" for v in chunk)
            hex_ = " ".join(f"{v:02x}" for v in chunk)
            f.write(f"[{row:6d}]  {dec}    |  {hex_}\n")


def _save_chw(arr: np.ndarray, path: str) -> None:
    c, m, _ = arr.shape
    with open(path, "w") as f:
        for ci in range(c):
            f.write(f"# Channel {ci}\n")
            for r in range(m):
                f.write("  " + " ".join(f"{v:02x}" for v in arr[ci, r]) + "\n")
            f.write("\n")


def write_task_debug(result, output_dir: str, index: int) -> str:
    """Write debug_logs_task<index>/ with dec/hex and CHW dumps."""
    debug_dir = os.path.join(output_dir, f"debug_logs_task{index}")
    if os.path.isdir(debug_dir):
        shutil.rmtree(debug_dir)
    os.makedirs(debug_dir, exist_ok=True)

    _save_dec_hex(result.in_tensor, os.path.join(debug_dir, "golden_in_dec_hex.txt"))
    _save_dec_hex(result.out_tensor, os.path.join(debug_dir, "golden_out_dec_hex.txt"))

    if result.in_tensor.ndim == 3 and result.in_tensor.shape[0] > 1:
        _save_chw(result.in_tensor, os.path.join(debug_dir, "in_chw_hex.txt"))
    if result.out_tensor.ndim == 3 and result.out_tensor.shape[0] > 1:
        _save_chw(result.out_tensor, os.path.join(debug_dir, "out_chw_hex.txt"))

    return debug_dir
