#!/usr/bin/env python3
# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Author: Lionnus Kesting <lkesting@iis.ee.ethz.ch>

"""Datamover HWPE test runner (rich live progress, only/skip filters)."""

import argparse
import ctypes
import errno
import fnmatch
import glob
import json
import multiprocessing
import os
import re
import select
import signal
import subprocess
import sys
import termios
import threading
import time
import tty
from typing import List, Optional, Tuple

from rich.console import Console
from rich.live import Live
from rich.progress import (
    BarColumn,
    MofNCompleteColumn,
    Progress,
    TextColumn,
    TimeElapsedColumn,
)
from rich.text import Text

from datamover_model.testing.reports import (
    TestResult,
    build_default_report_paths,
    generate_json_report,
    generate_junit_report,
    generate_metrics_csv,
)
from datamover_model.workloads.suite import list_tests

STATUS_PASS = "pass"
STATUS_MISMATCH = "mismatch"
STATUS_BUILD = "build"
STATUS_TIMEOUT = "timeout"

MARK_TB_PASS = "==== TEST PASSED ===="
MARK_TB_FAIL = "==== TEST FAILED ===="
MARK_RUNNER_TIMEOUT = "TIMEOUT"

_PR_SET_PDEATHSIG = 1
try:
    _libc = ctypes.CDLL("libc.so.6", use_errno=True)
except OSError:
    _libc = None

_current_child_pgid: Optional[int] = None


def _preexec_isolate_and_die_with_parent():
    os.setpgrp()
    if _libc is not None:
        _libc.prctl(_PR_SET_PDEATHSIG, signal.SIGKILL, 0, 0, 0)


def _kill_current_child_and_exit(signum, frame):
    if _current_child_pgid is not None:
        try:
            os.killpg(_current_child_pgid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError, OSError):
            pass
    os._exit(1)


_STARTED_QUEUE: Optional["multiprocessing.Queue"] = None


def _worker_init(started_queue=None):
    global _STARTED_QUEUE
    _STARTED_QUEUE = started_queue
    signal.signal(signal.SIGTERM, _kill_current_child_and_exit)


def parse_metrics(stdout: str) -> dict:
    metrics = {"hwpe_cycles": None}
    m = re.findall(r"hwpe_cycles\s*=\s*(\d+)", stdout)
    if m:
        metrics["hwpe_cycles"] = int(m[-1])
    return metrics


def build_make_command(test: dict, json_file: str, vsim_flags: str = "-gui", make_args: str = "") -> str:
    """riscv make command running one test through the generate+execute pipeline."""
    no_debug = os.environ.get("NO_DEBUG", "0")
    extra = f" {make_args}" if make_args else ""
    return (
        f"riscv make TEST_JSON={json_file} TEST_NAME={test['name']} "
        f"NO_DEBUG={no_debug} VSIM_FLAGS='{vsim_flags}'{extra} run-sim-pipeline"
    )


def _kill_process_group(process: subprocess.Popen) -> None:
    try:
        os.killpg(os.getpgid(process.pid), signal.SIGKILL)
    except ProcessLookupError:
        pass
    except OSError as e:
        if e.errno != errno.ESRCH:
            raise


def _drain(process: subprocess.Popen) -> Tuple[str, str]:
    try:
        return process.communicate(timeout=2)
    except subprocess.TimeoutExpired:
        return "", ""


def _run_command_with_process_group(cmd: str, timeout: int):
    global _current_child_pgid
    start_time = time.time()
    process = subprocess.Popen(
        cmd, shell=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        preexec_fn=_preexec_isolate_and_die_with_parent,
    )
    _current_child_pgid = process.pid
    try:
        try:
            try:
                os.setpgid(process.pid, process.pid)
            except OSError as e:
                if e.errno != errno.EACCES:
                    raise
            stdout, stderr = process.communicate(timeout=timeout)
            return process.returncode, stdout, stderr, time.time() - start_time, False
        except subprocess.TimeoutExpired:
            _kill_process_group(process)
            stdout, stderr = _drain(process)
            return 1, stdout, stderr, time.time() - start_time, True
        except BaseException:
            _kill_process_group(process)
            _drain(process)
            raise
    finally:
        if process.poll() is None:
            _kill_process_group(process)
            _drain(process)
        _current_child_pgid = None


