#!/usr/bin/env python3
# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors: Lionnus Kesting <lkesting@iis.ee.ethz.ch>

"""CLI entrypoint: build a task and emit the C artifacts for one test.

Two modes:
  JSON mode  --json FILE [--test_name NAME]   take a test entry from a suite
  CLI mode   --DATAMOVER_MODE ... --BANDWIDTH ...  build a single task from flags
             (used by the Makefile test-<mode> quick targets)

Emits, into the build directory:

    datamover_workload.h   x-macro task table + HW/per-task #defines
    task<i>_data.h         golden_in / golden_out byte arrays
    test_config.mk         RTL compile-time params (BANDWIDTH, ...)
    debug_logs_task<i>/    {golden_in,golden_out} dec/hex dumps
"""

import argparse
import os
import sys

from datamover_model.headers.emit import HW_KEYS, emit_task_artifacts, write_test_config_mk, write_workload_header
from datamover_model.testing.debug import write_task_debug
from datamover_model.workloads.generator import TaskData, generate_chain_data, generate_task_data
from datamover_model.workloads.suite import (
    PARAM_DEFAULTS,
    auto_test_name,
    find_test_entry,
    list_tests,
    load_hw_config,
    load_test_suite,
    normalize_params,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate datamover C test headers.")
    parser.add_argument("--json", help="Unified test JSON file (JSON mode)")
    parser.add_argument("--test_name", help="Test name; in JSON mode, omit to list tests")
    parser.add_argument("--output_dir", help="Build directory (required unless listing tests)")
    parser.add_argument("--seed", type=int, default=42, help="Random seed for stimuli")
    parser.add_argument("--no-debug", action="store_true", help="Skip debug log dumps")
    # CLI mode: workload params + HW params (built from Make variables)
    for k in PARAM_DEFAULTS:
        parser.add_argument(f"--{k}", type=int)
    for k in HW_KEYS:
        parser.add_argument(f"--{k}", type=int)
    return parser


def _resolve(args):
    """Return (entry, hw, label). entry is None when only listing JSON tests."""
    if args.json:
        if not args.test_name:
            return None, None, None
        entry = find_test_entry(args.json, args.test_name)
        hw_name = entry.get("hw_config") or load_test_suite(args.json).get("hw_config")
        if not hw_name:
            raise ValueError(f"Test '{args.test_name}' has no 'hw_config' (and no default in {args.json})")
        return entry, load_hw_config(hw_name), hw_name

    raw = {k: getattr(args, k) for k in PARAM_DEFAULTS if getattr(args, k) is not None}
    params = normalize_params(raw)
    missing = [k for k in HW_KEYS if getattr(args, k) is None]
    if missing:
        raise SystemExit("CLI mode requires HW params: " + ", ".join(f"--{k}" for k in missing))
    hw = {k: getattr(args, k) for k in HW_KEYS}
    name = args.test_name or auto_test_name(params)
    return {"name": name, "params": params}, hw, "cli"


def main() -> int:
    args = build_parser().parse_args()
    entry, hw, label = _resolve(args)

    if entry is None:
        print(f"Available tests in {args.json}:")
        for name in list_tests(args.json):
            print(f"  - {name}")
        return 0

    if not args.output_dir:
        raise SystemExit("--output_dir is required")

    os.makedirs(args.output_dir, exist_ok=True)

    if "chain" in entry:
        input_tensor, stages = generate_chain_data(entry, seed=args.seed)
        n = len(stages)
        metas = []
        for i, (params, out) in enumerate(stages):
            result = TaskData(name=entry["name"], params=params,
                              in_tensor=(input_tensor if i == 0 else None), out_tensor=out)
            # Verify every stage against its own golden (pinpoints the failing stage),
            # except a stage whose output buffer the next stage overwrites as scratch
            # (cim_layout_transpose / mode 3 uses its input buffer as scratch).
            next_clobbers = (i + 1 < n) and (stages[i + 1][0]["DATAMOVER_MODE"] == 3)
            metas.append(emit_task_artifacts(result, args.output_dir, index=i,
                                             in_from=(None if i == 0 else i - 1),
                                             verify=not next_clobbers))
            if not args.no_debug and i == 0:
                write_task_debug(result, args.output_dir, index=0)
        write_workload_header(metas, hw, args.output_dir)
        write_test_config_mk(hw, args.output_dir)
        print(f"Generated chain {entry['name']}: hw={label} {n} stages, "
              f"in={tuple(input_tensor.shape)} out={tuple(stages[-1][1].shape)}")
        return 0

    result = generate_task_data(entry, seed=args.seed)
    meta = emit_task_artifacts(result, args.output_dir, index=0)
    write_workload_header([meta], hw, args.output_dir)
    write_test_config_mk(hw, args.output_dir)
    if not args.no_debug:
        write_task_debug(result, args.output_dir, index=0)

    print(f"Generated {entry['name']}: hw={label} "
          f"in={tuple(result.in_tensor.shape)} out={tuple(result.out_tensor.shape)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
