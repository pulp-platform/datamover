#!/usr/bin/env python3
# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors: Lionnus Kesting <lkesting@iis.ee.ethz.ch>

"""Print the canonical auto-derived test name for a single workload.

Used by mk/config.mk to compute TEST_NAME in CLI mode without duplicating the
naming algorithm in Make. The JSON path derives names via the same
suite.auto_test_name.
"""

import argparse
import sys

from datamover_model.workloads.suite import PARAM_DEFAULTS, auto_test_name, hw_tag, normalize_params


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Print the canonical auto test name")
    for k in PARAM_DEFAULTS:
        p.add_argument(f"--{k}", type=int)
    p.add_argument("--HW_CONFIG", default="")
    return p


def main() -> int:
    args = build_parser().parse_args()
    raw = {k: getattr(args, k) for k in PARAM_DEFAULTS if getattr(args, k) is not None}
    print(auto_test_name(normalize_params(raw), hw_tag(args.HW_CONFIG)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
