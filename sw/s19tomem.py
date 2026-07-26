#
# Copyright (C) 2018-2019 ETH Zurich and University of Bologna
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# SPDX-License-Identifier: Apache-2.0
#

import numpy as np
import sys

# Instructions start at 0x1c00_0000
# Data starts at 0x1c01_0000
# Stack starts at 0x1c18_8000 (just above dataram)
# Must match sw/link.ld and rtl/verif/tb_datamover.sv MEMORY_SIZE
MEM_START  = 0x1c000000
INSTR_SIZE = 0x10000               # 64KB instruction memory
INSTR_END  = MEM_START + INSTR_SIZE
DATA_BASE  = MEM_START + 0x10000
DATA_SIZE  = 0x180000              # 1.5 MB data memory (1504 KB data + 32 KB stack)
DATA_END   = DATA_BASE + DATA_SIZE

INSTR_MEM_SIZE = INSTR_SIZE // 4   # in 32b words
DATA_MEM_SIZE  = DATA_SIZE // 4    # in 32b words

with open(sys.argv[1], "r") as f:
    s = f.read()

if len(sys.argv) >= 4:
    instr_txt = sys.argv[2]
    data_txt  = sys.argv[3]
else:
    instr_txt = "stim_instr.txt"
    data_txt  = "stim_data.txt"

instr_mem = np.zeros(INSTR_MEM_SIZE, dtype=np.int64)
# poison unwritten memory so bytes the DUT fails to write mismatch golden in verify
data_mem  = np.random.default_rng(0).integers(1 << 32, size=DATA_MEM_SIZE, dtype=np.int64)

# Vectorized parsing: each token is "AAAAAAAA?HHHHHHHHLLLLLLLL" (25 chars).
tokens = s.split()
parsed = np.array(
    [(int(t[0:8], 16), int(t[9:17], 16), int(t[17:25], 16)) for t in tokens],
    dtype=np.int64,
)
addrs, whs, wls = parsed[:, 0], parsed[:, 1], parsed[:, 2]

data_mask = (addrs >= DATA_BASE) & (addrs < DATA_END)
imem_mask = (addrs >= MEM_START) & (addrs < INSTR_END) & ~data_mask

didx = ((addrs[data_mask] - DATA_BASE) // 4).astype(np.int64)
data_mem[didx]     = wls[data_mask]
data_mem[didx + 1] = whs[data_mask]

iidx = ((addrs[imem_mask] - MEM_START) // 4).astype(np.int64)
instr_mem[iidx]     = wls[imem_mask]
instr_mem[iidx + 1] = whs[imem_mask]

with open(instr_txt, "w") as f:
    f.write("\n".join(np.char.mod("%08x", instr_mem).tolist()))
    f.write("\n")
with open(data_txt, "w") as f:
    f.write("\n".join(np.char.mod("%08x", data_mem).tolist()))
