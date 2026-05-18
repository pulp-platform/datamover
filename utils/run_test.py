#!/usr/bin/env python3
# Copyright (C) 2025-2026 ETH Zurich and University of Bologna
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

"""Datamover HWPE test runner."""

import argparse
import errno
import glob
import json
import multiprocessing
import os
import re
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional

from utils.gen_workload_header import list_tests as gen_list_tests


@dataclass
class TestResult:
    name: str
    passed: bool
    time: float
    stdout: str
    stderr: str
    returncode: int
    hwpe_cycles: Optional[int] = None


def parse_metrics(stdout: str) -> dict:
    metrics = {"hwpe_cycles": None}
    m = re.findall(r"hwpe_cycles\s*=\s*(\d+)", stdout)
    if m:
        metrics["hwpe_cycles"] = int(m[-1])
    return metrics


def build_make_command(test_name: str, json_file: str, vsim_flags: str) -> str:
    no_debug = os.environ.get("NO_DEBUG", "0")
    return (
        f"riscv make TEST_JSON={json_file} TEST_NAME={test_name} NO_DEBUG={no_debug} "
        f"VSIM_FLAGS='{vsim_flags}' run-sim-pipeline"
    )


def _kill_pg(p: subprocess.Popen) -> None:
    try:
        os.killpg(os.getpgid(p.pid), signal.SIGKILL)
    except ProcessLookupError:
        pass
    except OSError as e:
        if e.errno != errno.ESRCH:
            raise


def _run(cmd: str, timeout: int):
    start = time.time()
    p = subprocess.Popen(
        cmd, shell=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, preexec_fn=os.setpgrp,
    )
    try:
        try:
            try:
                os.setpgid(p.pid, p.pid)
            except OSError as e:
                if e.errno != errno.EACCES:
                    raise
            stdout, stderr = p.communicate(timeout=timeout)
            return p.returncode, stdout, stderr, time.time() - start, False
        except subprocess.TimeoutExpired:
            _kill_pg(p)
            stdout, stderr = p.communicate()
            return 1, stdout, stderr, time.time() - start, True
        except BaseException:
            _kill_pg(p)
            p.communicate()
            raise
    finally:
        if p.poll() is None:
            _kill_pg(p)
            p.communicate()


def run_single(test_name: str, json_file: str, vsim_flags: str, timeout: int) -> TestResult:
    cmd = build_make_command(test_name, json_file, vsim_flags)
    is_gui = "-gui" in vsim_flags
    print(f"[RUN ] {test_name}")
    try:
        rc, out, err, elapsed, timed_out = _run(cmd, timeout)
        m = parse_metrics(out)
        if timed_out:
            print(f"[\033[1;31mTIME\033[0m] {test_name} (timeout after {elapsed:.1f}s)")
            return TestResult(test_name, False, elapsed, out,
                              ("TIMEOUT\n" + err) if err else "TIMEOUT", 1, m["hwpe_cycles"])
        passed = rc == 0 and "==== TEST PASSED ====" in out
        if is_gui and not passed and rc == 0:
            print(f"[DONE] {test_name} ({elapsed:.1f}s)")
        else:
            tag = "\033[1;32m OK \033[0m" if passed else "\033[1;31mFAIL\033[0m"
            print(f"[{tag}] {test_name} ({elapsed:.1f}s)")
        return TestResult(test_name, passed, elapsed, out, err, rc, m["hwpe_cycles"])
    except KeyboardInterrupt:
        print(f"[\033[1;31mKILL\033[0m] {test_name} (interrupted)")
        raise


def run_wrapper(args):
    return run_single(*args)


def junit_report(results: List[TestResult], path: str) -> None:
    try:
        from junit_xml import TestSuite, TestCase
    except ImportError:
        print("Warning: junit_xml not installed, skipping JUnit report")
        return
    cases = []
    for r in results:
        tc = TestCase(name=r.name, classname="datamover_tests",
                      elapsed_sec=r.time, stdout=r.stdout, stderr=r.stderr)
        if not r.passed:
            tc.add_failure_info(r.stderr or "Test failed")
        cases.append(tc)
    ts = TestSuite("Datamover HWPE Tests", cases)
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    with open(path, 'w') as f:
        TestSuite.to_file(f, [ts], prettyprint=True)
    print(f"JUnit report: {path}")


def json_report(results: List[TestResult], path: str) -> None:
    payload = {
        "total": len(results),
        "passed": sum(1 for r in results if r.passed),
        "failed": sum(1 for r in results if not r.passed),
        "tests": [
            {"name": r.name, "passed": r.passed, "time": r.time,
             "returncode": r.returncode, "hwpe_cycles": r.hwpe_cycles}
            for r in results
        ],
    }
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    with open(path, 'w') as f:
        json.dump(payload, f, indent=2)
    print(f"JSON report: {path}")


