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

  // OBI plug between hwpe_ctrl_target and datamover_regif
  logic                 target_obi_req;
  logic                 target_obi_gnt;
  logic [31:0]          target_obi_addr;
  logic                 target_obi_we;
  logic [3:0]           target_obi_be;
  logic [31:0]          target_obi_wdata;
  logic [ID_WIDTH-1:0]  target_obi_aid;
  logic                 target_obi_rvalid;
  logic                 target_obi_rready;
  logic [31:0]          target_obi_rdata;
  logic                 target_obi_err;
  logic [ID_WIDTH-1:0]  target_obi_rid;

  // hwpe_ctrl_target outputs
  logic                                                      target_clear;
  logic                                                      job_trigger;
  logic                                                      job_done;
  logic                                                      job_done_q;
  logic [31:0]                                               job_status;
  datamover_regif_pkg::datamover_regif__hwpe_ctrl_job_indep__out_t job_indep_regs;
  logic                                                      job_dep_regs_valid;
  datamover_regif_pkg::datamover_regif__hwpe_ctrl_job_dep__out_t   job_dep_regs;

  logic             start;
  ctrl_streamer_t   streamer_ctrl_cfg;
  ctrl_engine_t     engine_ctrl;
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
    .job_done_i           ( job_done           ),
    .job_status_i         ( job_status         ),
    .job_indep_regs_o     ( job_indep_regs     ),
    .job_dep_regs_valid_o ( job_dep_regs_valid ),
    .job_dep_regs_o       ( job_dep_regs       ),
    .target_obi_req_o     ( target_obi_req     ),
    .target_obi_gnt_i     ( target_obi_gnt     ),
    .target_obi_addr_o    ( target_obi_addr    ),
    .target_obi_we_o      ( target_obi_we      ),
    .target_obi_be_o      ( target_obi_be      ),
    .target_obi_wdata_o   ( target_obi_wdata   ),
    .target_obi_aid_o     ( target_obi_aid     ),
    .target_obi_rvalid_i  ( target_obi_rvalid  ),
    .target_obi_rready_o  ( target_obi_rready  ),
    .target_obi_rdata_i   ( target_obi_rdata   ),
    .target_obi_err_i     ( target_obi_err     ),
    .target_obi_rid_i     ( target_obi_rid     ),
    .hwif_in              ( hwif_in            ),
    .hwif_out             ( hwif_out           )
  );

  datamover_regif #(
    .ID_WIDTH ( ID_WIDTH )
  ) i_regif (
    .clk          ( clk_i             ),
    .arst_n       ( rst_ni            ),
    .s_obi_req    ( target_obi_req    ),
    .s_obi_gnt    ( target_obi_gnt    ),
    .s_obi_addr   ( target_obi_addr   ),
    .s_obi_we     ( target_obi_we     ),
    .s_obi_be     ( target_obi_be     ),
    .s_obi_wdata  ( target_obi_wdata  ),
    .s_obi_aid    ( target_obi_aid    ),
    .s_obi_rvalid ( target_obi_rvalid ),
    .s_obi_rready ( target_obi_rready ),
    .s_obi_rdata  ( target_obi_rdata  ),
    .s_obi_err    ( target_obi_err    ),
    .s_obi_rid    ( target_obi_rid    ),
    .hwif_in      ( hwif_in           ),
    .hwif_out     ( hwif_out          )
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
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni)
      job_done_q <= 1'b0;
    else
      job_done_q <= job_done;
  end
  always_comb begin
    evt_o = '0;
    evt_o[0][0] = job_done_q;
  end

  // ----------------------------------------------------------------------
  // Datamover FSM
  // ----------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin : fsm_seq
    if (~rst_ni)
      state_q <= DM_IDLE;
    else if (clear_o)
      state_q <= DM_IDLE;
    else
      state_q <= state_d;
  end

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

  // FSM outputs: drive req_start while STARTING, signal job completion when FINISHED.
  always_comb begin : fsm_out_comb
    job_done        = 1'b0;
    ctrl_streamer_o = streamer_ctrl_cfg;
    if (state_q == DM_STARTING) begin
      ctrl_streamer_o.data_in_source_ctrl.req_start = 1'b1;
      ctrl_streamer_o.data_out_sink_ctrl.req_start  = 1'b1;
    end
    else if (state_q == DM_FINISHED) begin
      job_done = 1'b1;
    end
  end

  // ----------------------------------------------------------------------
  // Streamer base configuration from the typed job-dependent registers
  // ----------------------------------------------------------------------
  always_comb begin
    streamer_ctrl_cfg = '0;
    // Enabled address-generator dimensions (d0 is always enabled).
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.dim_enable_1h = job_dep_regs.ctrl_engine.read_dim_en.value;
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.dim_enable_1h  = job_dep_regs.ctrl_engine.write_dim_en.value;
    // Base addresses.
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.base_addr = job_dep_regs.in_ptr.value.value;
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.base_addr  = job_dep_regs.out_ptr.value.value;
    // Total length (in number of beats).
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.tot_len   = job_dep_regs.tot_len.value.value;
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.tot_len    = job_dep_regs.tot_len.value.value;
    // Source (input) per-dimension stride/length.
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d0_len    = job_dep_regs.in_d0.length.value;
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d0_stride = job_dep_regs.in_d0.stride.value;
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d1_len    = job_dep_regs.in_d1.length.value;
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d1_stride = job_dep_regs.in_d1.stride.value;
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d2_len    = job_dep_regs.in_d2.length.value;
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d2_stride = job_dep_regs.in_d2.stride.value;
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d3_len    = job_dep_regs.in_d3.length.value;
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d3_stride = job_dep_regs.in_d3.stride.value;
    streamer_ctrl_cfg.data_in_source_ctrl.addressgen_ctrl.d4_stride = job_dep_regs.in_out_d4_stride.in_stride.value;
    // Sink (output) per-dimension stride/length.
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d0_len     = job_dep_regs.out_d0.length.value;
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d0_stride  = job_dep_regs.out_d0.stride.value;
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d1_len     = job_dep_regs.out_d1.length.value;
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d1_stride  = job_dep_regs.out_d1.stride.value;
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d2_len     = job_dep_regs.out_d2.length.value;
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d2_stride  = job_dep_regs.out_d2.stride.value;
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d3_len     = job_dep_regs.out_d3.length.value;
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d3_stride  = job_dep_regs.out_d3.stride.value;
    streamer_ctrl_cfg.data_out_sink_ctrl.addressgen_ctrl.d4_stride  = job_dep_regs.in_out_d4_stride.out_stride.value;
  end

  // ----------------------------------------------------------------------
  // Engine configuration from the typed job-dependent registers
  // ----------------------------------------------------------------------
  always_comb begin
    engine_ctrl = '0;
    engine_ctrl.transp_mode   = job_dep_regs.ctrl_engine.transp_mode.value == 3'b000 ? TRANSP_NONE  :
                                job_dep_regs.ctrl_engine.transp_mode.value == 3'b001 ? TRANSP_1ELEM :
                                job_dep_regs.ctrl_engine.transp_mode.value == 3'b010 ? TRANSP_2ELEM : TRANSP_4ELEM;
    engine_ctrl.transp_stride = job_dep_regs.ctrl_engine.transp_mode.value == 3'b000 ? 1 :
                                job_dep_regs.ctrl_engine.transp_mode.value == 3'b001 ? 1 :
                                job_dep_regs.ctrl_engine.transp_mode.value == 3'b010 ? 2 : 4;
    engine_ctrl.datamover_mode = datamover_mode_e'(job_dep_regs.ctrl_engine.datamover_mode.value);
    engine_ctrl.tensor_size_m  = job_dep_regs.matrix_dim.tensor_size_m.value;
    engine_ctrl.tensor_size_n  = job_dep_regs.matrix_dim.tensor_size_n.value;
    engine_ctrl.num_channels   = job_dep_regs.channels.num_channels.value;
    engine_ctrl.total_elements = job_dep_regs.channels.total_elements.value;
    engine_ctrl.transp_len     = TRANSP_LEN;
  end
  assign ctrl_engine_o = engine_ctrl;

endmodule // datamover_ctrl
