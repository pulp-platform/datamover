# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors: Lionnus Kesting <lkesting@iis.ee.ethz.ch>

"""TestResult data type + JUnit / JSON / CSV report writers."""

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional


@dataclass
class TestResult:
    name: str
    passed: bool
    time: float
    stdout: str
    stderr: str
    returncode: int
    status: str = "mismatch"  # pass | mismatch | build | timeout
    hwpe_cycles: Optional[int] = None


def generate_junit_report(results: List[TestResult], output_file: str):
    try:
        from junit_xml import TestCase, TestSuite
    except ImportError:
        print("Warning: junit_xml not installed, skipping JUnit report")
        return

    test_cases = []
    for r in results:
        tc = TestCase(name=r.name, classname="datamover_tests", elapsed_sec=r.time, stdout=r.stdout, stderr=r.stderr)
        if not r.passed:
            tc.add_failure_info(r.stderr or "Test failed")
        test_cases.append(tc)

    ts = TestSuite("Datamover HWPE Tests", test_cases)
    os.makedirs(os.path.dirname(output_file) or ".", exist_ok=True)
    with open(output_file, "w") as f:
        TestSuite.to_file(f, [ts], prettyprint=True)


def generate_json_report(results: List[TestResult], output_file: str):
    report = {
        "total": len(results),
        "passed": sum(1 for r in results if r.passed),
        "failed": sum(1 for r in results if not r.passed),
        "tests": [
            {
                "name": r.name,
                "passed": r.passed,
                "status": r.status,
                "time": r.time,
                "returncode": r.returncode,
                "hwpe_cycles": r.hwpe_cycles,
            }
            for r in results
        ],
    }
    os.makedirs(os.path.dirname(output_file) or ".", exist_ok=True)
    with open(output_file, "w") as f:
        json.dump(report, f, indent=2)


def generate_metrics_csv(results: List[TestResult], output_file: str):
    os.makedirs(os.path.dirname(output_file) or ".", exist_ok=True)
    with open(output_file, "w") as f:
        f.write("name,passed,status,time_s,hwpe_cycles\n")
        for r in results:
            f.write(
                f"{r.name},{int(r.passed)},{r.status},{r.time:.6f},"
                f"{'' if r.hwpe_cycles is None else r.hwpe_cycles}\n"
            )


def build_default_report_paths(json_file: str, test: Optional[str], report_dir: str) -> dict:
    suite_name = Path(json_file).stem
    suffix = f"__{test}" if test else ""
    return {
        "junit": os.path.join(report_dir, "junit", f"{suite_name}{suffix}.xml"),
        "json": os.path.join(report_dir, "metrics", f"{suite_name}{suffix}.json"),
        "csv": os.path.join(report_dir, "metrics", f"{suite_name}{suffix}.csv"),
    }
