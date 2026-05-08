"""Load datamover test suites: expand mode, merge HW config + per-test params, auto-name."""

import json
from pathlib import Path
from typing import List

HW_CONFIGS_FILE = Path(__file__).parent / "hw_configs.json"

MODE_TABLE = {
    "COPY":       {"DATAMOVER_MODE": 0, "TRANSP_MODE": 0, "CIM_MODE": 0, "ROW_TILE_SIZE": 0},
    "TRANSP_1":   {"DATAMOVER_MODE": 1, "TRANSP_MODE": 1, "CIM_MODE": 0, "ROW_TILE_SIZE": 0},
    "TRANSP_2":   {"DATAMOVER_MODE": 1, "TRANSP_MODE": 2, "CIM_MODE": 0, "ROW_TILE_SIZE": 0},
    "TRANSP_4":   {"DATAMOVER_MODE": 1, "TRANSP_MODE": 4, "CIM_MODE": 0, "ROW_TILE_SIZE": 0},
    "CIM_FWD":    {"DATAMOVER_MODE": 2, "TRANSP_MODE": 0, "CIM_MODE": 0},
    "CIM_REV":    {"DATAMOVER_MODE": 2, "TRANSP_MODE": 0, "CIM_MODE": 1},
    "CIMT_FWD_1": {"DATAMOVER_MODE": 3, "TRANSP_MODE": 1, "CIM_MODE": 0},
    "CIMT_FWD_2": {"DATAMOVER_MODE": 3, "TRANSP_MODE": 2, "CIM_MODE": 0},
    "CIMT_FWD_4": {"DATAMOVER_MODE": 3, "TRANSP_MODE": 4, "CIM_MODE": 0},
    "CIMT_REV_1": {"DATAMOVER_MODE": 3, "TRANSP_MODE": 1, "CIM_MODE": 1},
    "CIMT_REV_2": {"DATAMOVER_MODE": 3, "TRANSP_MODE": 2, "CIM_MODE": 1},
    "CIMT_REV_4": {"DATAMOVER_MODE": 3, "TRANSP_MODE": 4, "CIM_MODE": 1},
    "UNFOLD":     {"DATAMOVER_MODE": 4, "TRANSP_MODE": 0, "CIM_MODE": 0},
    "FOLD":       {"DATAMOVER_MODE": 5, "TRANSP_MODE": 0, "CIM_MODE": 0},
}


def load_hw_configs() -> dict:
    with open(HW_CONFIGS_FILE) as f:
        return json.load(f)


def auto_name(mode: str, params: dict) -> str:
    M = params["TENSOR_SIZE_M"]
    N = params["TENSOR_SIZE_N"]
    BW = params["BANDWIDTH"]
    WW = params["WORD_WIDTH"]
    base = f"M{M}_N{N}_BW{BW}_W{WW}"
    if mode == "COPY":
        return f"COPY_{base}"
    if mode.startswith("TRANSP_"):
        suffix = "_MA1" if int(params["MISALIGNED_ACCESSES"]) else ""
        return f"{mode}_{base}{suffix}"
    if mode.startswith("CIM"):
        return f"{mode}_{base}_RT{params['ROW_TILE_SIZE']}"
    return f"{mode}_{base}"


def load_test_suite(json_file: str) -> List[dict]:
    with open(json_file) as f:
        data = json.load(f)
    if not isinstance(data, dict) or "tests" not in data:
        raise ValueError(f"{json_file}: expected object with 'tests' array")

    hw_configs = load_hw_configs()
    suite_default_hw = data.get("hw_config", "default")

    tests = []
    seen = set()
    for entry in data["tests"]:
        hw_name = entry.get("hw_config", suite_default_hw)
        if hw_name not in hw_configs:
            raise ValueError(f"{json_file}: unknown hw_config '{hw_name}'")

        mode = entry.get("mode")
        if mode is None:
            raise ValueError(f"{json_file}: each test entry needs a 'mode' field")
        if mode not in MODE_TABLE:
            raise ValueError(f"{json_file}: unknown mode '{mode}'. Valid: {sorted(MODE_TABLE)}")

        merged = {**hw_configs[hw_name], **MODE_TABLE[mode], **entry.get("params", {})}
        name = entry.get("name") or auto_name(mode, merged)
        if name in seen:
            raise ValueError(f"{json_file}: duplicate test name '{name}'")
        seen.add(name)
        tests.append({"name": name, "params": merged, "hw_config": hw_name, "mode": mode})
    return tests


def find_test(tests: List[dict], name: str) -> dict:
    for t in tests:
        if t["name"] == name:
            return t
    raise KeyError(name)


if __name__ == "__main__":
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("json_file")
    p.add_argument("--list", action="store_true")
    args = p.parse_args()
    tests = load_test_suite(args.json_file)
    if args.list:
        for t in tests:
            print(f"{t['name']}\t[{t['hw_config']}, mode={t['mode']}]")
    else:
        print(f"{len(tests)} tests in {Path(args.json_file).name}")
