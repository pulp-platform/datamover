#!/usr/bin/env python3
# Copyright (C) 2025-2026 ETH Zurich and University of Bologna
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors: Lionnus Kesting <lkesting@iis.ee.ethz.ch>

"""Datamover workload-header generator.

Reads a unified test definition (JSON) and emits, into the build directory:

    datamover_workload.h          x-macro task table + HW/per-task #defines
    task<i>_data.h                golden_in / golden_out byte arrays
    test_config.mk                RTL compile-time params (BANDWIDTH, …)
    debug_logs_task<i>/           {golden_in,golden_out}_dec_hex.txt

Reuses the golden generators (cim_layout, transpose, unfold, fold, …) from
``verif.python.datamover_golden_model``.
"""

import argparse
import json
import os
import shutil
import sys
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from verif.python.datamover_golden_model import (  # noqa: E402
    cim_layout,
    cim_layout_reverse,
    cim_layout_transpose,
    fold,
    unfold,
)


HW_KEYS = ("BANDWIDTH", "WORD_WIDTH", "ELEM_WIDTH", "MISALIGNED_ACCESSES")
PARAM_KEYS = (
    "DATAMOVER_MODE",
    "TRANSP_MODE",
    "CIM_MODE",
    "ROW_TILE_SIZE",
    "SIZE_C",
    "SIZE_M",
    "SIZE_N",
    "COUNT",
)
PARAM_DEFAULTS = {
    "DATAMOVER_MODE": 0,
    "TRANSP_MODE": 1,
    "CIM_MODE": 0,
    "ROW_TILE_SIZE": 64,
    "SIZE_C": 1,
    "SIZE_M": 1,
    "SIZE_N": 1,
    "COUNT": 0,
}
PATCH_SIZE = 4   # 2x2 patch, currently the only supported unfold/fold patch


# ------------------------------------------------------------------
# JSON helpers
# ------------------------------------------------------------------

def load_hw_config(name: str) -> dict:
    path = REPO_ROOT / "utils" / "hw_configs.json"
    with open(path) as f:
        configs = json.load(f)
    if name not in configs:
        available = ", ".join(sorted(configs.keys()))
        raise ValueError(f"HW config '{name}' not found. Available: {available}")
    cfg = configs[name]
    missing = [k for k in HW_KEYS if k not in cfg]
    if missing:
        raise ValueError(f"HW config '{name}' missing keys: {missing}")
    return {k: cfg[k] for k in HW_KEYS}


def load_test_suite(json_path: str) -> dict:
    with open(json_path) as f:
        config = json.load(f)
    return config


def normalize_params(raw: dict) -> dict:
    out = dict(PARAM_DEFAULTS)
    for k, v in raw.items():
        if k not in PARAM_DEFAULTS:
            raise ValueError(f"Unknown param '{k}' (allowed: {list(PARAM_DEFAULTS)})")
        out[k] = int(v)
    if out["DATAMOVER_MODE"] not in range(6):
        raise ValueError(f"DATAMOVER_MODE must be in 0..5, got {out['DATAMOVER_MODE']}")
    if out["TRANSP_MODE"] not in (0, 1, 2, 4):
        raise ValueError(f"TRANSP_MODE must be in {{0,1,2,4}}, got {out['TRANSP_MODE']}")
    if out["CIM_MODE"] not in (0, 1):
        raise ValueError(f"CIM_MODE must be 0 or 1, got {out['CIM_MODE']}")
    return out


def auto_test_name(params: dict, hw_tag: str = "") -> str:
    mode = params["DATAMOVER_MODE"]
    c, m, n = params["SIZE_C"], params["SIZE_M"], params["SIZE_N"]
    if mode == 0:
        base = f"COPY_{m}x{n}"
    elif mode == 1:
        base = f"TRANSP{params['TRANSP_MODE']}_{m}x{n}"
    elif mode == 2:
        tag = "FWD" if params["CIM_MODE"] == 0 else "REV"
        base = f"CIM{tag}_{m}x{n}_RT{params['ROW_TILE_SIZE']}"
    elif mode == 3:
        base = f"CIMTR{params['TRANSP_MODE']}_{m}x{n}_RT{params['ROW_TILE_SIZE']}"
    elif mode == 4:
        base = f"UNFOLD_C{c}_{m}x{n}"
    else:
        base = f"FOLD_C{c}_{m}x{n}"
    if c > 1 and mode in (0, 1, 2, 3):
        base += f"_C{c}"
    if hw_tag:
        base += f"_{hw_tag}"
    return base


def hw_tag_for(name: str) -> str:
    if not name or name == "default":
        return ""
    return name.upper()


def _entry_name(entry: dict, suite_hw: str = "") -> str:
    params = normalize_params(entry.get("params", {}))
    if entry.get("name"):
        return entry["name"]
    hw = entry.get("hw_config") or suite_hw
    return auto_test_name(params, hw_tag_for(hw))


