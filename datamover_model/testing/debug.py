# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors: Lionnus Kesting <lkesting@iis.ee.ethz.ch>

"""Human-readable tensor dumps for debugging RTL vs golden mismatches."""

import os
import shutil

import numpy as np

DATAMOVER_IM2COL = 6


def _save_dec_hex(arr: np.ndarray, path: str, cols: int = 16) -> None:
    flat = arr.reshape(-1).astype(np.uint8)
    with open(path, "w") as f:
        for row in range(0, len(flat), cols):
            chunk = flat[row:row + cols]
            dec = "  ".join(f"{v:3d}" for v in chunk)
            hex_ = " ".join(f"{v:02x}" for v in chunk)
            f.write(f"[{row:6d}]  {dec}    |  {hex_}\n")


def _save_chw(arr: np.ndarray, path: str, marker_stride: int = 0) -> None:
    """Dump a [C, H, W] tensor as hex, with w/h index headers."""
    c, h, w = arr.shape
    w_iw = max(2, len(str(w - 1)))
    h_iw = max(2, len(str(h - 1)), len("h_idx"))

    def _wheader() -> str:
        parts = []
        for wi in range(w):
            if marker_stride and wi and wi % marker_stride == 0:
                parts.append("|")
            parts.append(f"{wi:0{w_iw}d}")
        return " ".join(parts)

    header = _wheader()
    with open(path, "w") as f:
        f.write(f"Tensor hex dump in CHW view [C, H, W] = [{c}, {h}, {w}]\n")
        f.write("C blocks; each block has H rows; columns are W indices\n\n")
        for ci in range(c):
            f.write(f"=== c={ci} ===\n")
            f.write(f"{'h_idx':>{h_iw}} | {header}\n")
            f.write(f"{'-' * h_iw}-+-{'-' * len(header)}\n")
            for hi in range(h):
                parts = []
                for wi in range(w):
                    if marker_stride and wi and wi % marker_stride == 0:
                        parts.append("|")
                    parts.append(f"{int(arr[ci, hi, wi]) & 0xff:02x}".rjust(w_iw))
                f.write(f"{hi:{h_iw}d} | {' '.join(parts)}\n")
            f.write("\n")


def _save_im2col_matrix(matrix: np.ndarray, path: str, kh: int, kw: int, c: int,
                        h_out: int, w_out: int, stride: int) -> None:
    """Dump the im2col output matrix with row=(ci,kh,kw) / col=(oh,ow) decoded."""
    rows, ncol = matrix.shape
    assert rows == kh * kw * c and ncol == h_out * w_out, "unexpected im2col shape"
    lbl_w = len(f"(c{c - 1} kh{kh - 1} kw{kw - 1}) r{rows - 1}")

    with open(path, "w") as f:
        f.write(f"im2col matrix: {rows} rows (Kh*Kw*C) x {ncol} cols (H_out*W_out)\n")
        f.write(f"Kh={kh} Kw={kw} C={c} H_out={h_out} W_out={w_out} stride={stride}\n")
        f.write("row = ci*Kh*Kw + kh_i*Kw + kw_i ; col = oh*W_out + ow\n")
        f.write("check: matrix[row, col] == input[ci, oh*S+kh_i, ow*S+kw_i]\n")
        f.write("column groups separated by '|' are one output row (oh); "
                "each group has W_out=ow columns\n\n")

        head = " " * (lbl_w + 3)
        for oh in range(h_out):
            head += "| " + f"oh={oh}".ljust(w_out * 3 - 1) + " "
        f.write(head.rstrip() + "\n")

        for r in range(rows):
            ci = r // (kh * kw)
            kh_i = (r % (kh * kw)) // kw
            kw_i = r % kw
            label = f"(c{ci} kh{kh_i} kw{kw_i}) r{r}".ljust(lbl_w)
            parts = []
            for col in range(ncol):
                if col % w_out == 0:
                    parts.append("|")
                parts.append(f"{int(matrix[r, col]) & 0xff:02x}")
            f.write(f"{label} : {' '.join(parts)}\n")


def write_task_debug(result, output_dir: str, index: int) -> str:
    """Write debug_logs_task<index>/ with dec/hex and logical-view dumps."""
    debug_dir = os.path.join(output_dir, f"debug_logs_task{index}")
    if os.path.isdir(debug_dir):
        shutil.rmtree(debug_dir)
    os.makedirs(debug_dir, exist_ok=True)

    params = getattr(result, "params", {}) or {}
    mode = params.get("DATAMOVER_MODE")

    _save_dec_hex(result.in_tensor, os.path.join(debug_dir, "golden_in_dec_hex.txt"))
    _save_dec_hex(result.out_tensor, os.path.join(debug_dir, "golden_out_dec_hex.txt"))

    if result.in_tensor.ndim == 3:
        s = int(params.get("CONV_STRIDE", 1)) if mode == DATAMOVER_IM2COL else 0
        _save_chw(result.in_tensor, os.path.join(debug_dir, "in_chw_hex.txt"),
                  marker_stride=s if s > 1 else 0)

    if mode == DATAMOVER_IM2COL and result.out_tensor.ndim == 2:
        kh = int(params["KERNEL_SIZE_H"])
        kw = int(params["KERNEL_SIZE_W"])
        c = int(params["SIZE_C"])
        s = int(params.get("CONV_STRIDE", 1))
        p = int(params.get("CONV_PAD", 0))
        h_out = (int(params["SIZE_M"]) + 2 * p - kh) // s + 1
        w_out = (int(params["SIZE_N"]) + 2 * p - kw) // s + 1
        _save_im2col_matrix(result.out_tensor,
                            os.path.join(debug_dir, "im2col_matrix_hex.txt"),
                            kh, kw, c, h_out, w_out, s)
    elif result.out_tensor.ndim == 3 and result.out_tensor.shape[0] > 1:
        _save_chw(result.out_tensor, os.path.join(debug_dir, "out_chw_hex.txt"))

    return debug_dir
