/*
 * datamover_ctrl.sv
 *
 * Copyright (C) 2020-2026 ETH Zurich, University of Bologna
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

`include "common_cells/registers.svh"

module datamover_ctrl
  import datamover_package::*;
  import datamover_regif_pkg::*;
  import hwpe_ctrl_package::*;
  import hci_package::*;
#(
  parameter int unsigned NUM_CORES     = 2,   // number of cores for event outputs
  parameter int unsigned NUM_CONTEXT   = 2,   // depth of the job queue (committed-but-not-done jobs)
  parameter int unsigned ID_WIDTH      = 4,   // control target peripheral ID width
  parameter int unsigned REGFILE_N_EVT = hwpe_ctrl_package::REGFILE_N_EVT,
  parameter int unsigned TRANSP_LEN    = 64   // BANDWIDTH_ALIGNED / ELEM_WIDTH (number of elements per beat)
)
(
  input  logic                                    clk_i,
  input  logic                                    rst_ni,
  // events
  output logic [NUM_CORES-1:0][REGFILE_N_EVT-1:0] evt_o,
  // status / clear
  output logic                                    busy_o,
  output logic                                    clear_o,
  // streamer + engine control
  output datamover_package::ctrl_streamer_t       ctrl_streamer_o,
  input  datamover_package::flags_streamer_t      flags_streamer_i,
  output datamover_package::ctrl_engine_t         ctrl_engine_o,
  // peripheral slave port
  hwpe_ctrl_intf_periph.slave                     periph
);

  // SystemRDL-generated regif hwif handshake signals
  datamover_regif_pkg::datamover_regif__in_t  hwif_in;
  datamover_regif_pkg::datamover_regif__out_t hwif_out;

  // cpuif plug between hwpe_ctrl_target and datamover_regif
  logic        target_cpuif_req;
  logic        target_cpuif_req_is_wr;
  logic [31:0] target_cpuif_addr;
  logic [31:0] target_cpuif_wr_data;
  logic [31:0] target_cpuif_wr_biten;
  logic        target_cpuif_req_stall_wr;
  logic        target_cpuif_req_stall_rd;
  logic        target_cpuif_rd_ack;
  logic        target_cpuif_rd_err;
  logic [31:0] target_cpuif_rd_data;
  logic        target_cpuif_wr_ack;
  logic        target_cpuif_wr_err;

  // hwpe_ctrl_target outputs
  logic                                                      target_clear;
  logic                                                      job_trigger;
  logic                                                      job_done_d, job_done_q;
  logic [31:0]                                               job_status;
  datamover_regif_pkg::datamover_regif__hwpe_ctrl_job_indep__out_t job_indep_regs;
  logic                                                      job_dep_regs_valid;
  datamover_regif_pkg::datamover_regif__hwpe_ctrl_job_dep__out_t   job_dep_regs;

  logic             start;
  ctrl_engine_t     engine_ctrl_d, engine_ctrl_q;
  datamover_state_e state_d, state_q;

  // ----------------------------------------------------------------------
  // HWPE control target + SystemRDL register file
  // ----------------------------------------------------------------------
  hwpe_ctrl_target #(
    .NB_CONTEXT            ( NUM_CONTEXT                                                    ),
    .ID_WIDTH              ( ID_WIDTH                                                       ),
    .ADDR_WIDTH            ( 10                                                             ),
    .hwpe_ctrl_regif_in_t  ( datamover_regif_pkg::datamover_regif__in_t                     ),
    .hwpe_ctrl_regif_out_t ( datamover_regif_pkg::datamover_regif__out_t                    ),
    .hwpe_ctrl_job_indep_t ( datamover_regif_pkg::datamover_regif__hwpe_ctrl_job_indep__out_t ),
    .hwpe_ctrl_job_dep_t   ( datamover_regif_pkg::datamover_regif__hwpe_ctrl_job_dep__out_t   )
  ) i_target (
    .clk_i                ( clk_i              ),
    .rst_ni               ( rst_ni             ),
    .clear_o              ( target_clear       ),
    .target               ( periph             ),
    .job_trigger_o        ( job_trigger        ),
    .job_done_i           ( job_done_d         ),
    .job_status_i         ( job_status         ),
    .job_indep_regs_o     ( job_indep_regs     ),
    .job_dep_regs_valid_o ( job_dep_regs_valid ),
    .job_dep_regs_o       ( job_dep_regs       ),
    .target_cpuif_req_o          ( target_cpuif_req          ),
    .target_cpuif_req_is_wr_o    ( target_cpuif_req_is_wr    ),
    .target_cpuif_addr_o         ( target_cpuif_addr         ),
    .target_cpuif_wr_data_o      ( target_cpuif_wr_data      ),
    .target_cpuif_wr_biten_o     ( target_cpuif_wr_biten     ),
    .target_cpuif_req_stall_wr_i ( target_cpuif_req_stall_wr ),
    .target_cpuif_req_stall_rd_i ( target_cpuif_req_stall_rd ),
    .target_cpuif_rd_ack_i       ( target_cpuif_rd_ack       ),
    .target_cpuif_rd_err_i       ( target_cpuif_rd_err       ),
    .target_cpuif_rd_data_i      ( target_cpuif_rd_data      ),
    .target_cpuif_wr_ack_i       ( target_cpuif_wr_ack       ),
    .target_cpuif_wr_err_i       ( target_cpuif_wr_err       ),
    .hwif_in              ( hwif_in            ),
    .hwif_out             ( hwif_out           )
  );

  datamover_regif i_regif (
    .clk                  ( clk_i                     ),
    .arst_n               ( rst_ni                    ),
    .s_cpuif_req          ( target_cpuif_req          ),
    .s_cpuif_req_is_wr    ( target_cpuif_req_is_wr    ),
    .s_cpuif_addr         ( target_cpuif_addr         ),
    .s_cpuif_wr_data      ( target_cpuif_wr_data      ),
    .s_cpuif_wr_biten     ( target_cpuif_wr_biten     ),
    .s_cpuif_req_stall_wr ( target_cpuif_req_stall_wr ),
    .s_cpuif_req_stall_rd ( target_cpuif_req_stall_rd ),
    .s_cpuif_rd_ack       ( target_cpuif_rd_ack       ),
    .s_cpuif_rd_err       ( target_cpuif_rd_err       ),
    .s_cpuif_rd_data      ( target_cpuif_rd_data      ),
    .s_cpuif_wr_ack       ( target_cpuif_wr_ack       ),
    .s_cpuif_wr_err       ( target_cpuif_wr_err       ),
    .hwif_in              ( hwif_in                   ),
    .hwif_out             ( hwif_out                  )
  );

  // ----------------------------------------------------------------------
  // Control glue between hwpe_ctrl_target and the datapath
  // ----------------------------------------------------------------------

  // Soft clear only resets the datapath (the FSM is re-armed per job).
  assign clear_o = target_clear;

  // Start a job on its commit pulse, or -- one cycle after a job completes --
  // start the next committed job already waiting in the FIFO. The latter lets a
  // job programmed while another runs begin as soon as the engine frees, which
  // is the point of the NB_CONTEXT job queue. (cf. neureka_ctrl)
  assign start = job_trigger | (job_done_q & job_dep_regs_valid);

  // Busy while a job is committed (in the FIFO) or the FSM is running.
  assign busy_o     = job_dep_regs_valid | (state_q != DM_IDLE);
  assign job_status = busy_o ? 32'h1 : 32'h0;

  // Completion event, one cycle after the job is done.
  for (genvar c = 0; c < NUM_CORES; c++) begin : gen_evt_core
    for (genvar e = 0; e < REGFILE_N_EVT; e++) begin : gen_evt_bit
      if (c == 0 && e == 0) begin : gen_job_done_evt
        assign evt_o[c][e] = job_done_q;
      end else begin : gen_zero_evt
        assign evt_o[c][e] = 1'b0;
      end
    end
  end

  // ----------------------------------------------------------------------
  // Datamover FSM
  // ----------------------------------------------------------------------
  always_comb begin : fsm_ns_comb
    state_d = state_q;
    if (state_q == DM_IDLE) begin
      if (start)
        state_d = DM_STARTING;
    end
    else if (state_q == DM_STARTING) begin
      state_d = DM_WORKING;
    end
    else if (state_q == DM_WORKING) begin
      if ((flags_streamer_i.data_out_sink_flags.done | flags_streamer_i.data_out_sink_flags.ready_start) &
          (flags_streamer_i.data_in_source_flags.done | flags_streamer_i.data_in_source_flags.ready_start) &
          flags_streamer_i.tcdm_fifo_empty)
        state_d = DM_FINISHED;
    end
    else begin
      state_d = DM_IDLE;
    end
  end

  assign job_done_d = (state_q == DM_FINISHED);

  // ----------------------------------------------------------------------
  // Streamer base configuration from the typed job-dependent registers
  // ----------------------------------------------------------------------
  assign ctrl_streamer_o.data_in_source_ctrl.req_start = (state_q == DM_STARTING);
  assign ctrl_streamer_o.data_out_sink_ctrl.req_start  = (state_q == DM_STARTING);
  // Enabled address-generator dimensions (d0 is always enabled).
  assign ctrl_streamer_o.data_in_source_ctrl.addressgen_ctrl.dim_enable_1h = job_dep_regs.ctrl_engine.read_dim_en.value;
  assign ctrl_streamer_o.data_out_sink_ctrl.addressgen_ctrl.dim_enable_1h  = job_dep_regs.ctrl_engine.write_dim_en.value;
  // Base addresses.
  assign ctrl_streamer_o.data_in_source_ctrl.addressgen_ctrl.base_addr = job_dep_regs.in_ptr.value.value;
  assign ctrl_streamer_o.data_out_sink_ctrl.addressgen_ctrl.base_addr  = job_dep_regs.out_ptr.value.value;
  // Total length (in number of beats).
  assign ctrl_streamer_o.data_in_source_ctrl.addressgen_ctrl.tot_len   = job_dep_regs.tot_len.value.value;
  assign ctrl_streamer_o.data_out_sink_ctrl.addressgen_ctrl.tot_len    = job_dep_regs.out_tot_len.value.value;
  // Source (input) per-dimension stride/length.
  assign ctrl_streamer_o.data_in_source_ctrl.addressgen_ctrl.d0_len    = job_dep_regs.in_d0.length.value;
  assign ctrl_streamer_o.data_in_source_ctrl.addressgen_ctrl.d0_stride = job_dep_regs.in_d0.stride.value;
  assign ctrl_streamer_o.data_in_source_ctrl.addressgen_ctrl.d1_len    = job_dep_regs.in_d1.length.value;
  assign ctrl_streamer_o.data_in_source_ctrl.addressgen_ctrl.d1_stride = job_dep_regs.in_d1.stride.value;
  assign ctrl_streamer_o.data_in_source_ctrl.addressgen_ctrl.d2_len    = job_dep_regs.in_d2.length.value;
  assign ctrl_streamer_o.data_in_source_ctrl.addressgen_ctrl.d2_stride = job_dep_regs.in_d2.stride.value;
  assign ctrl_streamer_o.data_in_source_ctrl.addressgen_ctrl.d3_len    = job_dep_regs.in_d3.length.value;
  assign ctrl_streamer_o.data_in_source_ctrl.addressgen_ctrl.d3_stride = job_dep_regs.in_d3.stride.value;
  assign ctrl_streamer_o.data_in_source_ctrl.addressgen_ctrl.d4_stride = job_dep_regs.in_d4_stride.value.value;
  // Sink (output) per-dimension stride/length.
  assign ctrl_streamer_o.data_out_sink_ctrl.addressgen_ctrl.d0_len     = job_dep_regs.out_d0.length.value;
  assign ctrl_streamer_o.data_out_sink_ctrl.addressgen_ctrl.d0_stride  = job_dep_regs.out_d0.stride.value;
  assign ctrl_streamer_o.data_out_sink_ctrl.addressgen_ctrl.d1_len     = job_dep_regs.out_d1.length.value;
  assign ctrl_streamer_o.data_out_sink_ctrl.addressgen_ctrl.d1_stride  = job_dep_regs.out_d1.stride.value;
  assign ctrl_streamer_o.data_out_sink_ctrl.addressgen_ctrl.d2_len     = job_dep_regs.out_d2.length.value;
  assign ctrl_streamer_o.data_out_sink_ctrl.addressgen_ctrl.d2_stride  = job_dep_regs.out_d2.stride.value;
  assign ctrl_streamer_o.data_out_sink_ctrl.addressgen_ctrl.d3_len     = job_dep_regs.out_d3.length.value;
  assign ctrl_streamer_o.data_out_sink_ctrl.addressgen_ctrl.d3_stride  = job_dep_regs.out_d3.stride.value;
  assign ctrl_streamer_o.data_out_sink_ctrl.addressgen_ctrl.d4_stride  = job_dep_regs.out_d4_stride.value.value;

  // ----------------------------------------------------------------------
  // Engine configuration from the typed job-dependent registers
  // ----------------------------------------------------------------------
  assign engine_ctrl_d.transp_mode   = job_dep_regs.ctrl_engine.transp_mode.value == 3'b000 ? TRANSP_NONE  :
                                       job_dep_regs.ctrl_engine.transp_mode.value == 3'b001 ? TRANSP_1ELEM :
                                       job_dep_regs.ctrl_engine.transp_mode.value == 3'b010 ? TRANSP_2ELEM : TRANSP_4ELEM;
  assign engine_ctrl_d.transp_stride = job_dep_regs.ctrl_engine.transp_mode.value == 3'b000 ? 1 :
                                       job_dep_regs.ctrl_engine.transp_mode.value == 3'b001 ? 1 :
                                       job_dep_regs.ctrl_engine.transp_mode.value == 3'b010 ? 2 : 4;
  assign engine_ctrl_d.datamover_mode = datamover_mode_e'(job_dep_regs.ctrl_engine.datamover_mode.value);
  // im2col subsamples each beat by the conv stride; all other modes pass through (stride 1).
  assign engine_ctrl_d.conv_stride    = (engine_ctrl_d.datamover_mode == DATAMOVER_IM2COL) ?
                                        job_dep_regs.ctrl_engine.conv_stride.value : 1'b1;
  assign engine_ctrl_d.im2col_pack     = job_dep_regs.ctrl_engine.im2col_pack.value;
  assign engine_ctrl_d.im2col_pad      = job_dep_regs.ctrl_engine.im2col_pad.value;
  assign engine_ctrl_d.pack_log2w      = job_dep_regs.ctrl_engine.pack_log2w.value;
  assign engine_ctrl_d.pack_row_stride = job_dep_regs.ctrl_engine.pack_row_stride.value;
  assign engine_ctrl_d.tensor_size_m  = job_dep_regs.matrix_dim.tensor_size_m.value;
  assign engine_ctrl_d.tensor_size_n  = job_dep_regs.matrix_dim.tensor_size_n.value;
  assign engine_ctrl_d.num_channels   = job_dep_regs.channels.num_channels.value;
  assign engine_ctrl_d.total_elements = job_dep_regs.channels.total_elements.value;
  assign engine_ctrl_d.transp_len     = TRANSP_LEN;

  assign ctrl_engine_o = engine_ctrl_q;

  // ----------------------------------------------------------------------
  // Sequential logic
  // ----------------------------------------------------------------------
  `FFARN(job_done_q, job_done_d, 1'b0, clk_i, rst_ni)
  `FFARNC(state_q, state_d, clear_o, DM_IDLE, clk_i, rst_ni)
  `FFARNC(engine_ctrl_q, engine_ctrl_d, clear_o, '0, clk_i, rst_ni)

endmodule // datamover_ctrl
