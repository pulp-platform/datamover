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

// im2col unit. Every output beat holds NumElems output pixels of one tap.
//
// conv_stride 1: the input is (C x pixels) in NumElems-pixel blocks with image rows of W pixels,
// W a power of two from 2**Im2colMinLog2W to NumElems. The unit keeps Im2colKernel/2 previous
// blocks, the current block, and Im2colKernel/2 - 1 next blocks, and it reads the last next block
// from the input stream. For a kernel side K, 3 or 5, it emits K*K taps per block with a zero
// border of K/2 pixels.
//
// conv_stride 2: every input beat gives NumElems/2 output pixels, the even input columns. Two
// beats merge into one output beat.
`include "common_cells/registers.svh"

module datamover_im2col
  import datamover_pkg::*;
#(
  parameter int unsigned NumElems       = 64,
  parameter int unsigned ElemWidth      = 8,
  parameter int unsigned Im2colKernel   = 3,  // largest kernel side, 3 or 5
  parameter int unsigned Im2colMinLog2W = 3   // log2 of the smallest image row width
) (
  input  logic                                   clk_i,
  input  logic                                   rst_ni,
  input  logic                                   clear_i,
  input  ctrl_engine_t                           ctrl_i,
  input  logic [NumElems-1:0][ElemWidth-1:0] data_i,
  input  logic                                   valid_i,
  output logic                                   ready_o,
  output logic [NumElems-1:0][ElemWidth-1:0] data_o,
  output logic                                   valid_o,
  input  logic                                   ready_i
);

  localparam int unsigned NumElemsLog2 = $clog2(NumElems);
  localparam int unsigned NumW         = NumElemsLog2 - Im2colMinLog2W + 1;
  // The taps reach Reach rows and columns. The unit keeps Reach past blocks, the current block,
  // and Reach - 1 future blocks, and it reads the next future block from the input.
  localparam int unsigned Reach        = (Im2colKernel - 1) / 2;
  localparam int unsigned NumOffs      = 2 * Reach + 1;
  localparam int unsigned NumFut       = (Reach > 1) ? Reach - 1 : 1;
  localparam int unsigned TapWidth     = $clog2(NumOffs);
  localparam int unsigned CntWidth     = TensorSizeWidth + NumElemsLog2;

  typedef enum logic { PRIME, DRAIN } state_e;
  state_e state_d, state_q;

  logic [Reach-1:0][NumElems-1:0][ElemWidth-1:0]   past_d, past_q;
  logic [NumFut-1:0][NumElems-1:0][ElemWidth-1:0]  fut_d, fut_q;
  logic [NumElems-1:0][ElemWidth-1:0]              cur_d, cur_q;
  logic [NumOffs-1:0][NumElems-1:0][ElemWidth-1:0] win;
  logic [NumElems-1:0][ElemWidth-1:0]              row_sel, tap, out_window, out_merge, out;
  logic [NumElems/2-1:0][ElemWidth-1:0]            lo_d, lo_q;
  logic [NumElems+2*Reach-1:0][ElemWidth-1:0]      row_pad;
  logic [NumElems-1:0]                             zero;
  logic [Reach:1]                                  near_start, near_end;
  logic [Im2colLog2wWidth-1:0]                     w_idx;
  logic [TensorSizeWidth-1:0]                      blk_d, blk_q, n_blocks;
  logic [CntWidth-1:0]                             n_pixels;
  logic [TapWidth-1:0]                             kh_d, kh_q, kw_d, kw_q, k_last, row_idx, col_idx;
  logic [TapWidth-1:0]                             prime_cnt_d, prime_cnt_q;
  logic [1:0]                                      reach;
  logic                                            half_d, half_q, out_valid, out_free;
  logic                                            merge, last_blk, last_tap, need_next, prime_last;
  logic                                            drain_valid, out_load, prime_hs, shift, accept;

  // A kernel of 3 on a 5x5 unit uses the inner taps of the window.
  if (Reach > 1) begin : gen_reach_runtime
    assign reach = (ctrl_i.im2col_kernel == 5) ? 2'd2 : 2'd1;
  end else begin : gen_reach_fixed
    assign reach = 2'd1;
  end

  assign merge     = (ctrl_i.conv_stride != 1);
  assign w_idx     = ctrl_i.im2col_log2w - Im2colMinLog2W;
  assign n_pixels  = CntWidth'(ctrl_i.tensor_size_m) << ctrl_i.im2col_log2w;
  assign n_blocks  = TensorSizeWidth'(n_pixels >> NumElemsLog2);
  assign last_blk  = (blk_q == n_blocks - 1);
  assign k_last    = TapWidth'(2 * reach);
  assign row_idx   = kh_q + TapWidth'(Reach - reach);
  assign col_idx   = kw_q + TapWidth'(Reach - reach);
  assign last_tap  = (kh_q == k_last) && (kw_q == k_last);
  // The last tap waits for the next block too: the shift stores it even when the kernel is smaller.
  assign need_next = ((row_idx == TapWidth'(2 * Reach)) || last_tap) && !near_end[Reach];

  for (genvar r = 1; r <= Reach; r++) begin : gen_near
    assign near_start[r] = (blk_q < r);
    assign near_end[r]   = (CntWidth'(blk_q) + r >= CntWidth'(n_blocks));
  end

  // The window of blocks around the current block: win[Reach + s] is block blk + s.
  for (genvar s = 0; s < NumOffs; s++) begin : gen_win
    if (s < Reach) begin : gen_past
      assign win[s] = past_q[Reach - 1 - s];
    end else if (s == Reach) begin : gen_cur
      assign win[s] = cur_q;
    end else if (s < 2 * Reach) begin : gen_future
      assign win[s] = fut_q[s - Reach - 1];
    end else begin : gen_next
      assign win[s] = data_i;
    end
  end

  // Tap select: row by the row offset and W, then column by the column offset, then the zero border.
  for (genvar jj = 0; jj < NumElems; jj++) begin : gen_lane
    logic [NumW-1:0][NumOffs-1:0][ElemWidth-1:0] row_w;
    logic [NumW-1:0][NumOffs-1:0]                row_zero_w, col_zero_w;
    for (genvar ll = 0; ll < NumW; ll++) begin : gen_width
      localparam int W = 1 << (Im2colMinLog2W + ll);
      for (genvar dd = 0; dd < NumOffs; dd++) begin : gen_offset
        localparam int Pos = jj + (dd - int'(Reach)) * W;
        localparam int Blk = Pos >>> NumElemsLog2;
        localparam int Idx = Pos & (NumElems - 1);
        localparam int Col = (jj & (W - 1)) + dd - int'(Reach);
        assign row_w[ll][dd] = win[int'(Reach) + Blk][Idx];
        if (Blk < 0) begin : gen_above
          assign row_zero_w[ll][dd] = near_start[-Blk];
        end else if (Blk > 0) begin : gen_below
          assign row_zero_w[ll][dd] = near_end[Blk];
        end else begin : gen_inside
          assign row_zero_w[ll][dd] = 1'b0;
        end
        assign col_zero_w[ll][dd] = (Col < 0) || (Col >= W);
      end
    end
    assign row_sel[jj]         = row_w[w_idx][row_idx];
    assign row_pad[jj + Reach] = row_sel[jj];
    assign tap[jj]             = row_pad[jj + col_idx];
    assign zero[jj]            = row_zero_w[w_idx][row_idx] || col_zero_w[w_idx][col_idx];
    assign out_window[jj]      = zero[jj] ? '0 : tap[jj];
  end
  for (genvar pp = 0; pp < Reach; pp++) begin : gen_pad
    assign row_pad[pp]                    = '0;
    assign row_pad[NumElems + Reach + pp] = '0;
  end

  for (genvar ii = 0; ii < NumElems / 2; ii++) begin : gen_merge
    assign lo_d[ii]                     = (accept && !half_q) ? data_i[2*ii] : lo_q[ii];
    assign out_merge[ii]                = lo_q[ii];
    assign out_merge[ii + NumElems / 2] = data_i[2*ii];
  end

  // Handshakes
  assign accept      = merge && valid_i && out_free;
  assign drain_valid = !need_next || valid_i;
  assign out_load    = !merge && (state_q == DRAIN) && drain_valid && out_free;
  assign prime_hs    = !merge && (state_q == PRIME) && valid_i;
  assign shift       = out_load && last_tap;
  assign ready_o     = merge ? out_free : (state_q == PRIME) ? 1'b1 : (shift && !near_end[Reach]);

  // Priming loads the current block and the future blocks that exist, then the unit drains.
  assign prime_last  = (prime_cnt_q == TapWidth'(Reach - 1)) || (TensorSizeWidth'(prime_cnt_q) == n_blocks - 1);
  assign prime_cnt_d = prime_hs ? (prime_last ? '0 : prime_cnt_q + 1'b1) : prime_cnt_q;
  assign state_d     = (prime_hs && prime_last) ? DRAIN : (shift && last_blk) ? PRIME : state_q;
  assign blk_d       = shift ? (last_blk ? '0 : blk_q + 1'b1) : blk_q;
  assign kw_d        = out_load ? ((kw_q == k_last) ? '0 : kw_q + 1'b1) : kw_q;
  assign kh_d        = (out_load && kw_q == k_last) ? ((kh_q == k_last) ? '0 : kh_q + 1'b1) : kh_q;
  assign half_d      = accept ? ~half_q : half_q;
  assign out         = merge ? out_merge : out_window;
  assign out_valid   = merge ? (accept && half_q) : out_load;

  // The history shifts by one block at the last tap.
  for (genvar pp = 0; pp < Reach; pp++) begin : gen_past_shift
    if (pp == 0) begin : gen_first
      assign past_d[pp] = shift ? cur_q : past_q[pp];
    end else begin : gen_rest
      assign past_d[pp] = shift ? past_q[pp - 1] : past_q[pp];
    end
  end

  if (Reach > 1) begin : gen_future_blocks
    assign cur_d = (prime_hs && prime_cnt_q == '0) ? data_i : shift ? fut_q[0] : cur_q;
    for (genvar ff = 0; ff < NumFut; ff++) begin : gen_fut
      assign fut_d[ff] = (prime_hs && prime_cnt_q == TapWidth'(ff + 1)) ? data_i    :
                         !shift                                         ? fut_q[ff] :
                         (ff == NumFut - 1)                             ? data_i    :
                                                                          fut_q[ff + 1];
    end
  end else begin : gen_no_future_blocks
    assign cur_d = (prime_hs || shift) ? data_i : cur_q;
    assign fut_d = '0;
  end

  stream_register #(
    .T ( logic [NumElems-1:0][ElemWidth-1:0] )
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
  `FFARNC(prime_cnt_q, prime_cnt_d, clear_i, '0,    clk_i, rst_ni)
  `FFARNC(half_q,      half_d,      clear_i, 1'b0,  clk_i, rst_ni)
  `FFARNC(past_q,      past_d,      clear_i, '0,    clk_i, rst_ni)
  `FFARNC(cur_q,       cur_d,       clear_i, '0,    clk_i, rst_ni)
  `FFARNC(fut_q,       fut_d,       clear_i, '0,    clk_i, rst_ni)
  `FFARNC(lo_q,        lo_d,        clear_i, '0,    clk_i, rst_ni)

endmodule // datamover_im2col
