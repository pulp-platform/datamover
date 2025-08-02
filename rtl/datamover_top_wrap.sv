/*
 * Copyright (C) 2025 ETH Zurich and University of Bologna
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
 * Authors: Sergio Mazzola <smazzola@iis.ee.ethz.ch>
 *          Arpan Suravi Prasad <prasadar@iis.ee.ethz.ch>s
 */

// A wrapper for datamover_top that unrolls the interfaces to HCI and
// the peripheral slave interconnect, making it possible to manually
// connect the desired ports

`include "hci_helpers.svh"

module datamover_top_wrap
  import hwpe_ctrl_package::*;
  import hci_package::*;
  import datamover_package::*;
#(
`ifndef SYNTHESIS
  parameter bit WAIVE_RQ3_ASSERT  = 1'b0,
  parameter bit WAIVE_RQ4_ASSERT  = 1'b0,
  parameter bit WAIVE_RSP3_ASSERT = 1'b0,
  parameter bit WAIVE_RSP5_ASSERT = 1'b0,
`endif
  parameter int unsigned ADDR_WIDTH = 32,         // width of addres bus
  parameter int unsigned ID = 10,                 // control slave peripheral ID width
  parameter int unsigned BW = 288,                // total bandwidth to TCDM (in bits)
  parameter int unsigned NUM_ELEM_WORD = 4,       // number of elements in a word
  parameter int unsigned ELEM_WIDTH = 8,          // element width (in bits)
  parameter int unsigned N_CORES   = 8,           // number of cores for event inputs
  parameter int unsigned N_CONTEXT = 2,           // number of context for control slave regfile
  parameter int unsigned MISALIGNED_ACCESSES = 0, // enable misaligned accesses on TCDM interface
  // Dependent parameters: do not modify!
  localparam int unsigned WORD_WIDTH = NUM_ELEM_WORD * ELEM_WIDTH, // should correspond to bank width
  localparam int unsigned NUM_WORDS = BW / WORD_WIDTH // TCDM interface width in number of words
)
(
  // global signals
  input  logic clk_i,
  input  logic rst_ni,
  input  logic test_mode_i,
  // events
  output logic [N_CORES-1:0][REGFILE_N_EVT-1:0] evt_o,
  // tcdm master ports
  output logic [NUM_WORDS-1:0]                    tcdm_req,
  input  logic [NUM_WORDS-1:0]                    tcdm_gnt,
  output logic [NUM_WORDS-1:0][ADDR_WIDTH-1:0]    tcdm_add,
  output logic [NUM_WORDS-1:0]                    tcdm_wen,
  output logic [NUM_WORDS-1:0][NUM_ELEM_WORD-1:0] tcdm_be,
  output logic [NUM_WORDS-1:0][WORD_WIDTH-1:0]    tcdm_data,
  input  logic [NUM_WORDS-1:0][WORD_WIDTH-1:0]    tcdm_r_data,
  input  logic [NUM_WORDS-1:0]                    tcdm_r_valid,
  // periph slave port
  input  logic          periph_req,
  output logic          periph_gnt,
  input  logic   [31:0] periph_add,
  input  logic          periph_wen,
  input  logic    [3:0] periph_be,
  input  logic   [31:0] periph_data,
  input  logic [ID-1:0] periph_id,
  output logic   [31:0] periph_r_data,
  output logic          periph_r_valid,
  output logic [ID-1:0] periph_r_id
);

  ////////////////////
  // TCDM interface //
  ////////////////////

  localparam hci_size_ter_t `HCI_SIZE_PARAM(tcdm) = '{
    DW:  BW,
    AW:  ADDR_WIDTH,
    BW:  ELEM_WIDTH,
    UW:  DEFAULT_UW,
    IW:  DEFAULT_IW,
    EW:  DEFAULT_EW,
    EHW: DEFAULT_EHW
  };

  hci_core_intf #(
  `ifndef SYNTHESIS
    .WAIVE_RQ3_ASSERT  ( WAIVE_RQ3_ASSERT  ),
    .WAIVE_RQ4_ASSERT  ( WAIVE_RQ4_ASSERT  ),
    .WAIVE_RSP3_ASSERT ( WAIVE_RSP3_ASSERT ),
    .WAIVE_RSP5_ASSERT ( WAIVE_RSP5_ASSERT ),
  `endif
    .DW  ( BW          ),
    .AW  ( ADDR_WIDTH  ),
    .BW  ( ELEM_WIDTH  ),
    .UW  ( DEFAULT_UW  ),
    .IW  ( DEFAULT_IW  ),
    .EW  ( DEFAULT_EW  ),
    .EHW ( DEFAULT_EHW )
  ) tcdm (
    .clk ( clk_i )
  );

  // HCI bindings
  generate
    for(genvar i = 0; i < NUM_WORDS; i++) begin: tcdm_bin
      // All banks are accessed at the same time, so `req` and `wen` are the same for all banks
      assign tcdm_req[i]  = tcdm.req;
      assign tcdm_wen[i]  = tcdm.wen;
      // The datamover accessess a number of NUM_WORDS adjacent words.
      // Assuming the memory is element-indexed, i.e., every word-element is individually addressable
      // on the address bus: to go from word `n` to word `n+1` we have to skip NUM_ELEM_WORD addresses.
      assign tcdm_add[i]  = tcdm.add + i * NUM_ELEM_WORD;
      assign tcdm_be[i]   = tcdm.be[(i+1)*NUM_ELEM_WORD - 1 : i*NUM_ELEM_WORD];
      assign tcdm_data[i] = tcdm.data[(i+1)*WORD_WIDTH - 1 : i*WORD_WIDTH];
    end 
      assign tcdm.gnt     = &(tcdm_gnt); // only when all words are granted
      assign tcdm.r_data  = { >> {tcdm_r_data}};
      assign tcdm.r_valid = &(tcdm_r_valid); // only when all words are valid
  endgenerate

  /////////////////////
  // Peripheral intf //
  /////////////////////

  hwpe_ctrl_intf_periph #(
    .ID_WIDTH ( ID )
  ) periph (
    .clk ( clk_i )
  );

  assign periph.req     = periph_req;
  assign periph.add     = periph_add;
  assign periph.wen     = periph_wen;
  assign periph.be      = periph_be;
  assign periph.data    = periph_data;
  assign periph.id      = periph_id;
  assign periph_gnt     = periph.gnt;
  assign periph_r_data  = periph.r_data;
  assign periph_r_valid = periph.r_valid;
  assign periph_r_id    = periph.r_id;

  ///////////////
  // Top-level //
  ///////////////

  datamover_top #(
    .ID ( ID ),
    .BW ( BW ),
    .NUM_ELEM_WORD ( NUM_ELEM_WORD ),
    .ELEM_WIDTH ( ELEM_WIDTH ),
    .N_CORES ( N_CORES ),
    .N_CONTEXT ( N_CONTEXT ),
    .MISALIGNED_ACCESSES ( MISALIGNED_ACCESSES ),
    .`HCI_SIZE_PARAM(tcdm) ( `HCI_SIZE_PARAM(tcdm) )
  ) i_datamover_top (
    .clk_i       ( clk_i ),
    .rst_ni      ( rst_ni ),
    .test_mode_i ( test_mode_i ),
    .evt_o       ( evt_o ),
    .tcdm        ( tcdm.initiator ),
    .periph      ( periph )
  );

  ///////////
  // Debug //
  ///////////

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
      assert (BW % WORD_WIDTH == 0)
        else $fatal("BW (%0d) must be a multiple of WORD_WIDTH (%0d)", BW, WORD_WIDTH);
    end
  `endif
  `endif
  `endif

endmodule // datamover_top_wrap