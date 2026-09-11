# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Author: Lionnus Kesting <lkesting@iis.ee.ethz.ch>

"""Summarize a URG dashboard report and emit the CI-parsable coverage line."""

import argparse
import json
import re
import sys
from pathlib import Path

DEFAULT_METRIC = "SCORE"

_SUMMARY_RE = re.compile(
    r"Total Coverage Summary\s*\n\s*(?P<head>[A-Z ]+?)\s*\n\s*(?P<vals>[\d.\s]+?)\n",
)
_NTESTS_RE = re.compile(r"Number of tests:\s*(\d+)")


def parse_dashboard(text: str) -> tuple[dict[str, float], int | None]:
    m = _SUMMARY_RE.search(text)
    if not m:
        raise ValueError("no 'Total Coverage Summary' block found in dashboard report")
    names = m.group("head").split()
    values = [float(v) for v in m.group("vals").split()]
    if len(names) != len(values):
        raise ValueError(f"malformed summary block: {names} vs {values}")
    n = _NTESTS_RE.search(text)
    return dict(zip(names, values, strict=True)), (int(n.group(1)) if n else None)


def main() -> int:
    parser = argparse.ArgumentParser(description="URG coverage summary")
    parser.add_argument("dashboard", help="Path to urgReport/dashboard.txt")
    parser.add_argument("--label", default="", help="Configuration name shown in the header")
    parser.add_argument(
        "--metric", default=DEFAULT_METRIC, help=f"Headline metric (default: {DEFAULT_METRIC})"
    )
    parser.add_argument("--json-out", help="Also write the metrics as JSON to this path")
    args = parser.parse_args()

    path = Path(args.dashboard)
    if not path.is_file():
        print(f"ERROR: no coverage dashboard at {path}", file=sys.stderr)
        return 1
    try:
        metrics, n_tests = parse_dashboard(path.read_text())
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    if args.metric not in metrics:
        print(f"ERROR: metric '{args.metric}' not in {sorted(metrics)}", file=sys.stderr)
        return 1

    label = f" [{args.label}]" if args.label else ""
    tests = f" ({n_tests} tests)" if n_tests is not None else ""
    print(f"Coverage summary{label}{tests}:")
    print("  " + "  ".join(f"{k} {v:.2f}" for k, v in metrics.items()))
    print(f"Total coverage: {metrics[args.metric]:.2f}%")

    if args.json_out:
        out = Path(args.json_out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(
            json.dumps(
                {"label": args.label, "metric": args.metric, "tests": n_tests, "metrics": metrics},
                indent=2,
            )
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
