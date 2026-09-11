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
    "LAYOUT": "CHW",      # unfold and fold: CHW row-major, or CIM 64-column blocks on both sides
    "IM2COL_IN": "CHW",   # image layout: CHW, HWC, or CIM ((C, pixels) in 64-pixel blocks)
    "IM2COL_OUT": "COL",  # COL: one column per patch (torch unfold); ROW_CIM: one row per patch; COL_CIM: COL in 64-pixel blocks
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
        out[k] = str(v).upper() if k in STR_PARAMS else int(v)
    if out["IM2COL_IN"] not in IM2COL_IN or out["IM2COL_OUT"] not in IM2COL_OUT:
        raise ValueError(f"IM2COL_IN must be in {IM2COL_IN} and IM2COL_OUT in {IM2COL_OUT}")
    if out["LAYOUT"] not in LAYOUTS:
        raise ValueError(f"LAYOUT must be in {LAYOUTS}")
    if out["DATAMOVER_MODE"] not in range(7):
        raise ValueError(f"DATAMOVER_MODE must be in 0..6, got {out['DATAMOVER_MODE']}")
    if out["TRANSP_MODE"] not in (0, 1, 2, 4):
        raise ValueError(f"TRANSP_MODE must be in {{0,1,2,4}}, got {out['TRANSP_MODE']}")
    if out["CIM_MODE"] not in (0, 1):
        raise ValueError(f"CIM_MODE must be 0 or 1, got {out['CIM_MODE']}")
    if out["DATAMOVER_MODE"] == 6:
        _validate_im2col_params(out)
    if out["DATAMOVER_MODE"] in (4, 5):
        _validate_unfold_params(out)
    return out


STR_PARAMS = ("LAYOUT", "IM2COL_IN", "IM2COL_OUT")
LAYOUTS = ("CHW", "CIM")
IM2COL_IN = ("CHW", "HWC", "CIM")
IM2COL_OUT = ("COL", "ROW_CIM", "COL_CIM")
IM2COL_UNIT_WIDTHS = (8, 16, 32, 64)


def _validate_unfold_params(params: dict) -> None:
    """Even H and W; the CIM layout needs whole 64-pixel blocks."""
    m, n = params["SIZE_M"], params["SIZE_N"]
    if m % 2 != 0 or n % 2 != 0:
        raise ValueError(f"unfold and fold need even H and W, got {m}x{n}")
    if params["LAYOUT"] == "CIM" and (m * n) % 64 != 0:
        raise ValueError(f"LAYOUT=CIM needs H*W a multiple of 64, got {m}x{n}")


def _validate_im2row_params(params: dict) -> None:
    """ROW_CIM is a strided copy of patch rows, one run per patch row."""
    k, s, pad, c = params["KERNEL_SIZE_H"], params["CONV_STRIDE"], params["CONV_PAD"], params["SIZE_C"]
    if not (k == params["KERNEL_SIZE_W"] == s) or pad != 0:
        raise ValueError(f"ROW_CIM needs kernel == stride and no pad, got K={k} S={s} pad={pad}")
    if params["IM2COL_IN"] == "CHW" and (64 % k != 0 or (k * k) % 64 != 0):
        raise ValueError(f"CHW ROW_CIM needs a kernel side in (8, 16, 32, 64), got {k}")
    if params["IM2COL_IN"] == "HWC" and (k * c != 48 or k % 4 != 0):
        raise ValueError(f"HWC ROW_CIM needs 48-byte patch rows and a kernel side that is a multiple of 4, got K={k} C={c}")


def _validate_im2col_params(params: dict) -> None:
    """The relations of the HAL paths."""
    kh, kw = params["KERNEL_SIZE_H"], params["KERNEL_SIZE_W"]
    s, pad = params["CONV_STRIDE"], params["CONV_PAD"]
    m, n = params["SIZE_M"], params["SIZE_N"]
    layout = (params["IM2COL_IN"], params["IM2COL_OUT"])
    if kh < 1 or kw < 1:
        raise ValueError(f"KERNEL_SIZE_H/KERNEL_SIZE_W must be >= 1, got {kh}x{kw}")
    if params["IM2COL_OUT"] == "ROW_CIM":
        _validate_im2row_params(params)
        return
    if s not in (1, 2):
        raise ValueError(f"im2col CONV_STRIDE must be 1 or 2, got {s}")
    if layout == ("CIM", "COL_CIM"):
        if (kh, kw, s, pad) != (3, 3, 1, 1):
            raise ValueError(f"CIM im2col is 3x3, stride 1, pad 1, got K={kh}x{kw} S={s} pad={pad}")
        if n not in IM2COL_UNIT_WIDTHS or (m * n) % 64 != 0:
            raise ValueError(f"CIM im2col needs W in {IM2COL_UNIT_WIDTHS} and H*W a multiple of 64, got {m}x{n}")
    elif layout == ("CHW", "COL_CIM"):
        w_out = (n - kw) // s + 1
        if s != 2 or pad != 0 or w_out % 64 != 0:
            raise ValueError(f"CHW to COL_CIM needs stride 2, no pad, and w_out a multiple of 64, got S={s} pad={pad} w_out={w_out}")
    elif layout == ("CHW", "COL"):
        if pad != 0:
            raise ValueError("CONV_PAD needs IM2COL_IN=CIM and IM2COL_OUT=COL_CIM")
    else:
        raise ValueError(f"unsupported im2col layouts {layout}")


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
        base = f"UNFOLD_C{c}_{m}x{n}" + ("_CIM" if params["LAYOUT"] == "CIM" else "")
    elif mode == 5:
        base = f"FOLD_C{c}_{m}x{n}" + ("_CIM" if params["LAYOUT"] == "CIM" else "")
    else:
        kh, kw = params["KERNEL_SIZE_H"], params["KERNEL_SIZE_W"]
        k_tag = f"{kh}" if kh == kw else f"{kh}x{kw}"
        base = f"IM2COL_C{c}_{m}x{n}_K{k_tag}_S{params['CONV_STRIDE']}"
        if params["CONV_PAD"] > 0:
            base += f"_P{params['CONV_PAD']}"
        if (params["IM2COL_IN"], params["IM2COL_OUT"]) != ("CHW", "COL"):
            base += f"_{params['IM2COL_IN']}_{params['IM2COL_OUT']}"
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
