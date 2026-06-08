#!/bin/bash
# Generate the datamover register interface (SystemVerilog + C header + HTML doc)
# from the SystemRDL description with PeakRDL.
#
# Requires `peakrdl` on PATH. Run this script through `uv run scripts/gen_regif.sh`.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REGIF_DIR="${REPO_ROOT}/rtl/ctrl"
RDL_FILE="${REGIF_DIR}/datamover_regif.rdl"
OUT_DIR="${REGIF_DIR}/regif"
# The C header lives with the rest of the SW (the SV register file stays in OUT_DIR).
C_HEADER="${REPO_ROOT}/sw/datamover_regif.h"

mkdir -p "${OUT_DIR}"

peakrdl regblock  "${RDL_FILE}" -o "${OUT_DIR}/"                  --cpuif obi-flat --default-reset arst_n --hwif-report --addr-width 32
peakrdl html      "${RDL_FILE}" -o "${OUT_DIR}/html/"
peakrdl c-header  "${RDL_FILE}" -o "${C_HEADER}"

# PeakRDL emits unpacked structs; the hwpe_ctrl_target FIFOes the job-dependent
# struct, which requires a packed type. Convert all generated typedefs to packed.
sed -i 's/typedef[[:space:]]\+struct\b/typedef struct packed/g' "${OUT_DIR}/datamover_regif_pkg.sv"
