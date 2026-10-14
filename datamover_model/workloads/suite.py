# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors: Lionnus Kesting <lkesting@iis.ee.ethz.ch>

"""JSON suite loading, parameter defaults, and test-name resolution."""

import json
import os
from pathlib import Path

HW_KEYS = ("BANDWIDTH", "WORD_WIDTH", "ELEM_WIDTH", "MISALIGNED_ACCESSES")
# Optional feature keys of a profile; a profile without the key has the default.
HW_FEATURES = {"ENABLE_BUFFER": 1, "IM2COL_KERNEL": 3, "IM2COL_MIN_LOG2W": 3}

PARAM_DEFAULTS = {
    "DATAMOVER_MODE": 0,
    "TRANSP_MODE": 1,
    "BLOCK_MODE": 0,
    "SIZE_C": 1,
    "SIZE_M": 1,
    "SIZE_N": 1,
    "COUNT": 0,
    "KERNEL_SIZE_H": 1,
    "KERNEL_SIZE_W": 1,
    "CONV_STRIDE": 1,
    "CONV_PAD": 0,
    "LAYOUT": "CHW",      # unfold and fold: CHW row-major, or BLOCK column blocks of one beat on both sides
    "IM2COL_IN": "CHW",   # image layout: CHW, HWC, or BLOCK ((C, pixels) in pixel blocks of one beat)
    "IM2COL_OUT": "COL",  # COL: one column per patch (torch unfold); ROW_BLOCK: one row per patch; COL_BLOCK: COL in pixel blocks of one beat
}


def hw_fingerprint(hw: dict) -> str:
    """Deterministic build-dir name from the RTL compile-time HW params."""
    t = {k: int(hw[k]) for k in HW_KEYS}
    features = "".join(f"_{k}{int(hw.get(k, d))}" for k, d in HW_FEATURES.items() if int(hw.get(k, d)) != d)
    return f"BW{t['BANDWIDTH']}_WW{t['WORD_WIDTH']}_EW{t['ELEM_WIDTH']}_MA{t['MISALIGNED_ACCESSES']}{features}"


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
    return {**{k: cfg[k] for k in HW_KEYS}, **{k: cfg.get(k, d) for k, d in HW_FEATURES.items()}}


def beat_elems(hw: dict) -> int:
    """Payload elements per beat, the block width; misaligned accesses reserve one word."""
    payload_bits = hw["BANDWIDTH"] - (hw["WORD_WIDTH"] if hw["MISALIGNED_ACCESSES"] else 0)
    return payload_bits // hw["ELEM_WIDTH"]


def hw_features(hw: dict) -> dict:
    """The feature keys of a profile, with the defaults for the missing keys."""
    return {k: hw.get(k, d) for k, d in HW_FEATURES.items()}


def align_elems(hw: dict) -> int:
    """Elements per aligned access: one word without misaligned accesses, else one element."""
    return 1 if hw["MISALIGNED_ACCESSES"] else hw["WORD_WIDTH"] // hw["ELEM_WIDTH"]


def normalize_params(raw: dict, beat: int, align: int = 1, features: dict = None) -> dict:
    """Defaults, types, and the checks of the HAL paths.

    `beat` is the block width in elements. `align` is the row alignment the streamer needs:
    a row of a strided access starts and ends on a word when the profile has no misaligned
    accesses.
    """
    features = {**HW_FEATURES, **(features or {})}
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
    if out["BLOCK_MODE"] not in (0, 1):
        raise ValueError(f"BLOCK_MODE must be 0 or 1, got {out['BLOCK_MODE']}")
    if out["DATAMOVER_MODE"] == 6:
        _validate_im2col_params(out, beat, features)
    if out["DATAMOVER_MODE"] in (4, 5):
        _validate_unfold_params(out, beat)
    _validate_alignment(out, align, beat)
    if not features["ENABLE_BUFFER"] and out["DATAMOVER_MODE"] in (1, 3, 4, 5):
        raise ValueError(f"DATAMOVER_MODE {out['DATAMOVER_MODE']} needs the element buffer, the profile has ENABLE_BUFFER 0")
    return out


