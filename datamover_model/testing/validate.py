#!/usr/bin/env python3
# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors: Lionnus Kesting <lkesting@iis.ee.ethz.ch>

"""Offline validator for the CIM-layout HAL register programming.

Reimplements the hwpe_stream_addressgen_v4 nested-counter model and the
datamover_build_cim_complete() / *_rev_complete() register computation, then
checks the resulting memory transform against the golden cim_layout /
cim_layout_reverse. Also flags stride and len field overflow. Lets us vet
test configs without running ModelSim.
"""

import sys

import numpy as np

from datamover_model.golden_model.transforms import cim_layout

LEN_BITS = 16
STRIDE_BITS = 21


def field(v, bits, name, errs):
    mask = (1 << bits) - 1
    if v < 0 or v > mask:
        errs.append(f"{name}={v} overflows {bits}-bit field")
    return v & mask


def addr_seq(dims, dim_enable, tot_len):
    """Yield the element address for each of tot_len beats.

    dims: list of (stride, len) for d0..d3 (len of the top/unbounded dim ignored).
    dim_enable: bitmask, bit i enables the d_i -> d_{i+1} wrap (chain).
    """
    top = 0
    while top < 4 and (dim_enable >> top) & 1:
        top += 1
    lens = [dims[i][1] for i in range(4)]
    strides = [dims[i][0] for i in range(4)]
    counters = [0, 0, 0, 0]
    out = []
    for _ in range(tot_len):
        out.append(sum(counters[i] * strides[i] for i in range(4)))
        d = 0
        while True:
            counters[d] += 1
            if d == top:
                break
            if counters[d] < lens[d]:
                break
            counters[d] = 0
            d += 1
    return out


def beat_copy(in_flat, dims_in, en_in, dims_out, en_out, tot_len, bw):
    ra = addr_seq(dims_in, en_in, tot_len)
    wa = addr_seq(dims_out, en_out, tot_len)
    out = np.full(in_flat.shape, 0xA5, dtype=np.uint8)
    for j in range(tot_len):
        out[wa[j]:wa[j] + bw] = in_flat[ra[j]:ra[j] + bw]
    return out


def check_fields(dims, prefix, errs):
    for i, (s, length) in enumerate(dims):
        field(s, STRIDE_BITS, f"{prefix}_d{i}.stride", errs)
        field(length, LEN_BITS, f"{prefix}_d{i}.len", errs)


def cfg_forward(m, n, bw):
    """Mirror datamover_build_cim_complete (aligned, no leftover)."""
    errs = []
    n_blocks = n // bw
    tot_len = m * n_blocks
    dims_in = [(bw, 1), (n, m), (bw, 0), (0, 0)]
    en_in = 0x3
    dims_out = [(bw, m), (bw * m, n_blocks), (0, 0), (0, 0)]
    en_out = 0x1
    check_fields(dims_in, "in", errs)
    check_fields(dims_out, "out", errs)
    field(n_blocks * bw, LEN_BITS, "matrix_dim.n", errs)
    field(m, LEN_BITS, "matrix_dim.m", errs)
    return dims_in, en_in, dims_out, en_out, tot_len, errs


def cfg_reverse(m, n, bw):
    """Mirror datamover_build_cim_rev_complete (aligned)."""
    errs = []
    n_blocks = n // bw
    tot_len = m * n_blocks
    dims_in = [(bw, m * n_blocks), (0, 0), (0, 0), (0, 0)]
    en_in = 0x0
    dims_out = [(n, m), (bw, n_blocks), (0, 0), (0, 0)]
    en_out = 0x1
    check_fields(dims_in, "in", errs)
    check_fields(dims_out, "out", errs)
    field(bw, LEN_BITS, "matrix_dim.n", errs)
    field(m * n_blocks, LEN_BITS, "matrix_dim.m", errs)
    return dims_in, en_in, dims_out, en_out, tot_len, errs


def check(m, n, bw, mode):
    rng = np.random.default_rng(0)
    if mode == "fwd":
        src = rng.integers(0, 256, size=m * n, dtype=np.uint8)
        di, ei, do, eo, tl, errs = cfg_forward(m, n, bw)
        got = beat_copy(src, di, ei, do, eo, tl, bw)
        gold = np.asarray(cim_layout(src.reshape(m, n), bw, m, n)).reshape(-1).astype(np.uint8)
    else:
        rm = rng.integers(0, 256, size=m * n, dtype=np.uint8).reshape(m, n)
        src = np.asarray(cim_layout(rm, bw, m, n)).reshape(-1).astype(np.uint8)
        di, ei, do, eo, tl, errs = cfg_reverse(m, n, bw)
        got = beat_copy(src, di, ei, do, eo, tl, bw)
        gold = rm.reshape(-1)
    ok = (got.shape == gold.shape) and bool(np.array_equal(got, gold))
    return ok, errs


def main():
    cases = []
    if len(sys.argv) > 1:
        for a in sys.argv[1:]:
            m, n, bw, mode = a.split(",")
            cases.append((int(m), int(n), int(bw), mode))
    else:
        for bw in (8, 16, 32, 64):
            for m in (1, 33, 64, 100):
                n = 4 * bw
                cases.append((m, n, bw, "fwd"))
                cases.append((m, n, bw, "rev"))
    bad = 0
    for (m, n, bw, mode) in cases:
        ok, errs = check(m, n, bw, mode)
        tag = "OK  " if (ok and not errs) else "BAD "
        if not (ok and not errs):
            bad += 1
        extra = (" overflow:" + ";".join(errs)) if errs else ""
        print(f"{tag} {mode} m={m} n={n} bw={bw} correct={ok}{extra}")
    print(f"\n{len(cases) - bad}/{len(cases)} configs clean")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