def find_test_entry(suite: dict, test_name: str) -> dict:
    suite_hw = suite.get("hw_config", "")
    for entry in suite.get("tests", []):
        if _entry_name(entry, suite_hw) == test_name:
            out = dict(entry)
            out["params"] = normalize_params(entry.get("params", {}))
            out["name"] = test_name
            return out
    available = ", ".join(_entry_name(e, suite_hw) for e in suite.get("tests", []))
    raise ValueError(f"Test '{test_name}' not found. Available: {available}")


def list_tests(json_path: str) -> list:
    suite = load_test_suite(json_path)
    suite_hw = suite.get("hw_config", "")
    return [_entry_name(e, suite_hw) for e in suite.get("tests", [])]


# ------------------------------------------------------------------
# Tensor + golden generation
# ------------------------------------------------------------------

def make_input_tensor(params: dict, seed: int) -> np.ndarray:
    c, m, n = params["SIZE_C"], params["SIZE_M"], params["SIZE_N"]
    if params["COUNT"]:
        return np.arange(c * m * n, dtype=np.uint8).reshape(c, m, n)
    rng = np.random.default_rng(seed)
    return rng.integers(0, 256, size=(c, m, n), dtype=np.uint8)


def golden_for(params: dict, in_tensor: np.ndarray):
    """Return (input_tensor_actual, golden_output_tensor).

    For modes that consume an unfolded input, in_tensor is regenerated.
    """
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
        out = unfold(in_tensor, PATCH_SIZE)
        return in_tensor, out
    if mode == 5:
        # In fold mode the *input* is an unfolded tensor; we synthesize it by
        # unfolding a counting tensor so the golden round-trips.
        unfolded = unfold(in_tensor, PATCH_SIZE)
        folded = fold(unfolded, PATCH_SIZE, c, m, n)
        return unfolded, folded
    raise ValueError(f"Unsupported DATAMOVER_MODE: {mode}")


# ------------------------------------------------------------------
# Header writers
# ------------------------------------------------------------------

def _hex_lines(arr: np.ndarray, per_line: int = 16) -> list:
    flat = arr.reshape(-1).astype(np.uint8).tolist()
    lines = []
    for i in range(0, len(flat), per_line):
        chunk = flat[i:i + per_line]
        text = ", ".join(f"0x{v:02x}" for v in chunk)
        suffix = "," if i + per_line < len(flat) else ""
        lines.append(f"  {text}{suffix}")
    return lines


def write_task_data_header(
    output_dir: str,
    task_idx: int,
    in_tensor: np.ndarray,
    out_tensor: np.ndarray,
) -> str:
    """Write task<i>_data.h with golden_in/golden_out arrays."""
    path = os.path.join(output_dir, f"task{task_idx}_data.h")
    in_size = int(np.prod(in_tensor.shape))
    out_size = int(np.prod(out_tensor.shape))
    guard = f"TASK{task_idx}_DATA_H"
    lines = [
        f"#ifndef {guard}",
        f"#define {guard}",
        "",
        "#include <stdint.h>",
        "",
        f"#define TASK{task_idx}_IN_SIZE  {in_size}",
        f"#define TASK{task_idx}_OUT_SIZE {out_size}",
        "",
        f"uint8_t task{task_idx}_golden_in[{in_size}] __attribute__((aligned(8))) = {{",
    ]
    lines.extend(_hex_lines(in_tensor))
    lines.extend([
        "};",
        "",
        f"uint8_t task{task_idx}_golden_out[{out_size}] __attribute__((aligned(8))) = {{",
    ])
    lines.extend(_hex_lines(out_tensor))
    lines.extend([
        "};",
        "",
        f"#endif /* {guard} */",
        "",
    ])
    with open(path, "w") as f:
        f.write("\n".join(lines))
    return path


def write_workload_header(
    output_dir: str,
    hw: dict,
    tasks: list,
) -> str:
    """Write datamover_workload.h with HW/per-task defines + x-macro table."""
    num_tasks = len(tasks)
    path = os.path.join(output_dir, "datamover_workload.h")
    guard = "DATAMOVER_WORKLOAD_H"

    lines = [
        f"#ifndef {guard}",
        f"#define {guard}",
        "",
        "#include <stdint.h>",
        "",
    ]

    for i in range(num_tasks):
        lines.append(f"#include \"task{i}_data.h\"")
    lines.append("")

    lines.append(f"#define NUM_TASKS {num_tasks}")
    for k in HW_KEYS:
        lines.append(f"#define DM_HW_{k} {hw[k]}")
    lines.append("")

    for i, task in enumerate(tasks):
        params = task["params"]
        for k in PARAM_KEYS:
            lines.append(f"#define TASK{i}_{k} {params[k]}")
        lines.append(
            f"#define TASK{i}_TOT_SIZE "
            f"(TASK{i}_SIZE_C * TASK{i}_SIZE_M * TASK{i}_SIZE_N)"
        )
        # Pointers that resolve to symbols defined in task<i>_data.h.
        lines.append(f"#define TASK{i}_IN_PTR        task{i}_golden_in")
        lines.append(f"#define TASK{i}_OUT_GOLDEN    task{i}_golden_out")
        lines.append(f"#define TASK{i}_NAME         \"{task['name']}\"")
        lines.append("")

    lines.append("#define DATAMOVER_TASKS(APPLY) \\")
    for i in range(num_tasks):
        sep = " \\" if i < num_tasks - 1 else ""
        lines.append(f"    APPLY({i}){sep}")
    lines.extend(["", f"#endif /* {guard} */", ""])

    with open(path, "w") as f:
        f.write("\n".join(lines))
    return path


