# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors: Lionnus Kesting <lkesting@iis.ee.ethz.ch>

"""JSON suite loading, parameter defaults, and test-name resolution."""

import json
from pathlib import Path

HW_KEYS = ("BANDWIDTH", "WORD_WIDTH", "ELEM_WIDTH", "MISALIGNED_ACCESSES")

PARAM_DEFAULTS = {
    "DATAMOVER_MODE": 0,
    "TRANSP_MODE": 1,
    "CIM_MODE": 0,
    "ROW_TILE_SIZE": 64,
    "SIZE_C": 1,
    "SIZE_M": 1,
    "SIZE_N": 1,
    "COUNT": 0,
    "KERNEL_SIZE_H": 1,
    "KERNEL_SIZE_W": 1,
    "CONV_STRIDE": 1,
    "CONV_PAD": 0,
}


def hw_fingerprint(hw: dict) -> str:
    """Deterministic build-dir name from the RTL compile-time HW params."""
    t = {k: int(hw[k]) for k in HW_KEYS}
    return f"BW{t['BANDWIDTH']}_WW{t['WORD_WIDTH']}_EW{t['ELEM_WIDTH']}_MA{t['MISALIGNED_ACCESSES']}"


def build_tag(hw: dict, stall: str = "0.0") -> str:
    """Compiled-build dir name `<hw_fingerprint>[_S<stall>]`: HW geometry plus
    the memory stall probability baked into the image. Shared by mk/config.mk."""
    s = str(stall).strip()
    suffix = "" if s in ("", "0.0") else f"_S{s.replace('.', '_')}"
    return hw_fingerprint(hw) + suffix


def _hw_configs_path() -> Path:
    return Path(__file__).resolve().parent.parent.parent / "configs" / "hw_configs.json"


def load_hw_config(name: str) -> dict:
    """Load a hardware configuration by name from configs/hw_configs.json."""
    path = _hw_configs_path()
    with open(path) as f:
        configs = json.load(f)
    if name not in configs:
        available = ", ".join(sorted(configs.keys()))
        raise ValueError(f"HW config '{name}' not found. Available: {available}")
    cfg = configs[name]
    missing = [k for k in HW_KEYS if k not in cfg]
    if missing:
        raise ValueError(f"HW config '{name}' missing keys: {missing}")
    return {k: cfg[k] for k in HW_KEYS}


def normalize_params(raw: dict) -> dict:
    out = dict(PARAM_DEFAULTS)
    for k, v in raw.items():
        if k not in PARAM_DEFAULTS:
            raise ValueError(f"Unknown param '{k}' (allowed: {list(PARAM_DEFAULTS)})")
        out[k] = int(v)
    if out["DATAMOVER_MODE"] not in range(7):
        raise ValueError(f"DATAMOVER_MODE must be in 0..6, got {out['DATAMOVER_MODE']}")
    if out["TRANSP_MODE"] not in (0, 1, 2, 4):
        raise ValueError(f"TRANSP_MODE must be in {{0,1,2,4}}, got {out['TRANSP_MODE']}")
    if out["CIM_MODE"] not in (0, 1):
        raise ValueError(f"CIM_MODE must be 0 or 1, got {out['CIM_MODE']}")
    if out["DATAMOVER_MODE"] == 6:
        _validate_im2col_params(out)
    return out


IM2COL_MAX_PADDED_KERNEL_SIZE = 15
IM2COL_PADDED_KERNEL_W = 3


