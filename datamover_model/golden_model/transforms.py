# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors: Cyrill Durrer <cdurrer@iis.ee.ethz.ch>
#          Lionnus Kesting <lkesting@iis.ee.ethz.ch>

"""Datamover golden-model transforms: cim_layout, transpose, unfold, fold."""

import math

import numpy as np


def cim_layout(tensor, row_tile_size, size_m, size_n):
    # Columns are grouped into tiles of row_tile_size; for each tile all rows'
    # slices are stored consecutively. (size_m, size_n) -> (1, size_m * size_n).
    n_tiles = size_n // row_tile_size
    leftover = size_n % row_tile_size

    parts = [tensor[:, :n_tiles * row_tile_size].reshape(size_m, n_tiles, row_tile_size).transpose(1, 0, 2).reshape(-1)]
    if leftover > 0:
        parts.append(tensor[:, n_tiles * row_tile_size:].reshape(-1))
    return np.concatenate(parts).reshape(1, -1)


def cim_layout_reverse(tensor, row_tile_size, size_m, size_n):
    # Inverse of cim_layout: CIM layout (1, size_m * size_n) -> (size_m, size_n).
    n_tiles = size_n // row_tile_size
    leftover = size_n % row_tile_size
    flat = tensor.reshape(-1)

    complete = flat[:n_tiles * size_m * row_tile_size].reshape(n_tiles, size_m, row_tile_size).transpose(1, 0, 2)
    if leftover > 0:
        leftover_part = flat[n_tiles * size_m * row_tile_size:].reshape(size_m, leftover)
        return np.concatenate([complete.reshape(size_m, n_tiles * row_tile_size), leftover_part], axis=1)
    return complete.reshape(size_m, size_n)


def cim_layout_transpose(tensor, row_tile_size, size_m, size_n):
    # Transpose a CIM-layout matrix, keeping the result in CIM layout.
    row_major = cim_layout_reverse(tensor, row_tile_size, size_m, size_n)
    return cim_layout(np.transpose(row_major), row_tile_size, size_n, size_m)


def unfold(tensor, patch_size):
    # (C, H, W) -> (PATCH_SIZE, NUM_PATCHES, C).
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
    return tensor_unfolded


def fold(tensor, patch_size, num_channels, height, width):
    # (PATCH_SIZE, NUM_PATCHES, C) -> (C, H, W); folded dims are num_channels, height, width.
    patch_sidelength = int(math.sqrt(patch_size))
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
    return tensor_folded
