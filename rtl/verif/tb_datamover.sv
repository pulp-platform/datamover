// Copyright 2025-2026 ETH Zurich and University of Bologna.
//
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51.
//
// SPDX-License-Identifier: SHL-0.51
//
// Authors: Lionnus Kesting <lkesting@iis.ee.ethz.ch>
//          Cyrill Durrer <cdurrer@iis.ee.ethz.ch>

timeunit 1ps;
timeprecision 1ps;

module tb_datamover;
  import datamover_package::*;
  import hwpe_ctrl_package::*;
  import hci_package::*;
  import ibex_pkg::*;

`ifndef BANDWIDTH
  `define BANDWIDTH 512
`endif
`ifndef WORD_WIDTH
  `define WORD_WIDTH 64
`endif
`ifndef ELEM_WIDTH
  `define ELEM_WIDTH 8
`endif
`ifndef MISALIGNED_ACCESSES
  `define MISALIGNED_ACCESSES 1
`endif
`ifndef PROB_STALL
  `define PROB_STALL 0.0
`endif

  localparam int unsigned BANDWIDTH           = `BANDWIDTH;
  localparam int unsigned WORD_WIDTH          = `WORD_WIDTH;
  localparam int unsigned ELEM_WIDTH          = `ELEM_WIDTH;
  localparam int unsigned MISALIGNED_ACCESSES = `MISALIGNED_ACCESSES;
  localparam real         PROB_STALL          = `PROB_STALL;
  localparam int unsigned NUM_ELEM_WORD       = WORD_WIDTH / ELEM_WIDTH;
  localparam int unsigned NUM_WORDS           = BANDWIDTH / WORD_WIDTH;

  // The Ibex data port is 32-bit. tb_dummy_memory uses WORD_WIDTH-wide banks
  // natively; an aligner places the Ibex's 32-bit data into the right slice
  // of the wide bus. WORD_WIDTH must be a multiple of 32.
  localparam int unsigned NUM_SLOTS  = WORD_WIDTH / 32;
  localparam int unsigned SLOT_BITS  = (NUM_SLOTS <= 1) ? 1 : $clog2(NUM_SLOTS);
  localparam int unsigned ALIGN_BITS = $clog2(WORD_WIDTH / 8);
  // Total number of WORD_WIDTH-wide TCDM ports: datamover footprint + Ibex.
  localparam int unsigned MP = NUM_WORDS + 1;

  // Must match sw/link.ld and sw/s19tomem.py. tb_dummy_memory storage is
  // 32-bit-wide regardless of bank port width, so MEMORY_SIZE counts 32-bit
  // entries (1.5 MB / 4).
  localparam int unsigned INSTR_MEM_SIZE = 16  * 1024;
  localparam int unsigned MEMORY_SIZE    = 384 * 1024;

  localparam logic [31:0] INSTR_BASE_ADDR = 32'h1c000000;
  localparam logic [31:0] TCDM_DATA_BASE  = 32'h1c010000;

  // Address decode by upper byte: avoids overlap between HWPE/MBOX and TCDM data.
  localparam logic [7:0] HWPE_REGION_MSB    = 8'h10;
  localparam logic [7:0] TCDM_REGION_MSB    = 8'h1c;
  localparam logic [7:0] TB_MBOX_REGION_MSB = 8'h80;

  localparam logic [31:0] TB_MBOX_BASE_ADDR        = 32'h80000000;
  localparam logic [31:0] TB_MBOX_ERRORS_ADDR      = TB_MBOX_BASE_ADDR + 32'h0;
  localparam logic [31:0] TB_MBOX_PUTC_ADDR        = TB_MBOX_BASE_ADDR + 32'h4;
  localparam logic [31:0] TB_MBOX_CYCLES_ADDR      = TB_MBOX_BASE_ADDR + 32'h8;
  localparam logic [31:0] TB_MBOX_VERIFY_PTR_ADDR  = TB_MBOX_BASE_ADDR + 32'h10;
  localparam logic [31:0] TB_MBOX_VERIFY_GOLD_ADDR = TB_MBOX_BASE_ADDR + 32'h18;
  localparam logic [31:0] TB_MBOX_VERIFY_SIZE_ADDR = TB_MBOX_BASE_ADDR + 32'h20;

  localparam string STIM_INSTR = "./stim_instr.txt";
  localparam string STIM_DATA  = "./stim_data.txt";

  localparam TCP = 1.0ns;
  localparam TA  = 0.2ns;
  localparam TT  = 0.8ns;

  initial begin
    if (WORD_WIDTH < 32 || (WORD_WIDTH % 32) != 0)
      $fatal(1, "tb_datamover: WORD_WIDTH (%0d) must be a multiple of 32 >= 32", WORD_WIDTH);
  end

  logic clk_i  = '0;
  logic rst_ni = '1;
  logic test_mode_i = '0;
  logic fetch_enable = 1'b0;

  // 32-bit-wide instruction port; WORD_WIDTH-wide TCDM ports for both the
  // datamover footprint and the Ibex (via aligner).
  hwpe_stream_intf_tcdm #(.DATA_WIDTH(32), .ELEMENT_WIDTH(ELEM_WIDTH))
    instr [0:0] (.clk(clk_i));
  hwpe_stream_intf_tcdm #(.DATA_WIDTH(WORD_WIDTH), .ELEMENT_WIDTH(ELEM_WIDTH))
    tcdm [MP-1:0] (.clk(clk_i));

  logic [NUM_WORDS-1:0]                    dm_tcdm_req;
  logic [NUM_WORDS-1:0]                    dm_tcdm_gnt;
  logic [NUM_WORDS-1:0][31:0]              dm_tcdm_add;
  logic [NUM_WORDS-1:0]                    dm_tcdm_wen;
  logic [NUM_WORDS-1:0][NUM_ELEM_WORD-1:0] dm_tcdm_be;
  logic [NUM_WORDS-1:0][WORD_WIDTH-1:0]    dm_tcdm_data;
  logic [NUM_WORDS-1:0][WORD_WIDTH-1:0]    dm_tcdm_r_data;
  logic [NUM_WORDS-1:0]                    dm_tcdm_r_valid;

  logic        periph_req;
  logic        periph_gnt;
  logic [31:0] periph_add;
  logic        periph_wen;
  logic [3:0]  periph_be;
  logic [31:0] periph_data;
  logic [9:0]  periph_id;
  logic [31:0] periph_r_data;
  logic        periph_r_valid;
  logic [9:0]  periph_r_id;

  logic [7:0][hwpe_ctrl_package::REGFILE_N_EVT-1:0] evt_unused;

  logic        instr_req, instr_gnt, instr_rvalid;
  logic [31:0] instr_addr, instr_rdata;

  logic        data_req, data_gnt, data_rvalid;
  logic        data_we;
  logic [3:0]  data_be;
  logic [31:0] data_addr, data_wdata, data_rdata;
  logic        data_err;
  logic        core_sleep_o;
  assign data_err = 1'b0;

  task cycle;
    clk_i <= #(TCP/2) 0;
    clk_i <= #TCP 1;
    #TCP;
  endtask

  wire is_periph_req = (data_addr[31:24] == HWPE_REGION_MSB);
  wire is_mbox_req   = (data_addr[31:24] == TB_MBOX_REGION_MSB);
  wire is_tcdm_req   = (data_addr[31:24] == TCDM_REGION_MSB);

  always_comb begin : bind_periph
    periph_req  = data_req & is_periph_req;
    periph_add  = data_addr;
    periph_wen  = ~data_we;
    periph_be   = data_be;
    periph_data = data_wdata;
    periph_id   = '0;
  end

  always_comb begin : bind_instrs
    instr[0].req  = instr_req;
    instr[0].add  = instr_addr;
    instr[0].wen  = 1'b1;
    instr[0].be   = '0;
    instr[0].data = '0;
    instr_gnt    = instr[0].gnt;
    instr_rdata  = instr[0].r_data;
    instr_rvalid = instr[0].r_valid;
  end

  // Mailbox bookkeeping.
  logic         other_r_valid, other_r_is_read;
  logic [31:0]  other_r_data, other_r_addr;
  int           cnt_cycles;
  logic [31:0]  verify_ptr, verify_gold;
  int           verify_errors;

  always_ff @(posedge clk_i) begin
    other_r_valid   <= data_req & is_mbox_req;
    other_r_is_read <= ~data_we;
    other_r_addr    <= data_addr;
  end

  always_comb begin
    if (other_r_addr == TB_MBOX_CYCLES_ADDR)
      other_r_data = cnt_cycles;
    else if (other_r_addr == TB_MBOX_VERIFY_SIZE_ADDR)
      other_r_data = verify_errors;
    else
      other_r_data = '0;
  end

  // Datamover ports: directly bound to the wide TCDM (no splitter).
  generate
    for (genvar p = 0; p < NUM_WORDS; p++) begin : g_dm_bind
      assign tcdm[p].req  = dm_tcdm_req[p];
      assign tcdm[p].add  = dm_tcdm_add[p];
      assign tcdm[p].wen  = dm_tcdm_wen[p];
      assign tcdm[p].be   = dm_tcdm_be[p];
      assign tcdm[p].data = dm_tcdm_data[p];
      assign dm_tcdm_gnt[p]     = tcdm[p].gnt;
      assign dm_tcdm_r_data[p]  = tcdm[p].r_data;
      assign dm_tcdm_r_valid[p] = tcdm[p].r_valid;
    end
  endgenerate

  // Ibex 32-bit data port -> last TCDM port (WORD_WIDTH-wide) via aligner.
  // For WW=32 the aligner is identity. For wider WW, the active 32-bit slice
  // within the WW-byte word is selected by data_addr[ALIGN_BITS-1:2].
  wire [SLOT_BITS-1:0] core_slot;
  if (NUM_SLOTS <= 1) begin : g_slot_one
    assign core_slot = '0;
  end else begin : g_slot_many
    assign core_slot = data_addr[ALIGN_BITS-1:2];
  end

  logic [WORD_WIDTH-1:0]            core_wide_data;
  logic [(WORD_WIDTH/8)-1:0]        core_wide_be;
  generate
    for (genvar k = 0; k < NUM_SLOTS; k++) begin : g_core_wide
      assign core_wide_data[(k+1)*32-1 -: 32] = data_wdata;
      assign core_wide_be  [(k+1)*4-1  -: 4 ] = (core_slot == k[SLOT_BITS-1:0]) ? data_be : 4'b0;
    end
  endgenerate

  assign tcdm[MP-1].req  = data_req & is_tcdm_req;
  assign tcdm[MP-1].add  = data_addr & ~((WORD_WIDTH/8) - 1);
  assign tcdm[MP-1].wen  = ~data_we;
  assign tcdm[MP-1].be   = core_wide_be;
  assign tcdm[MP-1].data = core_wide_data;

  // Latch slot at request time so the read-data mux uses the right slice.
  logic [SLOT_BITS-1:0] core_slot_q;
  always_ff @(posedge clk_i) begin
    if (data_req & is_tcdm_req)
      core_slot_q <= core_slot;
  end

  logic [31:0] core_r_data_sel;
  if (NUM_SLOTS <= 1) begin : g_rsel_one
    assign core_r_data_sel = tcdm[MP-1].r_data[31:0];
  end else begin : g_rsel_many
    assign core_r_data_sel = tcdm[MP-1].r_data[core_slot_q*32 +: 32];
  end

  // Data bus mux.
  assign data_gnt   = is_periph_req   ? periph_gnt        :
                      is_tcdm_req     ? tcdm[MP-1].gnt    : 1'b1;
  assign data_rdata = periph_r_valid     ? periph_r_data        :
                      tcdm[MP-1].r_valid ? core_r_data_sel      :
                      (other_r_valid & other_r_is_read) ? other_r_data : '0;
  assign data_rvalid = periph_r_valid | tcdm[MP-1].r_valid | other_r_valid;

  logic dut_busy;

  datamover_top_wrap #(