def _validate_im2col_params(params: dict) -> None:
    kh, kw = params["KERNEL_SIZE_H"], params["KERNEL_SIZE_W"]
    s, pad = params["CONV_STRIDE"], params["CONV_PAD"]
    if kh < 1 or kw < 1:
        raise ValueError(f"KERNEL_SIZE_H/KERNEL_SIZE_W must be >= 1, got {kh}x{kw}")
    if s not in (1, 2):
        raise ValueError(f"im2col CONV_STRIDE must be 1 or 2, got {s}")
    if pad not in (0, 1):
        raise ValueError(f"im2col CONV_PAD must be 0 or 1, got {pad}")
    if pad != 0 and s != 1:
        raise ValueError(f"im2col CONV_PAD requires CONV_STRIDE == 1, got CONV_STRIDE={s}")
    if pad != 0 and kw != IM2COL_PADDED_KERNEL_W:
        raise ValueError(
            f"im2col CONV_PAD requires KERNEL_SIZE_W == {IM2COL_PADDED_KERNEL_W} "
            f"(the fixed 1-pixel border only preserves row width at kw=3), got KERNEL_SIZE_W={kw}"
        )
    if pad != 0 and kh > IM2COL_MAX_PADDED_KERNEL_SIZE:
        raise ValueError(
            f"im2col CONV_PAD requires KERNEL_SIZE_H <= {IM2COL_MAX_PADDED_KERNEL_SIZE}, got {kh}"
        )


def hw_tag(name: str) -> str:
    if not name or name == "default":
        return ""
    return name.upper()


def auto_test_name(params: dict, hw_tag: str = "") -> str:
    mode = params["DATAMOVER_MODE"]
    c, m, n = params["SIZE_C"], params["SIZE_M"], params["SIZE_N"]
    if mode == 0:
        base = f"COPY_{m}x{n}"
    elif mode == 1:
        base = f"TRANSP{params['TRANSP_MODE']}_{m}x{n}"
    elif mode == 2:
        tag = "FWD" if params["CIM_MODE"] == 0 else "REV"
        base = f"CIM{tag}_{m}x{n}_RT{params['ROW_TILE_SIZE']}"
    elif mode == 3:
        base = f"CIMTR{params['TRANSP_MODE']}_{m}x{n}_RT{params['ROW_TILE_SIZE']}"
    elif mode == 4:
        base = f"UNFOLD_C{c}_{m}x{n}"
    elif mode == 5:
        base = f"FOLD_C{c}_{m}x{n}"
    else:
        kh, kw = params["KERNEL_SIZE_H"], params["KERNEL_SIZE_W"]
        k_tag = f"{kh}" if kh == kw else f"{kh}x{kw}"
        base = f"IM2COL_C{c}_{m}x{n}_K{k_tag}_S{params['CONV_STRIDE']}"
        if params["CONV_PAD"] > 0:
            base += f"_P{params['CONV_PAD']}"
    if c > 1 and mode in (0, 1, 2, 3):
        base += f"_C{c}"
    if hw_tag:
        base += f"_{hw_tag}"
    return base


def _entry_name(entry: dict, suite_hw: str = "") -> str:
    if entry.get("name"):
        return entry["name"]
    if "chain" in entry:
        raise ValueError("Chained tests require a 'name' field")
    params = normalize_params(entry.get("params", {}))
    hw = entry.get("hw_config") or suite_hw
    return auto_test_name(params, hw_tag(hw))


def load_test_suite(json_path: str) -> dict:
    with open(json_path) as f:
        return json.load(f)


def list_tests(json_path: str) -> list:
    suite = load_test_suite(json_path)
    suite_hw = suite.get("hw_config", "")
    return [_entry_name(e, suite_hw) for e in suite.get("tests", [])]


def find_test_entry(json_path: str, test_name: str) -> dict:
    suite = load_test_suite(json_path)
    suite_hw = suite.get("hw_config", "")
    for entry in suite.get("tests", []):
        if _entry_name(entry, suite_hw) == test_name:
            out = dict(entry)
            out["name"] = test_name
            out["hw_config"] = entry.get("hw_config") or suite_hw
            if "chain" in entry:
                out["chain"] = [normalize_params(p) for p in entry["chain"]]
            else:
                out["params"] = normalize_params(entry.get("params", {}))
            return out
    available = ", ".join(_entry_name(e, suite_hw) for e in suite.get("tests", []))
    raise ValueError(f"Test '{test_name}' not found in {json_path}. Available: {available}")