def _validate_alignment(params: dict, align: int, beat: int) -> None:
    """Every row of a strided access is a whole number of words without misaligned accesses."""
    if align == 1:
        return
    mode, m, n = params["DATAMOVER_MODE"], params["SIZE_M"], params["SIZE_N"]
    t = params["TRANSP_MODE"]
    rows = {1: (n, m * t), 2: (n,), 3: (n, m * t)}.get(mode, ())  # a transposed row holds m groups of t
    if mode in (4, 5):
        # The token matrix has rows of SIZE_C; the row-major image has rows of W.
        rows = (params["SIZE_C"],) + ((n,) if params["LAYOUT"] == "CHW" else ())
    if mode == 6 and params["IM2COL_IN"] != "BLOCK" and params["IM2COL_OUT"] != "ROW_BLOCK":
        # The source reads word-aligned beats; the engine shifts two beats by the kernel column offset.
        kw, s, pad = params["KERNEL_SIZE_W"], params["CONV_STRIDE"], params["CONV_PAD"]
        shift = -pad % align
        kh = params["KERNEL_SIZE_H"]
        if (kw > 1 or shift) and (max(kh, kw) > IM2COL_MAX_KERNEL or shift + kw > beat):
            raise ValueError(f"row-major im2col without misaligned accesses counts kernel sides up to "
                             f"{IM2COL_MAX_KERNEL} and shifts by up to {beat - 1} elements, got a start offset "
                             f"of {shift} and a kernel {kh}x{kw}")
        rows = (n, (n + 2 * pad - kw) // s + 1)
    for r in rows:
        if r % align != 0:
            raise ValueError(f"a row of {r} elements needs a multiple of {align} without misaligned accesses")


STR_PARAMS = ("LAYOUT", "IM2COL_IN", "IM2COL_OUT")
LAYOUTS = ("CHW", "BLOCK")
IM2COL_IN = ("CHW", "HWC", "BLOCK")
IM2COL_OUT = ("COL", "ROW_BLOCK", "COL_BLOCK")


def im2col_unit_widths(beat: int, min_log2w: int = 3) -> tuple:
    """Image row widths the im2col unit supports: powers of two from 2**min_log2w to the beat."""
    return tuple(1 << l for l in range(min_log2w, beat.bit_length()) if (1 << l) <= beat)


def _validate_unfold_params(params: dict, beat: int) -> None:
    """Even H and W; the block layout needs whole blocks."""
    m, n = params["SIZE_M"], params["SIZE_N"]
    if m % 2 != 0 or n % 2 != 0:
        raise ValueError(f"unfold and fold need even H and W, got {m}x{n}")
    if params["LAYOUT"] == "BLOCK" and (m * n) % beat != 0:
        raise ValueError(f"LAYOUT=BLOCK needs H*W a multiple of {beat}, got {m}x{n}")
    if params["LAYOUT"] == "BLOCK" and m * n // beat > 0xFFFF:
        raise ValueError(f"LAYOUT=BLOCK needs at most 65535 pixel blocks per job, got {m * n // beat}")


def _validate_im2row_params(params: dict, beat: int) -> None:
    """ROW_BLOCK is a strided copy of patch rows, one run per patch row."""
    k, s, pad, c = params["KERNEL_SIZE_H"], params["CONV_STRIDE"], params["CONV_PAD"], params["SIZE_C"]
    if not (k == params["KERNEL_SIZE_W"] == s) or pad != 0:
        raise ValueError(f"ROW_BLOCK needs kernel == stride and no pad, got K={k} S={s} pad={pad}")
    if params["IM2COL_IN"] == "CHW" and (beat % k != 0 or (k * k) % beat != 0):
        raise ValueError(f"CHW ROW_BLOCK needs a kernel side that divides {beat} with K*K a multiple of it, got {k}")
    if params["IM2COL_IN"] == "BLOCK":
        raise ValueError("ROW_BLOCK needs IM2COL_IN CHW or HWC")
    if params["IM2COL_IN"] == "HWC" and (k * c != 48 or k % 4 != 0 or beat != 64):
        # TODO the HWC builder packs four 48-byte patch rows into three 64-element blocks; other beats need a generic scheme (B15)
        raise ValueError(f"HWC ROW_BLOCK needs a 64-element beat, 48-byte patch rows and a kernel side that is a multiple of 4, got beat={beat} K={k} C={c}")


# Widths of the DM_IM2COL_PAD fields: the pad of a row-major im2col job and the kernel side its
# engine counts.
IM2COL_MAX_PAD = 7
IM2COL_MAX_KERNEL = 15


def im2col_w_main(w_out: int, beat: int) -> int:
    """Output columns of the first row-major im2col job; the leftover job takes the rest."""
    return w_out if w_out < beat else w_out // beat * beat


def im2col_right(n: int, kw: int, s: int, pad: int, ow0: int, w_seg: int, beat: int) -> int:
    """Lanes of the last beat of a row past the image, for the last kernel column (the HAL's dm_im2col_right)."""
    return ow0 * s - pad + kw - 1 + -(-s * w_seg // beat) * beat - n


def _validate_row_major_pad(params: dict, beat: int, w_out: int) -> None:
    """The engine makes the zero border of the CHW paths: the pad fields bound it."""
    kh, kw, s, pad, n = (params[k] for k in ("KERNEL_SIZE_H", "KERNEL_SIZE_W", "CONV_STRIDE", "CONV_PAD", "SIZE_N"))
    if pad > IM2COL_MAX_PAD:
        raise ValueError(f"row-major im2col takes CONV_PAD up to {IM2COL_MAX_PAD}, the width of the pad fields, got {pad}")
    if pad == 0:
        return
    if max(kh, kw) > IM2COL_MAX_KERNEL:
        raise ValueError(f"a padded row-major im2col counts kernel sides up to {IM2COL_MAX_KERNEL}, got {kh}x{kw}")
    w_main = im2col_w_main(w_out, beat)
    jobs = [(0, w_main)] + ([(w_main, w_out - w_main)] if w_main < w_out else [])
    for ow0, w_seg in jobs:
        if im2col_right(n, kw, s, pad, ow0, w_seg, beat) > beat:
            raise ValueError(f"the right border of a row-major im2col must fit the last beat of a row, got W={n} K={kw} S={s} pad={pad}")


def _validate_im2col_params(params: dict, beat: int, features: dict) -> None:
    """The relations of the HAL paths."""
    kh, kw = params["KERNEL_SIZE_H"], params["KERNEL_SIZE_W"]
    s, pad = params["CONV_STRIDE"], params["CONV_PAD"]
    m, n = params["SIZE_M"], params["SIZE_N"]
    layout = (params["IM2COL_IN"], params["IM2COL_OUT"])
    if kh < 1 or kw < 1:
        raise ValueError(f"KERNEL_SIZE_H/KERNEL_SIZE_W must be >= 1, got {kh}x{kw}")
    if params["IM2COL_OUT"] == "ROW_BLOCK":
        _validate_im2row_params(params, beat)
        return
    if s not in (1, 2):
        raise ValueError(f"im2col CONV_STRIDE must be 1 or 2, got {s}")
    if layout == ("BLOCK", "COL_BLOCK"):
        kernels = tuple(range(3, features["IM2COL_KERNEL"] + 1, 2))
        if kh != kw or kh not in kernels or s != 1 or pad != kh // 2:
            raise ValueError(f"BLOCK im2col is K x K with K in {kernels}, stride 1, pad K // 2, got K={kh}x{kw} S={s} pad={pad}")
        widths = im2col_unit_widths(beat, features["IM2COL_MIN_LOG2W"])
        if n not in widths or (m * n) % beat != 0:
            raise ValueError(f"BLOCK im2col needs W in {widths} and H*W a multiple of {beat}, got {m}x{n}")
    elif layout in (("CHW", "COL_BLOCK"), ("CHW", "COL")):
        if pad < 0 or m + 2 * pad < kh or n + 2 * pad < kw:
            raise ValueError(f"the padded image {m}x{n} with pad {pad} must hold the kernel {kh}x{kw}")
        w_out = (n + 2 * pad - kw) // s + 1
        if layout[1] == "COL_BLOCK" and (s != 2 or w_out % beat != 0):
            raise ValueError(f"CHW to COL_BLOCK needs stride 2 and w_out a multiple of {beat}, got S={s} w_out={w_out}")
        _validate_row_major_pad(params, beat, w_out)
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
        tag = "FWD" if params["BLOCK_MODE"] == 0 else "REV"
        base = f"BLOCK{tag}_{m}x{n}"
    elif mode == 3:
        base = f"BLOCKTR{params['TRANSP_MODE']}_{m}x{n}"
    elif mode == 4:
        base = f"UNFOLD_C{c}_{m}x{n}" + ("_BLOCK" if params["LAYOUT"] == "BLOCK" else "")
    elif mode == 5:
        base = f"FOLD_C{c}_{m}x{n}" + ("_BLOCK" if params["LAYOUT"] == "BLOCK" else "")
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


def default_hw_config() -> str:
    """The profile of an entry without `hw_config`: the HW_CONFIG variable of make, else `default`."""
    return os.environ.get("HW_CONFIG") or "default"


def entry_hw_config(entry: dict, suite_hw: str = "") -> str:
    return entry.get("hw_config") or suite_hw or default_hw_config()


def entry_geometry(entry: dict, suite_hw: str = "") -> tuple:
    """(beat, align, features) of the profile of the entry."""
    hw = load_hw_config(entry_hw_config(entry, suite_hw))
    return beat_elems(hw), align_elems(hw), hw_features(hw)


def entry_beat(entry: dict, suite_hw: str = "") -> int:
    return entry_geometry(entry, suite_hw)[0]


def _entry_name(entry: dict, suite_hw: str = "") -> str:
    """The test name; every entry, named or not, passes the checks of its profile.

    An explicit name gets the profile tag like an auto name, so two profiles never share a test dir.
    """
    beat, align, features = entry_geometry(entry, suite_hw)
    tag = hw_tag(entry_hw_config(entry, suite_hw))
    if "chain" in entry:
        if not entry.get("name"):
            raise ValueError("Chained tests require a 'name' field")
        for p in entry["chain"]:
            normalize_params(p, beat, align, features)
        return entry["name"] + (f"_{tag}" if tag else "")
    params = normalize_params(entry.get("params", {}), beat, align, features)
    if entry.get("name"):
        return entry["name"] + (f"_{tag}" if tag else "")
    return auto_test_name(params, tag)


def load_test_suite(json_path: str) -> dict:
    with open(json_path) as f:
        return json.load(f)


def list_tests(json_path: str, skipped: list = None) -> list:
    """Test names. An entry that the profile rejects goes to `skipped` as (entry, reason) when
    the caller passes a list, else the error propagates."""
    suite = load_test_suite(json_path)
    suite_hw = suite.get("hw_config", "")
    names = []
    for e in suite.get("tests", []):
        try:
            names.append(_entry_name(e, suite_hw))
        except ValueError as err:
            if skipped is None:
                raise
            skipped.append((e, str(err)))
    return names


def find_test_entry(json_path: str, test_name: str) -> dict:
    suite = load_test_suite(json_path)
    suite_hw = suite.get("hw_config", "")
    for entry in suite.get("tests", []):
        try:
            name = _entry_name(entry, suite_hw)
        except ValueError:
            continue  # the profile rejects this entry; list_tests reports it
        if name == test_name:
            out = dict(entry)
            out["name"] = test_name
            out["hw_config"] = entry_hw_config(entry, suite_hw)
            beat, align, features = entry_geometry(entry, suite_hw)
            if "chain" in entry:
                out["chain"] = [normalize_params(p, beat, align, features) for p in entry["chain"]]
            else:
                out["params"] = normalize_params(entry.get("params", {}), beat, align, features)
            return out
    available = ", ".join(list_tests(json_path, []))
    raise ValueError(f"Test '{test_name}' not found in {json_path}. Available: {available}")
