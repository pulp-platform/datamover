# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors: Lionnus Kesting <lkesting@iis.ee.ethz.ch>

"""Spec-driven suite generation.

A *spec* describes one workload family as a set of axis value-sets. This module draws
candidate parameter combinations, and keeps the candidates that pass the central
legality validation. The module emits a plain suite JSON file that the normal
`make tests` runner consumes without changes.

An axis value-set has one of three forms: an explicit `list`, a random integer range
`{"min","max"}` (optionally snapped to a multiple with `"multiple_of"`), or a scalar
constant. The module draws each axis randomly for each candidate.

A `list` axis may also hold objects (a *group* axis). The draw then merges the object
entries into the candidate, so one draw sets several params together — for example a
kernel size tied to its stride. The axis name is only a label. The first and the last
object are the boundary values.

When every axis is finite (a list or a scalar) and the full cross product fits the
draw budget, the module enumerates the product instead of sampling, so every
combination is covered exactly once.

A `{"min","max"}` range may also carry `"tile"`. Random draws then stay uniform over
the full range, unlike `"multiple_of"`, which snaps every draw. In addition, the module
always emits every multiple of `tile` in the range as a guaranteed corner case (see
`tile_candidates`), so the exact-tile sizes always get exercised.

This module does not re-encode any constraint. `validate_candidate` delegates every
legality check to the layers that already enforce the checks.
"""

import argparse
import glob
import itertools
import json
import random
import sys
from collections import Counter
from pathlib import Path

# ============================================================================
# Project adapter -- the only repo-specific section
# ============================================================================
# Everything below the adapter is generic. Keep the generic part line-identical
# with the Surya copy of this module, so the sweep can move into a shared
# testing package later.

from datamover_model.workloads.generator import generate_task_data
from datamover_model.workloads.suite import auto_test_name, hw_tag, load_hw_config, normalize_params

# Spec `op` -> fixed params merged under the drawn axes.
OP_TO_PARAMS = {
    "copy": {"DATAMOVER_MODE": 0},
    "transpose": {"DATAMOVER_MODE": 1},
    "cim": {"DATAMOVER_MODE": 2},
    "cim_transpose": {"DATAMOVER_MODE": 3},
    "unfold": {"DATAMOVER_MODE": 4},
    "fold": {"DATAMOVER_MODE": 5},
    "im2col": {"DATAMOVER_MODE": 6},
}

OPS = tuple(sorted(OP_TO_PARAMS))
DEFAULT_MAX_TESTS = 30


def load_hw(spec: dict):
    """Opaque HW context handed to `validate_candidate`; here the config name."""
    load_hw_config(spec["hw_config"])
    return spec["hw_config"]


def validate_candidate(op: str, params: dict, hw, deep: bool = False):
    """Return (derived_name, None) if the candidate is legal, else return (None, reason).

    `normalize_params` enforces the parameter rules. The golden-model run enforces
    every shape rule and the TB memory budget; the datamover has no separate task
    class, so the golden run is the shape validator and always runs (`deep` has no
    effect here).
    """
    try:
        full = normalize_params({**OP_TO_PARAMS[op], **params})
        generate_task_data({"name": "candidate", "params": full}, seed=0)
        return auto_test_name(full, hw_tag(hw)), None
    except (ValueError, AssertionError, KeyError, TypeError, IndexError, RuntimeError) as e:
        return None, f"{type(e).__name__}: {e}"


def make_test_entry(op: str, params: dict) -> dict:
    """Suite JSON entry for one accepted candidate."""
    return {"params": {**OP_TO_PARAMS[op], **params}}


def suite_extra_fields(spec: dict) -> dict:
    """Optional suite-level fields; the datamover Makefile only knows STALL."""
    if "stall" in spec:
        return {"make_args": f"STALL={spec['stall']}"}
    return {}


# ============================================================================
# Generic sweep
# ============================================================================

# Per-target candidate draws before giving up on reaching `max_tests`.
OVERSAMPLE = 8


def draw_axis(value, rng: random.Random):
    """Draw one random value for an axis."""
    if isinstance(value, list):
        return rng.choice(value)
    if isinstance(value, dict):
        lo, hi = value["min"], value["max"]
        k = value.get("multiple_of")
        if k:
            return rng.randrange(lo + (-lo % k), hi + 1, k)
        return rng.randint(lo, hi)
    return value


def axis_bounds(value) -> tuple:
    """Lowest and highest value an axis can take."""
    if isinstance(value, list):
        if all(isinstance(v, (int, float)) for v in value):
            return min(value), max(value)
        return value[0], value[-1]
    if isinstance(value, dict):
        lo, hi, k = value["min"], value["max"], value.get("multiple_of")
        if k:
            return lo + (-lo % k), hi - (hi % k)
        return lo, hi
    return value, value


def boundary_candidates(spec: dict) -> list:
    """Corner cases: the smallest workload (all axes low), the biggest workload (all
    axes high), and each axis driven to each extreme against the opposite background."""
    axes = spec["axes"]
    names = list(axes)
    lo = {n: axis_bounds(axes[n])[0] for n in names}
    hi = {n: axis_bounds(axes[n])[1] for n in names}
    cands = [dict(lo), dict(hi)]
    for n in names:
        cands.append({**hi, n: lo[n]})
        cands.append({**lo, n: hi[n]})
    return cands


def tile_multiples(lo: int, hi: int, tile: int) -> list:
    """Every multiple of `tile` within [lo, hi] (inclusive)."""
    return list(range(lo + (-lo % tile), hi + 1, tile))


