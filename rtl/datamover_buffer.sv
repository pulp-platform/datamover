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

module datamover_buffer
#(
  parameter int unsigned NB_ELEMENTS = 64,
  parameter int unsigned ELEM_WIDTH  = 8
) (
  input  logic                                    clk_i,
  input  logic                                    rst_ni,
  input  logic                                    clear_i,
  input  logic                                    clear_matrix_i,
  input  logic [NB_ELEMENTS-1:0]                  wr_row_en_i,
  input  logic [NB_ELEMENTS-1:0][ELEM_WIDTH-1:0]  wr_row_data_i [NB_ELEMENTS-1:0],
  output logic [NB_ELEMENTS-1:0][ELEM_WIDTH-1:0]  rd_data_o     [NB_ELEMENTS-1:0]
);

  logic [NB_ELEMENTS-1:0][ELEM_WIDTH-1:0] elem_matrix_d [NB_ELEMENTS-1:0], elem_matrix_q [NB_ELEMENTS-1:0];
  logic clear_int;
  assign clear_int = clear_i | clear_matrix_i;

  for(genvar ii=0; ii<NB_ELEMENTS; ii++) begin : gen_elem_matrix_x
    for(genvar jj=0; jj<NB_ELEMENTS; jj++) begin : gen_elem_matrix_y
      assign elem_matrix_d[ii][jj] = wr_row_en_i[ii] ? wr_row_data_i[ii][jj]
                                                      : elem_matrix_q[ii][jj];
    end // gen_elem_matrix_y
  end // gen_elem_matrix_x

  assign rd_data_o = elem_matrix_q;

  for(genvar ii=0; ii<NB_ELEMENTS; ii++) begin : gen_elem_matrix_ff_x
    for(genvar jj=0; jj<NB_ELEMENTS; jj++) begin : gen_elem_matrix_ff_y
      `FFARNC(elem_matrix_q[ii][jj], elem_matrix_d[ii][jj], clear_int, '0, clk_i, rst_ni)
    end // gen_elem_matrix_ff_y
  end // gen_elem_matrix_ff_x

endmodule // datamover_buffer
