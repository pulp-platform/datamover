/*
 * datamover_package.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2019-2020 ETH Zurich, University of Bologna
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */

/*
 * Authors:  Francesco Conti <f.conti@unibo.it>
 */

package datamover_package;

  typedef struct packed {
    hci_package::hci_streamer_ctrl_t data_in_source_ctrl;
    hci_package::hci_streamer_ctrl_t data_out_sink_ctrl;
  } ctrl_streamer_t;
  typedef struct packed {
    hci_package::hci_streamer_flags_t data_in_source_flags;
    hci_package::hci_streamer_flags_t data_out_sink_flags;
    logic tcdm_fifo_empty;
  } flags_streamer_t;

  parameter int unsigned MAX_BANDWIDTH = 512; // support maximum 512bits of bandwidth

  typedef enum logic[1:0] { TRANSP_NONE, TRANSP_1ELEM, TRANSP_2ELEM, TRANSP_4ELEM } transp_mode_e;
  typedef struct packed {
    transp_mode_e                     transp_mode;
    logic [$clog2(MAX_BANDWIDTH/8):0] transp_len;
    logic [2:0]                       transp_stride; // 1, 2, or 4
    logic [4:0]                       datamover_mode; // 0: copy, 1: tranpose, 2: CIM layout conversion
    logic [11:0]                      matrix_dim_m;
    logic [11:0]                      matrix_dim_n;
  } ctrl_engine_t;

  parameter int unsigned HWPE_REGISTER_OFFS           = 32'h00; // Standard HWPE register offset
  // General hwpe register offsets
  parameter int unsigned DATAMOVER_COMMIT_AND_TRIGGER = 32'h00;  // Trigger commit
  parameter int unsigned DATAMOVER_ACQUIRE            = 32'h04;  // Acquire command
  parameter int unsigned DATAMOVER_FINISHED           = 32'h08;  // Finished signal
  parameter int unsigned DATAMOVER_STATUS             = 32'h0C;  // Status register
  parameter int unsigned DATAMOVER_RUNNING_JOB        = 32'h10;  // Running job ID
  parameter int unsigned DATAMOVER_SOFT_CLEAR         = 32'h14;  // Soft clear
  parameter int unsigned DATAMOVER_SWSYNC             = 32'h18;  // Software synchronization
  parameter int unsigned DATAMOVER_URISCY_IMEM        = 32'h1C;  // uRISCy instruction memory

  // Job configuration register offsets
  parameter int unsigned DATAMOVER_REGISTER_OFFS       = 32'h40;  // Register base offset
  parameter int unsigned DATAMOVER_REGISTER_CXT0_OFFS  = 32'h80;  // Context 0 offset
  parameter int unsigned DATAMOVER_REGISTER_CXT1_OFFS  = 32'h120; // Context 1 offset

  // Job-specific registers (packed into 32-bit words to speed up configuration and save memory)
  parameter int unsigned DATAMOVER_REG_IN_PTR           = 32'h00;  // Input pointer
  parameter int unsigned DATAMOVER_REG_OUT_PTR          = 32'h04;  // Output pointer
  parameter int unsigned DATAMOVER_REG_TOT_LEN          = 32'h08;  // Total length in number of accesses (BW)
  parameter int unsigned DATAMOVER_REG_IN_D0            = 32'h0C;  // [31:16] in_d0_stride; [15:0] in_d0_len
  parameter int unsigned DATAMOVER_REG_IN_D1            = 32'h10;  // [31:16] in_d1_stride; [15:0] in_d1_len
  parameter int unsigned DATAMOVER_REG_IN_D2            = 32'h14;  // [31:16] in_d2_stride; [15:0] in_d2_len
  parameter int unsigned DATAMOVER_REG_IN_D3            = 32'h18;  // [31:16] in_d3_stride; [15:0] in_d3_len
  parameter int unsigned DATAMOVER_REG_OUT_D0           = 32'h1C;  // [31:16] out_d0_stride; [15:0] out_d0_len
  parameter int unsigned DATAMOVER_REG_OUT_D1           = 32'h20;  // [31:16] out_d1_stride; [15:0] out_d1_len
  parameter int unsigned DATAMOVER_REG_OUT_D2           = 32'h24;  // [31:16] out_d2_stride; [15:0] out_d2_len
  parameter int unsigned DATAMOVER_REG_OUT_D3           = 32'h28;  // [31:16] out_d3_stride; [15:0] out_d3_len
  parameter int unsigned DATAMOVER_REG_IN_OUT_D4_STRIDE = 32'h2C;  // [31:16] out_d4_stride; [15:0] in_d4_stride (d4_len unnecessary due to tot_len)
  parameter int unsigned DATAMOVER_REG_DIM_ENABLE       = 32'h30;  // [31:8] unused;[7:4] write_dim_en; [3:0] read_dim_en -> one-hot encoding (LSB->d1), d0 is always enabled
  parameter int unsigned DATAMOVER_REG_CTRL_ENGINE      = 32'h34;  // [31:27] datamover_mode (0: copy, 1: transpose, 2: CIM layout conversion); [26:15] matrix_dim_n; [14:3] matrix_dim_m [2:0] transp_mode (LSB: 000=none, 001=1 elem, 010=2 elem, 100=4 elem)

  // Note: increase N_IO_REGS in datamover_top.sv when adding new registers here!


endpackage
