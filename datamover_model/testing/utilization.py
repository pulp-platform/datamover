# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors: Lionnus Kesting <lkesting@iis.ee.ethz.ch>

"""Ideal-cycle estimation and bandwidth utilization for datamover jobs.

Loads and stores share one BANDWIDTH-wide TCDM port, so utilization is the
ideal beat count (full-width reads + writes) against measured busy cycles.
"""

import math


def _elems_per_beat(hw: dict) -> int:
    """Payload elements per beat (misaligned accesses reserve one WORD_WIDTH slice)."""
    payload_bits = hw["BANDWIDTH"] - (hw["WORD_WIDTH"] if hw["MISALIGNED_ACCESSES"] else 0)
    return payload_bits // hw["ELEM_WIDTH"]


def _axis_referenced(size: int, out: int, k: int, s: int, p: int) -> int:
    """Distinct in-range input indices touched along one axis by the unfold."""
    idx = {o * s + t - p for o in range(out) for t in range(k)}
    return sum(1 for i in idx if 0 <= i < size)


def transfer_elems(params: dict) -> tuple:
    """(in_elems, out_elems) that must cross the TCDM port for one job."""
    mode = params["DATAMOVER_MODE"]
    c, m, n = params["SIZE_C"], params["SIZE_M"], params["SIZE_N"]
    if mode == 6:
        kh, kw = params["KERNEL_SIZE_H"], params["KERNEL_SIZE_W"]
        s, p = params["CONV_STRIDE"], params["CONV_PAD"]
        h_out = (m + 2 * p - kh) // s + 1
        w_out = (n + 2 * p - kw) // s + 1
        read = c * _axis_referenced(m, h_out, kh, s, p) * _axis_referenced(n, w_out, kw, s, p)
        write = kh * kw * c * h_out * w_out
        return read, write
    return c * m * n, c * m * n


def ideal_cycles(params: dict, hw: dict) -> int:
    """Minimum shared-port beats: ceil(read / B) + ceil(write / B)."""
    b = _elems_per_beat(hw)
    in_elems, out_elems = transfer_elems(params)
    return math.ceil(in_elems / b) + math.ceil(out_elems / b)


def ideal_cycles_entry(entry: dict, hw: dict) -> int:
    """Ideal cycles for a suite entry: a single job or a chain of jobs."""
    if "chain" in entry:
        return sum(ideal_cycles(p, hw) for p in entry["chain"])
    return ideal_cycles(entry["params"], hw)


def bw_utilization(ideal: int, busy_cycles: int) -> float:
    """Fraction of the busy window spent moving full-bandwidth beats."""
    if not busy_cycles:
        return 0.0
    return ideal / busy_cycles
