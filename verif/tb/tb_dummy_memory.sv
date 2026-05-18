// Copyright 2024-2026 ETH Zurich and University of Bologna.
// Licensed under the Solderpad Hardware License, Version 0.51.
// SPDX-License-Identifier: SHL-0.51
//
// Authors: Arpan Suravi Prasad <prasadar@iis.ee.ethz.ch>
//          Lionnus Kesting <lkesting@iis.ee.ethz.ch>
//
// Adapted from surya/rtl/verif/tb_dummy_memory.sv. The original assumed
// BANK_WORD_WIDTH was the natural storage element width (e.g. 32 bits).
// For the datamover standalone TB the datamover ports are WORD_WIDTH bits
// wide (e.g. 64) but $readmemh-loaded data is 32-bit-aligned (s19tomem.py
// writes one 32-bit hex token per line). Storage is therefore split off
// into a STORAGE_WIDTH parameter (defaults to BANK_WORD_WIDTH so existing
// callers are unchanged); when STORAGE_WIDTH < BANK_WORD_WIDTH each port
// access spans BANK_WORD_WIDTH/STORAGE_WIDTH consecutive storage entries
// with per-byte enables.

timeunit 1ps;
timeprecision 1ps;

module tb_dummy_memory
#(
  parameter MP                 = 1,
  parameter MEMORY_SIZE        = 1024,
  parameter BANK_WORD_WIDTH    = 32,
  parameter STORAGE_WIDTH      = BANK_WORD_WIDTH,
  parameter ELEMENT_WIDTH      = 8,
  parameter BASE_ADDR          = 0,
  parameter PROB_STALL         = 0.0,
  parameter TCP                = 1.0ns,
  parameter TA                 = 0.2ns,
  parameter TT                 = 0.8ns,
  localparam int unsigned N_STORAGE_PER_PORT = BANK_WORD_WIDTH / STORAGE_WIDTH,
  localparam int unsigned N_BYTES_PER_STORAGE = STORAGE_WIDTH / ELEMENT_WIDTH,
  localparam int unsigned ADDR_SHIFT = $clog2(N_BYTES_PER_STORAGE)
)
(
  input  logic                clk_i,
  input  logic                randomize_i,
  input  logic                enable_i,
  input  logic                stallable_i,
  hwpe_stream_intf_tcdm.slave tcdm [MP-1:0]
);

  initial begin
    if ((BANK_WORD_WIDTH % STORAGE_WIDTH) != 0)
      $fatal(1, "tb_dummy_memory: BANK_WORD_WIDTH (%0d) must be a multiple of STORAGE_WIDTH (%0d)",
             BANK_WORD_WIDTH, STORAGE_WIDTH);
  end

  logic [STORAGE_WIDTH-1:0] memory [MEMORY_SIZE];

  logic [MP-1:0]                          tcdm_req;
  logic [MP-1:0]                          tcdm_gnt;
  logic [MP-1:0][31:0]                    tcdm_add;
  logic [MP-1:0]                          tcdm_wen;
  logic [MP-1:0][BANK_WORD_WIDTH/8-1:0]   tcdm_be;
  logic [MP-1:0][BANK_WORD_WIDTH-1:0]     tcdm_data;
  logic [MP-1:0][BANK_WORD_WIDTH-1:0]     tcdm_r_data;
  logic [MP-1:0]                          tcdm_r_valid;
  logic [MP-1:0][BANK_WORD_WIDTH-1:0]     tcdm_r_data_int;
  logic [MP-1:0]                          tcdm_r_vld_int;

  real probs [MP-1:0];
  logic clk_delayed;

  always_ff @(posedge clk_i) begin : probs_proc
    for (int i = 0; i < MP; i++)
      probs[i] = real'($urandom_range(0, 1000)) / 1000.0;
  end

  generate
    for (genvar i = 0; i < MP; i++)
      assign tcdm_gnt[i] = (probs[i] < PROB_STALL) & stallable_i ? 1'b0 : 1'b1;

    for (genvar ii = 0; ii < MP; ii++) begin : binding_gen
      assign tcdm_req  [ii] = tcdm[ii].req;
      assign tcdm_add  [ii] = tcdm[ii].add;
      assign tcdm_wen  [ii] = tcdm[ii].wen;
      assign tcdm_be   [ii] = tcdm[ii].be;
      assign tcdm_data [ii] = tcdm[ii].data;
      assign tcdm[ii].gnt     = tcdm_gnt [ii] & tcdm_req [ii];
      assign tcdm[ii].r_data  = tcdm_r_data  [ii];
      assign tcdm[ii].r_valid = tcdm_r_valid [ii];
    end
  endgenerate

  always @(clk_i) clk_delayed <= #(TA) clk_i;

  // Per-port atomic access: each BANK_WORD_WIDTH-bit transaction touches
  // N_STORAGE_PER_PORT consecutive STORAGE_WIDTH-bit memory entries.
  always_ff @(posedge clk_i) begin : dummy_proc
    for (int i = 0; i < MP; i++) begin
      automatic int base_idx = (tcdm_add[i] - BASE_ADDR) >> ADDR_SHIFT;
      if ((tcdm_req[i] & enable_i) == 1'b0) begin
        tcdm_r_data_int[i] <= 'z;
        tcdm_r_vld_int [i] <= 1'b0;
      end
      else if (tcdm_gnt[i] & tcdm_wen[i]) begin
        // Read: assemble N_STORAGE_PER_PORT chunks from consecutive entries.
        for (int k = 0; k < N_STORAGE_PER_PORT; k++)
          tcdm_r_data_int[i][(k+1)*STORAGE_WIDTH-1 -: STORAGE_WIDTH] <= memory[base_idx + k];
        tcdm_r_vld_int[i] <= 1'b1;
      end
      else if (tcdm_gnt[i] & ~tcdm_wen[i]) begin
        // Write: byte-enable masked write across N_STORAGE_PER_PORT entries.
        for (int k = 0; k < N_STORAGE_PER_PORT; k++) begin
          for (int b = 0; b < N_BYTES_PER_STORAGE; b++) begin
            if (tcdm_be[i][k*N_BYTES_PER_STORAGE + b])
              memory[base_idx + k][b*ELEMENT_WIDTH +: ELEMENT_WIDTH] <=
                tcdm_data[i][(k*N_BYTES_PER_STORAGE + b)*ELEMENT_WIDTH +: ELEMENT_WIDTH];
          end
        end
        // Drive r_data with the merged value (writes that pass BE see new
        // bytes; writes masked off see old memory).
        for (int k = 0; k < N_STORAGE_PER_PORT; k++) begin
          for (int b = 0; b < N_BYTES_PER_STORAGE; b++) begin
            if (tcdm_be[i][k*N_BYTES_PER_STORAGE + b])
              tcdm_r_data_int[i][(k*N_BYTES_PER_STORAGE + b)*ELEMENT_WIDTH +: ELEMENT_WIDTH] <=
                tcdm_data[i][(k*N_BYTES_PER_STORAGE + b)*ELEMENT_WIDTH +: ELEMENT_WIDTH];
            else
              tcdm_r_data_int[i][(k*N_BYTES_PER_STORAGE + b)*ELEMENT_WIDTH +: ELEMENT_WIDTH] <=
                memory[base_idx + k][b*ELEMENT_WIDTH +: ELEMENT_WIDTH];
          end
        end
        tcdm_r_vld_int[i] <= 1'b1;
      end
      else begin
        tcdm_r_data_int[i] <= 'x;
        tcdm_r_vld_int [i] <= 1'b0;
      end
    end
  end

  if (TA == 0.0ns) begin
    assign tcdm_r_data  = tcdm_r_data_int;
    assign tcdm_r_valid = tcdm_r_vld_int;
  end else begin
    always_ff @(posedge clk_delayed) begin
      tcdm_r_data  <= tcdm_r_data_int;
      tcdm_r_valid <= tcdm_r_vld_int;
    end
  end

endmodule
