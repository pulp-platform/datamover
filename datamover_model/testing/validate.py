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
cim_layout_reverse. Also flags 16-bit stride/len overflow. Lets us vet test
configs without running ModelSim.
"""

import sys

import numpy as np

from datamover_model.golden_model.transforms import cim_layout

MASK16 = 0xFFFF


def field16(v, name, errs):
    if v < 0 or v > MASK16:
        errs.append(f"{name}={v} overflows 16-bit field")
    return v & MASK16


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


def cfg_forward(m, n, rt, bw):
    """Mirror datamover_build_cim_complete (aligned, no leftover)."""
    errs = []
    m_tiles = (m + bw - 1) // bw
    cnt = n // rt
    R = rt // bw
    tot_len = m_tiles * cnt * rt
    field16(rt, "in_d1.stride(size_n)", errs)
    dims_in = [(bw, R), (n, m_tiles * bw), (rt, 0), (0, 0)]
    en_in = 0x3
    if R > 1:
        dims_out = [(bw, R), (rt, m_tiles * bw), (rt * m, cnt), (0, 0)]
        en_out = 0x3
    else:
        dims_out = [(bw, m_tiles * bw), (rt * m, cnt), (0, 0), (0, 0)]
        en_out = 0x1
    for nm, (s, length) in [("in_d0", dims_in[0]), ("in_d1", dims_in[1]), ("in_d2", dims_in[2]),
                            ("out_d0", dims_out[0]), ("out_d1", dims_out[1]), ("out_d2", dims_out[2])]:
        field16(s, nm + ".stride", errs)
        field16(length, nm + ".len", errs)
    field16(cnt * rt, "matrix_dim.n", errs)
    field16(m, "matrix_dim.m", errs)
    return dims_in, en_in, dims_out, en_out, tot_len, errs


def cfg_reverse(m, n, rt, bw):
    """Mirror datamover_build_cim_rev_complete (aligned)."""
    errs = []
    cnt = n // rt
    R = rt // bw
    Mp = m * cnt
    m_tiles = (Mp + bw - 1) // bw
    tot_len = m_tiles * rt
    dims_in = [(bw, Mp * R), (0, 0), (0, 0), (0, 0)]
    en_in = 0x0
    if R > 1:
        dims_out = [(bw, R), (n, m), (rt, cnt), (0, 0)]
        en_out = 0x3
    else:
        dims_out = [(n, m), (bw, cnt), (0, 0), (0, 0)]
        en_out = 0x1
    for nm, (s, length) in [("in_d0", dims_in[0]),
                            ("out_d0", dims_out[0]), ("out_d1", dims_out[1]), ("out_d2", dims_out[2])]:
        field16(s, nm + ".stride", errs)
        field16(length, nm + ".len", errs)
    field16(rt, "matrix_dim.n", errs)
    field16(Mp, "matrix_dim.m", errs)
    return dims_in, en_in, dims_out, en_out, tot_len, errs


def check(m, n, rt, bw, mode):
    rng = np.random.default_rng(0)
    if mode == "fwd":
        src = rng.integers(0, 256, size=m * n, dtype=np.uint8)
        di, ei, do, eo, tl, errs = cfg_forward(m, n, rt, bw)
        got = beat_copy(src, di, ei, do, eo, tl, bw)
        gold = np.asarray(cim_layout(src.reshape(m, n), rt, m, n)).reshape(-1).astype(np.uint8)
    else:
        rm = rng.integers(0, 256, size=m * n, dtype=np.uint8).reshape(m, n)
        src = np.asarray(cim_layout(rm, rt, m, n)).reshape(-1).astype(np.uint8)
        di, ei, do, eo, tl, errs = cfg_reverse(m, n, rt, bw)
        got = beat_copy(src, di, ei, do, eo, tl, bw)
        gold = rm.reshape(-1)
    ok = (got.shape == gold.shape) and bool(np.array_equal(got, gold))
    return ok, errs


def main():
    cases = []
    if len(sys.argv) > 1:
        for a in sys.argv[1:]:
            m, n, rt, bw, mode = a.split(",")
            cases.append((int(m), int(n), int(rt), int(bw), mode))
    else:
        for bw in (8, 16, 32, 64):
            for R in (1, 2, 4, 8):
                rt = R * bw
                m, n = 64, 4 * rt
                if rt * m > 0xFFFF or n > 0xFFFF:
                    continue
                cases.append((m, n, rt, bw, "fwd"))
                cases.append((m, n, rt, bw, "rev"))
    bad = 0
    for (m, n, rt, bw, mode) in cases:
        ok, errs = check(m, n, rt, bw, mode)
        tag = "OK  " if (ok and not errs) else "BAD "
        if not (ok and not errs):
            bad += 1
        extra = (" overflow:" + ";".join(errs)) if errs else ""
        print(f"{tag} {mode} m={m} n={n} rt={rt} bw={bw} R={rt // bw} correct={ok}{extra}")
    print(f"\n{len(cases) - bad}/{len(cases)} configs clean")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
