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
`include "hci_helpers.svh"
import hwpe_ctrl_package::*;
import hci_package::*;
import datamover_package::*;

module datamover_top #(
  parameter int unsigned ID        = 10,
  parameter int unsigned BW        = 288,
  parameter int unsigned N_CORES   = 8,
  parameter int unsigned N_CONTEXT = 2,
  parameter int unsigned MISALIGNED_ACCESSES = 0,
  parameter  logic [6:0] Opcode                = 7'b1011011,
  parameter  logic [2:0] InOutPtrFunct3        = 3'b111,
  parameter  logic [2:0] LenCfgFunct3          = 3'b110,
  parameter  logic [2:0] InPatternFunct3       = 3'b100,
  parameter  logic [2:0] OutPatternFunct3      = 3'b000,
  // XIF parameters
  parameter int unsigned XifNumHarts           = 1,
  parameter int unsigned XifIdWidth            = 1,
  parameter int unsigned XifIssueRegisterSplit = 0,
  // XIF types
  parameter type         x_issue_req_t         = logic,
  parameter type         x_issue_resp_t        = logic,
  parameter type         x_register_t          = logic,
  parameter type         x_commit_t            = logic,
  parameter type         x_result_t            = logic,
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(tcdm) = '0
) (
  // global signals
  input  logic                    clk_i,
  input  logic                    rst_ni,
  input  logic                    test_mode_i,
  // events
  output logic [N_CORES-1:0][1:0] evt_o,

  input   x_issue_req_t           x_issue_req_i,
  output  x_issue_resp_t          x_issue_resp_o,
  input   logic                   x_issue_valid_i,
  output  logic                   x_issue_ready_o,
  input   x_register_t            x_register_i,
  input   logic                   x_register_valid_i,
  output  logic                   x_register_ready_o,
  input   x_commit_t              x_commit_i,
  input   logic                   x_commit_valid_i,
  output  x_result_t              x_result_o,
  output  logic                   x_result_valid_o,
  input   logic                   x_result_ready_i,
  // tcdm master ports
  hci_core_intf.initiator         tcdm
);

  // We "sacrifice" 1 word of memory interface bandwidth in order to support
  // realignment at a byte boundary if the access are misaligned.
  localparam BW_ALIGNED = MISALIGNED_ACCESSES === 0 ? BW : BW-32;

  // State for the FSM declared directly in datamover_top.
  typedef enum { DM_IDLE, DM_STARTING, DM_WORKING, DM_FINISHED } dm_state;
  dm_state state_d, state_q;

  // Software-generated clear signal.
  logic clear;
  assign clear = '0;

  // These are the bit fields used to control the streamer.
  ctrl_streamer_t  streamer_ctrl, streamer_ctrl_cfg;
  flags_streamer_t streamer_flags;

  // Bit field to control the engine.
  ctrl_engine_t engine_ctrl;

  datamover_config_t datamover_config;
  logic              datamover_config_valid;

  logic busy;
  assign busy = state_q != DM_IDLE;

  logic clk_acc;

  tc_clk_gating i_acc_clock_gating (
    .clk_i     ( clk_i   ),
    .en_i      ( busy    ),
    .test_en_i ( '0      ),
    .clk_o     ( clk_acc )
  );

  // Data in and data out internal HWPE-Streams. Notice that the data width
  // is set to 256 bits by default, 32 bits less than the default external
  // bandwidth. The additional 32 bits of memory bandwidth are used to
  // support access to non-word-aligned data packets.
  hwpe_stream_intf_stream #(
    .DATA_WIDTH(BW_ALIGNED)
  ) data_in  (
    .clk(clk_acc)
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH(BW_ALIGNED)
  ) data_out (
    .clk(clk_acc)
  );

  // The streamer exposes on the memory side a single TCDM 288-bit interface
  // meant to be directly plugged into an Heterogeneous Cluster Interconnect.
  // On the accelerator side, it exposes an outgoing data in stream and
  // an incoming data out HWPE-Streams, each 256-bit wide.
  datamover_streamer #(
    .BW              ( BW ),
    .`HCI_SIZE_PARAM(tcdm) ( `HCI_SIZE_PARAM(tcdm)     ),
    .MISALIGNED_ACCESSES(MISALIGNED_ACCESSES),
    .TCDM_FIFO_DEPTH ( 0  )
  ) i_streamer (
    .clk_i      ( clk_acc        ),
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

  // The "engine", i.e., the datapath of the HWPE, is as simple as it gets:
  // a FIFO copying the data in stream into the data out one!
  datamover_engine #(
    .FIFO_DEPTH ( 4          ),
    .BW_ALIGNED ( BW_ALIGNED )
  ) i_engine (
    .clk_i      ( clk_acc        ),
    .rst_ni     ( rst_ni         ),
    .test_mode_i( test_mode_i    ),
    .enable_i   ( 1'b1           ),
    .clear_i    ( clear          ),
    .ctrl_i     ( engine_ctrl    ),
    .data_in    ( data_in        ),
    .data_out   ( data_out       )
  );

  datamover_inst_decoder #(
    .InstFifoDepth         ( 4                     ),
    .Opcode                ( Opcode                ),
    .InOutPtrFunct3        ( InOutPtrFunct3        ),
    .LenCfgFunct3          ( LenCfgFunct3          ),
    .InPatternFunct3       ( InPatternFunct3       ),
    .OutPatternFunct3      ( OutPatternFunct3      ),
    .XifIdWidth            ( XifIdWidth            ),
    .XifNumHarts           ( XifNumHarts           ),
    .XifIssueRegisterSplit ( XifIssueRegisterSplit ),
    .x_issue_req_t         ( x_issue_req_t         ),
    .x_issue_resp_t        ( x_issue_resp_t        ),
    .x_register_t          ( x_register_t          ),
    .x_commit_t            ( x_commit_t            ),
    .x_result_t            ( x_result_t            )
  ) i_inst_decoder (
    .clk_i              ( clk_i                  ),
    .rst_ni             ( rst_ni                 ),
    .clear_i            ( '0                     ),
    .busy_i             ( busy                   ),
    .config_valid_o     ( datamover_config_valid ),
    .config_o           ( datamover_config       ),
    .x_issue_req_i      ( x_issue_req_i          ),
    .x_issue_resp_o     ( x_issue_resp_o         ),
    .x_issue_valid_i    ( x_issue_valid_i        ),
    .x_issue_ready_o    ( x_issue_ready_o        ),
    .x_register_i       ( x_register_i           ),
    .x_register_valid_i ( x_register_valid_i     ),
    .x_register_ready_o ( x_register_ready_o     ),
    .x_commit_i         ( x_commit_i             ),
    .x_commit_valid_i   ( x_commit_valid_i       ),
    .x_result_o         ( x_result_o             ),
    .x_result_valid_o   ( x_result_valid_o       ),
    .x_result_ready_i   ( x_result_ready_i       )
  );

  // Datamover FSM: sequential process.
  always_ff @(posedge clk_acc or negedge rst_ni)
  begin : fsm_seq
    if(~rst_ni)
      state_q <= DM_IDLE;
    else if(clear)
      state_q <= DM_IDLE;
    else
      state_q <= state_d;
  end

  // Datamover FSM: combinational next-state calculation process.
  always_comb
  begin : fsm_ns_comb
    state_d = state_q;
    if(state_q == DM_IDLE) begin
      if(datamover_config_valid)
        state_d = DM_STARTING;
    end
    else if(state_q == DM_STARTING) begin
      state_d = DM_WORKING;
    end
    else if(state_q == DM_WORKING) begin
      if ((streamer_flags.data_out_sink_flags.done | streamer_flags.data_out_sink_flags.ready_start) & (streamer_flags.data_in_source_flags.done | streamer_flags.data_in_source_flags.ready_start) & streamer_flags.tcdm_fifo_empty)
        state_d = DM_FINISHED;
    end
    else begin
      state_d = DM_IDLE;
    end
  end

  // Datamover FSM: combinational output calculation process.
  always_comb
  begin : fsm_out_comb
    streamer_ctrl = streamer_ctrl_cfg;
    if(state_q == DM_STARTING) begin
      streamer_ctrl.data_in_source_ctrl.req_start = 1'b1;
      streamer_ctrl.data_out_sink_ctrl.req_start = 1'b1;
    end
  end

  // Here we bind the register file parameters to the streamer configuration.
  // `streamer_ctrl_cfg` contains the "base" configuration, with null `req_start`.
  // The FSM copies this base configuration into `streamer_ctrl` and sets
  // the `req_start` signals when in state DM_STARTING.
  always_comb
  begin
    streamer_ctrl_cfg = '0;
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.dim_enable_1h = '1;
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.dim_enable_1h  = '1;
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.base_addr     = datamover_config.in_ptr;
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.base_addr      = datamover_config.out_ptr;
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.tot_len       = datamover_config.tot_len;
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.tot_len        = datamover_config.tot_len;
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d0_len        = datamover_config.in_d0_len;
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d0_stride     = datamover_config.in_d0_stride;
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d1_len        = datamover_config.in_d1_len;
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d1_stride     = datamover_config.in_d1_stride;
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d2_stride     = datamover_config.in_d2_stride;
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d0_len         = datamover_config.out_d0_len;
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d0_stride      = datamover_config.out_d0_stride;
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d1_len         = datamover_config.out_d1_len;
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d1_stride      = datamover_config.out_d1_stride;
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d2_stride      = datamover_config.out_d2_stride;
  end

  // Binding of engine configuration
  always_comb
  begin
    engine_ctrl = '0;
    engine_ctrl.transp_mode = datamover_config.transp_mode == 3'b000 ? TRANSP_NONE :
                              datamover_config.transp_mode == 3'b001 ? TRANSP_8B :
                              datamover_config.transp_mode == 3'b010 ? TRANSP_16B : TRANSP_32B;
    engine_ctrl.transp_stride = datamover_config.transp_mode == 3'b000 ? 1 :
                                datamover_config.transp_mode == 3'b001 ? 1 :
                                datamover_config.transp_mode == 3'b010 ? 2 : 4;
    if(datamover_config.leftover == '0) begin // no leftover
      engine_ctrl.transp_len = BW_ALIGNED/8;
    end
    else begin // in case of leftover, use the reg content as length
      engine_ctrl.transp_len = datamover_config.leftover;
    end
  end

  // Bind the output event, which is propagated to the event unit and used
  // to implement HWPE datamover barriers.
  assign evt_o = {15'b0, state_q == DM_FINISHED};


  localparam int unsigned DEBUG_DW  = `HCI_SIZE_GET_DW(tcdm);
  localparam int unsigned DEBUG_BW  = `HCI_SIZE_GET_BW(tcdm);
  localparam int unsigned DEBUG_AW  = `HCI_SIZE_GET_AW(tcdm);
  localparam int unsigned DEBUG_UW  = `HCI_SIZE_GET_UW(tcdm);
  localparam int unsigned DEBUG_IW  = `HCI_SIZE_GET_IW(tcdm);
  localparam int unsigned DEBUG_EW  = `HCI_SIZE_GET_EW(tcdm);
  localparam int unsigned DEBUG_EHW = `HCI_SIZE_GET_EHW(tcdm);

endmodule // datamover_top
