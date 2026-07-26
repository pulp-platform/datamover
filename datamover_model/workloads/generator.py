# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors: Lionnus Kesting <lkesting@iis.ee.ethz.ch>

"""Per-task data generation: build stimuli, run golden, produce a TaskData."""

from dataclasses import dataclass

import numpy as np

from datamover_model.golden_model.transforms import (
    cim_layout,
    cim_layout_reverse,
    cim_layout_transpose,
    fold,
    im2col,
    unfold,
)

PATCH_SIZE = 4  # 2x2 patch, only supported unfold/fold patch


@dataclass
class TaskData:
    name: str
    params: dict
    in_tensor: np.ndarray
    out_tensor: np.ndarray


def make_input_tensor(params: dict, seed: int) -> np.ndarray:
    c, m, n = params["SIZE_C"], params["SIZE_M"], params["SIZE_N"]
    if params["COUNT"]:
        return np.arange(c * m * n, dtype=np.uint8).reshape(c, m, n)
    rng = np.random.default_rng(seed)
    return rng.integers(0, 256, size=(c, m, n), dtype=np.uint8)


def golden_for(params: dict, in_tensor: np.ndarray):
    """Return (actual_input_tensor, golden_output_tensor)."""
    mode = params["DATAMOVER_MODE"]
    c, m, n = params["SIZE_C"], params["SIZE_M"], params["SIZE_N"]
    rt = params["ROW_TILE_SIZE"]
    t = params["TRANSP_MODE"]

    if mode == 0:
        return in_tensor, in_tensor.copy()
    if mode == 1:
        if t not in (1, 2, 4):
            raise ValueError(f"transpose requires TRANSP_MODE in {{1,2,4}}, got {t}")
        if n % t != 0:
            raise ValueError(f"SIZE_N ({n}) must be divisible by TRANSP_MODE ({t})")
        out = in_tensor.reshape(c, m, n // t, t).transpose(0, 2, 1, 3).reshape(c, n // t, m * t)
        return in_tensor, out
    if mode == 2:
        flat = in_tensor.reshape(m, n)
        out = cim_layout(flat, rt, m, n) if params["CIM_MODE"] == 0 \
            else cim_layout_reverse(flat, rt, m, n)
        return in_tensor, np.asarray(out).reshape(-1)
    if mode == 3:
        flat = in_tensor.reshape(m, n)
        out = cim_layout_transpose(flat, rt, m, n)
        return in_tensor, np.asarray(out).reshape(-1)
    if mode == 4:
        return in_tensor, unfold(in_tensor, PATCH_SIZE)
    if mode == 5:
        # Fold consumes an unfolded tensor; synthesize it so the golden round-trips.
        unfolded = unfold(in_tensor, PATCH_SIZE)
        return unfolded, fold(unfolded, PATCH_SIZE, c, m, n)
    if mode == 6:
        return in_tensor, im2col(in_tensor, params["KERNEL_SIZE_H"], params["KERNEL_SIZE_W"],
                                  params["CONV_STRIDE"], params["CONV_PAD"])
    raise ValueError(f"Unsupported DATAMOVER_MODE: {mode}")


def generate_task_data(entry: dict, seed: int) -> TaskData:
    params = entry["params"]
    in_tensor, out_tensor = golden_for(params, make_input_tensor(params, seed))
    return TaskData(name=entry["name"], params=params, in_tensor=in_tensor, out_tensor=out_tensor)


def generate_chain_data(entry: dict, seed: int):
    """Compose a chain of ops, each consuming the previous output as a flat byte
    sequence. Returns (input_tensor, [(params, out_tensor), ...] per stage)."""
    chain = entry["chain"]
    input_tensor = make_input_tensor(chain[0], seed)
    cur = input_tensor
    stages = []
    for params in chain:
        c, m, n = params["SIZE_C"], params["SIZE_M"], params["SIZE_N"]
        if cur.size != c * m * n:
            raise ValueError(
                f"chain stage {len(stages)} expects {c}*{m}*{n}={c * m * n} elements "
                f"but previous stage produced {cur.size}"
            )
        _, out = golden_for(params, cur.reshape(c, m, n))
        out = np.asarray(out)
        stages.append((params, out))
        cur = out
    return input_tensor, stages