def run_single_test(test: dict, json_file: str, vsim_flags: str, timeout: int, make_args: str = "") -> TestResult:
    test_name = test["name"]
    if _STARTED_QUEUE is not None:
        try:
            _STARTED_QUEUE.put_nowait(test_name)
        except Exception:
            pass
    cmd = build_make_command(test, json_file, vsim_flags, make_args)
    returncode, stdout, stderr, elapsed, timed_out = _run_command_with_process_group(cmd, timeout)
    metrics = parse_metrics(stdout)
    if timed_out:
        status = STATUS_TIMEOUT
    elif MARK_TB_PASS in stdout:
        status = STATUS_PASS
    elif MARK_TB_FAIL in stdout:
        status = STATUS_MISMATCH
    else:
        status = STATUS_BUILD
    if status == STATUS_TIMEOUT:
        stderr = f"{MARK_RUNNER_TIMEOUT}\n{stderr}" if stderr else MARK_RUNNER_TIMEOUT
    return TestResult(
        name=test_name, passed=(status == STATUS_PASS), time=elapsed,
        stdout=stdout, stderr=stderr,
        returncode=returncode if not timed_out else 1, status=status, **metrics,
    )


def run_test_wrapper(args):
    return run_single_test(*args)


def discover_test_json_files(pattern: str) -> List[str]:
    discovered = []
    for path in sorted(glob.glob(pattern)):
        try:
            with open(path) as f:
                data = json.load(f)
        except Exception:
            continue
        if isinstance(data, dict) and "tests" in data:
            discovered.append(path)
    return discovered


def _filter_tests(tests: List[dict], only: Optional[str], skip: Optional[str]) -> List[dict]:
    def match_any(name, patterns):
        return any(fnmatch.fnmatchcase(name, p) for p in patterns)
    if only:
        pats = [p.strip() for p in only.split(",") if p.strip()]
        tests = [t for t in tests if match_any(t["name"], pats)]
    if skip:
        pats = [p.strip() for p in skip.split(",") if p.strip()]
        tests = [t for t in tests if not match_any(t["name"], pats)]
    return tests


def _suite_tests(json_file: str) -> List[dict]:
    return [{"name": n} for n in list_tests(json_file)]


def _suite_make_args(json_file: str) -> str:
    try:
        with open(json_file) as f:
            return json.load(f).get("make_args", "") or ""
    except Exception:
        return ""


_CONSOLE = Console(log_path=False)
_SKIP_HANDLER: Optional["callable"] = None  # set by the running _run_pool


class _KeyListener:
    """Background reader: pressing 'n' invokes the active skip handler. No-op without TTY."""

    def __init__(self):
        self.stop = threading.Event()
        self.thread: Optional[threading.Thread] = None
        self.old_termios = None
        self.fd = sys.stdin.fileno() if sys.stdin.isatty() else -1

    def __enter__(self):
        if self.fd < 0:
            return self
        self.old_termios = termios.tcgetattr(self.fd)
        tty.setcbreak(self.fd)
        self.thread = threading.Thread(target=self._loop, daemon=True)
        self.thread.start()
        return self

    def __exit__(self, *exc):
        self.stop.set()
        if self.thread:
            self.thread.join(timeout=1)
        if self.old_termios is not None:
            termios.tcsetattr(self.fd, termios.TCSADRAIN, self.old_termios)

    def _loop(self):
        while not self.stop.is_set():
            r, _, _ = select.select([self.fd], [], [], 0.2)
            if not r:
                continue
            try:
                key = os.read(self.fd, 1).decode("utf-8", "ignore")
            except Exception:
                continue
            if key in ("n", "N") and _SKIP_HANDLER is not None:
                _SKIP_HANDLER()


_NAME_W = 32
_CYC_W = 10

_STATUS_PREFIX = {
    STATUS_PASS:     "[green]✓[/]",
    STATUS_MISMATCH: "[red]✗[/]",
    STATUS_BUILD:    "[yellow]✗[/]",
    STATUS_TIMEOUT:  "[magenta]✗[/]",
}


def _fmt_done(r: TestResult) -> str:
    prefix = _STATUS_PREFIX.get(r.status, "[red]✗[/]")
    base = f"{prefix} {r.name:<{_NAME_W}}  ({r.time:5.1f}s)"
    if r.status != STATUS_PASS:
        return f"{base}  [dim]{r.status}[/]"
    cyc = f"cyc={r.hwpe_cycles:>6}" if r.hwpe_cycles is not None else " " * _CYC_W
    return f"{base}  {cyc}"


