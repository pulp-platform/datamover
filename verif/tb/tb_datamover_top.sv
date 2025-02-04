/* 
 * tb_datamover_top.sv
 * Arpan Suravi Prasad <prasadar@iis.ee.ethz.ch>
 *
 * Copyright (C) 2018-2023 ETH Zurich, University of Bologna
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */


module tb_datamover_top;
import datamover_package::*;
import tb_package::*;


  // parameters
  parameter PROB_STALL = 0.1;
  parameter BASE_ADDR = 0;
  parameter MP = 4;
  parameter NC = 1;
  string STIMULI_PATH  = `STIMULI_PATH;
  string GOLDEN_PATH = `GOLDEN_PATH;

  // global signals
  logic                         clk_i  = 1'b0;
  logic                         rst_ni = 1'b1;
  logic                         test_mode_i = 1'b0;
  // local enable
  logic                         enable_i = 1'b1;
  logic                         clear_i  = 1'b0;

  logic randomize_mem      = 1'b0;
  logic stallable_mem      = 1'b1;

  hwpe_stream_intf_tcdm tcdm [MP-1:0] (.clk(clk_i));

  logic [MP-1:0]       tcdm_req;
  logic [MP-1:0]       tcdm_gnt;
  logic [MP-1:0][31:0] tcdm_add;
  logic [MP-1:0]       tcdm_wen;
  logic [MP-1:0][3:0]  tcdm_be;
  logic [MP-1:0][31:0] tcdm_data;
  logic [MP-1:0][31:0] tcdm_r_data;
  logic [MP-1:0]       tcdm_r_valid;

  logic          periph_req;
  logic          periph_gnt;
  logic [31:0]   periph_add;
  logic          periph_wen;
  logic [3:0]    periph_be;
  logic [31:0]   periph_data;
  logic [ID-1:0] periph_id;
  logic [31:0]   periph_r_data;
  logic          periph_r_valid;
  logic [ID-1:0] periph_r_id;



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
    for(genvar ii=0; ii<MP; ii++) begin : tcdm_binding
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
    logic [31:0] d0_stride;
    logic [31:0] d1_stride;
    logic [31:0] d0_length;
    logic [31:0] d1_length;
    logic [31:0] tot_length;
  } addressgen_t;

  addressgen_t read_addr, write_addr;

  assign read_addr = '{`STIM_READ_BASE_ADDR, `STIM_READ_D0_STRIDE, `STIM_READ_D1_STRIDE, `STIM_READ_D0_LENGTH, `STIM_READ_D1_LENGTH, `STIM_READ_TOT_LENGTH};
  assign write_addr = '{`STIM_WRITE_BASE_ADDR, `STIM_WRITE_D0_STRIDE, `STIM_WRITE_D1_STRIDE, `STIM_WRITE_D0_LENGTH, `STIM_WRITE_D1_LENGTH, `STIM_WRITE_TOT_LENGTH};
  // assign read_addr = '{`STIM_READ_BASE_ADDR, 32'h4, 32'h10, 32'h4, 32'h4, 32'h10};
  // assign write_addr = '{32'h40, 32'h4, 32'h10, 32'h4, 32'h4, 32'h10};


  datamover_top_wrap #(
    // waive all asserts in testbench at this stage: the dummy memory
    // responds with a bit of delay which messes them up!
