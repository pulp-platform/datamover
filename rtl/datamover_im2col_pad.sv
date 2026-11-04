/*
 * Copyright (C) 2026 ETH Zurich and University of Bologna
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

// Zero border of the row-major im2col paths: the pass-through and the stride-2 merge.
//
// The source reads one segment of n beats per output row and kernel tap, in the order beat, output
// row, kernel column, kernel row, channel. The unit counts the same loops and zeroes the elements
// outside the image: a complete beat of a row above or below the image, the first lanes of the first
// beat, and the last lanes of the last beat. Without misaligned accesses, the source reads n + 1
// word-aligned beats per segment, and the unit shifts two consecutive beats by the start offset.
`include "common_cells/registers.svh"

module datamover_im2col_pad
  import datamover_pkg::*;
#(
  parameter int unsigned NumElems           = 64,
  parameter int unsigned ElemWidth          = 8,
  parameter int unsigned MisalignedAccesses = 1
) (
  input  logic                               clk_i,
  input  logic                               rst_ni,
  input  logic                               clear_i,
  input  ctrl_engine_t                       ctrl_i,
  input  logic [NumElems-1:0][ElemWidth-1:0] data_i,
  input  logic                               valid_i,
  output logic                               ready_o,
  output logic [NumElems-1:0][ElemWidth-1:0] data_o,
  output logic                               valid_o,
  input  logic                               ready_i
);

  localparam int unsigned NumElemsLog2 = $clog2(NumElems);
  // A segment holds up to 2 * 2**TensorSizeWidth elements.
  localparam int unsigned PosWidth     = TensorSizeWidth + 2;
  localparam int unsigned SegWidth     = PosWidth - NumElemsLog2;
  localparam logic [NumElems-1:0] StrbOne = {{(NumElems-1){1'b0}}, 1'b1};

  logic [NumElems-1:0][ElemWidth-1:0] base;
  logic [NumElems-1:0]                keep_d, keep_q;
  logic [SegWidth-1:0]                n_seg, r_d, r_q;
  logic [TensorSizeWidth-1:0]         oh_d, oh_q;
  logic [PadKernelWidth-1:0]          kw_d, kw_q, kh_d, kh_q;
  logic [PosWidth-1:0]                seg_len;
  logic                               active, half, out_hs, step;
  logic                               r_last, oh_last, kw_last, kh_last;

  // The merge and the pass-through read row-major images; the stride-1 unit reads the block layout.
  // The HAL sets the kernel fields only for a job with a border or a realignment.
  assign active  = (ctrl_i.datamover_mode == DATAMOVER_IM2COL) && !(ctrl_i.im2col_pack && ctrl_i.conv_stride == 1) &&
                   (ctrl_i.pad_kernel_w != '0);
  assign half    = (ctrl_i.conv_stride == 2);
  assign seg_len = (PosWidth'(ctrl_i.tensor_size_n) << half) + PosWidth'(NumElems - 1);
  assign n_seg   = SegWidth'(seg_len >> NumElemsLog2);
  assign out_hs  = valid_o && ready_i;
  assign step    = active && out_hs;

  // Loop counters
  assign r_last  = (r_q == n_seg - 1'b1);
  assign oh_last = (oh_q == ctrl_i.tensor_size_m - 1'b1);
  assign kw_last = (kw_q == ctrl_i.pad_kernel_w - 1'b1);
  assign kh_last = (kh_q == ctrl_i.pad_kernel_h - 1'b1);
  assign r_d     = step ? (r_last ? '0 : r_q + 1'b1) : r_q;
  assign oh_d    = (step && r_last) ? (oh_last ? '0 : oh_q + 1'b1) : oh_q;
  assign kw_d    = (step && r_last && oh_last) ? (kw_last ? '0 : kw_q + 1'b1) : kw_q;
  assign kh_d    = (step && r_last && oh_last && kw_last) ? (kh_last ? '0 : kh_q + 1'b1) : kh_q;

  // The lanes a beat keeps. A register holds the mask of the next beat, from the next loop counts,
  // so the mask logic does not reach the data path. The job registers settle two or more cycles
  // before the first beat of a job, because the source reads the TCDM first.
  function automatic logic [NumElems-1:0] keep_mask(logic [SegWidth-1:0]        r,
                                                    logic [TensorSizeWidth-1:0] oh,
                                                    logic [PadKernelWidth-1:0]  kw,
                                                    logic [PadKernelWidth-1:0]  kh);
    logic [TensorSizeWidth-1:0] oh_rev;
    logic [PadKernelWidth-1:0]  kw_rev, kh_rev;
    logic [PosWidth-1:0]        top_pos, bot_pos;
    logic [PadWidth-1:0]        left_n;
    logic [PadRightWidth-1:0]   right_n;
    logic                       row_zero, left_on, right_on;
    logic [NumElems-1:0]        keep_l, keep_r;
    // Rows: the image row is oh * stride + kh - pad_top. pad_bottom counts from the last row backwards.
    oh_rev   = ctrl_i.tensor_size_m - 1'b1 - oh;
    kh_rev   = ctrl_i.pad_kernel_h - 1'b1 - kh;
    kw_rev   = ctrl_i.pad_kernel_w - 1'b1 - kw;
    top_pos  = (PosWidth'(oh) << half) + PosWidth'(kh);
    bot_pos  = (PosWidth'(oh_rev) << half) + PosWidth'(kh_rev);
    row_zero = (top_pos < PosWidth'(ctrl_i.pad_top)) || (bot_pos < PosWidth'(ctrl_i.pad_bottom));
    // Columns: the first beat starts pad_left - kw lanes left of the image. The last beat ends
    // pad_right - (Kw - 1 - kw) lanes right of it.
    left_on  = (r == '0) && (PadKernelWidth'(ctrl_i.pad_left) > kw);
    left_n   = ctrl_i.pad_left - PadWidth'(kw);
    right_on = (r == n_seg - 1'b1) && (ctrl_i.pad_right > PadRightWidth'(kw_rev));
    right_n  = ctrl_i.pad_right - PadRightWidth'(kw_rev);
    keep_l   = left_on  ? ~((StrbOne << left_n) - 1'b1) : '1;
    keep_r   = right_on ? ((StrbOne << (NumElems - right_n)) - 1'b1) : '1;
    return !active ? '1 : row_zero ? '0 : (keep_l & keep_r);
  endfunction

  always_comb keep_d = keep_mask(r_d, oh_d, kw_d, kh_d);

  for (genvar jj = 0; jj < NumElems; jj++) begin : gen_lane
    assign data_o[jj] = keep_q[jj] ? base[jj] : '0;
  end

  if (MisalignedAccesses == 0) begin : gen_realign
    // The source reads word-aligned beats from pad_shift elements before the kernel column 0.
    logic [NumElems-1:0][ElemWidth-1:0]   prev_d, prev_q;
    logic [2*NumElems-1:0][ElemWidth-1:0] win, win_sh;
    logic [NumElemsLog2-1:0]              sh;
    logic                                 realign, first, have_d, have_q;

    assign realign = active && ((ctrl_i.pad_kernel_w > 1) || (ctrl_i.pad_shift != '0));
    assign first   = realign && !have_q;
    assign sh      = NumElemsLog2'(ctrl_i.pad_shift) + NumElemsLog2'(kw_q);
    assign win     = {data_i, prev_q};
    assign win_sh  = win >> (ElemWidth * sh);
    assign base    = realign ? win_sh[NumElems-1:0] : data_i;
    assign ready_o = first || ready_i;
    assign valid_o = valid_i && !first;
    assign prev_d  = (realign && valid_i && ready_o) ? data_i : prev_q;
    assign have_d  = (valid_i && first) ? 1'b1 : (out_hs && r_last) ? 1'b0 : have_q;

    `FFARNC(prev_q, prev_d, clear_i, '0,   clk_i, rst_ni)
    `FFARNC(have_q, have_d, clear_i, 1'b0, clk_i, rst_ni)
  end else begin : gen_no_realign
    assign base    = data_i;
    assign ready_o = ready_i;
    assign valid_o = valid_i;
  end

  `FFARNC(r_q,  r_d,  clear_i, '0, clk_i, rst_ni)
  `FF(keep_q, keep_d, '1, clk_i, rst_ni)
  `FFARNC(oh_q, oh_d, clear_i, '0, clk_i, rst_ni)
  `FFARNC(kw_q, kw_d, clear_i, '0, clk_i, rst_ni)
  `FFARNC(kh_q, kh_d, clear_i, '0, clk_i, rst_ni)

endmodule // datamover_im2col_pad
