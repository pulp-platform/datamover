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
 * Authors: Sergio Mazzola <smazzola@iis.ee.ethz.ch>
 *          Arpan Suravi Prasad <prasadar@iis.ee.ethz.ch>
 *          Cyrill Durrer <cdurrer@iis.ee.ethz.ch>
 */

// OUTDATED!
// ToDo: Implement SW-based testing with a CPU core

module tb_datamover_top_wrap;
import datamover_package::*;
import tb_package::*;
  // global signals
  logic clk_i  = 1'b0;
  logic rst_ni = 1'b1;
  logic test_mode_i = 1'b0;
  // local enable
  logic enable_i = 1'b1;
  logic clear_i  = 1'b0;

  logic randomize_mem = 1'b0;
  logic enable_mem = 1'b1;
  logic stallable_mem = 1'b1;

  hwpe_stream_intf_tcdm #(
    .DATA_WIDTH ( WORD_WIDTH ),
    .ELEMENT_WIDTH ( ELEM_WIDTH ),
    .STRB_WIDTH ( NUM_ELEM_WORD )
  )
  tcdm [BANDWIDTH_WORDS-1:0] (
    .clk(clk_i)
  );

  logic [BANDWIDTH_WORDS-1:0]                    tcdm_req;
  logic [BANDWIDTH_WORDS-1:0]                    tcdm_gnt;
  logic [BANDWIDTH_WORDS-1:0][ADDR_WIDTH-1:0]    tcdm_add;
  logic [BANDWIDTH_WORDS-1:0]                    tcdm_wen;
  logic [BANDWIDTH_WORDS-1:0][NUM_ELEM_WORD-1:0] tcdm_be;
  logic [BANDWIDTH_WORDS-1:0][WORD_WIDTH-1:0]    tcdm_data;
  logic [BANDWIDTH_WORDS-1:0][WORD_WIDTH-1:0]    tcdm_r_data;
  logic [BANDWIDTH_WORDS-1:0]                    tcdm_r_valid;

  logic                 periph_req;
  logic                 periph_gnt;
  logic [31:0]          periph_add;
  logic                 periph_wen;
  logic [3:0]           periph_be;
  logic [31:0]          periph_data;
  logic [PERIPH_ID-1:0] periph_id;
  logic [31:0]          periph_r_data;
  logic                 periph_r_valid;
  logic [PERIPH_ID-1:0] periph_r_id;

  logic [2:0]           transp_mode;
  // logic [15:0]          transp_len;
  logic [11:0]          tensor_size_m;
  logic [11:0]          tensor_size_n;
  logic [3:0]           read_dim_enable;
  logic [3:0]           write_dim_enable;
  logic [10:0]          num_channels;
  logic [20:0]          total_elements;

  // Performs one entire clock cycle.
  task cycle;
    clk_i <= #(TCP/2) 0;
    clk_i <= #TCP 1;
    #TCP;
  endtask

  // The following task schedules the clock edges for the next cycle and
  // advances the simulation time to that cycles test time (localparam TT)
  // according to ATI timings.
  task cycle_start;
    clk_i <= #(TCP/2) 0;
    clk_i <= #TCP 1;
    #TT;
  endtask

  // The following task finishes a clock cycle previously started with
  // cycle_start by advancing the simulation time to the end of the cycle.
  task cycle_end;
    #(TCP-TT);
  endtask

  generate
    for(genvar ii=0; ii<BANDWIDTH_WORDS; ii++) begin : tcdm_binding
      assign tcdm[ii].req  = tcdm_req  [ii];
      assign tcdm[ii].add  = {8'b0, tcdm_add [ii][23:0]};
      assign tcdm[ii].wen  = tcdm_wen  [ii];
      assign tcdm[ii].be   = tcdm_be   [ii];
      assign tcdm[ii].data = tcdm_data [ii];
      assign tcdm_gnt     [ii] = tcdm[ii].gnt;
      assign tcdm_r_data  [ii] = tcdm[ii].r_data;
      assign tcdm_r_valid [ii] = tcdm[ii].r_valid;
    end
  endgenerate

  periph_bus_t periph_bus;

  typedef struct {
    logic [31:0] base_addr;
    logic [15:0] d0_stride;
    logic [15:0] d1_stride;
    logic [15:0] d2_stride;
    logic [15:0] d3_stride;
    logic [15:0] d4_stride;
    logic [15:0] d0_length;
    logic [15:0] d1_length;
    logic [15:0] d2_length;
    logic [15:0] d3_length;
    logic [31:0] tot_length;
  } addressgen_t;

  addressgen_t read_addr, write_addr;

  assign read_addr = '{`STIM_READ_BASE_ADDR, `STIM_READ_D0_STRIDE, `STIM_READ_D1_STRIDE, `STIM_READ_D2_STRIDE, `STIM_READ_D3_STRIDE, `STIM_READ_D4_STRIDE, `STIM_READ_D0_LENGTH, `STIM_READ_D1_LENGTH, `STIM_READ_D2_LENGTH, `STIM_READ_D3_LENGTH, `STIM_READ_TOT_LENGTH};
  assign write_addr = '{`STIM_WRITE_BASE_ADDR, `STIM_WRITE_D0_STRIDE, `STIM_WRITE_D1_STRIDE, `STIM_WRITE_D2_STRIDE, `STIM_WRITE_D3_STRIDE, `STIM_WRITE_D4_STRIDE, `STIM_WRITE_D0_LENGTH, `STIM_WRITE_D1_LENGTH, `STIM_WRITE_D2_LENGTH, `STIM_WRITE_D3_LENGTH, `STIM_WRITE_TOT_LENGTH};

  assign transp_mode = `STIM_TRANSP_MODE;
  // assign transp_len  = `STIM_TRANSP_LEN;
  assign tensor_size_m = `STIM_TENSOR_SIZE_M;
  assign tensor_size_n = `STIM_TENSOR_SIZE_N;
  assign read_dim_enable  = `STIM_READ_DIM_ENABLE;
  assign write_dim_enable = `STIM_WRITE_DIM_ENABLE;
  assign num_channels   = `STIM_NUM_CHANNELS;
  assign total_elements = `STIM_TOTAL_ELEMENTS;


  datamover_top_wrap #(
    // waive all asserts in testbench at this stage: the dummy memory
    // responds with a bit of delay which messes them up!
`ifndef SYNTHESIS
    .WAIVE_RQ3_ASSERT  ( 1'b1 ),
    .WAIVE_RQ4_ASSERT  ( 1'b1 ),
    .WAIVE_RSP3_ASSERT ( 1'b1 ),
    .WAIVE_RSP5_ASSERT ( 1'b1 ),
`endif
    .ADDR_WIDTH          ( ADDR_WIDTH ),
    .ID                  ( PERIPH_ID ),
    .BANDWIDTH           ( BANDWIDTH ),
    .NUM_ELEM_WORD       ( NUM_ELEM_WORD ),
    .ELEM_WIDTH          ( ELEM_WIDTH ),
    .N_CORES             ( N_CORES ),
    .N_CONTEXT           ( 2 ),
    .MISALIGNED_ACCESSES ( 0 )
  ) i_hwpe_top_wrap (
    .clk_i          ( clk_i          ),
    .rst_ni         ( rst_ni         ),
    .test_mode_i    ( 1'b0           ),
    .evt_o          ( /* Unconnected */),
    .tcdm_req       ( tcdm_req       ),
    .tcdm_gnt       ( tcdm_gnt       ),
    .tcdm_add       ( tcdm_add       ),
    .tcdm_wen       ( tcdm_wen       ),
    .tcdm_be        ( tcdm_be        ),
    .tcdm_data      ( tcdm_data      ),
    .tcdm_r_data    ( tcdm_r_data    ),
    .tcdm_r_valid   ( tcdm_r_valid   ),
    .periph_req     ( periph_req     ),
    .periph_gnt     ( periph_gnt     ),
    .periph_add     ( periph_add     ),
    .periph_wen     ( periph_wen     ),
    .periph_be      ( periph_be      ),
    .periph_data    ( periph_data    ),
    .periph_id      ( periph_id      ),
    .periph_r_data  ( periph_r_data  ),
    .periph_r_valid ( periph_r_valid ),
    .periph_r_id    ( periph_r_id    )
  );

  logic busy = 1'b0;

  testbench_memory #(
    .BANDWIDTH_WORDS ( BANDWIDTH_WORDS ),
    .NUM_ELEM_WORD   ( NUM_ELEM_WORD   ),
    .ELEM_WIDTH      ( ELEM_WIDTH      ),
    .MEMORY_SIZE     ( MEMORY_SIZE     ),
    .BASE_ADDR       ( BASE_ADDR       ),
    .PROB_STALL      ( PROB_STALL      ),
    .TCP             ( TCP             ),
    .TA              ( TA              ),
    .TT              ( TT              )
  ) i_testbench_memory (
    .clk_i       ( clk_i         ),
    .clk_delayed_i ( ),
    .randomize_i ( randomize_mem ),
    .enable_i    ( enable_mem    ),
    .stallable_i ( busy          ),
    .tcdm        ( tcdm          )
  );

  initial begin
    $display("Stimuli path: %s\n", STIMULI_PATH);
    $display("Golden path: %s\n", GOLDEN_PATH);
    #(20*TCP);

    // Reset phase.
    rst_ni <= #TA 1'b0;
    #(20*TCP);
    rst_ni <= #TA 1'b1;

    for (int i = 0; i < 10; i++)
      cycle();
    rst_ni <= #TA 1'b0;
    for (int i = 0; i < 10; i++)
      cycle();
    rst_ni <= #TA 1'b1;

    while(1) begin
      cycle();
    end
  end

  assign periph_req = periph_bus.req;
  assign periph_bus.gnt = periph_gnt;
  assign periph_add = periph_bus.add;
  assign periph_wen = periph_bus.wen;
  assign periph_be = periph_bus.be;
  assign periph_data = periph_bus.data;
  assign periph_bus.r_valid = periph_r_valid;
  assign periph_id = periph_bus.id;
  assign periph_bus.r_data = periph_r_data;

  logic [31:0] status;


  int error_status;

  initial begin : main_execution
    logic [31:0] ctrl_engine_reg;
    logic [31:0] tensor_dim_reg;
    logic [31:0] channels_reg;

    $info("Start execution...\n");

    #(100*TCP); // enough time to wait for the reset to complete;
    status = -1;
    periph_bus.req <= #TA '0;
    periph_bus.add <= #TA '0;
    periph_bus.wen <= #TA '0;
    periph_bus.be  <= #TA '0;
    periph_bus.id  <= #TA '0;

    $readmemh(STIMULI_PATH, tb_datamover_top_wrap.i_testbench_memory.memory);

    // soft clear
    periph_write(datamover_package::DATAMOVER_SOFT_CLEAR, datamover_package::HWPE_REGISTER_OFFS, 32'habcdefab,  clk_i, periph_bus);
    #(100*TCP);

    $info("[%0t] Acquiring job...\n", $time);
    // acquire job
    $info("Acquiring job...\n");
    while(status != 32'h00)
      periph_read(datamover_package::DATAMOVER_ACQUIRE, datamover_package::HWPE_REGISTER_OFFS, status,  clk_i, periph_bus);
    $info("Job acquired, configuring datamover...\n");


    periph_write(datamover_package::DATAMOVER_REG_IN_PTR,  datamover_package::DATAMOVER_REGISTER_OFFS, read_addr.base_addr, clk_i, periph_bus);
    periph_write(datamover_package::DATAMOVER_REG_OUT_PTR, datamover_package::DATAMOVER_REGISTER_OFFS, write_addr.base_addr, clk_i, periph_bus);

    // Configure packed length registers (see datamover_package.sv)
    ctrl_engine_reg = {16'b0, write_dim_enable[3:0], read_dim_enable[3:0], 5'b0, transp_mode[2:0]};
    tensor_dim_reg  = {tensor_size_n[15:0], tensor_size_m[15:0]};
    channels_reg    = {total_elements[20:0], num_channels[10:0]};

    // Make sure tot_length is the same for read and write
    assert (read_addr.tot_length == write_addr.tot_length) else $fatal("Read and write total lengths do not match!");

    periph_write(datamover_package::DATAMOVER_REG_TOT_LEN, datamover_package::DATAMOVER_REGISTER_OFFS, read_addr.tot_length, clk_i, periph_bus);
    periph_write(datamover_package::DATAMOVER_REG_IN_D0, datamover_package::DATAMOVER_REGISTER_OFFS, {read_addr.d0_stride, read_addr.d0_length}, clk_i, periph_bus);
    periph_write(datamover_package::DATAMOVER_REG_IN_D1, datamover_package::DATAMOVER_REGISTER_OFFS, {read_addr.d1_stride, read_addr.d1_length}, clk_i, periph_bus);
    periph_write(datamover_package::DATAMOVER_REG_IN_D2, datamover_package::DATAMOVER_REGISTER_OFFS, {read_addr.d2_stride, read_addr.d2_length}, clk_i, periph_bus);
    periph_write(datamover_package::DATAMOVER_REG_IN_D3, datamover_package::DATAMOVER_REGISTER_OFFS, {read_addr.d3_stride, read_addr.d3_length}, clk_i, periph_bus);
    periph_write(datamover_package::DATAMOVER_REG_OUT_D0, datamover_package::DATAMOVER_REGISTER_OFFS, {write_addr.d0_stride, write_addr.d0_length}, clk_i, periph_bus);
    periph_write(datamover_package::DATAMOVER_REG_OUT_D1, datamover_package::DATAMOVER_REGISTER_OFFS, {write_addr.d1_stride, write_addr.d1_length}, clk_i, periph_bus);
    periph_write(datamover_package::DATAMOVER_REG_OUT_D2, datamover_package::DATAMOVER_REGISTER_OFFS, {write_addr.d2_stride, write_addr.d2_length}, clk_i, periph_bus);
    periph_write(datamover_package::DATAMOVER_REG_OUT_D3, datamover_package::DATAMOVER_REGISTER_OFFS, {write_addr.d3_stride, write_addr.d3_length}, clk_i, periph_bus);
    periph_write(datamover_package::DATAMOVER_REG_IN_OUT_D4_STRIDE, datamover_package::DATAMOVER_REGISTER_OFFS, {write_addr.d4_stride, read_addr.d4_stride}, clk_i, periph_bus);
    periph_write(datamover_package::DATAMOVER_REG_MATRIX_DIM, datamover_package::DATAMOVER_REGISTER_OFFS, tensor_dim_reg, clk_i, periph_bus);
    periph_write(datamover_package::DATAMOVER_REG_CHANNELS,    datamover_package::DATAMOVER_REGISTER_OFFS, channels_reg,    clk_i, periph_bus);
    periph_write(datamover_package::DATAMOVER_REG_CTRL_ENGINE, datamover_package::DATAMOVER_REGISTER_OFFS, ctrl_engine_reg, clk_i, periph_bus);

    periph_write(datamover_package::DATAMOVER_COMMIT_AND_TRIGGER, datamover_package::HWPE_REGISTER_OFFS, 32'h0, clk_i, periph_bus);

    while(status == 32'h00)
      periph_read(datamover_package::DATAMOVER_STATUS, datamover_package::HWPE_REGISTER_OFFS, status, clk_i, periph_bus);   // ToDo(cdurrer): Why STATUS and not FINISHED register?

     $info("Datamover working...\n");

    while(status != 32'h00)
      periph_read(datamover_package::DATAMOVER_STATUS, datamover_package::HWPE_REGISTER_OFFS, status, clk_i, periph_bus);

    $info("Datamover finished transfer. Checking output...\n");

    check_output(
      GOLDEN_PATH,  // File containing golden reference data
      32'h0,        // Start address in memory
      MEMORY_SIZE,  // Number of entries to check
      tb_datamover_top_wrap.i_testbench_memory.memory,  // Reference to memory array
      error_status
    );

    // Check if there were any errors and fail the simulation if so
    if (error_status != 0) begin
      $error("Test FAILED: Output mismatch detected (error_status = %0d)", error_status);
      $display("DATAMOVER_TEST_FAILED");
      $stop(1);
    end else begin
      $info("Test PASSED: All output verification checks successful");
      $display("DATAMOVER_TEST_PASSED");
    end

    $finish;

  end : main_execution

endmodule // tb_datamover_top_wrap
