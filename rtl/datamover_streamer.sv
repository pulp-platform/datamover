/*
 * Copyright (C) 2020 ETH Zurich and University of Bologna
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
 */

import hwpe_stream_package::*;
import hci_package::*;
import datamover_package::*;

`include "hci_helpers.svh"

module datamover_streamer #(
  parameter int unsigned TCDM_FIFO_DEPTH = 2,
  parameter int unsigned BW = 32,
  parameter int unsigned MISALIGNED_ACCESSES = 1,
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(tcdm) = '0
) (
  // global signals
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   test_mode_i,
  // local enable & clear
  input  logic                   enable_i,
  input  logic                   clear_i,
  // input data stream + handshake
  hwpe_stream_intf_stream.source data_in,
  // output data stream + handshake
  hwpe_stream_intf_stream.sink   data_out,
  // TCDM ports
  hci_core_intf.initiator        tcdm,
  // control channel
  input  ctrl_streamer_t         ctrl_i,
  output flags_streamer_t        flags_o
);

  localparam int unsigned UW  = `HCI_SIZE_GET_UW(tcdm);
  localparam int unsigned IW  = `HCI_SIZE_GET_IW(tcdm);
  localparam int unsigned EW  = `HCI_SIZE_GET_EW(tcdm);
  localparam int unsigned EHW = `HCI_SIZE_GET_EHW(tcdm);

  flags_fifo_t tcdm_fifo_flags;

  // "Virtual" HCI TCDM interfaces. Interface [0] maps loads (coming from
  // and HCI source) and interface [1] maps stores (coming from an HCI sink).
  hci_core_intf #(
    .DW  ( BW ),
    .BW  ( 32 ),
    .UW  ( UW ),
    .IW  ( IW ),
    .EW  ( EW ),
    .EHW ( EHW)
  ) virt_tcdm [1:0] (
    .clk ( clk_i )
  );

  // "Virtual" TCDM interface, used to embody data after mixing loads and
  // stores, but before the TCDM FIFO (if present).
  hci_core_intf #(
    .DW ( BW ),
    .BW ( 32 ),
    .UW ( UW ),
    .IW ( IW ),
    .EW ( EW ),
    .EHW( EHW)
  ) tcdm_prefifo (
    .clk ( clk_i )
  );
  
  // "Virtual" TCDM interface, used to embody data after the TCDM FIFO
  // (if present) but before the load filter. Notice this is technically
  // an array of interfaces, with one single instance inside. This is
  // useful because HCI muxes expect an array of output interfaces.
  hci_core_intf #(
    .DW  ( BW ),
    .BW  ( 32 ),
    .UW  ( UW                        ),
    .IW  ( IW                        ),
    .EW  ( EW                        ),
    .EHW ( EHW                       )
  ) tcdm_prefilter [0:0] (
    .clk ( clk_i )
  );

  // Standard HCI core source. The DATA_WIDTH parameter is referred to
  // the HWPE-Stream, since the source also performs realignment, it will
  // expose a 32-bit larger HCI TCDM interface.
  hci_core_source #(
    .`HCI_SIZE_PARAM(tcdm) ( `HCI_SIZE_PARAM(tcdm) ),
    .MISALIGNED_ACCESSES(MISALIGNED_ACCESSES)
  ) i_source (
    .clk_i       ( clk_i                         ),
    .rst_ni      ( rst_ni                        ),
    .test_mode_i ( test_mode_i                   ),
    .clear_i     ( clear_i                       ),
    .enable_i    ( 1'b1                          ),
    .tcdm        ( virt_tcdm [0]                 ),
    .stream      ( data_in                       ),
    .ctrl_i      ( ctrl_i.data_in_source_ctrl    ),
    .flags_o     ( flags_o.data_in_source_flags  )
  );

  // Standard HCI core sink. The DATA_WIDTH parameter is referred to
  // the HWPE-Stream, since the sink also performs realignment, it will
  // expose a 32-bit larger HCI TCDM interface.
  hci_core_sink #(
    .`HCI_SIZE_PARAM(tcdm) ( `HCI_SIZE_PARAM(tcdm) ),
    .MISALIGNED_ACCESSES(MISALIGNED_ACCESSES)
  ) i_sink (
    .clk_i       ( clk_i                       ),
    .rst_ni      ( rst_ni                      ),
    .test_mode_i ( test_mode_i                 ),
    .clear_i     ( clear_i                     ),
    .enable_i    ( 1'b1                        ),
    .tcdm        ( virt_tcdm [1]               ),
    .stream      ( data_out                    ),
    .ctrl_i      ( ctrl_i.data_out_sink_ctrl   ),
    .flags_o     ( flags_o.data_out_sink_flags )
  );

  generate
    if(TCDM_FIFO_DEPTH > 0) begin : use_fifo_gen

      // TCDM muxing is not possible in general before a FIFO, because
      // there is no standard way to couple a response with the channel
      // that requested it. Here we bypass the issue by using a mixer
      // that is specifically designed for a LOAD-exclusive channel and
      // a STORE-exclusive channel. It will couple any valid response to
      // the LOAD channel exclusively.
      hci_core_load_store_mixer #(
        .DW          ( BW )
      ) i_ld_st_mux_static (
        .clk_i    ( clk_i        ),
        .rst_ni   ( rst_ni       ),
        .clear_i  ( clear_i      ),
        .in_load  ( virt_tcdm[0] ),
        .in_store ( virt_tcdm[1] ),
        .out      ( tcdm_prefifo )
      );

      // The HCI core FIFO the request path from the response path, easing
      // timing closure when integrating the accelerator in a cluster.
      hci_core_fifo #(
        .FIFO_DEPTH ( TCDM_FIFO_DEPTH )
      ) i_tcdm_fifo (
        .clk_i         ( clk_i             ),
        .rst_ni        ( rst_ni            ),
        .clear_i       ( clear_i           ),
        .flags_o       ( tcdm_fifo_flags   ),
        .tcdm_target   ( tcdm_prefifo      ),
        .tcdm_initiator( tcdm_prefilter[0] )
      );
    end
    else begin : dont_use_fifo_gen

      // If not using a FIFO, it is possible to use a standard mux instead
      // of a mixer.
      hci_core_mux_dynamic #(
        .NB_IN_CHAN  ( 2  ),
        .NB_OUT_CHAN ( 1  ),
        .`HCI_SIZE_PARAM(in)(( `HCI_SIZE_PARAM(tcdm) ))
      ) i_ld_st_mux_static (
        .clk_i   ( clk_i          ),
        .rst_ni  ( rst_ni         ),
        .clear_i ( clear_i        ),
        .in      ( virt_tcdm[1:0] ),
        .out     ( tcdm_prefilter )
      );
      assign tcdm_fifo_flags.empty = 1'b1;

    end
  endgenerate

  // The HCI core filter is meant to filter out r_valid strobes that the
  // cluster may generate even when the TCDM access is a write. These 
  // pollute HCI TCDM FIFOs and mixers, and it is better to remove them
  // altogether.
  hci_core_r_valid_filter i_tcdm_filter (
    .clk_i         ( clk_i                ),
    .rst_ni        ( rst_ni               ),
    .clear_i       ( clear_i              ),
    .enable_i      ( 1'b1                 ),
    .tcdm_target   ( tcdm_prefilter[0].target ),
    .tcdm_initiator( tcdm                 )
  );
  assign flags_o.tcdm_fifo_empty = tcdm_fifo_flags.empty;

endmodule // datamover_streamer
