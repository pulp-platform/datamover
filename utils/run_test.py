"""Datamover HWPE Test Runner.

Runs JSON-defined tests in parallel via `make sim` with per-test build dirs,
captures pass/fail from stdout markers, and emits JUnit/JSON/CSV reports.
"""

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

from utils.test_loader import load_test_suite


PASS_MARKER = "DATAMOVER_TEST_PASSED"
FAIL_MARKER = "DATAMOVER_TEST_FAILED"


@dataclass
class TestResult:
    name: str
    passed: bool
    time: float
    stdout: str
    stderr: str
    returncode: int


def build_make_command(test: dict, vsim_flags: str) -> str:
    name = test["name"]
    params = test["params"]
    overrides = " ".join(f"{k}={v}" for k, v in params.items())
    gui = "0" if "-c" in vsim_flags else "1"
    build_dir = f"modelsim/build_{name}"
    return (
        f"make sim {overrides} "
        f"SIM_PATH={build_dir}/vsim "
        f"STIMULI_DIR={build_dir}/stim "
        f"GUI={gui}"
    )


def _kill_process_group(process: subprocess.Popen) -> None:
    try:
        os.killpg(os.getpgid(process.pid), signal.SIGKILL)
    except ProcessLookupError:
        pass
    except OSError as e:
        if e.errno != errno.ESRCH:
            raise


def _run_with_pgid(cmd: str, timeout: int):
    start = time.time()
    process = subprocess.Popen(
        cmd, shell=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        preexec_fn=os.setpgrp,
    )
    try:
        try:
            stdout, stderr = process.communicate(timeout=timeout)
            return process.returncode, stdout, stderr, time.time() - start, False
        except subprocess.TimeoutExpired:
            _kill_process_group(process)
            stdout, stderr = process.communicate()
            return 1, stdout, stderr, time.time() - start, True
        except BaseException:
            _kill_process_group(process)
            process.communicate()
            raise
    finally:
        if process.poll() is None:
            _kill_process_group(process)
            process.communicate()


def run_single_test(test: dict, vsim_flags: str, timeout: int) -> TestResult:
    name = test["name"]
    cmd = build_make_command(test, vsim_flags)
    is_gui = "-gui" in vsim_flags or ("-c" not in vsim_flags and "GUI=0" not in cmd)

    print(f"[RUN ] {name}")
    try:
        rc, stdout, stderr, elapsed, timed_out = _run_with_pgid(cmd, timeout)

        if timed_out:
            print(f"[\033[1;31mTIME\033[0m] {name} (timeout after {elapsed:.1f}s)")
            return TestResult(name, False, elapsed, stdout,
                              ("TIMEOUT\n" + stderr) if stderr else "TIMEOUT", 1)

        passed = rc == 0 and PASS_MARKER in stdout and FAIL_MARKER not in stdout

        if is_gui and not passed and rc == 0:
            print(f"[DONE] {name} ({elapsed:.1f}s)")
        else:
            tag = "\033[1;32m OK \033[0m" if passed else "\033[1;31mFAIL\033[0m"
            print(f"[{tag}] {name} ({elapsed:.1f}s)")

        return TestResult(name, passed, elapsed, stdout, stderr, rc)
    except KeyboardInterrupt:
        print(f"[\033[1;31mKILL\033[0m] {name} (interrupted)")
        raise


def run_test_wrapper(args):
    return run_single_test(*args)


def generate_junit_report(results: List[TestResult], output_file: str):
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
    os.makedirs(os.path.dirname(output_file) or ".", exist_ok=True)
    with open(output_file, "w") as f:
        TestSuite.to_file(f, [ts], prettyprint=True)
    print(f"JUnit report: {output_file}")


def generate_json_report(results: List[TestResult], output_file: str):
    report = {
        "total": len(results),
        "passed": sum(1 for r in results if r.passed),
        "failed": sum(1 for r in results if not r.passed),
        "tests": [
            {"name": r.name, "passed": r.passed, "time": r.time, "returncode": r.returncode}
            for r in results
        ],
    }
    os.makedirs(os.path.dirname(output_file) or ".", exist_ok=True)
    with open(output_file, "w") as f:
        json.dump(report, f, indent=2)
    print(f"JSON report: {output_file}")


