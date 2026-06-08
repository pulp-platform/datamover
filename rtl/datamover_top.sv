/*
 * Copyright (C) 2020-2026 ETH Zurich and University of Bologna
 *
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
 *           Sergio Mazzola <smazzola@iis.ee.ethz.ch>
 *           Cyrill Durrer <cdurrer@iis.ee.ethz.ch>
 *           Lionnus Kesting <lkesting@iis.ee.ethz.ch>
 */

`include "hci_helpers.svh"

module datamover_top
  import hwpe_ctrl_package::*;
  import hci_package::*;
  import datamover_package::*;
#(
  parameter int unsigned ID = 4,                  // control target peripheral ID width
  parameter int unsigned BANDWIDTH = 512,         // total bandwidth of HWPE to TCDM (in bits)
  parameter int unsigned NUM_ELEM_WORD = 8,       // number of elements in a memory bank word
  parameter int unsigned ELEM_WIDTH = 8,          // element width (in bits)
  parameter int unsigned N_CORES   = 2,           // number of cores for event inputs
  parameter int unsigned N_CONTEXT = 2,           // depth of the control target job queue
  parameter int unsigned MISALIGNED_ACCESSES = 0, // enable misaligned accesses on TCDM interface
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(tcdm) = '0,
  // Dependent parameters: do not modify!
  localparam int unsigned WORD_WIDTH = NUM_ELEM_WORD * ELEM_WIDTH, // should correspond to bank width
  localparam int unsigned NUM_WORDS = BANDWIDTH / WORD_WIDTH // TCDM interface width in number of words
) (
  // global signals
  input  logic                    clk_i,
  input  logic                    rst_ni,
  input  logic                    test_mode_i,
  // events
  output logic [N_CORES-1:0][REGFILE_N_EVT-1:0] evt_o,
  // busy status
  output logic                    busy_o,
  // tcdm master ports
  hci_core_intf.initiator         tcdm,
  // periph slave port
  hwpe_ctrl_intf_periph.slave     periph
);

  // We "sacrifice" 1 word of memory interface bandwidth in order to support
  // realignment at a word boundary if the access are misaligned.
  localparam BANDWIDTH_ALIGNED = MISALIGNED_ACCESSES == 0 ? BANDWIDTH : BANDWIDTH-WORD_WIDTH;

  // Software-generated clear signal.
  logic clear;

  // These are the bit fields used to control the streamer.
  ctrl_streamer_t  streamer_ctrl;
  flags_streamer_t streamer_flags;

  // Bit field to control the engine.
  ctrl_engine_t engine_ctrl;

  // number of elements (in the full bandwidth, not a single bank word)
  localparam NB_ELEMENTS = BANDWIDTH_ALIGNED / ELEM_WIDTH;

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( BANDWIDTH_ALIGNED ),
    .ELEMENT_WIDTH ( ELEM_WIDTH ),
    .STRB_WIDTH ( NB_ELEMENTS )
  ) data_in  (
    .clk(clk_i)
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( BANDWIDTH_ALIGNED ),
    .ELEMENT_WIDTH ( ELEM_WIDTH ),
    .STRB_WIDTH ( NB_ELEMENTS )
  ) data_out (
    .clk(clk_i)
  );

  // The streamer exposes on the memory side a single TCDM 512-bit interface
  // meant to be directly plugged into an Heterogeneous Cluster Interconnect.
  // On the accelerator side, it exposes an outgoing data in stream and
  // an incoming data out HWPE-Streams, each 512-bit wide.
  datamover_streamer #(
    .BANDWIDTH             ( BANDWIDTH             ),
    .NUM_ELEM_WORD         ( NUM_ELEM_WORD         ),
    .ELEM_WIDTH            ( ELEM_WIDTH            ),
    .TCDM_FIFO_DEPTH       ( 0                     ),
    .MISALIGNED_ACCESSES   ( MISALIGNED_ACCESSES   ),
    .`HCI_SIZE_PARAM(tcdm) ( `HCI_SIZE_PARAM(tcdm) )
  ) i_streamer (
    .clk_i      ( clk_i          ),
    .rst_ni     ( rst_ni         ),
    .test_mode_i( test_mode_i    ),
    .enable_i   ( 1'b1           ),
    .clear_i    ( clear          ),
    .data_in    ( data_in        ),
    .data_out   ( data_out       ),
    .tcdm       ( tcdm           ),
    .ctrl_i     ( streamer_ctrl  ),
    .flags_o    ( streamer_flags )
  );

  // The engine transforms the data_in stream into data_out. Supported modes:
  // copy, transpose, CIM layout conversion, unfold, and fold.
  // An internal buffer (elem_matrix) of size BWxBW is used to reshuffle the data.
  datamover_engine #(
    .FIFO_DEPTH ( 4          ),
    .BANDWIDTH_ALIGNED ( BANDWIDTH_ALIGNED ),
    .NUM_ELEM_WORD ( NUM_ELEM_WORD ),
    .ELEM_WIDTH ( ELEM_WIDTH )
  ) i_engine (
    .clk_i      ( clk_i          ),
    .rst_ni     ( rst_ni         ),
    .test_mode_i( test_mode_i    ),
    .enable_i   ( 1'b1           ),
    .clear_i    ( clear          ),
    .ctrl_i     ( engine_ctrl    ),
    .data_in    ( data_in        ),
    .data_out   ( data_out       )
  );

  datamover_ctrl #(
    .NUM_CORES   ( N_CORES                        ),
    .NUM_CONTEXT ( N_CONTEXT                      ),
    .ID_WIDTH    ( ID                             ),
    .TRANSP_LEN  ( BANDWIDTH_ALIGNED / ELEM_WIDTH )
  ) i_ctrl (
    .clk_i            ( clk_i          ),
    .rst_ni           ( rst_ni         ),
    .evt_o            ( evt_o          ),
    .busy_o           ( busy_o         ),
    .clear_o          ( clear          ),
    .ctrl_streamer_o  ( streamer_ctrl  ),
    .flags_streamer_i ( streamer_flags ),
    .ctrl_engine_o    ( engine_ctrl    ),
    .periph           ( periph         )
  );

  localparam int unsigned DEBUG_DW  = `HCI_SIZE_GET_DW(tcdm);
  localparam int unsigned DEBUG_BW  = `HCI_SIZE_GET_BW(tcdm);
  localparam int unsigned DEBUG_AW  = `HCI_SIZE_GET_AW(tcdm);
  localparam int unsigned DEBUG_UW  = `HCI_SIZE_GET_UW(tcdm);
  localparam int unsigned DEBUG_IW  = `HCI_SIZE_GET_IW(tcdm);
  localparam int unsigned DEBUG_EW  = `HCI_SIZE_GET_EW(tcdm);
  localparam int unsigned DEBUG_EHW = `HCI_SIZE_GET_EHW(tcdm);

  `ifndef SYNTHESIS
  `ifndef VERILATOR
  `ifndef VCS
    initial begin
      assert (BANDWIDTH % WORD_WIDTH == 0)
        else $fatal("BANDWIDTH (%0d) must be a multiple of WORD_WIDTH (%0d)", BANDWIDTH, WORD_WIDTH);
    end
  `endif
  `endif
  `endif

endmodule // datamover_top
