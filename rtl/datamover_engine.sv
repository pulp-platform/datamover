/*
 * Copyright (C) 2025 ETH Zurich and University of Bologna
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

module datamover_engine
  import hwpe_stream_package::*;
  import hci_package::*;
  import datamover_package::*;
#(
  parameter int unsigned FIFO_DEPTH = 2,
  parameter int unsigned BW_ALIGNED = 32
) (
  // global signals
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   test_mode_i,
  // local enable & clear
  input  logic                   enable_i,
  input  logic                   clear_i,
  // FIXME make it ctrl
  input  ctrl_engine_t           ctrl_i,
  // input data stream + handshake
  hwpe_stream_intf_stream.sink   data_in,
  // output data stream + handshake
  hwpe_stream_intf_stream.source data_out
);

  localparam NB_BYTES = BW_ALIGNED / 8;

  // Type def and internal signals
  typedef enum logic { WRITE, READ } datamover_engine_fsm_t;
  datamover_engine_fsm_t fsm_d, fsm_q;
  logic clear_bytes_matrix;
  logic [$clog2(NB_BYTES):0] cnt_q, cnt_d;
  logic cnt_en;
  logic [NB_BYTES-1:0][7:0] data_in_unrolled;
  logic                     data_in_valid;
  logic                     data_in_ready;
  logic [NB_BYTES-1:0][7:0] data_out_unrolled;
  logic                     data_out_valid;
  logic                     data_out_ready;
  
  // FSM: WRITE -> READ on input handshake at end of write, READ -> WRITE on output handshake at end of read
  always_comb
  begin
    fsm_d = fsm_q;
    case (fsm_q)
      WRITE: begin
        if ((cnt_q == ctrl_i.transp_len-ctrl_i.transp_stride) && (data_in_valid & data_in_ready)) begin
          fsm_d = READ;
        end
      end
      READ: begin
        if ((cnt_q == ctrl_i.transp_len-ctrl_i.transp_stride) && (data_out_valid & data_out_ready)) begin
          fsm_d = WRITE;
        end
      end
      default: begin
        fsm_d = WRITE;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      fsm_q <= WRITE;
    end else if (clear_i) begin
      fsm_q <= WRITE;
    end else begin
      fsm_q <= fsm_d;
    end
  end

  assign clear_bytes_matrix = (fsm_q == READ && fsm_d == WRITE) ? 1'b1 : 1'b0;

  // internal interfaces and unrolling
  hwpe_stream_intf_stream #(
    .DATA_WIDTH (BW_ALIGNED )
  ) data_in_postfifo (
    .clk ( clk_i )
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH (BW_ALIGNED )
  ) data_out_prefifo (
    .clk ( clk_i )
  );

  // decouple in/out with FIFOs
  hwpe_stream_fifo #(
    .DATA_WIDTH ( BW_ALIGNED ),
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
    .DATA_WIDTH ( BW_ALIGNED ),
    .FIFO_DEPTH ( FIFO_DEPTH )
  ) i_fifo_out (
    .clk_i   ( clk_i            ),
    .rst_ni  ( rst_ni           ),
    .clear_i ( clear_i          ),
    .flags_o (                  ),
    .push_i  ( data_out_prefifo ),
    .pop_o   ( data_out         )
  );
  assign data_out_prefifo.strb = '1; // FIXME for leftovers
  assign data_out_prefifo.data = data_out_unrolled;
  assign data_out_prefifo.valid = data_out_valid;
  assign data_out_ready = data_out_prefifo.ready;

  // Write counter
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if (~rst_ni) begin
      cnt_q <= '0;
    end
    else if(clear_i) begin
      cnt_q <= '0;
    end
    else if(cnt_en) begin
      cnt_q <= cnt_d;
    end
  end
  assign cnt_d = cnt_q < ctrl_i.transp_len-ctrl_i.transp_stride ? cnt_q+ctrl_i.transp_stride : '0;
  assign cnt_en = fsm_q == WRITE ? data_in_valid & data_in_ready : data_out_valid & data_out_ready;

  // "Smart shifting": this set of combinational blocks shifts data_in_unrolled
  // appropriately, depending on the configuration (8b transpose, 16b transpose,
  // 32b transpose). We assume that transposes >= 64b can be done efficiently
  // by Snitch processors through SSRs and those <8b are not interesting in our
  // use case.
  localparam MAX_SHIFTING = 4; // in bytes, 4 for 32b transpose (includes shifting by 0 bytes)
  logic [MAX_SHIFTING-1:0][NB_BYTES-1:0][7:0] data_in_shifted;
  
  for(genvar ii=0; ii<MAX_SHIFTING; ii++) begin : gen_data_shifting_x
    for(genvar jj=0; jj<NB_BYTES; jj++) begin : gen_data_shifting_y

      if(ii+jj < NB_BYTES) begin : gen_feasible_shiftings
        assign data_in_shifted[ii][jj] = data_in_unrolled[ii+jj];
      end
      else begin : gen_unfeasible_shiftings
        assign data_in_shifted[ii][jj] = '0;
      end

    end // gen_data_shifting_y
  end // gen_data_shifting_x

  // Buffering matrix: this 2D array of bytes is used to buffer values to transpose.
  logic [NB_BYTES-1:0][NB_BYTES-1:0][7:0] bytes_matrix_q;
  for(genvar ii=0; ii<NB_BYTES; ii++) begin : gen_bytes_matrix_x

    // enable buffer rows that are aligned with counter in groups of four (in 32b mode),
    // of two (in 16b mode) or single rows (in 8b mode).
    logic buffer_enable;
    assign buffer_enable = ctrl_i.transp_mode == TRANSP_32B ? ((cnt_q >> 2) == (ii >> 2)) & data_in_valid & data_in_ready :
                           ctrl_i.transp_mode == TRANSP_16B ? ((cnt_q >> 1) == (ii >> 1)) & data_in_valid & data_in_ready :
                                                              ( cnt_q       ==  ii      ) & data_in_valid & data_in_ready;
    // select appropriately shifted rows
    logic [NB_BYTES-1:0][7:0] data_in_selected;
    assign data_in_selected = ctrl_i.transp_mode == TRANSP_32B ? data_in_shifted[ii % 4] :
                              ctrl_i.transp_mode == TRANSP_16B ? data_in_shifted[ii % 2] : 
                                                                 data_in_shifted[0];

    for(genvar jj=0; jj<NB_BYTES; jj++) begin : gen_bytes_matrix_y

      logic clear_int;
      assign clear_int = clear_i | clear_bytes_matrix;

      always_ff @(posedge clk_i or negedge rst_ni)
      begin
        if (~rst_ni) begin
          bytes_matrix_q[ii][jj] <= '0;
        end
        else if(clear_int) begin
          bytes_matrix_q[ii][jj] <= '0;
        end
        else if(buffer_enable) begin
          bytes_matrix_q[ii][jj] <= data_in_selected[jj];
        end
      end

    end // gen_bytes_matrix_y
  end // gen_bytes_matrix_x

  // Output assignment
  for(genvar ii=0; ii<NB_BYTES; ii++) begin : gen_output
    assign data_out_unrolled[ii] = bytes_matrix_q[ii][cnt_q];
  end // gen_output

  // Input ready & output valid generation
  assign data_in_ready  = fsm_q == WRITE;
  assign data_out_valid = fsm_q == READ;

`ifndef SYNTHESIS
`ifndef VERILATOR
`ifndef VCS
  initial begin
    assert (BW_ALIGNED <= MAX_BW)
      else $fatal("BW_ALIGNED (%0d) must not be greater than MAX_BW (%0d)", BW_ALIGNED, MAX_BW);
    assert ((BW_ALIGNED % 32) == 0)
      else $fatal("BW_ALIGNED (%0d) must be a multiple of 32", BW_ALIGNED);
  end
`endif
`endif
`endif

endmodule // datamover_engine