def generate_metrics_csv(results: List[TestResult], output_file: str):
    os.makedirs(os.path.dirname(output_file) or ".", exist_ok=True)
    with open(output_file, "w") as f:
        f.write("name,passed,time_s,returncode\n")
        for r in results:
            f.write(f"{r.name},{int(r.passed)},{r.time:.6f},{r.returncode}\n")
    print(f"CSV report: {output_file}")


def report_paths(json_file: str, test: Optional[str], report_dir: str) -> dict:
    suite = Path(json_file).stem
    suffix = f"__{test}" if test else ""
    return {
        "junit": os.path.join(report_dir, "junit", f"{suite}{suffix}.xml"),
        "json":  os.path.join(report_dir, "metrics", f"{suite}{suffix}.json"),
        "csv":   os.path.join(report_dir, "metrics", f"{suite}{suffix}.csv"),
    }


def discover_suites(pattern: str) -> List[str]:
    found = []
    for path in sorted(glob.glob(pattern)):
        try:
            with open(path) as f:
                data = json.load(f)
        except Exception:
            continue
        if isinstance(data, dict) and "tests" in data:
            found.append(path)
    return found


def run_suite(args, json_file: str) -> int:
    tests = load_test_suite(json_file)
    if not tests:
        print(f"No tests in {json_file}")
        return 1

    if args.test:
        names = [t["name"] for t in tests]
        tests = [t for t in tests if t["name"] == args.test]
        if not tests:
            print(f"Test '{args.test}' not found in {json_file}")
            print(f"Available: {', '.join(names)}")
            return 1

    print(f"Running {len(tests)} test(s) from {json_file}\n")

    parallel = args.parallel if (args.parallel > 1 and len(tests) > 1) else 1

    if parallel > 1:
        pool_args = [(t, args.vsim_flags, args.timeout) for t in tests]
        old_sigint = signal.signal(signal.SIGINT, signal.SIG_IGN)
        pool = multiprocessing.Pool(parallel)
        signal.signal(signal.SIGINT, old_sigint)
        try:
            results = pool.map(run_test_wrapper, pool_args)
            pool.close()
            pool.join()
        except KeyboardInterrupt:
            print("\nTerminating run_test.py")
            pool.terminate()
            pool.join()
            return 1
    else:
        try:
            results = [run_single_test(t, args.vsim_flags, args.timeout) for t in tests]
        except KeyboardInterrupt:
            print("\nTerminating run_test.py")
            return 1

    results.sort(key=lambda r: r.name)

    passed = sum(1 for r in results if r.passed)
    failed = len(results) - passed
    print(f"\nResults: {passed}/{len(results)} passed")
    if failed:
        print("\nFailed tests:")
        for r in results:
            if not r.passed:
                print(f"  - {r.name}")

    if not args.no_report:
        paths = report_paths(json_file, args.test, args.report_dir)
        generate_junit_report(results, paths["junit"])
        generate_json_report(results, paths["json"])
        generate_metrics_csv(results, paths["csv"])

    return 0 if failed == 0 else 1


def main():
    p = argparse.ArgumentParser(description="Datamover HWPE Test Runner")
    p.add_argument("json_file", nargs="?", help="JSON test suite file")
    p.add_argument("--discover-glob", type=str, help="Glob to discover JSON suites")
    p.add_argument("--test", "-t", type=str, help="Run only the named test")
    p.add_argument("--parallel", "-p", type=int, default=4, help="Parallel processes")
    p.add_argument("--timeout", type=int, default=600, help="Timeout per test (s)")
    p.add_argument("--report-dir", default="reports", help="Report directory")
    p.add_argument("--no-report", action="store_true", help="Disable report generation")
    p.add_argument("--vsim-flags", default="-c", help="VSIM flags ('-c' headless, '-gui' GUI)")

    args = p.parse_args()

    if "-gui" in args.vsim_flags and args.parallel > 1:
        print("GUI mode detected, forcing parallel=1")
        args.parallel = 1

    if not args.json_file and not args.discover_glob:
        p.error("Provide json_file or --discover-glob")
    if args.json_file and args.discover_glob:
        p.error("Use either json_file or --discover-glob, not both")

    if args.discover_glob:
        suites = discover_suites(args.discover_glob)
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
