"""Load datamover test suites. HW_RTL_KEYS and WORKLOAD_KEYS are disjoint."""

import json
from pathlib import Path
from typing import List

HW_CONFIGS_FILE = Path(__file__).parent / "hw_configs.json"

HW_RTL_KEYS   = frozenset({"BANDWIDTH", "WORD_WIDTH", "ELEM_WIDTH", "MISALIGNED_ACCESSES"})
WORKLOAD_KEYS = frozenset({"DATAMOVER_MODE", "TRANSP_MODE", "CIM_MODE",
                           "TENSOR_SIZE_M", "TENSOR_SIZE_N", "NUM_CHANNELS", "ROW_TILE_SIZE"})

WORKLOAD_DEFAULTS = {"TRANSP_MODE": 0, "CIM_MODE": 0, "NUM_CHANNELS": 1, "ROW_TILE_SIZE": 0}

assert HW_RTL_KEYS.isdisjoint(WORKLOAD_KEYS)
assert WORKLOAD_DEFAULTS.keys() <= WORKLOAD_KEYS


def load_hw_configs() -> dict:
    with open(HW_CONFIGS_FILE) as f:
        configs = json.load(f)
    for name, vals in configs.items():
        if set(vals.keys()) != HW_RTL_KEYS:
            raise ValueError(f"hw_config '{name}' must have exactly keys {sorted(HW_RTL_KEYS)}, got {sorted(vals.keys())}")
    return configs


def auto_name(p: dict) -> str:
    dm, tm, cm = p["DATAMOVER_MODE"], p["TRANSP_MODE"], p["CIM_MODE"]
    base = f"M{p['TENSOR_SIZE_M']}_N{p['TENSOR_SIZE_N']}_BW{p['BANDWIDTH']}_W{p['WORD_WIDTH']}"
    if dm == 0:
        prefix = "COPY"
    elif dm == 1:
        prefix = f"TRANSP_{tm}"
        if int(p["MISALIGNED_ACCESSES"]):
            base += "_MA1"
    elif dm == 2:
        prefix = "CIM_FWD" if cm == 0 else "CIM_REV"
        base += f"_RT{p['ROW_TILE_SIZE']}"
    elif dm == 3:
        prefix = f"CIMT_{'FWD' if cm == 0 else 'REV'}_{tm}"
        base += f"_RT{p['ROW_TILE_SIZE']}"
    elif dm == 4:
        prefix = "UNFOLD"
    elif dm == 5:
        prefix = "FOLD"
    else:
        raise ValueError(f"unknown DATAMOVER_MODE={dm}")
    return f"{prefix}_{base}"


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

        params = entry.get("params", {})
        bad = params.keys() - WORKLOAD_KEYS
        if bad:
            raise ValueError(
                f"{json_file}: test 'params' may only contain {sorted(WORKLOAD_KEYS)}, "
                f"got disallowed {sorted(bad)}"
            )

        merged = {**WORKLOAD_DEFAULTS, **hw_configs[hw_name], **params}
        missing = WORKLOAD_KEYS - merged.keys()
        if missing:
            raise ValueError(f"{json_file}: test missing required workload keys {sorted(missing)}")

        name = entry.get("name") or auto_name(merged)
        if name in seen:
            raise ValueError(f"{json_file}: duplicate test name '{name}'")
        seen.add(name)
        tests.append({"name": name, "params": merged, "hw_config": hw_name})
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
            print(f"{t['name']}\t[{t['hw_config']}]")
    else:
        print(f"{len(tests)} tests in {Path(args.json_file).name}")
