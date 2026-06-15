/*
 * datamover_package.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2019-2026 ETH Zurich, University of Bologna
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
 *           Cyrill Durrer <cdurrer@iis.ee.ethz.ch>
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
  typedef enum logic[4:0] { DATAMOVER_COPY, DATAMOVER_TRANSPOSE, DATAMOVER_CIM_CONVERSION, DATAMOVER_CIM_TRANSPOSE, DATAMOVER_UNFOLD, DATAMOVER_FOLD, DATAMOVER_IM2COL } datamover_mode_e;
  typedef struct packed {
    transp_mode_e                     transp_mode;
    logic [$clog2(MAX_BANDWIDTH/8):0] transp_len;
    logic [2:0]                       transp_stride; // 1, 2, or 4 elements
    datamover_mode_e                  datamover_mode; // 0: copy, 1: tranpose, 2: CIM layout conversion
    logic [11:0]                      tensor_size_m;
    logic [11:0]                      tensor_size_n;
    logic [20:0]                      total_elements; // num_channels * size_m * size_n (pre-computed by HAL)
    logic [10:0]                      num_channels;   // number of channels (for unfolding/folding)
  } ctrl_engine_t;

  // Datamover job FSM states
  typedef enum logic [1:0] { DM_IDLE, DM_STARTING, DM_WORKING, DM_FINISHED } datamover_state_e;

endpackage
