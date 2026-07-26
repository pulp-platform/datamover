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
 *           Lionnus Kesting <lkesting@iis.ee.ethz.ch>
 */

`include "common_cells/registers.svh"

module datamover_im2col_ctrl
  import datamover_package::*;
#(
  parameter int unsigned NB_ELEMENTS = 64,
  parameter int unsigned ELEM_WIDTH  = 8
) (
  input  logic                                   clk_i,
  input  logic                                   rst_ni,
  input  logic                                   clear_run_i,
  input  ctrl_engine_t                           ctrl_i,
  input  logic [NB_ELEMENTS-1:0][ELEM_WIDTH-1:0] data_in_unrolled_i,
  input  logic                                   data_in_valid_i,
  input  logic                                   data_in_ready_i,
  output logic [NB_ELEMENTS-1:0][ELEM_WIDTH-1:0] pack_extract_o,
  output logic                                   pack_wr_lo_o,
  output logic                                   pack_half_q_o,
  output logic [NB_ELEMENTS-1:0]                 pad_zero_o
);

  localparam int unsigned NB_ELEM_LOG2 = $clog2(NB_ELEMENTS);

  logic pack_accept, pack_wr_lo;
  logic pack_half_d, pack_half_q;
  logic [NB_ELEMENTS-1:0][ELEM_WIDTH-1:0] pack_extract;

  assign pack_accept = ctrl_i.im2col_pack & data_in_valid_i & data_in_ready_i;
  assign pack_wr_lo  = pack_accept & (pack_half_q == 1'b0);
  assign pack_half_d = pack_accept ? ~pack_half_q : pack_half_q;

  for(genvar ii=0; ii<NB_ELEMENTS; ii++) begin : gen_pack_extract
    if (ii < NB_ELEMENTS/2) begin : gen_valid
      logic [NB_ELEM_LOG2-1:0] pack_col, pack_row;
      assign pack_col = ii & ((32'd1 << ctrl_i.pack_log2w) - 32'd1);
      assign pack_row = ii >> ctrl_i.pack_log2w;
      assign pack_extract[ii] = data_in_unrolled_i[pack_row * ctrl_i.pack_row_stride
                                                  + pack_col * ctrl_i.conv_stride];
    end else begin : gen_zero
      assign pack_extract[ii] = '0;
    end
  end

  logic pad_beat;
  logic [11:0] pad_oh_base_d, pad_oh_base_q;
  logic [3:0]  pad_kw_d, pad_kw_q, pad_kh_d, pad_kh_q;
  logic [NB_ELEM_LOG2:0] pad_P;
  logic pad_oh_wrap, pad_kw_wrap, pad_kh_wrap;
  logic [3:0] pad_kw_next, pad_kh_next;
  logic [NB_ELEMENTS-1:0] pad_zero;
  logic [3:0] pad_kw_max, pad_kh_max;
  assign pad_kw_max = ctrl_i.pack_row_stride[3:0];
  assign pad_kh_max = ctrl_i.pack_row_stride[7:4];

  assign pad_beat    = ctrl_i.im2col_pad & data_in_valid_i & data_in_ready_i;
  assign pad_P       = NB_ELEMENTS >> ctrl_i.pack_log2w;
  assign pad_oh_wrap = (pad_oh_base_q + pad_P >= ctrl_i.tensor_size_m);
  assign pad_kw_wrap = (pad_kw_q == pad_kw_max - 1);
  assign pad_kh_wrap = (pad_kh_q == pad_kh_max - 1);
  assign pad_kw_next = pad_kw_wrap ? 4'd0 : pad_kw_q + 4'd1;
  assign pad_kh_next = pad_kh_wrap ? 4'd0 : pad_kh_q + 4'd1;

  assign pad_oh_base_d = pad_beat ? (pad_oh_wrap ? '0 : pad_oh_base_q + pad_P) : pad_oh_base_q;
  assign pad_kw_d      = (pad_beat & pad_oh_wrap)               ? pad_kw_next : pad_kw_q;
  assign pad_kh_d      = (pad_beat & pad_oh_wrap & pad_kw_wrap) ? pad_kh_next : pad_kh_q;

  for(genvar ii=0; ii<NB_ELEMENTS; ii++) begin : gen_pad_zero
    logic [11:0] pad_oh_ii;
    logic [NB_ELEM_LOG2-1:0] pad_col;
    logic pad_col_first, pad_col_last, pad_row_first, pad_row_last;
    assign pad_oh_ii = pad_oh_base_q + (ii >> ctrl_i.pack_log2w);
    assign pad_col = ii & ((32'd1 << ctrl_i.pack_log2w) - 32'd1);
    assign pad_col_first = (pad_col == 0);
    assign pad_col_last  = (pad_col == ((32'd1 << ctrl_i.pack_log2w) - 32'd1));
    assign pad_row_first = (pad_oh_ii == 12'd0);
    assign pad_row_last  = (pad_oh_ii == ctrl_i.tensor_size_m - 12'd1);
    assign pad_zero[ii] = (pad_kw_q == 4'd0           && pad_col_first) ||
                          (pad_kw_q == pad_kw_max - 1 && pad_col_last)  ||
                          (pad_kh_q == 4'd0           && pad_row_first) ||
                          (pad_kh_q == pad_kh_max - 1 && pad_row_last);
  end

  assign pack_extract_o = pack_extract;
  assign pack_wr_lo_o   = pack_wr_lo;
  assign pack_half_q_o  = pack_half_q;
  assign pad_zero_o     = pad_zero;

  `FFARNC(pack_half_q,   pack_half_d,   clear_run_i, 1'b0, clk_i, rst_ni)
  `FFARNC(pad_oh_base_q, pad_oh_base_d, clear_run_i, '0,   clk_i, rst_ni)
  `FFARNC(pad_kw_q,      pad_kw_d,      clear_run_i, '0,   clk_i, rst_ni)
  `FFARNC(pad_kh_q,      pad_kh_d,      clear_run_i, '0,   clk_i, rst_ni)

endmodule // datamover_im2col_ctrl
