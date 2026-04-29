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
 */

`include "hci_helpers.svh"

module datamover_top
  import hwpe_ctrl_package::*;
  import hci_package::*;
  import datamover_package::*;
#(
  parameter int unsigned ID = 4,                  // control slave peripheral ID width
  parameter int unsigned BANDWIDTH = 512,         // total bandwidth of HWPE to TCDM (in bits)
  parameter int unsigned NUM_ELEM_WORD = 8,       // number of elements in a memory bank word
  parameter int unsigned ELEM_WIDTH = 8,          // element width (in bits)
  parameter int unsigned N_CORES   = 2,           // number of cores for event inputs
  parameter int unsigned N_CONTEXT = 2,           // number of context for control slave regfile
  parameter int unsigned MISALIGNED_ACCESSES = 0, // enable misaligned accesses on TCDM interface
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(tcdm) = '0,
  // Dependent parameters: do not modify!
  localparam int unsigned WORD_WIDTH = NUM_ELEM_WORD * ELEM_WIDTH, // should correspond to bank width
  localparam int unsigned NUM_WORDS = BANDWIDTH / WORD_WIDTH, // TCDM interface width in number of words
  localparam int unsigned N_IO_REGS = 15          // number of configuration registers exposed by the control slave, adapt here if number of configuration registers changes
) (
  // global signals
  input  logic                    clk_i,
  input  logic                    rst_ni,
  input  logic                    test_mode_i,
  // events
  output logic [N_CORES-1:0][REGFILE_N_EVT-1:0] evt_o,
  // tcdm master ports
  hci_core_intf.initiator         tcdm,
  // periph slave port
  hwpe_ctrl_intf_periph.slave     periph
);

  // We "sacrifice" 1 word of memory interface bandwidth in order to support
  // realignment at a word boundary if the access are misaligned.
  localparam BANDWIDTH_ALIGNED = MISALIGNED_ACCESSES == 0 ? BANDWIDTH : BANDWIDTH-WORD_WIDTH;

  // State for the FSM declared directly in datamover_top.
  typedef enum { DM_IDLE, DM_STARTING, DM_WORKING, DM_FINISHED } dm_state;
  dm_state state_d, state_q;

  // Software-generated clear signal.
  logic clear;

  // These are the bit fields used to control the streamer.
  ctrl_streamer_t  streamer_ctrl, streamer_ctrl_cfg;
  flags_streamer_t streamer_flags;

  // Bit field to control the engine.
  ctrl_engine_t engine_ctrl;

  // These are the bit fields used to propagate flags from/to the peripheral
  // interconnect slave interface.
  ctrl_slave_t slave_ctrl;
  flags_slave_t slave_flags;
  ctrl_regfile_t reg_file;

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

  // The slave module exposes a peripheral interconnect HWPE-Periph plug
  hwpe_ctrl_slave #(
    .REGFILE_SCM    ( 0  ),
    .N_CORES        ( N_CORES   ),
    .N_CONTEXT      ( N_CONTEXT ),
    .N_IO_REGS      ( N_IO_REGS ),
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
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.dim_enable_1h = reg_file.hwpe_params[DATAMOVER_REG_CTRL_ENGINE >> 2][11:8]; // Enabled dimensions (d0 is always enabled)
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.dim_enable_1h  = reg_file.hwpe_params[DATAMOVER_REG_CTRL_ENGINE >> 2][15:12]; // Enabled dimensions (d0 is always enabled)
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.base_addr = reg_file.hwpe_params[DATAMOVER_REG_IN_PTR >> 2];
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.base_addr  = reg_file.hwpe_params[DATAMOVER_REG_OUT_PTR >> 2];
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.tot_len   = reg_file.hwpe_params[DATAMOVER_REG_TOT_LEN >> 2][31:0];
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.tot_len    = reg_file.hwpe_params[DATAMOVER_REG_TOT_LEN >> 2][31:0];
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d0_len    = reg_file.hwpe_params[DATAMOVER_REG_IN_D0 >> 2][15:0];
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d0_stride = reg_file.hwpe_params[DATAMOVER_REG_IN_D0 >> 2][31:16];
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d1_len    = reg_file.hwpe_params[DATAMOVER_REG_IN_D1 >> 2][15:0];
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d1_stride = reg_file.hwpe_params[DATAMOVER_REG_IN_D1 >> 2][31:16];
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d2_len    = reg_file.hwpe_params[DATAMOVER_REG_IN_D2 >> 2][15:0];
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d2_stride = reg_file.hwpe_params[DATAMOVER_REG_IN_D2 >> 2][31:16];
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d3_len    = reg_file.hwpe_params[DATAMOVER_REG_IN_D3 >> 2][15:0];
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d3_stride = reg_file.hwpe_params[DATAMOVER_REG_IN_D3 >> 2][31:16];
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d4_stride = reg_file.hwpe_params[DATAMOVER_REG_IN_OUT_D4_STRIDE >> 2][15:0];
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d0_len     = reg_file.hwpe_params[DATAMOVER_REG_OUT_D0 >> 2][15:0];
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d0_stride  = reg_file.hwpe_params[DATAMOVER_REG_OUT_D0 >> 2][31:16];
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d1_len     = reg_file.hwpe_params[DATAMOVER_REG_OUT_D1 >> 2][15:0];
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d1_stride  = reg_file.hwpe_params[DATAMOVER_REG_OUT_D1 >> 2][31:16];
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d2_len     = reg_file.hwpe_params[DATAMOVER_REG_OUT_D2 >> 2][15:0];
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d2_stride  = reg_file.hwpe_params[DATAMOVER_REG_OUT_D2 >> 2][31:16];
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d3_len     = reg_file.hwpe_params[DATAMOVER_REG_OUT_D3 >> 2][15:0];
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d3_stride  = reg_file.hwpe_params[DATAMOVER_REG_OUT_D3 >> 2][31:16];
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d4_stride  = reg_file.hwpe_params[DATAMOVER_REG_IN_OUT_D4_STRIDE >> 2][31:16];
  end

  // Binding of engine configuration
  always_comb
  begin
    engine_ctrl = '0;
    engine_ctrl.transp_mode = reg_file.hwpe_params[DATAMOVER_REG_CTRL_ENGINE >> 2][2:0] == 3'b000 ? TRANSP_NONE :
                              reg_file.hwpe_params[DATAMOVER_REG_CTRL_ENGINE >> 2][2:0] == 3'b001 ? TRANSP_1ELEM :
                              reg_file.hwpe_params[DATAMOVER_REG_CTRL_ENGINE >> 2][2:0] == 3'b010 ? TRANSP_2ELEM : TRANSP_4ELEM;
    engine_ctrl.transp_stride = reg_file.hwpe_params[DATAMOVER_REG_CTRL_ENGINE >> 2][2:0] == 3'b000 ? 1 :
                                reg_file.hwpe_params[DATAMOVER_REG_CTRL_ENGINE >> 2][2:0] == 3'b001 ? 1 :
                                reg_file.hwpe_params[DATAMOVER_REG_CTRL_ENGINE >> 2][2:0] == 3'b010 ? 2 : 4;
    engine_ctrl.datamover_mode = datamover_mode_e'(reg_file.hwpe_params[DATAMOVER_REG_CTRL_ENGINE >> 2][7:3]);
    engine_ctrl.tensor_size_m = reg_file.hwpe_params[DATAMOVER_REG_MATRIX_DIM >> 2][15:0];
    engine_ctrl.tensor_size_n = reg_file.hwpe_params[DATAMOVER_REG_MATRIX_DIM >> 2][31:16];
    engine_ctrl.num_channels   = reg_file.hwpe_params[DATAMOVER_REG_CHANNELS >> 2][10:0];
    engine_ctrl.total_elements = reg_file.hwpe_params[DATAMOVER_REG_CHANNELS >> 2][31:11];
    engine_ctrl.transp_len = BANDWIDTH_ALIGNED/ELEM_WIDTH;
  end

  // Bind the output event, which is propagated to the event unit and used
  // to implement HWPE datamover barriers.
  assign evt_o = slave_flags.evt[N_CORES-1:0];

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