def write_test_config_mk(output_dir: str, hw: dict) -> str:
    path = os.path.join(output_dir, "test_config.mk")
    lines = [
        "# Auto-generated by gen_workload_header.py - DO NOT EDIT",
        "# Included by Makefile to set RTL compile-time params for the DUT.",
    ]
    for k in HW_KEYS:
        lines.append(f"{k} := {hw[k]}")
    lines.append("")
    with open(path, "w") as f:
        f.write("\n".join(lines))
    return path


def write_debug_logs(
    output_dir: str,
    task_idx: int,
    in_tensor: np.ndarray,
    out_tensor: np.ndarray,
) -> None:
    debug_dir = os.path.join(output_dir, f"debug_logs_task{task_idx}")
    if os.path.isdir(debug_dir):
        shutil.rmtree(debug_dir)
    os.makedirs(debug_dir, exist_ok=True)

    def _save(arr: np.ndarray, name: str) -> None:
        flat = arr.reshape(-1).astype(np.uint8)
        path = os.path.join(debug_dir, name)
        with open(path, "w") as f:
            cols = 16
            for row in range(0, len(flat), cols):
                chunk = flat[row:row + cols]
                dec = "  ".join(f"{v:3d}" for v in chunk)
                hex_ = " ".join(f"{v:02x}" for v in chunk)
                f.write(f"[{row:6d}]  {dec}    |  {hex_}\n")

    _save(in_tensor, "golden_in_dec_hex.txt")
    _save(out_tensor, "golden_out_dec_hex.txt")

    # CHW view for unfold / fold modes.
    if in_tensor.ndim == 3 and in_tensor.shape[0] > 1:
        with open(os.path.join(debug_dir, "in_chw_hex.txt"), "w") as f:
            c, m, n = in_tensor.shape
            for ci in range(c):
                f.write(f"# Channel {ci}\n")
                for r in range(m):
                    f.write("  " + " ".join(f"{v:02x}" for v in in_tensor[ci, r]) + "\n")
                f.write("\n")
    if out_tensor.ndim == 3 and out_tensor.shape[0] > 1:
        with open(os.path.join(debug_dir, "out_chw_hex.txt"), "w") as f:
            c, m, n = out_tensor.shape
            for ci in range(c):
                f.write(f"# Channel {ci}\n")
                for r in range(m):
                    f.write("  " + " ".join(f"{v:02x}" for v in out_tensor[ci, r]) + "\n")
                f.write("\n")


# ------------------------------------------------------------------
# CLI entry point
# ------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", required=True, help="Unified test JSON file")
    parser.add_argument("--test_name", help="Test name; if omitted, lists tests and exits")
    parser.add_argument("--output_dir", help="Build directory (required unless listing tests)")
    parser.add_argument("--seed", type=int, default=42, help="Random seed for stimuli")
    parser.add_argument("--no-debug", action="store_true", help="Skip debug log dumps")
    args = parser.parse_args()

    suite = load_test_suite(args.json)

    if not args.test_name:
        print(f"Available tests in {args.json}:")
        for n in list_tests(args.json):
            print(f"  - {n}")
        return 0

    if not args.output_dir:
        raise SystemExit("--output_dir is required when --test_name is set")

    entry = find_test_entry(suite, args.test_name)
    hw_name = entry.get("hw_config") or suite.get("hw_config")
    if not hw_name:
        raise ValueError(
            f"Test '{args.test_name}' has no 'hw_config' (and no top-level default in {args.json})"
        )
    hw = load_hw_config(hw_name)

    os.makedirs(args.output_dir, exist_ok=True)

    in_tensor, out_tensor = golden_for(entry["params"], make_input_tensor(entry["params"], args.seed))

    write_task_data_header(args.output_dir, 0, in_tensor, out_tensor)
    write_workload_header(args.output_dir, hw, [entry])
    write_test_config_mk(args.output_dir, hw)
    if not args.no_debug:
        write_debug_logs(args.output_dir, 0, in_tensor, out_tensor)

    print(
        f"Generated {entry['name']}: hw={hw_name} "
        f"in={tuple(in_tensor.shape)} out={tuple(out_tensor.shape)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
