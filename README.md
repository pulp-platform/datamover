<p align="left">
  <img src="logo.png" width="300" alt="Ratha Logo">
</p>

[![License HW](https://img.shields.io/badge/License%20HW-SHL--0.51-green)](https://solderpad.org/licenses/SHL-0.51/)
[![License SW](https://img.shields.io/badge/License%20SW-Apache--2.0-orange)](https://www.apache.org/licenses/LICENSE-2.0)
[![CI status](https://github.com/pulp-platform/datamover/actions/workflows/gitlab-ci.yml/badge.svg?branch=lkesting/konark)](https://github.com/pulp-platform/datamover/actions/workflows/gitlab-ci.yml?query=branch%3Alkesting%2Fkonark)

**Ratha** (formerly Datamover) is a parameterizable HWPE that operates on tensors stored in TCDM, reading from one region and writing back the transformed result to another. Supported transformations are element-wise transpose, mapping a tensor to 'CIM layout', a blocked layout with 64 elements consumed by the Surya accelerator, and unfold/fold for MobileViT-style convolutions. This repository contains the SystemVerilog RTL, a Python golden model, and a RISC-V core driven testbench with JSON-defined test suites.

## 🚀 Quick Start

```bash
uv sync --python 3.11
source .venv/bin/activate
bender-0.31.0 checkout
make run-all-tests
```

`make run-all-tests` auto-loads the `riscv` env wrapper; single-test invocations must be prefixed with `riscv` manually.

## Repository Structure

- `rtl/` — `datamover_top{_wrap}.sv`, `datamover_engine.sv`, `datamover_streamer.sv`, `datamover_package.sv`
- `rtl/ctrl/` — SystemRDL register map (`datamover_regif.rdl`), control wrapper around `hwpe_ctrl_target` + regif + job FSM (`datamover_ctrl.sv`), and the generated register file (`regif/`)
- `rtl/verif/` — Ibex-driven SystemVerilog testbench (`tb_datamover.sv`, `tb_dummy_memory.sv`)
- `scripts/` — register-interface generation from the RDL (`gen_regif.sh`)
- `sw/` — Software for the testbench and the HAL(`datamover_config.h`, `datamover_hal.h`, `tb_datamover.c`)
- `datamover_model/` — Python package: `golden_model/` (transforms), `headers/` (C header emit), `workloads/` (suite parsing + `cli`), `testing/` (`runner`, `validate`, reports)
- `configs/` — `hw_configs.json`
- `tests/` — JSON test suites
- `mk/config.mk` — HW config, workload defaults
- `modelsim/` — simulation infra; RTL is compiled once per HW tag into `builds/<BUILD_TAG>/` and shared by every test, while per-test stimuli live in `tests/<TEST_NAME>/`

## Hardware Parameters

Set via `config.mk` defaults or per-test via `configs/hw_configs.json`:

| Parameter             | Meaning |
|-----------------------|---------|
| `BANDWIDTH`           | Total HWPE↔TCDM port width (bits) |
| `WORD_WIDTH`          | Memory-bank word width (bits) |
| `ELEM_WIDTH`          | Element width (bits) |
| `MISALIGNED_ACCESSES` | Non-power-of-two strobed accesses (RTL path currently disabled) |

**Constraints**: `BANDWIDTH` must divide by `WORD_WIDTH`; `WORD_WIDTH/ELEM_WIDTH` must be a power of two. Transpose only supports `NUM_ELEM_WORD ∈ {2, 4}`; granularity is selected at runtime via `TRANSP_MODE`.

## Operating Modes

| `DATAMOVER_MODE` | Description |
|------------------|-------------|
| 0 | **Copy** — straight-through |
| 1 | **Transpose** — granularity via `TRANSP_MODE` (1/2/4 elements) |
| 2 | **CIM fwd/rev** — blocked layout (blocks of 64), `CIM_MODE` selects direction, `ROW_TILE_SIZE` controls geometry |
| 3 | **CIMT fwd/rev** |
| 4 | **Unfold** (MobileViT) |
| 5 | **Fold** (MobileViT) |

For register layout, see [datamover_package.sv](rtl/datamover_package.sv).

## Running Tests

```bash
# Single test (note: riscv prefix required)
riscv make run-sim-pipeline TEST_JSON=tests/copy.json TEST_NAME=COPY_8x8 NO_GUI=1

# A whole suite
make run-test TEST_JSON=tests/cim.json PARALLEL=8

# A single test by name
make run-test TEST_JSON=tests/cim.json TEST=<TEST_NAME> NO_GUI=1

# All enabled suites
make run-all-tests PARALLEL=8
```

### Quick tests (no JSON)

Run a single transform directly from the command line; HW comes from `HW_CONFIG`
(a profile in `configs/hw_configs.json`, default `default`). Defined in `mk/config.mk`:

```bash
riscv make test-copy SIZE_M=64 SIZE_N=64 NO_GUI=1
riscv make test-transpose SIZE_M=64 SIZE_N=128 TRANSP_MODE=2 HW_CONFIG=bw128_w32
riscv make test-cim-layout SIZE_M=64 SIZE_N=128 ROW_TILE_SIZE=64 HW_CONFIG=bw128_w32
riscv make test-cim-layout-reverse SIZE_M=64 SIZE_N=128 ROW_TILE_SIZE=64 HW_CONFIG=bw128_w32
riscv make test-cim-layout-transpose SIZE_M=64 SIZE_N=128 ROW_TILE_SIZE=64 HW_CONFIG=bw128_w32
riscv make test-unfold SIZE_C=64 SIZE_M=16 SIZE_N=16
riscv make test-fold   SIZE_C=64 SIZE_M=16 SIZE_N=16
```

`TEST_NAME` is auto-derived; add `COUNT=1` for counting stimuli or `NO_GUI=1` for headless.

JUnit/JSON/CSV reports land in `reports/`; each test runs in `modelsim/build_<TEST_NAME>/`. Suites live in `tests/*.json`; HW configs in `configs/hw_configs.json`. Test entries use `params` (e.g. `DATAMOVER_MODE`, `TRANSP_MODE`, `CIM_MODE`, `ROW_TILE_SIZE`, `SIZE_M`, `SIZE_N`, `SIZE_C`, `COUNT`) and an optional per-test `hw_config`; the name is auto-generated when omitted.

## Cleanup

```bash
make clean        # build artifacts + reports
make clean-all    # also remove .bender
```

## Contributors

- Francesco Conti, University of Bologna (*f.conti@unibo.it*)
- Arpan Suravi Prasad, ETH Zurich (*prasadar@iis.ee.ethz.ch*)
- Sergio Mazzola, ETH Zurich (*smazzola@iis.ee.ethz.ch*)
- Cyrill Durrer, ETH Zurich (*cdurrer@iis.ee.ethz.ch*)
- Lionnus Kesting, ETH Zurich (*lkesting@iis.ee.ethz.ch*)

## License

- *Software*: Apache License Version 2.0 (`LICENSE.sw`)
- *Hardware*: Solderpad Hardware License Version 0.51 (`LICENSE.hw`)