`ifndef SYNTHESIS
    .WAIVE_RQ3_ASSERT  ( 1'b1 ),
    .WAIVE_RQ4_ASSERT  ( 1'b1 ),
    .WAIVE_RSP3_ASSERT ( 1'b1 ),
    .WAIVE_RSP5_ASSERT ( 1'b1 ),
`endif
    .N_CORES          ( NC ),
    .MP               ( MP ),
    .ID               ( ID )
  ) i_hwpe_top_wrap (
    .clk_i          ( clk_i          ),
    .rst_ni         ( rst_ni         ),
    .test_mode_i    ( 1'b0           ),
    .tcdm_add       ( tcdm_add       ),
    .tcdm_be        ( tcdm_be        ),
    .tcdm_data      ( tcdm_data      ),
    .tcdm_gnt       ( tcdm_gnt       ),
    .tcdm_wen       ( tcdm_wen       ),
    .tcdm_req       ( tcdm_req       ),
    .tcdm_r_data    ( tcdm_r_data    ),
    .tcdm_r_valid   ( tcdm_r_valid   ),
    .periph_add     ( periph_add     ),
    .periph_be      ( periph_be      ),
    .periph_data    ( periph_data    ),
    .periph_gnt     ( periph_gnt     ),
    .periph_wen     ( periph_wen     ),
    .periph_req     ( periph_req     ),
    .periph_id      ( periph_id      ),
    .periph_r_data  ( periph_r_data  ),
    .periph_r_valid ( periph_r_valid ),
    .periph_r_id    ( periph_r_id    ),
    .evt_o          ( evt            )
  );

  logic busy = 1'b0;

  tb_dummy_memory #(
    .MP          ( MP          ),
    .MEMORY_SIZE ( MEMORY_SIZE ),
    .BASE_ADDR   ( BASE_ADDR   ),
    .PROB_STALL  ( PROB_STALL  ),
    .TCP         ( TCP         ),
    .TA          ( TA          ),
    .TT          ( TT          )
  ) i_dummy_memory (
    .clk_i       ( clk_i         ),
    .randomize_i ( randomize_mem ),
    .enable_i    ( enable_mem    ),
    .stallable_i ( busy          ),
    .tcdm        ( tcdm          )
  );

  initial begin
    $display("stimuli path : %s\n", STIMULI_PATH);
    $display("golden path : %s\n", GOLDEN_PATH);
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

    #(100*TCP); // enough time to wait for the reset to complete;
    status = -1;
    periph_bus.req  <= #TA '0;
    periph_bus.add  <= #TA '0;
    periph_bus.wen  <= #TA '0;
    periph_bus.be   <= #TA '0;
    periph_bus.id   <= #TA '0;

    $readmemh(STIMULI_PATH, tb_datamover_top.i_dummy_memory.memory);

    // soft clear
    periph_write(datamover_package::DATAMOVER_SOFT_CLEAR, datamover_package::HWPE_REGISTER_OFFS, 32'habcdefab,  clk_i, periph_bus);   
    #(100*TCP);

    // acquire job
    while(status !== 32'h00)
      periph_read(datamover_package::DATAMOVER_ACQUIRE, datamover_package::HWPE_REGISTER_OFFS, status,  clk_i, periph_bus);   
    

    periph_write(datamover_package::DATAMOVER_REG_IN_PTR,       datamover_package::DATAMOVER_REGISTER_OFFS, read_addr.base_addr,  clk_i, periph_bus);   
    periph_write(datamover_package::DATAMOVER_REG_OUT_PTR,      datamover_package::DATAMOVER_REGISTER_OFFS, write_addr.base_addr,  clk_i, periph_bus);   
    
    periph_write(datamover_package::DATAMOVER_REG_TOT_LEN,      datamover_package::DATAMOVER_REGISTER_OFFS, read_addr.tot_length,  clk_i, periph_bus);   
    periph_write(datamover_package::DATAMOVER_REG_IN_D0_LEN,    datamover_package::DATAMOVER_REGISTER_OFFS, read_addr.d0_length,  clk_i, periph_bus);   
    periph_write(datamover_package::DATAMOVER_REG_IN_D0_STRIDE, datamover_package::DATAMOVER_REGISTER_OFFS, read_addr.d0_stride,  clk_i, periph_bus);   
    periph_write(datamover_package::DATAMOVER_REG_IN_D1_LEN,    datamover_package::DATAMOVER_REGISTER_OFFS, read_addr.d1_length,  clk_i, periph_bus);   
    periph_write(datamover_package::DATAMOVER_REG_IN_D1_STRIDE, datamover_package::DATAMOVER_REGISTER_OFFS, read_addr.d1_stride,  clk_i, periph_bus);   
    periph_write(datamover_package::DATAMOVER_REG_IN_D2_STRIDE, datamover_package::DATAMOVER_REGISTER_OFFS, 32'h0,  clk_i, periph_bus);   

    periph_write(datamover_package::DATAMOVER_REG_OUT_D0_LEN,    datamover_package::DATAMOVER_REGISTER_OFFS, write_addr.d0_length,  clk_i, periph_bus);   
    periph_write(datamover_package::DATAMOVER_REG_OUT_D0_STRIDE, datamover_package::DATAMOVER_REGISTER_OFFS, write_addr.d0_stride,  clk_i, periph_bus);   
    periph_write(datamover_package::DATAMOVER_REG_OUT_D1_LEN,    datamover_package::DATAMOVER_REGISTER_OFFS, write_addr.d1_length,  clk_i, periph_bus);   
    periph_write(datamover_package::DATAMOVER_REG_OUT_D1_STRIDE, datamover_package::DATAMOVER_REGISTER_OFFS, write_addr.d1_stride,  clk_i, periph_bus);   
    periph_write(datamover_package::DATAMOVER_REG_OUT_D2_STRIDE, datamover_package::DATAMOVER_REGISTER_OFFS, 32'h4,  clk_i, periph_bus);   

    periph_write(datamover_package::DATAMOVER_COMMIT_AND_TRIGGER, datamover_package::HWPE_REGISTER_OFFS, 32'h0,  clk_i, periph_bus);   

    while(status === 32'h00)
      periph_read(datamover_package::DATAMOVER_STATUS, datamover_package::HWPE_REGISTER_OFFS, status,  clk_i, periph_bus);  
    
    while(status !== 32'h00)
      periph_read(datamover_package::DATAMOVER_STATUS, datamover_package::HWPE_REGISTER_OFFS,  status,  clk_i, periph_bus);  
    
    check_output(GOLDEN_PATH,  // File containing golden reference data
      32'h0,  // Start address in memory
      MEMORY_SIZE >> 2,  // Number of entries to check
      tb_datamover_top.i_dummy_memory.memory,  // Reference to memory array
      error_status
    );

    

    $finish;
    
  end : main_execution

endmodule // tb_datamover_top