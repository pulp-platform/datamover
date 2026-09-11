# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors: Cyrill Durrer <cdurrer@iis.ee.ethz.ch>
#          Lionnus Kesting <lkesting@iis.ee.ethz.ch>

"""Datamover golden-model transforms: cim_layout, transpose, unfold, fold, im2col."""

import math

import numpy as np


def cim_layout(tensor, block, size_m, size_n):
    # Columns are grouped into blocks of `block` columns; for each block all rows'
    # slices are stored consecutively. (size_m, size_n) -> (1, size_m * size_n).
    n_tiles = size_n // block
    leftover = size_n % block

    parts = [tensor[:, :n_tiles * block].reshape(size_m, n_tiles, block).transpose(1, 0, 2).reshape(-1)]
    if leftover > 0:
        parts.append(tensor[:, n_tiles * block:].reshape(-1))
    return np.concatenate(parts).reshape(1, -1)


def cim_layout_reverse(tensor, block, size_m, size_n):
    # Inverse of cim_layout: CIM layout (1, size_m * size_n) -> (size_m, size_n).
    n_tiles = size_n // block
    leftover = size_n % block
    flat = tensor.reshape(-1)

    complete = flat[:n_tiles * size_m * block].reshape(n_tiles, size_m, block).transpose(1, 0, 2)
    if leftover > 0:
        leftover_part = flat[n_tiles * size_m * block:].reshape(size_m, leftover)
        return np.concatenate([complete.reshape(size_m, n_tiles * block), leftover_part], axis=1)
    return complete.reshape(size_m, size_n)


def cim_layout_transpose(tensor, block, size_m, size_n):
    # Transpose a CIM-layout matrix, keeping the result in CIM layout.
    row_major = cim_layout_reverse(tensor, block, size_m, size_n)
    return cim_layout(np.transpose(row_major), block, size_n, size_m)


def cim_activation(tensor, block):
    # (C, H, W) -> the (C, H*W) matrix in CIM layout with blocks of `block` pixels, flat.
    c = tensor.shape[0]
    return np.asarray(cim_layout(tensor.reshape(c, -1), block, c, tensor.size // c)).reshape(-1)


def unfold(tensor, patch_size, layout="CHW", block=64):
    # (C, H, W) -> (PATCH_SIZE, NUM_PATCHES, C); layout CIM returns the (PATCH_SIZE*NUM_PATCHES, C)
    # token matrix in CIM layout with column blocks of `block`, flat.
    channels, height, width = tensor.shape
    patch_sidelength = int(math.sqrt(patch_size))
    assert (height % patch_sidelength == 0) and (width % patch_sidelength == 0), \
        "Height and Width must be divisible by patch sidelength"
    num_patches_h = height // patch_sidelength
    num_patches_w = width // patch_sidelength
    num_patches = num_patches_h * num_patches_w
    tensor_unfolded = np.zeros((patch_size, num_patches, channels), dtype=tensor.dtype)
    for p in range(patch_size):
        for h in range(num_patches_h):
            for w in range(num_patches_w):
                n = h * num_patches_w + w
                h_idx = h * patch_sidelength + (p // patch_sidelength)
                w_idx = w * patch_sidelength + (p % patch_sidelength)
                tensor_unfolded[p, n, :] = tensor[:, h_idx, w_idx]
    if layout == "CIM":
        rows = patch_size * num_patches
        return np.asarray(cim_layout(tensor_unfolded.reshape(rows, channels), block, rows, channels)).reshape(-1)
    return tensor_unfolded


def fold(tensor, patch_size, num_channels, height, width, layout="CHW", block=64):
    # (PATCH_SIZE, NUM_PATCHES, C) -> (C, H, W); folded dims are num_channels, height, width.
    # layout CIM takes and returns the CIM layouts of unfold and cim_activation.
    patch_sidelength = int(math.sqrt(patch_size))
    if layout == "CIM":
        rows = patch_size * (height // patch_sidelength) * (width // patch_sidelength)
        tensor = cim_layout_reverse(tensor, block, rows, num_channels).reshape(patch_size, -1, num_channels)
    assert (height % patch_sidelength == 0) and (width % patch_sidelength == 0), \
        "Height and Width must be divisible by patch sidelength"
    num_patches_h = height // patch_sidelength
    num_patches_w = width // patch_sidelength
    tensor_folded = np.zeros((num_channels, height, width), dtype=tensor.dtype)
    for p in range(patch_size):
        for h in range(num_patches_h):
            for w in range(num_patches_w):
                n = h * num_patches_w + w
                h_idx = h * patch_sidelength + (p // patch_sidelength)
                w_idx = w * patch_sidelength + (p % patch_sidelength)
                tensor_folded[:, h_idx, w_idx] = tensor[p, n, :]
    if layout == "CIM":
        return cim_activation(tensor_folded, block)
    return tensor_folded


def im2col(tensor, kernel_h, kernel_w, stride=1, padding=0, in_layout="CHW", out_layout="COL", block=64):
    # out_layout COL: each patch is a column, (Kh*Kw*C, H_out*W_out) as torch unfold;
    #   row = c*Kh*Kw + kh*Kw + kw, col = oh*W_out + ow. Surya operand B.
    # out_layout ROW: each patch is a row, (H_out*W_out, C*Kh*Kw). Surya operand A.
    # out_layout ROW_CIM and COL_CIM: ROW or COL in column blocks of `block`, the CIM layout of mode 2.
    # in_layout HWC reads the bytes as an HWC image; the A columns are then ordered (kh, kw, c).
    # in_layout CIM is the (C, H*W) matrix in blocks of `block` pixels; the tensor passed here stays CHW.
    import torch
    if in_layout == "HWC":
        c, h, w = tensor.shape
        tensor = tensor.reshape(h, w, c).transpose(2, 0, 1)
    c = tensor.shape[0]
    x = torch.from_numpy(tensor.astype(np.float32)).unsqueeze(0)
    cols = torch.nn.functional.unfold(x, (kernel_h, kernel_w), stride=stride, padding=padding)
    cols = cols.squeeze(0).to(torch.uint8).numpy()
    if out_layout == "COL":
        return cols
    if out_layout == "COL_CIM":
        return np.asarray(cim_layout(cols, block, cols.shape[0], cols.shape[1])).reshape(-1)
    n = cols.shape[1]
    tokens = cols.T.reshape(n, c, kernel_h, kernel_w)
    if in_layout == "HWC":
        tokens = tokens.transpose(0, 2, 3, 1)
    tokens = np.ascontiguousarray(tokens.reshape(n, -1))
    if out_layout == "ROW":
        return tokens
    return cim_layout(tokens, block, n, tokens.shape[1])