class _LiveState:
    """Renderable showing the suite bar, optional overall bar, and running tests."""

    def __init__(self, suite_progress: Progress, overall_progress: Progress, show_overall: bool):
        self.sp = suite_progress
        self.op = overall_progress
        self.show_overall = show_overall
        self.running: dict = {}
        self.lock = threading.Lock()
        self.slots = 0

    def set_slots(self, n: int) -> None:
        self.slots = n

    def add(self, name: str) -> None:
        with self.lock:
            self.running[name] = time.time()

    def remove(self, name: str) -> None:
        with self.lock:
            self.running.pop(name, None)

    def clear_running(self) -> None:
        with self.lock:
            self.running.clear()

    def __rich_console__(self, console, options):
        with self.lock:
            items = sorted(self.running.items())
        now = time.time()
        for n, t0 in items:
            yield Text(f"  [RUN ] {n:<{_NAME_W}}  ({now - t0:5.1f}s)", style="cyan")
        for _ in range(max(0, self.slots - len(items))):
            yield Text("")
        yield self.sp
        if self.show_overall:
            yield self.op


def _run_pool(test_args, parallel, state: "_LiveState", started_q) -> List[TestResult]:
    global _SKIP_HANDLER
    parallel = max(1, min(parallel, len(test_args)))
    original = signal.signal(signal.SIGINT, signal.SIG_IGN)
    pool = multiprocessing.Pool(parallel, initializer=_worker_init, initargs=(started_q,))
    signal.signal(signal.SIGINT, original)
    results: List[TestResult] = []
    ok = fail = 0
    task_id = state.sp.add_task("", total=len(test_args), ok=0, fail=0)
    state.set_slots(parallel)
    stop = threading.Event()
    aborted = threading.Event()

    def drain():
        while not stop.is_set():
            try:
                name = started_q.get(timeout=0.2)
            except Exception:
                continue
            state.add(name)

    def skip_now():
        if aborted.is_set():
            return
        aborted.set()
        _CONSOLE.print("[yellow]Skipping rest of suite (user pressed 'n')[/]")
        try:
            pool.terminate()
        except Exception:
            pass

    drainer = threading.Thread(target=drain, daemon=True)
    drainer.start()
    _SKIP_HANDLER = skip_now
    try:
        it = pool.imap_unordered(run_test_wrapper, test_args)
        while not aborted.is_set():
            try:
                r = it.next(timeout=0.5)
            except multiprocessing.TimeoutError:
                continue
            except StopIteration:
                break
            except Exception:
                if aborted.is_set():
                    break
                raise
            results.append(r)
            state.remove(r.name)
            if r.passed:
                ok += 1
            else:
                fail += 1
            _CONSOLE.print(_fmt_done(r))
            state.sp.update(task_id, advance=1, ok=ok, fail=fail)
        if not aborted.is_set():
            pool.close()
        pool.join()
    except KeyboardInterrupt:
        pool.terminate()
        pool.join()
        raise
    finally:
        _SKIP_HANDLER = None
        stop.set()
        drainer.join(timeout=1)
        state.sp.remove_task(task_id)
        state.clear_running()
        state.set_slots(0)
    return results


def run_suite(args, json_file: str, state: "_LiveState", started_q) -> Tuple[int, List[TestResult]]:
    tests = _suite_tests(json_file)
    if args.test:
        tests = [t for t in tests if t["name"] == args.test]
        if not tests:
            _CONSOLE.print(f"[red]Test '{args.test}' not found in {json_file}[/]")
            return 1, []
    tests = _filter_tests(tests, args.only, args.skip)
    if not tests:
        _CONSOLE.print(f"[yellow]No tests selected in {json_file}[/]")
        return 0, []

    _CONSOLE.rule(f"[bold]{os.path.basename(json_file)}[/]  ({len(tests)} tests)")
    make_args = _suite_make_args(json_file)
    test_args = [(t, json_file, args.vsim_flags, args.timeout, make_args) for t in tests]
    results = _run_pool(test_args, args.parallel, state, started_q)
    results.sort(key=lambda r: r.name)

    if not args.no_report:
        rp = build_default_report_paths(json_file, args.test, args.report_dir)
        generate_junit_report(results, rp["junit"])
        generate_json_report(results, rp["json"])
        generate_metrics_csv(results, rp["csv"])
        _CONSOLE.print(f"[dim]reports: {rp['junit']}  {rp['json']}  {rp['csv']}[/]")

    failed = sum(1 for r in results if not r.passed)
    return (0 if failed == 0 else 1), results


