# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors: Lionnus Kesting <lkesting@iis.ee.ethz.ch>

"""Ideal-cycle estimation and bandwidth utilization for datamover jobs.

Loads and stores are muxed onto a single BANDWIDTH-wide TCDM port
(hci_core_load_store_mixer / hci_core_mux_dynamic in datamover_streamer.sv), so
a read beat and a write beat never occupy the same cycle. The ideal cost of a
job is therefore the number of full-width read beats plus full-width write
beats; utilization is that ideal against the measured busy cycles. im2col is the
only mode whose write volume exceeds its read volume, and whose ideal read
counts each input pixel once, so its utilization exposes redundant re-reads of
overlapping receptive fields.
"""

import math


def _elems_per_beat(hw: dict) -> int:
    return hw["BANDWIDTH"] // hw["ELEM_WIDTH"]


def transfer_elems(params: dict) -> tuple:
    """(in_elems, out_elems) that must cross the TCDM port for one job."""
    mode = params["DATAMOVER_MODE"]
    c, m, n = params["SIZE_C"], params["SIZE_M"], params["SIZE_N"]
    if mode == 6:
        kh, kw = params["KERNEL_SIZE_H"], params["KERNEL_SIZE_W"]
        s, p = params["CONV_STRIDE"], params["CONV_PAD"]
        h_out = (m + 2 * p - kh) // s + 1
        w_out = (n + 2 * p - kw) // s + 1
        return c * m * n, kh * kw * c * h_out * w_out
    # Modes 0-5 are volume-preserving re-layouts.
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