def csv_report(results: List[TestResult], path: str) -> None:
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    with open(path, 'w') as f:
        f.write("name,passed,time_s,hwpe_cycles\n")
        for r in results:
            f.write(f"{r.name},{int(r.passed)},{r.time:.6f},"
                    f"{'' if r.hwpe_cycles is None else r.hwpe_cycles}\n")
    print(f"CSV report: {path}")


def report_paths(json_file: str, test: Optional[str], report_dir: str) -> dict:
    suite = Path(json_file).stem
    suffix = f"__{test}" if test else ""
    return {
        "junit": os.path.join(report_dir, "junit", f"{suite}{suffix}.xml"),
        "json":  os.path.join(report_dir, "metrics", f"{suite}{suffix}.json"),
        "csv":   os.path.join(report_dir, "metrics", f"{suite}{suffix}.csv"),
    }


def discover_jsons(pattern: str) -> List[str]:
    found = []
    for path in sorted(glob.glob(pattern)):
        try:
            with open(path) as f:
                d = json.load(f)
        except Exception:
            continue
        if isinstance(d, dict) and "tests" in d:
            found.append(path)
    return found


def run_suite(args, json_file: str) -> int:
    names = gen_list_tests(json_file)
    if not names:
        print(f"No tests found in {json_file}")
        return 1
    if args.test:
        if args.test not in names:
            print(f"Test '{args.test}' not found in {json_file}")
            print(f"Available: {', '.join(names)}")
            return 1
        names = [args.test]

    print(f"Running {len(names)} test(s) from {json_file}")
    print()

    work = [(n, json_file, args.vsim_flags, args.timeout) for n in names]

    if args.parallel > 1 and len(names) > 1:
        old = signal.signal(signal.SIGINT, signal.SIG_IGN)
        pool = multiprocessing.Pool(args.parallel)
        signal.signal(signal.SIGINT, old)
        try:
            results = pool.map(run_wrapper, work)
            pool.close()
            pool.join()
        except KeyboardInterrupt:
            print("\nTerminating run_test.py")
            pool.terminate()
            pool.join()
            return 1
    else:
        try:
            results = [run_single(*w) for w in work]
        except KeyboardInterrupt:
            print("\nTerminating run_test.py")
            return 1

    results.sort(key=lambda r: r.name)
    print()
    passed = sum(1 for r in results if r.passed)
    failed = len(results) - passed
    print(f"Results: {passed}/{len(results)} passed")
    if failed:
        print("\nFailed tests:")
        for r in results:
            if not r.passed:
                print(f"  - {r.name}")

    if not args.no_report:
        rp = report_paths(json_file, args.test, args.report_dir)
        junit_report(results, rp["junit"])
        json_report(results, rp["json"])
        csv_report(results, rp["csv"])

    return 0 if failed == 0 else 1


def main():
    parser = argparse.ArgumentParser(description="Datamover HWPE Test Runner")
    parser.add_argument("json_file", nargs="?", help="JSON test suite file")
    parser.add_argument("--discover-glob", type=str, help="Run all matching JSON suites")
    parser.add_argument("--test", "-t", type=str, help="Run a specific test by name")
    parser.add_argument("--parallel", "-p", type=int, default=8, help="Parallel workers")
    parser.add_argument("--timeout", type=int, default=3600, help="Per-test timeout (s)")
    parser.add_argument("--report-dir", default="reports", help="Report directory")
    parser.add_argument("--no-report", action="store_true", help="Skip report generation")
    parser.add_argument("--vsim-flags", default="-gui", help="VSIM flags")
    args = parser.parse_args()

    if "-gui" in args.vsim_flags and args.parallel > 1:
        print("GUI mode detected, forcing parallel=1")
        args.parallel = 1

    if not args.json_file and not args.discover_glob:
        parser.error("Provide json_file or --discover-glob")
    if args.json_file and args.discover_glob:
        parser.error("Use either json_file or --discover-glob, not both")

    if args.discover_glob:
        suites = discover_jsons(args.discover_glob)
        if not suites:
            print(f"No test JSON files found (glob: {args.discover_glob})")
            sys.exit(1)
        rc = 0
        for s in suites:
            print(f"\n=== Suite: {s} ===")
            rc = run_suite(args, s) or rc
        sys.exit(rc)

    sys.exit(run_suite(args, args.json_file))


if __name__ == "__main__":
    main()
