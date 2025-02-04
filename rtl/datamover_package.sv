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

  // Job-specific registers
  parameter int unsigned DATAMOVER_REG_IN_PTR          = 32'h00;  // Input pointer
  parameter int unsigned DATAMOVER_REG_OUT_PTR         = 32'h04;  // Output pointer
  parameter int unsigned DATAMOVER_REG_TOT_LEN         = 32'h08;  // Total length
  parameter int unsigned DATAMOVER_REG_IN_D0_LEN       = 32'h0C;  // Input dimension 0 length
  parameter int unsigned DATAMOVER_REG_IN_D0_STRIDE    = 32'h10;  // Input dimension 0 stride
  parameter int unsigned DATAMOVER_REG_IN_D1_LEN       = 32'h14;  // Input dimension 1 length
  parameter int unsigned DATAMOVER_REG_IN_D1_STRIDE    = 32'h18;  // Input dimension 1 stride
  parameter int unsigned DATAMOVER_REG_IN_D2_STRIDE    = 32'h1C;  // Input dimension 2 stride
  parameter int unsigned DATAMOVER_REG_OUT_D0_LEN      = 32'h20;  // Output dimension 0 length
  parameter int unsigned DATAMOVER_REG_OUT_D0_STRIDE   = 32'h24;  // Output dimension 0 stride
  parameter int unsigned DATAMOVER_REG_OUT_D1_LEN      = 32'h28;  // Output dimension 1 length
  parameter int unsigned DATAMOVER_REG_OUT_D1_STRIDE   = 32'h2C;  // Output dimension 1 stride
  parameter int unsigned DATAMOVER_REG_OUT_D2_STRIDE   = 32'h30;  // Output dimension 2 stride


endpackage