`ifndef SYNTHESIS
    .WAIVE_RQ3_ASSERT  ( 1'b1 ),
    .WAIVE_RQ4_ASSERT  ( 1'b1 ),
    .WAIVE_RSP3_ASSERT ( 1'b1 ),
    .WAIVE_RSP5_ASSERT ( 1'b1 ),
`endif
    .ADDR_WIDTH          ( 32                  ),
    .ID                  ( 10                  ),
    .BANDWIDTH           ( BANDWIDTH           ),
    .NUM_ELEM_WORD       ( NUM_ELEM_WORD       ),
    .ELEM_WIDTH          ( ELEM_WIDTH          ),
    .N_CORES             ( 8                   ),
    .N_CONTEXT           ( 2                   ),
    .MISALIGNED_ACCESSES ( MISALIGNED_ACCESSES )
  ) i_dut (
    .clk_i          ( clk_i           ),
    .rst_ni         ( rst_ni          ),
    .test_mode_i    ( 1'b0            ),
    .evt_o          ( evt_unused      ),
    .busy_o         ( dut_busy        ),
    .tcdm_req       ( dm_tcdm_req     ),
    .tcdm_gnt       ( dm_tcdm_gnt     ),
    .tcdm_add       ( dm_tcdm_add     ),
    .tcdm_wen       ( dm_tcdm_wen     ),
    .tcdm_be        ( dm_tcdm_be      ),
    .tcdm_data      ( dm_tcdm_data    ),
    .tcdm_r_data    ( dm_tcdm_r_data  ),
    .tcdm_r_valid   ( dm_tcdm_r_valid ),
    .periph_req     ( periph_req      ),
    .periph_gnt     ( periph_gnt      ),
    .periph_add     ( periph_add      ),
    .periph_wen     ( periph_wen      ),
    .periph_be      ( periph_be       ),
    .periph_data    ( periph_data     ),
    .periph_id      ( periph_id       ),
    .periph_r_data  ( periph_r_data   ),
    .periph_r_valid ( periph_r_valid  ),
    .periph_r_id    ( periph_r_id     )
  );

  tb_dummy_memory #(
    .MP                ( MP              ),
    .BANK_WORD_WIDTH   ( WORD_WIDTH      ),
    .STORAGE_WIDTH     ( 32              ),
    .ELEMENT_WIDTH     ( ELEM_WIDTH      ),
    .MEMORY_SIZE       ( MEMORY_SIZE     ),
    .BASE_ADDR         ( TCDM_DATA_BASE  ),
    .PROB_STALL        ( PROB_STALL      ),
    .TCP               ( TCP             ),
    .TA                ( TA              ),
    .TT                ( TT              )
  ) i_dummy_memory (
    .clk_i       ( clk_i ),
    .randomize_i ( 1'b0  ),
    .enable_i    ( 1'b1  ),
    .stallable_i ( 1'b1  ),
    .tcdm        ( tcdm  )
  );

  localparam int unsigned DeadlockCycles = 10000;
  wire tcdm_handshake = |(i_dummy_memory.tcdm_req & i_dummy_memory.tcdm_gnt);
  int unsigned idle_cycles;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      idle_cycles <= 0;
    end else if (!tcdm_handshake) begin
      idle_cycles <= idle_cycles + 1;
      if (idle_cycles + 1 >= DeadlockCycles) begin
        $display("=====================");
        $display("==== TEST DEADLOCK ====");
        $display("=====================");
        $fatal(1, "TCDM idle: No TCDM handshake for %0d cycles", DeadlockCycles);
      end
    end else begin
      idle_cycles <= 0;
    end
  end

  tb_dummy_memory #(
    .MP              ( 1               ),
    .BANK_WORD_WIDTH  ( 32             ),
    .ELEMENT_WIDTH   ( ELEM_WIDTH      ),
    .MEMORY_SIZE     ( INSTR_MEM_SIZE  ),
    .BASE_ADDR       ( INSTR_BASE_ADDR ),
    .PROB_STALL      ( 0               ),
    .TCP             ( TCP             ),
    .TA              ( TA              ),
    .TT              ( TT              )
  ) i_dummy_instr_memory (
    .clk_i       ( clk_i ),
    .randomize_i ( 1'b0  ),
    .enable_i    ( 1'b1  ),
    .stallable_i ( 1'b0  ),
    .tcdm        ( instr )
  );

  ibex_core #(
    .PMPEnable        ( 1'b0                ),
    .PMPGranularity   ( 0                   ),
    .PMPNumRegions    ( 4                   ),
    .MHPMCounterNum   ( 0                   ),
    .MHPMCounterWidth ( 40                  ),
    .RV32E            ( 1'b0                ),
    .RV32M            ( ibex_pkg::RV32MFast ),
    .RV32B            ( ibex_pkg::RV32BNone ),
    .RegFile          ( ibex_pkg::RegFileFF ),
    .BranchTargetALU  ( 1'b0                ),
    .WritebackStage   ( 1'b0                ),
    .ICache           ( 1'b0                ),
    .ICacheECC        ( 1'b0                ),
    .BranchPredictor  ( 1'b0                ),
    .DbgTriggerEn     ( 1'b0                ),
    .DbgHwBreakNum    ( 1                   ),
    .SecureIbex       ( 1'b0                ),
    .DmHaltAddr       ( 32'h1A110800        ),
    .DmExceptionAddr  ( 32'h1A110808        )
  ) i_ibex (
    .clk_i               ( clk_i           ),
    .rst_ni              ( rst_ni          ),
    .test_en_i           ( 1'b0            ),
    .hart_id_i           ( 32'hFFFFFFFF    ),
    .boot_addr_i         ( INSTR_BASE_ADDR ),
    .instr_req_o         ( instr_req       ),
    .instr_gnt_i         ( instr_gnt       ),
    .instr_rvalid_i      ( instr_rvalid    ),
    .instr_addr_o        ( instr_addr      ),
    .instr_rdata_i       ( instr_rdata     ),
    .instr_err_i         ( 1'b0            ),
    .data_req_o          ( data_req        ),
    .data_gnt_i          ( data_gnt        ),
    .data_rvalid_i       ( data_rvalid     ),
    .data_we_o           ( data_we         ),
    .data_be_o           ( data_be         ),
    .data_addr_o         ( data_addr       ),
    .data_wdata_o        ( data_wdata      ),
    .data_rdata_i        ( data_rdata      ),
    .data_err_i          ( data_err        ),
    .irq_software_i      ( 1'b0            ),
    .irq_timer_i         ( 1'b0            ),
    .irq_external_i      ( 1'b0            ),
    .irq_fast_i          ( 15'b0           ),
    .irq_nm_i            ( 1'b0            ),
    .irq_x_i             ( 32'b0           ),
    .irq_x_ack_o         (                 ),
    .irq_x_ack_id_o      (                 ),
    .external_perf_i     ( 16'b0           ),
    .debug_req_i         ( 1'b0            ),
    .fetch_enable_i      ( fetch_enable    ),
    .alert_minor_o       (                 ),
    .alert_major_o       (                 ),
    .core_sleep_o        ( core_sleep_o    )
  );

  initial begin
    #(20*TCP);
    rst_ni <= #TA 1'b0;
    #(20*TCP);
    rst_ni <= #TA 1'b1;

    for (int i = 0; i < 10; i++) cycle();
    rst_ni <= #TA 1'b0;
    for (int i = 0; i < 10; i++) cycle();
    rst_ni <= #TA 1'b1;

    while (1) cycle();
  end

  int errors = -1;

  // tb_dummy_memory storage is 32-bit per entry; backdoor compare uses that.
  localparam int unsigned STORAGE_BYTES = 4;

  always_ff @(posedge clk_i) begin
    if ((data_addr == TB_MBOX_ERRORS_ADDR) && (data_we == 1'b1) && (data_req == 1'b1)) begin
      errors <= data_wdata;
      $display("[TB] Error count written: %0d", data_wdata);
    end
    if ((data_addr == TB_MBOX_PUTC_ADDR) && (data_we == 1'b1) && (data_req == 1'b1)) begin
      $write("%c", data_wdata);
    end
    if ((data_addr == TB_MBOX_VERIFY_PTR_ADDR) && (data_we == 1'b1) && (data_req == 1'b1)) begin
      verify_ptr <= data_wdata;
    end
    if ((data_addr == TB_MBOX_VERIFY_GOLD_ADDR) && (data_we == 1'b1) && (data_req == 1'b1)) begin
      verify_gold <= data_wdata;
    end
    if ((data_addr == TB_MBOX_VERIFY_SIZE_ADDR) && (data_we == 1'b1) && (data_req == 1'b1)) begin
      automatic int MaxLog = 50;
      automatic int errs = 0;
      automatic int first_n = 0;
      automatic int idx_log [50];
      automatic logic [7:0] act_log [50];
      automatic logic [7:0] gold_log [50];

      for (int i = 0; i < int'(data_wdata); i++) begin
        automatic int act_idx  = (verify_ptr  + i - TCDM_DATA_BASE) / STORAGE_BYTES;
        automatic int act_off  = (verify_ptr  + i - TCDM_DATA_BASE) % STORAGE_BYTES;
        automatic int gold_idx = (verify_gold + i - TCDM_DATA_BASE) / STORAGE_BYTES;
        automatic int gold_off = (verify_gold + i - TCDM_DATA_BASE) % STORAGE_BYTES;
        automatic logic [7:0] act_b  = i_dummy_memory.memory[act_idx][act_off*8 +: 8];
        automatic logic [7:0] gold_b = i_dummy_memory.memory[gold_idx][gold_off*8 +: 8];
        if (act_b !== gold_b) begin
          errs++;
          if (first_n < MaxLog) begin
            idx_log[first_n]  = i;
            act_log[first_n]  = act_b;
            gold_log[first_n] = gold_b;
            first_n++;
          end
        end
      end

      if (errs > 0) begin
        $display("[TB] VERIFY mismatches: %0d", errs);
        for (int k = 0; k < first_n; k++) begin
          $display("[TB] mismatch[%0d] idx=%0d gold=0x%02h act=0x%02h",
                   k, idx_log[k], gold_log[k], act_log[k]);
        end
      end

      verify_errors <= errs;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) cnt_cycles <= 0;
    else if (dm_tcdm_req != '0) cnt_cycles += 1;
  end

  initial begin
    $readmemh(STIM_INSTR, tb_datamover.i_dummy_instr_memory.memory);
    $readmemh(STIM_DATA,  tb_datamover.i_dummy_memory.memory);

    #(60*TCP);
    fetch_enable = 1'b1;
    #TA;

    #(400*TCP);
    while (core_sleep_o == 0 || errors == -1) #(TCP);

    if (errors == 0) begin
      $display("=====================");
      $display("==== TEST PASSED ====");
      $display("=====================");
    end else begin
      $display("=====================");
      $display("==== TEST FAILED ====");
      $display("=====================");
      $fatal(1, "errors happened: %0d", errors);
    end
    $finish(0);
  end

endmodule
