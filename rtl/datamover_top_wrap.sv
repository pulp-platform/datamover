/*
 * datamover_top_wrap.sv
 * Arpan Suravi Prasad <prasadar@iis.ee.ethz.ch>
 *
 * Copyright (C) 2017-2023 ETH Zurich, University of Bologna
 * All rights reserved.
 */

`include "hci_helpers.svh"

module datamover_top_wrap
  import datamover_package::*;
  import hwpe_ctrl_package::*;
  import hci_package::*;
#(
`ifndef SYNTHESIS
  parameter bit WAIVE_RQ3_ASSERT  = 1'b0,
  parameter bit WAIVE_RQ4_ASSERT  = 1'b0,
  parameter bit WAIVE_RSP3_ASSERT = 1'b0,
  parameter bit WAIVE_RSP5_ASSERT = 1'b0,
`endif
  parameter N_CORES = 2,
  parameter MP  = 4,
  parameter ID  = 10
)
(
  // global signals
  input  logic                                  clk_i,
  input  logic                                  rst_ni,
  input  logic                                  test_mode_i,
  // events
  output logic [N_CORES-1:0][REGFILE_N_EVT-1:0] evt_o,
  // tcdm master ports
  output logic [MP-1:0]                         tcdm_req,
  input  logic [MP-1:0]                         tcdm_gnt,
  output logic [MP-1:0][31:0]                   tcdm_add,
  output logic [MP-1:0]                         tcdm_wen,
  output logic [MP-1:0][3:0]                    tcdm_be,
  output logic [MP-1:0][31:0]                   tcdm_data,
  input  logic [MP-1:0][31:0]                   tcdm_r_data,
  input  logic [MP-1:0]                         tcdm_r_valid,
  // periph slave port
  input  logic                                  periph_req,
  output logic                                  periph_gnt,
  input  logic         [31:0]                   periph_add,
  input  logic                                  periph_wen,
  input  logic         [3:0]                    periph_be,
  input  logic         [31:0]                   periph_data,
  input  logic       [ID-1:0]                   periph_id,
  output logic         [31:0]                   periph_r_data,
  output logic                                  periph_r_valid,
  output logic       [ID-1:0]                   periph_r_id
);

  localparam BW = 32*MP;
  localparam hci_size_parameter_t `HCI_SIZE_PARAM(tcdm) = '{
    DW:  BW,
    AW:  DEFAULT_AW,
    BW:  32,
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
    .AW  ( DEFAULT_AW  ),
    .BW  ( DEFAULT_BW  ),
    .UW  ( DEFAULT_UW  ),
    .IW  ( DEFAULT_IW  ),
    .EW  ( DEFAULT_EW  ),
    .EHW ( DEFAULT_EHW )
  ) tcdm (
    .clk ( clk_i )
  );

  hwpe_ctrl_intf_periph #(
    .ID_WIDTH ( ID )
  ) periph (
    .clk ( clk_i )
  );

  // bindings
  generate
    for(genvar ii=0; ii<MP; ii++) begin: tcdm_binding
      assign tcdm_req  [ii] = tcdm.req;
      assign tcdm_add  [ii] = tcdm.add + ii*4;
      assign tcdm_wen  [ii] = tcdm.wen;
      assign tcdm_be   [ii] = tcdm.be[3:0];
      assign tcdm_data [ii] = tcdm.data[(ii+1)*32-1:ii*32];
    end 
      assign tcdm.gnt      = &(tcdm_gnt);
      assign tcdm.r_data   = { >> {tcdm_r_data}};
      assign tcdm.r_valid  = &(tcdm_r_valid);
  endgenerate

  always_comb
  begin
    periph.req  = periph_req;
    periph.add  = periph_add;
    periph.wen  = periph_wen;
    periph.be   = periph_be;
    periph.data = periph_data;
    periph.id   = periph_id;
    periph_gnt     = periph.gnt;
    periph_r_data  = periph.r_data;
    periph_r_valid = periph.r_valid;
    periph_r_id    = periph.r_id;
  end

  datamover_top #(
    .ID               ( ID       ),
    .BW               ( 32*MP    ),
    .N_CORES          ( N_CORES  ),
    .`HCI_SIZE_PARAM(tcdm) ( `HCI_SIZE_PARAM(tcdm) )
  ) i_datamover_top (
    .clk_i       ( clk_i       ),
    .rst_ni      ( rst_ni      ),
    .test_mode_i ( test_mode_i ),
    .evt_o       ( evt_o       ),
    .tcdm        ( tcdm.initiator        ),
    .periph      ( periph      )
  );


  localparam int unsigned DEBUG_DW  = `HCI_SIZE_GET_DW(tcdm);
  localparam int unsigned DEBUG_BW  = `HCI_SIZE_GET_BW(tcdm);
  localparam int unsigned DEBUG_AW  = `HCI_SIZE_GET_AW(tcdm);
  localparam int unsigned DEBUG_UW  = `HCI_SIZE_GET_UW(tcdm);
  localparam int unsigned DEBUG_IW  = `HCI_SIZE_GET_IW(tcdm);
  localparam int unsigned DEBUG_EW  = `HCI_SIZE_GET_EW(tcdm);
  localparam int unsigned DEBUG_EHW = `HCI_SIZE_GET_EHW(tcdm);

endmodule // datamover_top_wrap