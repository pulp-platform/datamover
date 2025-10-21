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

  parameter int unsigned MAX_BW = 512; // support maximum 512bits of bandwidth

  typedef enum logic[1:0] { TRANSP_32B, TRANSP_16B, TRANSP_8B, TRANSP_NONE } transp_mode_e;
  typedef struct packed {
    transp_mode_e              transp_mode;
    logic [$clog2(MAX_BW/8):0] transp_len;
    logic [2:0]                transp_stride; // 1, 2, or 4
  } ctrl_engine_t;

  typedef struct packed {
    logic [31:0] in_ptr;
    logic [31:0] out_ptr;
    logic [11:0] tot_len;
    logic [11:0] in_d0_len;
    logic [11:0] in_d1_len;
    logic [11:0] out_d0_len;
    logic [11:0] out_d1_len;
    logic [31:0] in_d0_stride;
    logic [31:0] in_d1_stride;
    logic [31:0] in_d2_stride;
    logic [31:0] out_d0_stride;
    logic [31:0] out_d1_stride;
    logic [31:0] out_d2_stride;
    logic [2:0]  transp_mode;
    logic [15:0] leftover;
  } datamover_config_t;

endpackage
