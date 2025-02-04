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
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(tcdm) = '0
) (
  // global signals
  input  logic                    clk_i,
  input  logic                    rst_ni,
  input  logic                    test_mode_i,
  // events
  output logic [N_CORES-1:0][1:0] evt_o,
  // tcdm master ports
  hci_core_intf.initiator         tcdm,
  // periph slave port
  hwpe_ctrl_intf_periph.slave     periph
);

  // We "sacrifice" 1 word of memory interface bandwidth in order to support
  // realignment at a byte boundary if the access are misaligned.
  localparam BW_ALIGNED = MISALIGNED_ACCESSES === 0 ? BW : BW-32;

  // State for the FSM declared directly in datamover_top.
  typedef enum { DM_IDLE, DM_STARTING, DM_WORKING, DM_FINISHED } dm_state;
  dm_state state_d, state_q;

  // Software-generated clear signal.
  logic clear;

  // These are the bit fields used to control the streamer.
  ctrl_streamer_t  streamer_ctrl, streamer_ctrl_cfg;
  flags_streamer_t streamer_flags;

  // These are the bit fields used to propagate flags from/to the peripheral
  // interconnect slave interface.
  ctrl_slave_t slave_ctrl;
  flags_slave_t slave_flags;
  ctrl_regfile_t reg_file;

  // Data in and data out internal HWPE-Streams. Notice that the data width
  // is set to 256 bits by default, 32 bits less than the default external
  // bandwidth. The additional 32 bits of memory bandwidth are used to 
  // support access to non-word-aligned data packets.
  hwpe_stream_intf_stream #(
    .DATA_WIDTH(BW_ALIGNED)
  ) data_in  (
    .clk(clk_i)
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH(BW_ALIGNED)
  ) data_out (
    .clk(clk_i)
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

  // The "engine", i.e., the datapath of the HWPE, is as simple as it gets:
  // a FIFO copying the data in stream into the data out one!
  datamover_engine #(
    .FIFO_DEPTH ( 4          ),
    .BW_ALIGNED ( BW_ALIGNED )
  ) i_engine (
    .clk_i      ( clk_i          ),
    .rst_ni     ( rst_ni         ),
    .test_mode_i( test_mode_i    ),
    .enable_i   ( 1'b1           ),
    .clear_i    ( clear          ),
    .data_in    ( data_in        ),
    .data_out   ( data_out       )
  );
  
  // The slave module exposes a peripheral interconnect HWPE-Periph plug;
  // in the default configuration, it provides 2 contexts with 13 registers
  // each, which are exposed into `reg_file.hwpe_params`
  hwpe_ctrl_slave #(
    .N_CORES        ( 8  ),
    .N_CONTEXT      ( 2  ),
    .N_IO_REGS      ( 13 ),
    .N_GENERIC_REGS ( 8  ),
    .ID_WIDTH       ( ID )
  ) i_slave (
    .clk_i   ( clk_i       ),
    .rst_ni  ( rst_ni      ),
    .clear_o ( clear       ),
    .cfg     ( periph      ),
    .ctrl_i  ( slave_ctrl  ),
    .flags_o ( slave_flags ),
    .reg_file( reg_file    )
  );

  // Datamover FSM: sequential process.
  always_ff @(posedge clk_i or negedge rst_ni)
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
      if(slave_flags.start)
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
    slave_ctrl = '0;
    streamer_ctrl = streamer_ctrl_cfg;
    if(state_q == DM_STARTING) begin
      streamer_ctrl.data_in_source_ctrl.req_start = 1'b1;
      streamer_ctrl.data_out_sink_ctrl.req_start = 1'b1;
    end
    else if (state_q == DM_FINISHED) begin
      slave_ctrl.done = 1'b1;
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
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.base_addr = reg_file.hwpe_params[0];
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.base_addr  = reg_file.hwpe_params[1];
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.tot_len   = reg_file.hwpe_params[2];
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.tot_len    = reg_file.hwpe_params[2];
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d0_len    = reg_file.hwpe_params[3];
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d0_stride = reg_file.hwpe_params[4];
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d1_len    = reg_file.hwpe_params[5];
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d1_stride = reg_file.hwpe_params[6];
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d2_stride = reg_file.hwpe_params[7];
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d0_len     = reg_file.hwpe_params[8];
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d0_stride  = reg_file.hwpe_params[9];
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d1_len     = reg_file.hwpe_params[10];
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d1_stride  = reg_file.hwpe_params[11];
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d2_stride  = reg_file.hwpe_params[12];
  end

  // Bind the output event, which is propagated to the event unit and used
  // to implement HWPE datamover barriers.
  assign evt_o = slave_flags.evt[7:0];


  localparam int unsigned DEBUG_DW  = `HCI_SIZE_GET_DW(tcdm);
  localparam int unsigned DEBUG_BW  = `HCI_SIZE_GET_BW(tcdm);
  localparam int unsigned DEBUG_AW  = `HCI_SIZE_GET_AW(tcdm);
  localparam int unsigned DEBUG_UW  = `HCI_SIZE_GET_UW(tcdm);
  localparam int unsigned DEBUG_IW  = `HCI_SIZE_GET_IW(tcdm);
  localparam int unsigned DEBUG_EW  = `HCI_SIZE_GET_EW(tcdm);
  localparam int unsigned DEBUG_EHW = `HCI_SIZE_GET_EHW(tcdm);

endmodule // datamover_top