def _print_summary(all_results: List[TestResult], report_dir: str, planned: int, aborted: bool = False) -> None:
    by_status = {STATUS_PASS: [], STATUS_MISMATCH: [], STATUS_BUILD: [], STATUS_TIMEOUT: []}
    for r in all_results:
        by_status.setdefault(r.status, []).append(r)
    remaining = max(0, planned - len(all_results))
    _CONSOLE.print()
    _CONSOLE.rule("Summary")
    parts = [f"[green]✓ {len(by_status[STATUS_PASS])} {STATUS_PASS}[/]"]
    if by_status[STATUS_MISMATCH]:
        parts.append(f"[red]✗ {len(by_status[STATUS_MISMATCH])} {STATUS_MISMATCH}[/]")
    if by_status[STATUS_BUILD]:
        parts.append(f"[yellow]✗ {len(by_status[STATUS_BUILD])} {STATUS_BUILD}[/]")
    if by_status[STATUS_TIMEOUT]:
        parts.append(f"[magenta]✗ {len(by_status[STATUS_TIMEOUT])} {STATUS_TIMEOUT}[/]")
    if remaining:
        parts.append(f"[orange3]{remaining} not run[/]")
    _CONSOLE.print("   ".join(parts) + f"   (of {planned} planned)")
    bad = [r for r in all_results if r.status != STATUS_PASS]
    if bad:
        _CONSOLE.print()
        for r in bad:
            _CONSOLE.print(f"  {_STATUS_PREFIX.get(r.status, '✗')} {r.name}")
    if not aborted:
        _CONSOLE.print(f"\nReports: {report_dir}/junit/  {report_dir}/metrics/")


def _count_planned(args, suites: List[str]) -> int:
    total = 0
    for s in suites:
        tests = _suite_tests(s)
        if args.test:
            tests = [t for t in tests if t["name"] == args.test]
        tests = _filter_tests(tests, args.only, args.skip)
        total += len(tests)
    return total


def main():
    parser = argparse.ArgumentParser(description="Datamover HWPE Test Runner")
    parser.add_argument("json_file", nargs="?", help="JSON test suite file")
    parser.add_argument("--discover-glob", type=str, help="Run all discovered JSON suites matching glob")
    parser.add_argument("--test", "-t", type=str, help="Run a specific test by exact name")
    parser.add_argument("--only", type=str, help="Run only tests matching glob(s), comma-separated")
    parser.add_argument("--skip", type=str, help="Skip tests matching glob(s), comma-separated")
    parser.add_argument("--parallel", "-p", type=int, default=8, help="Number of parallel processes")
    parser.add_argument("--timeout", type=int, default=600, help="Per-test wall-clock timeout in seconds")
    parser.add_argument("--report-dir", default="reports", help="Report directory")
    parser.add_argument("--no-report", action="store_true", help="Disable report generation")
    parser.add_argument("--vsim-flags", default="-gui", help="VSIM flags")
    args = parser.parse_args()

    if "-gui" in args.vsim_flags and not args.test:
        parser.error("GUI mode (-gui in --vsim-flags) requires --test=NAME (or TEST=NAME via make) to pick a single test")
    if "-gui" in args.vsim_flags:
        args.parallel = 1

    if not args.json_file and not args.discover_glob:
        parser.error("Provide json_file or --discover-glob")
    if args.json_file and args.discover_glob:
        parser.error("Use either json_file or --discover-glob, not both")

    suites = [args.json_file] if args.json_file else discover_test_json_files(args.discover_glob)
    if not suites:
        _CONSOLE.print(f"[red]No test JSON files found (glob: {args.discover_glob})[/]")
        sys.exit(1)

    planned = _count_planned(args, suites)
    started_q = multiprocessing.Queue()
    suite_progress = Progress(
        TextColumn("[bold]suite[/]"),
        BarColumn(),
        MofNCompleteColumn(),
        TextColumn("[green]✓{task.fields[ok]}[/] [red]✗{task.fields[fail]}[/]"),
        TimeElapsedColumn(),
        console=_CONSOLE,
    )
    overall_progress = Progress(
        TextColumn("[bold cyan]suites[/]"),
        BarColumn(),
        TextColumn("{task.completed}/{task.total}"),
        TimeElapsedColumn(),
        console=_CONSOLE,
    )
    state = _LiveState(suite_progress, overall_progress, show_overall=len(suites) > 1)

    all_results: List[TestResult] = []
    final_rc = 0
    hint = f"per-test timeout: {args.timeout}s"
    if sys.stdin.isatty():
        hint = "press 'n' to skip current suite, Ctrl-C to abort  |  " + hint
    _CONSOLE.print(f"[dim]{hint}[/]")
    try:
        with _KeyListener(), Live(state, console=_CONSOLE, refresh_per_second=4, transient=False):
            overall_task = overall_progress.add_task("", total=len(suites)) if state.show_overall else None
            for suite in suites:
                rc, results = run_suite(args, suite, state, started_q)
                all_results.extend(results)
                final_rc = final_rc or rc
                if overall_task is not None:
                    overall_progress.advance(overall_task)
    except KeyboardInterrupt:
        _print_summary(all_results, args.report_dir, planned, aborted=True)
        sys.exit(130)

    _print_summary(all_results, args.report_dir, planned)
    sys.exit(final_rc)


if __name__ == "__main__":
    sys.exit(main())
