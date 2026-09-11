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
 * Authors:  Lionnus Kesting <lkesting@iis.ee.ethz.ch>
 */

// im2col unit. Every output beat holds NB_ELEMENTS output pixels of one tap.
//
// conv_stride 1: the input is (C x pixels) in NB_ELEMENTS-pixel blocks with
// image rows of W pixels, W a power of two from 8 to NB_ELEMENTS. The unit
// keeps the previous and the current block row and reads the next one from
// the input stream. Per block row it emits the 9 taps of a 3x3 kernel with a
// 1-pixel zero border.
//
// conv_stride 2: every input beat gives NB_ELEMENTS/2 output pixels, the even
// input columns. Two beats merge into one output beat.

`include "common_cells/registers.svh"

module datamover_im2col
  import datamover_package::*;
#(
  parameter int unsigned NB_ELEMENTS = 64,
  parameter int unsigned ELEM_WIDTH  = 8
) (
  input  logic                                   clk_i,
  input  logic                                   rst_ni,
  input  logic                                   clear_i,
  input  ctrl_engine_t                           ctrl_i,
  input  logic [NB_ELEMENTS-1:0][ELEM_WIDTH-1:0] data_i,
  input  logic                                   valid_i,
  output logic                                   ready_o,
  output logic [NB_ELEMENTS-1:0][ELEM_WIDTH-1:0] data_o,
  output logic                                   valid_o,
  input  logic                                   ready_i
);

  localparam int unsigned NB_ELEM_LOG2 = $clog2(NB_ELEMENTS);
  localparam int unsigned LOG2W_MIN    = 3;
  localparam int unsigned NUM_W        = NB_ELEM_LOG2 - LOG2W_MIN + 1;

  typedef enum logic { PRIME, DRAIN } state_e;
  state_e state_d, state_q;

  logic [NB_ELEMENTS-1:0][ELEM_WIDTH-1:0] prev_d, prev_q, cur_d, cur_q;
  logic [NB_ELEMENTS-1:0][ELEM_WIDTH-1:0] up_row, dn_row, row_sel, tap, out_window, out_merge, out;
  logic [NB_ELEMENTS/2-1:0][ELEM_WIDTH-1:0] lo_d, lo_q;
  logic [NB_ELEMENTS+1:0][ELEM_WIDTH-1:0] row_pad;
  logic [NB_ELEMENTS-1:0]                 zero, first_col, last_col, top_row, bot_row;
  logic [IM2COL_LOG2W_WIDTH-1:0]          w_idx;
  logic [TENSOR_SIZE_WIDTH-1:0]           blk_d, blk_q, n_blocks;
  logic [1:0]                             kh_d, kh_q, kw_d, kw_q;
  logic                                   half_d, half_q, out_valid, out_free;
  logic                                   merge, first_blk, last_blk, last_tap, need_next;
  logic                                   drain_valid, out_load, prime_hs, shift, accept;

  assign merge     = (ctrl_i.conv_stride != 1);
  assign w_idx     = ctrl_i.im2col_log2w - LOG2W_MIN;
  assign n_blocks  = (ctrl_i.tensor_size_m << ctrl_i.im2col_log2w) >> NB_ELEM_LOG2;
  assign first_blk = (blk_q == '0);
  assign last_blk  = (blk_q == n_blocks - 1);
  assign last_tap  = (kh_q == 2) && (kw_q == 2);
  assign need_next = (kh_q == 2) && !last_blk;

  // Tap select: row by kh and W, then column by kw, then the zero border.
  for (genvar jj = 0; jj < NB_ELEMENTS; jj++) begin : gen_lane
    logic [NUM_W-1:0][ELEM_WIDTH-1:0] up_w, dn_w;
    logic [NUM_W-1:0]                 first_w, last_w, top_w, bot_w;
    for (genvar ll = 0; ll < NUM_W; ll++) begin : gen_width
      localparam int unsigned W  = 1 << (LOG2W_MIN + ll);
      localparam int unsigned Up = (jj >= W) ? jj - W : NB_ELEMENTS + jj - W;
      localparam int unsigned Dn = (jj + W < NB_ELEMENTS) ? jj + W : jj + W - NB_ELEMENTS;
      assign up_w[ll]    = (jj >= W) ? cur_q[Up] : prev_q[Up];
      assign dn_w[ll]    = (jj + W < NB_ELEMENTS) ? cur_q[Dn] : data_i[Dn];
      assign first_w[ll] = ((jj & (W - 1)) == 0);
      assign last_w[ll]  = ((jj & (W - 1)) == W - 1);
      assign top_w[ll]   = (jj < W);
      assign bot_w[ll]   = (jj >= NB_ELEMENTS - W);
    end
    assign up_row[jj]    = up_w[w_idx];
    assign dn_row[jj]    = dn_w[w_idx];
    assign first_col[jj] = first_w[w_idx];
    assign last_col[jj]  = last_w[w_idx];
    assign top_row[jj]   = top_w[w_idx];
    assign bot_row[jj]   = bot_w[w_idx];
    assign row_sel[jj]   = (kh_q == 0) ? up_row[jj] : (kh_q == 2) ? dn_row[jj] : cur_q[jj];
    assign row_pad[jj+1] = row_sel[jj];
    assign tap[jj]       = (kw_q == 0) ? row_pad[jj] : (kw_q == 2) ? row_pad[jj+2] : row_pad[jj+1];
    assign zero[jj]      = (kw_q == 0 && first_col[jj]) || (kw_q == 2 && last_col[jj]) ||
                           (kh_q == 0 && first_blk && top_row[jj]) ||
                           (kh_q == 2 && last_blk && bot_row[jj]);
    assign out_window[jj] = zero[jj] ? '0 : tap[jj];
  end
  assign row_pad[0]             = '0;
  assign row_pad[NB_ELEMENTS+1] = '0;

  for (genvar ii = 0; ii < NB_ELEMENTS / 2; ii++) begin : gen_merge
    assign lo_d[ii]                        = (accept && !half_q) ? data_i[2*ii] : lo_q[ii];
    assign out_merge[ii]                   = lo_q[ii];
    assign out_merge[ii + NB_ELEMENTS / 2] = data_i[2*ii];
  end

  // Handshakes
  assign accept      = merge && valid_i && out_free;
  assign drain_valid = !need_next || valid_i;
  assign out_load    = !merge && (state_q == DRAIN) && drain_valid && out_free;
  assign prime_hs    = !merge && (state_q == PRIME) && valid_i;
  assign shift       = out_load && last_tap;
  assign ready_o     = merge ? out_free : (state_q == PRIME) ? 1'b1 : (shift && !last_blk);

  assign state_d     = prime_hs ? DRAIN : (shift && last_blk) ? PRIME : state_q;
  assign cur_d       = (prime_hs || shift) ? data_i : cur_q;
  assign prev_d      = shift ? cur_q : prev_q;
  assign blk_d       = shift ? (last_blk ? '0 : blk_q + 1'b1) : blk_q;
  assign kw_d        = out_load ? ((kw_q == 2) ? '0 : kw_q + 1'b1) : kw_q;
  assign kh_d        = (out_load && kw_q == 2) ? ((kh_q == 2) ? '0 : kh_q + 1'b1) : kh_q;
  assign half_d      = accept ? ~half_q : half_q;
  assign out         = merge ? out_merge : out_window;
  assign out_valid   = merge ? (accept && half_q) : out_load;

  stream_register #(
    .T ( logic [NB_ELEMENTS-1:0][ELEM_WIDTH-1:0] )
  ) i_out_reg (
    .clk_i      ( clk_i     ),
    .rst_ni     ( rst_ni    ),
    .clr_i      ( clear_i   ),
    .testmode_i ( 1'b0      ),
    .valid_i    ( out_valid ),
    .ready_o    ( out_free  ),
    .data_i     ( out       ),
    .valid_o    ( valid_o   ),
    .ready_i    ( ready_i   ),
    .data_o     ( data_o    )
  );

  `FFARNC(state_q,     state_d,     clear_i, PRIME, clk_i, rst_ni)
  `FFARNC(blk_q,       blk_d,       clear_i, '0,    clk_i, rst_ni)
  `FFARNC(kh_q,        kh_d,        clear_i, '0,    clk_i, rst_ni)
  `FFARNC(kw_q,        kw_d,        clear_i, '0,    clk_i, rst_ni)
  `FFARNC(half_q,      half_d,      clear_i, 1'b0,  clk_i, rst_ni)
  `FFARNC(prev_q,      prev_d,      clear_i, '0,    clk_i, rst_ni)
  `FFARNC(cur_q,       cur_d,       clear_i, '0,    clk_i, rst_ni)
  `FFARNC(lo_q,        lo_d,        clear_i, '0,    clk_i, rst_ni)

endmodule // datamover_im2col
