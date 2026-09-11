# Sweep specs

Each `*.spec.json` file in this directory describes one parameter sweep of a datamover mode.

The generator is [`datamover_model/workloads/sweep.py`](../../datamover_model/workloads/sweep.py).
The generator expands one spec into a suite in `tests/generated/`. The generator keeps only the
combinations that pass `normalize_params` and the golden-model run, which also checks the TB
memory budget. A spec has no `"tests"` key. Thus the runner ignores the spec file and finds the
generated suites only.

## Commands

```sh
make gen-tests                                       # all specs -> tests/generated/*.json
make tests-generated PARALLEL=8 TIMEOUT=300          # generate, then run through the normal runner
make tests TEST_JSON=tests/generated/cim_sweep.json  # run one generated suite
```

## Format of a spec

```jsonc
{
  "name": "cim_sweep",      // the output stem -> tests/generated/cim_sweep.json
  "op": "cim",              // copy | transpose | cim | cim_transpose | unfold | fold | im2col
  "hw_config": "default",   // a key of configs/hw_configs.json
  "max_tests": 30,          // the maximum number of valid tests without duplicates
  "seed": 1,                // the RNG seed. The same seed gives the same suite
  "axes": {                 // an axis name is an exact test param key. Four value forms:
    "SIZE_M": {"min": 1, "max": 256},                     // a random integer in the range
    "SIZE_N": {"min": 8, "max": 64, "multiple_of": 8},    // a random integer, snapped to a multiple
    "CIM_MODE": [0, 1],                                   // a random choice from the list
    "CONV_STRIDE": 2,                                     // a scalar is a constant on every candidate
    "KERNEL": [                                           // a group axis: one draw sets several
      {"KERNEL_SIZE_H": 2, "KERNEL_SIZE_W": 2},           // params together. The axis name is only
      {"KERNEL_SIZE_H": 4, "KERNEL_SIZE_W": 4}            // a label; the first and the last object
    ]                                                     // are the boundary values
  },
  "exclude": [{"CIM_MODE": 1, "TRANSP_MODE": 4}]  // optional. The generator prunes matching combos
}
```

A group entry may hold a list or a range in place of a constant; the generator draws it when
the entry is picked, so one entry states the value set one case allows. A value may be a string.
The generator evaluates the string as a Python expression after the draw, with the drawn values as
variables: `"KERNEL_SIZE_W": "KERNEL_SIZE_H"`. The name of the param itself stands for its own
plain draw, so an expression can snap it: `"SIZE_M": "SIZE_M - SIZE_M % 8"`. A spec may carry
`"constraints"`, a list of expressions that every candidate must satisfy:

```jsonc
  "constraints": ["SIZE_C * SIZE_M * SIZE_N // 4 <= 65535 or LAYOUT == \"CIM\""],
  "axes": {
    "LAYOUTS": [{"IM2COL_IN": "CIM", "SIZE_N": [8, 16, 32, 64], "SIZE_M": {"min": 8, "max": 512, "multiple_of": 8}}]
  }
```

The `op` key sets `DATAMOVER_MODE`; the axes set the other params. The sweep validation rejects a
combination for the same reason the normal test generation rejects it, so the counts the generator
prints document the legal envelope of each mode.

When every axis is finite (a list or a scalar) and the full cross product fits the draw budget
(`max_tests * 8`), the generator enumerates the product instead of sampling, so every combination
appears exactly once.

A spec may carry a `description` key. The generator ignores it; use it to state the intent and the
limits the spec probes.
