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
 * Authors:  Francesco Conti <f.conti@unibo.it>
 *           Sergio Mazzola <smazzola@iis.ee.ethz.ch>
 *           Cyrill Durrer <cdurrer@iis.ee.ethz.ch>
 */

`include "common_cells/registers.svh"

module datamover_engine
  import hwpe_stream_package::*;
  import hci_package::*;
  import datamover_package::*;
#(
  parameter int unsigned FIFO_DEPTH = 2,
  parameter bit          EnableIm2col = 1'b1,
  parameter int unsigned BANDWIDTH_ALIGNED = 512,
  parameter int unsigned NUM_ELEM_WORD = 4, // number of elements in a bank word
  parameter int unsigned ELEM_WIDTH = 8,     // element width (in bits)
  // Dependent parameters: do not modify!
  localparam int unsigned WORD_WIDTH = NUM_ELEM_WORD * ELEM_WIDTH // should correspond to bank width
) (
  // global signals
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   test_mode_i,   // unused
  // local enable & clear
  input  logic                   enable_i,      // unused
  input  logic                   clear_i,
  // control registers
  input  ctrl_engine_t           ctrl_i,
  // input data stream + handshake
  hwpe_stream_intf_stream.sink   data_in,
  // output data stream + handshake
  hwpe_stream_intf_stream.source data_out
);

  // number of elements (in the full bandwidth, not a single bank word)
  localparam int unsigned NB_ELEMENTS = BANDWIDTH_ALIGNED / ELEM_WIDTH;
  localparam int unsigned NB_ELEM_LOG2 = $clog2(NB_ELEMENTS);

  // Counter widths
  //   TILE_CNT    holds ceil(tensor_size / NB_ELEMENTS)
  //   ACCESS_CNT  holds the output beats of one job
  localparam int unsigned TILE_CNT_WIDTH   = TENSOR_SIZE_WIDTH - NB_ELEM_LOG2 + 1;
  localparam int unsigned ACCESS_CNT_BASE  = (TENSOR_SIZE_WIDTH + NB_ELEM_LOG2 > TOTAL_ELEM_WIDTH) ?
                                             TENSOR_SIZE_WIDTH + NB_ELEM_LOG2 : TOTAL_ELEM_WIDTH;
  localparam int unsigned ACCESS_CNT_WIDTH = ACCESS_CNT_BASE + 2;

  // Type def and internal signals
  typedef enum logic { WRITE, READ } datamover_engine_fsm_t;
  datamover_engine_fsm_t                  fsm_d, fsm_q;
  logic                                   clear_elem_matrix;
  logic                                   clear_run;
  logic [NB_ELEM_LOG2-1:0]                cnt_q, cnt_d;
  logic [ACCESS_CNT_WIDTH-1:0]            tot_cnt_q, tot_cnt_d;
  logic                                   cnt_en;
  logic                                   tot_cnt_incr;
  logic [NB_ELEMENTS-1:0][ELEM_WIDTH-1:0] data_in_unrolled;
  logic                                   data_in_valid;
  logic                                   data_in_ready;
  logic [NB_ELEMENTS-1:0][ELEM_WIDTH-1:0] data_out_unrolled;
  logic                                   data_out_valid;
  logic                                   data_out_ready;
  logic [NB_ELEM_LOG2-1:0]                remaining_elems;
  logic [ACCESS_CNT_WIDTH-1:0]            total_accesses_copy_mode, total_accesses_cim, acc_target;
  logic [TILE_CNT_WIDTH-1:0]              inner_tiles, outer_tiles;
  logic [NB_ELEM_LOG2:0]                  inner_leftover, outer_leftover;
  logic [TILE_CNT_WIDTH-1:0]              inner_tile_q, inner_tile_d, outer_tile_q, outer_tile_d;
  logic [TENSOR_SIZE_WIDTH-1:0]           pass_cnt_q, pass_cnt_d, num_passes;
  logic [NB_ELEM_LOG2:0]                  inner_len, outer_len, fill_len, drain_len, phase_len;
  logic                                   buffer_mode, unfold_fold, tile_done, buffer_job_done;
  logic                                   last_inner_tile, last_outer_tile, last_pass;

  logic                                   execution_done;

  logic                                   im2col_unit;
  logic [NB_ELEMENTS-1:0][ELEM_WIDTH-1:0] im2col_data;
  logic                                   im2col_valid, im2col_ready;

  assign im2col_unit = EnableIm2col && (ctrl_i.datamover_mode == DATAMOVER_IM2COL) && ctrl_i.im2col_pack;

  // FSM: WRITE -> READ on input handshake at end of write, READ -> WRITE on output handshake at end of read
  always_comb
  begin
    fsm_d = fsm_q;
    case (fsm_q)
      WRITE: begin
        if (((cnt_q == phase_len-ctrl_i.transp_stride)) && (data_in_valid & data_in_ready)) begin
          fsm_d = READ;
        end
      end
      READ: begin
        if (((cnt_q == phase_len-ctrl_i.transp_stride)) && (data_out_valid & data_out_ready)) begin
          fsm_d = WRITE;
        end
      end
      default: begin
        fsm_d = WRITE;
      end
    endcase
  end

  assign clear_elem_matrix = (fsm_q == READ && fsm_d == WRITE) && (ctrl_i.transp_mode != TRANSP_NONE);
  assign clear_run = clear_i || execution_done;

  // internal interfaces and unrolling
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( BANDWIDTH_ALIGNED ),
    .ELEMENT_WIDTH ( ELEM_WIDTH ),
    .STRB_WIDTH ( NB_ELEMENTS )
  ) data_in_postfifo (
    .clk ( clk_i )
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( BANDWIDTH_ALIGNED ),
    .ELEMENT_WIDTH ( ELEM_WIDTH ),
    .STRB_WIDTH ( NB_ELEMENTS )
  ) data_out_prefifo (
    .clk ( clk_i )
  );

  // decouple in/out with FIFOs
  hwpe_stream_fifo #(
    .DATA_WIDTH ( BANDWIDTH_ALIGNED ),
    .ELEMENT_WIDTH ( ELEM_WIDTH ),
    .FIFO_DEPTH ( FIFO_DEPTH )
  ) i_fifo_in (
    .clk_i   ( clk_i            ),
    .rst_ni  ( rst_ni           ),
    .clear_i ( clear_i          ),
    .flags_o (                  ),
    .push_i  ( data_in          ),
    .pop_o   ( data_in_postfifo )
  );
  assign data_in_unrolled = data_in_postfifo.data;
  assign data_in_valid = data_in_postfifo.valid;
  assign data_in_postfifo.ready = data_in_ready;
  hwpe_stream_fifo #(
    .DATA_WIDTH ( BANDWIDTH_ALIGNED ),
    .ELEMENT_WIDTH ( ELEM_WIDTH ),
    .FIFO_DEPTH ( FIFO_DEPTH )
  ) i_fifo_out (
    .clk_i   ( clk_i            ),
    .rst_ni  ( rst_ni           ),
    .clear_i ( clear_i          ),
    .flags_o (                  ),
    .push_i  ( data_out_prefifo ),
    .pop_o   ( data_out         )
  );


  // Partial tile / leftover elements handling
  // Due to the streamer address generation, matrices need to be word-aligned in n-dimension for transposition
  localparam logic [NB_ELEMENTS-1:0] STRB_ONE = {{(NB_ELEMENTS-1){1'b0}}, 1'b1};    // Necessary to force the shifting operation to the correct bitwidth (default would be only 32b)
  assign remaining_elems = ctrl_i.total_elements & (NB_ELEMENTS - 1);         // modulo (NB_ELEMENTS: power of two) - this signal is only used in copy mode
  assign total_accesses_copy_mode = (ctrl_i.total_elements >> NB_ELEM_LOG2) + ((remaining_elems != 0) ? 1 : 0);

  // Tile geometry
  // The buffer modes walk a grid of NB_ELEMENTS tiles, inner dimension first, num_passes times.
  // The inner dimension is the channel count of unfold and fold, the m size of the other modes.
  // The outer dimension is the n size. A pass repeats the grid for one image row (unfold, fold).
  assign buffer_mode     = ctrl_i.transp_mode != TRANSP_NONE;
  assign unfold_fold     = (ctrl_i.datamover_mode == DATAMOVER_UNFOLD) || (ctrl_i.datamover_mode == DATAMOVER_FOLD);
  assign inner_tiles     = unfold_fold ? (ctrl_i.num_channels + NB_ELEMENTS - 1) >> NB_ELEM_LOG2 :
                                         (ctrl_i.tensor_size_m + NB_ELEMENTS - 1) >> NB_ELEM_LOG2;
  assign outer_tiles     = (ctrl_i.tensor_size_n + NB_ELEMENTS - 1) >> NB_ELEM_LOG2;
  assign inner_leftover  = unfold_fold ? ctrl_i.num_channels & (NB_ELEMENTS - 1) : ctrl_i.tensor_size_m & (NB_ELEMENTS - 1);
  assign outer_leftover  = ctrl_i.tensor_size_n & (NB_ELEMENTS - 1);
  assign num_passes      = (ctrl_i.datamover_mode == DATAMOVER_TRANSPOSE) ? TENSOR_SIZE_WIDTH'(1) : ctrl_i.tensor_size_m;
  assign last_inner_tile = (inner_tile_q == inner_tiles - 1);
  assign last_outer_tile = (outer_tile_q == outer_tiles - 1);
  assign last_pass       = (pass_cnt_q == num_passes - 1);
  assign inner_len       = (last_inner_tile && (inner_leftover != 0)) ? inner_leftover : ctrl_i.transp_len;
  assign outer_len       = (last_outer_tile && (outer_leftover != 0)) ? outer_leftover : ctrl_i.transp_len;

  // A tile fills fill_len buffer rows, then drains drain_len buffer columns.
  // The inner dimension fills the rows; fold fills the rows from the outer dimension.
  assign fill_len        = (ctrl_i.datamover_mode == DATAMOVER_FOLD) ? outer_len : inner_len;
  assign drain_len       = (ctrl_i.datamover_mode == DATAMOVER_FOLD) ? inner_len : outer_len;
  assign phase_len       = (fsm_q == WRITE) ? fill_len : drain_len;
  assign tile_done       = clear_elem_matrix;
  assign inner_tile_d    = tile_done ? (last_inner_tile ? '0 : inner_tile_q + 1'b1) : inner_tile_q;
  assign outer_tile_d    = (tile_done && last_inner_tile) ? (last_outer_tile ? '0 : outer_tile_q + 1'b1) : outer_tile_q;
  assign pass_cnt_d      = (tile_done && last_inner_tile && last_outer_tile) ? pass_cnt_q + 1'b1 : pass_cnt_q;
  assign buffer_job_done = last_inner_tile && last_outer_tile && last_pass && clear_elem_matrix;

  logic [NB_ELEMENTS-1:0] strb_copy, strb_buffer, strb_cim, strb_im2col;

  assign strb_copy   = ((tot_cnt_q >= total_accesses_copy_mode-1) && (remaining_elems != 0)) ? ((STRB_ONE << remaining_elems) - 1) : '1;

  // The buffer holds fill_len valid rows, so each drained column has fill_len elements.
  assign strb_buffer = (STRB_ONE << fill_len) - 1;

  // A block layout beat holds the leftover columns of the n size.
  assign strb_cim    = (outer_leftover != 0) ? ((STRB_ONE << outer_leftover) - 1) : '1;

  // The 3x3 unit fills every beat; other im2col beats hold tensor_size_n elements.
  assign strb_im2col = (im2col_unit && ctrl_i.conv_stride == 1) ? '1 :
                       (ctrl_i.tensor_size_n < NB_ELEMENTS) ? ((STRB_ONE << ctrl_i.tensor_size_n) - 1) : strb_copy;

  assign data_out_prefifo.strb = (ctrl_i.total_elements == 0)                        ? '1 :
                                 (ctrl_i.datamover_mode == DATAMOVER_COPY)           ? strb_copy :
                                 (ctrl_i.datamover_mode == DATAMOVER_IM2COL)         ? strb_im2col :
                                 (ctrl_i.datamover_mode == DATAMOVER_CIM_CONVERSION) ? strb_cim :
                                 buffer_mode                                         ? strb_buffer :
                                                                                       '1;

  assign data_out_prefifo.data = data_out_unrolled;
  assign data_out_prefifo.valid = data_out_valid;
  assign data_out_ready = data_out_prefifo.ready;

  // Write counter
  assign cnt_en = fsm_q == WRITE ? data_in_valid & data_in_ready : data_out_valid & data_out_ready;
  assign cnt_d = cnt_en ? ((cnt_q < (phase_len-ctrl_i.transp_stride)) ? cnt_q+ctrl_i.transp_stride : '0) : cnt_q;

  // Pass-through modes count output beats; buffer modes count tiles.
  assign total_accesses_cim = ctrl_i.tensor_size_m * outer_tiles;
  assign acc_target         = (ctrl_i.datamover_mode == DATAMOVER_CIM_CONVERSION) ? total_accesses_cim : total_accesses_copy_mode;
  assign execution_done     = buffer_mode ? buffer_job_done :
                              (acc_target != 0) && (data_out_prefifo.valid & data_out_prefifo.ready) && (tot_cnt_q >= acc_target - 1);

  assign tot_cnt_incr = data_out_prefifo.valid & data_out_prefifo.ready;
  assign tot_cnt_d    = tot_cnt_incr ? tot_cnt_q + 1 : tot_cnt_q;

  // "Smart shifting": this set of combinational blocks shifts data_in_unrolled
  // appropriately, depending on the configuration.
  // E.g., if you have a classical configuration with
  // - NUM_ELEM_WORD = 8 and
  // - ELEM_WIDTH = 8 bits, i.e. total is 64 bits per word
  // the configurations are: 8b transpose, 16b transpose, 32b transpose. We assume
  // that transposes >= 64b can be done efficiently by Snitch processors through SSRs
  // and those < 8b are not interesting in our use case.
  localparam MAX_SHIFTING = (NUM_ELEM_WORD > MAX_TRANSP_STRIDE) ? NUM_ELEM_WORD : MAX_TRANSP_STRIDE;
  // e.g., in a classical configuration (ELEM_WIDTH = 8), MAX_SHIFTING is
  // in bytes, i.e., "4" for 32b transpose (includes shifting by 0 bytes)
  logic [MAX_SHIFTING-1:0][NB_ELEMENTS-1:0][ELEM_WIDTH-1:0] data_in_shifted;

  for(genvar ii=0; ii<MAX_SHIFTING; ii++) begin : gen_data_shifting_x
    for(genvar jj=0; jj<NB_ELEMENTS; jj++) begin : gen_data_shifting_y

      if(ii+jj < NB_ELEMENTS) begin : gen_feasible_shiftings
        assign data_in_shifted[ii][jj] = data_in_unrolled[ii+jj];
      end
      else begin : gen_unfeasible_shiftings
        assign data_in_shifted[ii][jj] = '0;
      end

    end // gen_data_shifting_y
  end // gen_data_shifting_x

  if (EnableIm2col) begin : gen_im2col
    datamover_im2col #(
      .NB_ELEMENTS ( NB_ELEMENTS ),
      .ELEM_WIDTH  ( ELEM_WIDTH  )
    ) i_im2col (
      .clk_i   ( clk_i                       ),
      .rst_ni  ( rst_ni                      ),
      .clear_i ( clear_run                   ),
      .ctrl_i  ( ctrl_i                      ),
      .data_i  ( data_in_unrolled            ),
      .valid_i ( data_in_valid & im2col_unit ),
      .ready_o ( im2col_ready                ),
      .data_o  ( im2col_data                 ),
      .valid_o ( im2col_valid                ),
      .ready_i ( data_out_ready              )
    );
  end else begin : gen_no_im2col
    assign im2col_ready = 1'b0;
    assign im2col_data  = '0;
    assign im2col_valid = 1'b0;
  end

  logic [NB_ELEMENTS-1:0]                     wr_row_en;
  logic [NB_ELEMENTS-1:0][ELEM_WIDTH-1:0]     wr_row_data   [NB_ELEMENTS-1:0];
  logic [NB_ELEMENTS-1:0][ELEM_WIDTH-1:0]     elem_matrix_q [NB_ELEMENTS-1:0];

  for(genvar ii=0; ii<NB_ELEMENTS; ii++) begin : gen_buffer_write
    logic in_hs, buffer_enable;
    assign in_hs = data_in_valid & data_in_ready;
    assign buffer_enable = ctrl_i.transp_mode == TRANSP_NONE  ? 1'b0 :
                           ctrl_i.transp_mode == TRANSP_4ELEM ? ((cnt_q>>2) == (ii>>2)) & in_hs :
                           ctrl_i.transp_mode == TRANSP_2ELEM ? ((cnt_q>>1) == (ii>>1)) & in_hs :
                                                                ( cnt_q     ==  ii    ) & in_hs;
    logic [NB_ELEMENTS-1:0][ELEM_WIDTH-1:0] data_in_selected;
    assign data_in_selected = ctrl_i.transp_mode == TRANSP_4ELEM? data_in_shifted[ii % 4] :
                              ctrl_i.transp_mode == TRANSP_2ELEM ? data_in_shifted[ii % 2] :
                                                                   data_in_shifted[0];

    assign wr_row_en[ii]   = buffer_enable;
    assign wr_row_data[ii] = data_in_selected;
  end // gen_buffer_write

  datamover_buffer #(
    .NB_ELEMENTS ( NB_ELEMENTS ),
    .ELEM_WIDTH  ( ELEM_WIDTH  )
  ) i_buffer (
    .clk_i          ( clk_i             ),
    .rst_ni         ( rst_ni            ),
    .clear_i        ( clear_i           ),
    .clear_matrix_i ( clear_elem_matrix ),
    .wr_row_en_i    ( wr_row_en         ),
    .wr_row_data_i  ( wr_row_data       ),
    .rd_data_o      ( elem_matrix_q     )
  );

  // Output assignment
  for(genvar ii=0; ii<NB_ELEMENTS; ii++) begin : gen_output
    assign data_out_unrolled[ii] =
        ctrl_i.transp_mode != TRANSP_NONE ? elem_matrix_q[ii][cnt_q]
      : im2col_unit                       ? im2col_data[ii]
      : ctrl_i.conv_stride == 2           ? data_in_unrolled[(ii < NB_ELEMENTS/2) ? 2*ii : 2*ii - NB_ELEMENTS]
                                          : data_in_unrolled[ii];
  end // gen_output

  assign data_in_ready  = ctrl_i.transp_mode != TRANSP_NONE ? fsm_q == WRITE :
                          im2col_unit ? im2col_ready : data_out_ready;
  assign data_out_valid = ctrl_i.transp_mode != TRANSP_NONE ? fsm_q == READ  :
                          im2col_unit ? im2col_valid : data_in_valid;

  // Sequential logic

  `FFARNC(fsm_q,        fsm_d,        clear_run, WRITE, clk_i, rst_ni)
  `FFARNC(cnt_q,        cnt_d,        clear_run, '0,    clk_i, rst_ni)
  `FFARNC(tot_cnt_q,    tot_cnt_d,    clear_run, '0,    clk_i, rst_ni)
  `FFARNC(inner_tile_q, inner_tile_d, clear_run, '0,    clk_i, rst_ni)
  `FFARNC(outer_tile_q, outer_tile_d, clear_run, '0,    clk_i, rst_ni)
  `FFARNC(pass_cnt_q,   pass_cnt_d,   clear_run, '0,    clk_i, rst_ni)

`ifndef SYNTHESIS
`ifndef VERILATOR
`ifndef VCS
  // Parameter assertions (elaboration-time checks)
  initial begin
    assert (BANDWIDTH_ALIGNED <= MAX_BANDWIDTH)
      else $fatal("BANDWIDTH_ALIGNED (%0d) must not be greater than MAX_BANDWIDTH (%0d)", BANDWIDTH_ALIGNED, MAX_BANDWIDTH);
    assert ((BANDWIDTH_ALIGNED % WORD_WIDTH) == 0)
      else $fatal("BANDWIDTH_ALIGNED (%0d) must be a multiple of WORD_WIDTH (%0d)", BANDWIDTH_ALIGNED, WORD_WIDTH);
    assert ((NB_ELEMENTS != 0) && ((NB_ELEMENTS & (NB_ELEMENTS - 1)) == 0))
      else $fatal("NB_ELEMENTS (%0d) = BANDWIDTH_ALIGNED (%0d) / ELEM_WIDTH (%0d) must be a power of two", NB_ELEMENTS, BANDWIDTH_ALIGNED, ELEM_WIDTH);
    assert (NUM_ELEM_WORD <= MAX_SHIFTING)
      else $fatal("NUM_ELEM_WORD (%0d) must not be greater than MAX_SHIFTING (%0d)", NUM_ELEM_WORD, MAX_SHIFTING);
  end

  // Runtime assertions
  assert property (@(posedge clk_i) disable iff (!rst_ni || $isunknown(ctrl_i.transp_len))
    ctrl_i.transp_len <= NB_ELEMENTS
  ) else $error("transp_len (%0d) exceeds NB_ELEMENTS (%0d) - cnt_q will never match FSM transition condition",
                ctrl_i.transp_len, NB_ELEMENTS);
`endif
`endif
`endif

endmodule // datamover_engine
