/*
 * Copyright (C) 2025-2026 ETH Zurich and University of Bologna
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
 *          Arpan Suravi Prasad <prasadar@iis.ee.ethz.ch>
 */

// A wrapper for datamover_top that unrolls the interfaces to HCI and
// the peripheral slave interconnect, making it possible to manually
// connect the desired ports

`include "hci_helpers.svh"

module datamover_top_wrap
  import hwpe_ctrl_package::*;
  import hci_package::*;
  import datamover_pkg::*;
#(
  parameter int unsigned AddrWidth          = datamover_pkg::AddrWidth,          // width of address bus
  parameter int unsigned IdWidth            = datamover_pkg::IdWidth,            // control slave peripheral ID width
  parameter int unsigned Bandwidth          = datamover_pkg::Bandwidth,          // total bandwidth of HWPE to TCDM (in bits)
  parameter int unsigned ElemsPerWord       = datamover_pkg::ElemsPerWord,       // number of elements in a memory bank word
  parameter int unsigned ElemWidth          = datamover_pkg::ElemWidth,          // element width (in bits)
  parameter int unsigned NumCores           = datamover_pkg::NumCores,           // number of cores for event inputs
  parameter int unsigned NumContext         = datamover_pkg::NumContext,         // number of context for control slave regfile
  parameter int unsigned MisalignedAccesses = datamover_pkg::MisalignedAccesses, // enable misaligned accesses on TCDM interface
  parameter bit          EnableIm2col       = datamover_pkg::EnableIm2col,       // instantiate the im2col unit
  parameter bit          EnableBuffer       = datamover_pkg::EnableBuffer,       // instantiate the element buffer
  parameter int unsigned Im2colKernel       = datamover_pkg::Im2colKernel,       // largest im2col unit kernel, 3 or 5
  parameter int unsigned Im2colMinLog2W     = datamover_pkg::Im2colMinLog2W,     // log2 of the smallest im2col unit row width
  parameter int unsigned FifoDepth          = datamover_pkg::FifoDepth,          // depth of the engine stream FIFOs
  // Dependent parameters: do not modify!
  localparam int unsigned WordWidth = ElemsPerWord * ElemWidth, // should correspond to bank width
  localparam int unsigned NumWords  = Bandwidth / WordWidth     // TCDM interface width in number of words
)
(
  // global signals
  input  logic clk_i,
  input  logic rst_ni,
  input  logic test_mode_i,
  // events
  output logic [NumCores-1:0][REGFILE_N_EVT-1:0] evt_o,
  // busy status
  output logic                                    busy_o,
  // tcdm master ports
  output logic [NumWords-1:0]                    tcdm_req,
  input  logic [NumWords-1:0]                    tcdm_gnt,
  output logic [NumWords-1:0][AddrWidth-1:0]    tcdm_add,
  output logic [NumWords-1:0]                    tcdm_wen,
  output logic [NumWords-1:0][WordWidth/ByteWidth-1:0] tcdm_be,
  output logic [NumWords-1:0][WordWidth-1:0]    tcdm_data,
  input  logic [NumWords-1:0][WordWidth-1:0]    tcdm_r_data,
  input  logic [NumWords-1:0]                    tcdm_r_valid,
  // periph slave port
  input  logic          periph_req,
  output logic          periph_gnt,
  input  logic   [31:0] periph_add,
  input  logic          periph_wen,
  input  logic    [3:0] periph_be,
  input  logic   [31:0] periph_data,
  input  logic [IdWidth-1:0] periph_id,
  output logic   [31:0] periph_r_data,
  output logic          periph_r_valid,
  output logic [IdWidth-1:0] periph_r_id
);

  ////////////////////
  // TCDM interface //
  ////////////////////

  localparam hci_size_parameter_t `HCI_SIZE_PARAM(tcdm) = '{
    DW:  Bandwidth,
    AW:  AddrWidth,
    BW:  ElemWidth,
    UW:  DEFAULT_UW,
    IW:  DEFAULT_IW,
    EW:  DEFAULT_EW,
    EHW: DEFAULT_EHW
  };

  hci_core_intf #(
    .DW  ( Bandwidth   ),
    .AW  ( AddrWidth  ),
    .BW  ( ElemWidth  ),
    .UW  ( DEFAULT_UW  ),
    .IW  ( DEFAULT_IW  ),
    .EW  ( DEFAULT_EW  ),
    .EHW ( DEFAULT_EHW )
  ) tcdm (
    .clk ( clk_i )
  );

  // HCI bindings
  generate
    for(genvar i = 0; i < NumWords; i++) begin: tcdm_bin
      // All banks are accessed at the same time, so `req` and `wen` are the same for all banks
      assign tcdm_req[i]  = tcdm.req;
      assign tcdm_wen[i]  = tcdm.wen;
      // The bus is byte-addressed, so word n+1 starts one word of bytes after word n.
      assign tcdm_add[i]  = tcdm.add + i * (WordWidth / ByteWidth);
      for (genvar e = 0; e < ElemsPerWord; e++) begin : gen_byte_strobe
        assign tcdm_be[i][e*(ElemWidth/ByteWidth) +: ElemWidth/ByteWidth] = {(ElemWidth/ByteWidth){tcdm.be[i*ElemsPerWord + e]}};
      end
      assign tcdm_data[i] = tcdm.data[(i+1)*WordWidth - 1 : i*WordWidth];
    end
      assign tcdm.gnt     = &(tcdm_gnt); // only when all words are granted
      assign tcdm.r_data  = { >> {tcdm_r_data}};
      assign tcdm.r_valid = &(tcdm_r_valid); // only when all words are valid
      // The flat ports carry no response id, user, opcode, or ECC fields.
      assign tcdm.r_user   = '0;
      assign tcdm.r_id     = '0;
      assign tcdm.r_opc    = 1'b0;
      assign tcdm.r_ecc    = '0;
      assign tcdm.egnt     = '0;
      assign tcdm.r_evalid = '0;
  endgenerate

  /////////////////////
  // Peripheral intf //
  /////////////////////

  hwpe_ctrl_intf_periph #(
    .ID_WIDTH ( IdWidth )
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
    .IdWidth            ( IdWidth            ),
    .Bandwidth          ( Bandwidth          ),
    .ElemsPerWord       ( ElemsPerWord       ),
    .ElemWidth          ( ElemWidth          ),
    .NumCores           ( NumCores           ),
    .NumContext         ( NumContext         ),
    .MisalignedAccesses ( MisalignedAccesses ),
    .EnableIm2col       ( EnableIm2col       ),
    .EnableBuffer       ( EnableBuffer       ),
    .Im2colKernel       ( Im2colKernel       ),
    .Im2colMinLog2W     ( Im2colMinLog2W     ),
    .FifoDepth          ( FifoDepth          ),
    .`HCI_SIZE_PARAM(tcdm) ( `HCI_SIZE_PARAM(tcdm) )
  ) i_datamover_top (
    .clk_i       ( clk_i ),
    .rst_ni      ( rst_ni ),
    .test_mode_i ( test_mode_i ),
    .evt_o       ( evt_o ),
    .busy_o      ( busy_o ),
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
      assert (Bandwidth % WordWidth == 0)
        else $fatal("Bandwidth (%0d) must be a multiple of WordWidth (%0d)", Bandwidth, WordWidth);
    end
  `endif
  `endif
  `endif

endmodule // datamover_top_wrap