def tile_candidates(spec: dict) -> list:
    """Exact-tile sizes. For each axis that declares a `tile`, the function drives that axis
    through every tile multiple in its range, and holds the other axes at each extreme. This
    way, the no-remainder (whole-tile) shapes always get exercised, regardless of sampling."""
    axes = spec["axes"]
    names = list(axes)
    lo = {n: axis_bounds(axes[n])[0] for n in names}
    hi = {n: axis_bounds(axes[n])[1] for n in names}
    cands = []
    for n in names:
        ax = axes[n]
        if not (isinstance(ax, dict) and "tile" in ax):
            continue
        for m in tile_multiples(ax["min"], ax["max"], ax["tile"]):
            cands.append({**hi, n: m})
            cands.append({**lo, n: m})
    return cands


def expand_groups(cand: dict) -> dict:
    """Merge group-axis draws: a dict value splats its entries into the candidate."""
    out = {}
    for k, v in cand.items():
        if isinstance(v, dict):
            out.update(v)
        else:
            out[k] = v
    return out


def finite_values(value):
    """The full value list of a finite axis, or None for a random range."""
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        return None
    return [value]


def iter_candidates(spec: dict):
    """Yield candidate param dicts (the drawn axes only)."""
    axes = spec["axes"]
    names = list(axes)
    excludes = spec.get("exclude", [])
    rng = random.Random(spec.get("seed", 0))
    budget = spec.get("max_tests", DEFAULT_MAX_TESTS) * OVERSAMPLE

    def keep(cand: dict) -> bool:
        return not any(all(cand.get(k) == v for k, v in ex.items()) for ex in excludes)

    finite = [finite_values(axes[n]) for n in names]
    if all(v is not None for v in finite):
        total = 1
        for v in finite:
            total *= len(v)
        if total <= budget:
            for combo in itertools.product(*finite):
                cand = expand_groups(dict(zip(names, combo)))
                if keep(cand):
                    yield cand
            return

    if spec.get("boundaries", True):
        for cand in boundary_candidates(spec):
            cand = expand_groups(cand)
            if keep(cand):
                yield cand
        for cand in tile_candidates(spec):
            cand = expand_groups(cand)
            if keep(cand):
                yield cand

    for _ in range(budget):
        cand = expand_groups({n: draw_axis(axes[n], rng) for n in names})
        if keep(cand):
            yield cand


def generate_suite(spec: dict, deep: bool = False):
    """Expand one spec into (suite_dict, stats_dict).

    `stats["reasons"]` counts the rejected candidates by reason, so callers can report the counts.
    """
    op = spec["op"]
    if op not in OPS:
        raise ValueError(f"unknown op '{op}', expected one of {sorted(OPS)}")
    hw = load_hw(spec)
    max_tests = spec.get("max_tests", DEFAULT_MAX_TESTS)

    tests, seen = [], set()
    stats = {"candidates": 0, "valid": 0, "rejected": 0, "reasons": Counter()}
    for params in iter_candidates(spec):
        stats["candidates"] += 1
        dname, reason = validate_candidate(op, params, hw, deep)
        if dname is None:
            stats["rejected"] += 1
            stats["reasons"][reason] += 1
            continue
        stats["valid"] += 1
        if dname in seen:
            continue
        seen.add(dname)
        tests.append(make_test_entry(op, params))
        if len(tests) >= max_tests:
            break

    suite = {"hw_config": spec["hw_config"], "name": spec["name"], "tests": tests}
    suite.update(suite_extra_fields(spec))
    return suite, stats


def dump_suite(suite: dict) -> str:
    """Suite JSON text with one test per line, as in the hand-written suites."""
    head = "".join(
        f"  {json.dumps(k)}: {json.dumps(v)},\n" for k, v in suite.items() if k != "tests"
    )
    tests = ",\n".join(f"    {json.dumps(t)}" for t in suite["tests"])
    return f'{{\n{head}  "tests": [\n{tests}\n  ]\n}}\n'


def _load_spec(path: str) -> dict:
    with open(path) as f:
        return json.load(f)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Generate suite JSONs from sweep specs.")
    ap.add_argument(
        "--spec-glob", required=True, help="glob of spec files, e.g. 'tests/specs/*.spec.json'"
    )
    ap.add_argument("--out-dir", default="tests/generated", help="output directory")
    ap.add_argument("--dry-run", action="store_true", help="print counts, write nothing")
    ap.add_argument("--deep", action="store_true", help="also run golden compute per candidate")
    args = ap.parse_args(argv)

    spec_paths = sorted(glob.glob(args.spec_glob))
    if not spec_paths:
        ap.error(f"no specs match '{args.spec_glob}'")

    out_dir = Path(args.out_dir)
    if not args.dry_run:
        out_dir.mkdir(parents=True, exist_ok=True)

    empty = []
    for path in spec_paths:
        spec = _load_spec(path)
        name = spec["name"]
        suite, stats = generate_suite(spec, deep=args.deep)
        kept = len(suite["tests"])
        print(
            f"{name}: {stats['candidates']} candidates -> {stats['valid']} valid "
            f"-> {kept} unique (cap {spec.get('max_tests', DEFAULT_MAX_TESTS)})  "
            f"[rejected: {stats['rejected']}]"
        )
        for reason, count in stats["reasons"].most_common(5):
            print(f"  flagged {count}x: {reason}")
        if kept == 0:
            empty.append(name)
        if not args.dry_run and kept:
            out_path = out_dir / f"{name}.json"
            out_path.write_text(dump_suite(suite))
            print(f"wrote {out_path}")

    if empty:
        print(f"ERROR: specs produced zero tests: {', '.join(empty)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
