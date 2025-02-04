/* 
 * tb_package.sv
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
package tb_package;
  localparam int ID = 10;
  localparam int MEMORY_SIZE=256*1024;
  // // ATI timing parameters.
  timeunit 1ps;
  timeprecision 1ps;
  localparam TCP = 1.0ns; // clock period, 1 GHz clock
  localparam TA  = 0.2ns; // application time
  localparam TT  = 0.8ns; // test time

  typedef struct{
    logic          req;
    logic          gnt;
    logic [31:0]   add;
    logic          wen;
    logic [3:0]    be;
    logic [31:0]   data;
    logic [ID-1:0] id;
    logic [31:0]   r_data;
    logic          r_valid;
    logic [ID-1:0] r_id;
  } periph_bus_t;

  // periph_bus_t periph_bus;

  task automatic periph_write(
    input  logic [31:0] base_addr,      // Base address
    input  logic [31:0] offset,         // Offset
    input  logic [31:0] data,           // Write data
    ref    logic        clk_i,          // Clock signal
    ref    periph_bus_t periph_bus      // Peripheral bus reference
    );
  // Initialize the peripheral bus for write operation
      @(posedge clk_i);                   // Wait for positive clock edge
      #TA;
      periph_bus.req  = 1'b0;
      periph_bus.add  = 32'b0;
      periph_bus.wen  = 1'b1;             // Default state: write enable high
      periph_bus.be   = 4'b0000;          // Default state: no byte enable
      periph_bus.data = 32'b0;
      periph_bus.id   = '0;               // Reset transaction ID


      // Setup phase
      @(posedge clk_i);                   // Wait for positive clock edge
      #TA;                                // Application delay
      periph_bus.req  = 1'b1;             // Request signal active
      periph_bus.add  = base_addr + offset; // Set target address
      periph_bus.wen  = 1'b0;             // Enable write operation
      periph_bus.be   = 4'b1111;          // Enable all bytes
      periph_bus.data = data;             // Set write data
      periph_bus.id   = ID;               // Reset transaction ID


      // Wait for grant signal
      if (periph_bus.gnt !== 1) begin
          wait (periph_bus.gnt === 1); // Wait for it to become 1 if not already 1
      end           // Wait until grant is asserted

      // Hold phase
      @(posedge clk_i);                   // Wait for next clock edge
      #TA;                                // Application delay
      // Termination phase
      periph_bus.req  = 1'b0;             // Deassert request
      periph_bus.add  = 32'b0;            // Clear address
      periph_bus.wen  = 1'b1;             // Return to default state
      periph_bus.be   = 4'b1111;          // Maintain byte enable

      @(posedge clk_i);                   // Final clock edge for cleanup
  endtask : periph_write

  task automatic periph_read(
      input  logic [31:0] base_addr,      // Base address
      input  logic [31:0] offset,         // Offset
      output logic [31:0] data,           // Output data
      ref    logic        clk_i,          // Clock signal
      ref    periph_bus_t periph_bus      // Peripheral bus reference
  );
      // Initialize the peripheral bus for read operation
      periph_bus.req  = 1'b0;
      periph_bus.add  = 32'b0;
      periph_bus.wen  = 1'b1;             // Default state: not a write operation
      periph_bus.be   = 4'b0000;          // Reset byte enable
      periph_bus.data = 32'b0;            // Data not used for read
      periph_bus.id   = '0;               // Reset transaction ID

      // Setup phase
      @(posedge clk_i);                   // Wait for positive clock edge
      #TA;                                // Application delay
      periph_bus.req  = 1'b1;             // Assert request signal
      periph_bus.add  = base_addr + offset; // Set target address
      periph_bus.wen  = 1'b1;             // Enable read operation
      periph_bus.be   = 4'b1111;          // Enable all bytes
      periph_bus.id   = ID;               // Reset transaction ID


      // Wait for grant signal
      if (periph_bus.gnt !== 1) begin
          wait (periph_bus.gnt === 1); // Wait for it to become 1 if not already 1
      end

      // Wait for read data to be valid
      @(posedge clk_i);                   // Wait for next clock edge
      if (periph_bus.r_valid !== 1) begin
          wait (periph_bus.r_valid === 1); // Wait for it to become 1 if not already 1
      end
      data = periph_bus.r_data;           // Capture read data

      // Termination phase
      @(posedge clk_i);                   // Wait for positive clock edge
      periph_bus.req  = 1'b0;             // Deassert request signal
      periph_bus.add  = 32'b0;            // Clear address
      periph_bus.wen  = 1'b1;             // Return to default state
      periph_bus.be   = 4'b1111;          // Maintain byte enable
  endtask : periph_read

  task automatic check_output(
      input string golden_fname,  // File containing golden data
      input logic [31:0] start_addr,  // Start address in memory
      input logic [31:0] length,  // Number of entries to check
      logic [31:0] memory [MEMORY_SIZE],  // Reference to memory array
      output int status
  );
      integer file, i;
      logic [31:0] golden_data;
      logic [31:0] read_data;

      status = 0; // Assume pass initially

      
      // Open the golden reference file for reading
      file = $fopen(golden_fname, "r");
      if (file == 0) begin
          $display("ERROR: Unable to open golden file %s", golden_fname);
          status = 1;
          $finish;
      end

      $display("Checking memory output against golden reference...");

      // Loop to compare memory values with golden file
      for (i = 0; i < length; i++) begin
          // Read golden value from file
          if ($fscanf(file, "%h", golden_data) != 1) begin
              $display("ERROR: Failed to read golden data at index %0d", i);
              status = 1;
              $fclose(file);
              $finish;
          end

          // Read from memory at start_addr + i
          read_data = memory[start_addr + i];

          // Compare values
          if (read_data !== golden_data) begin
              status = 1;
              $display("MISMATCH at address %0d: Expected %h, Actual %h", start_addr + i, golden_data, read_data);
          end else begin
              $display("MATCH at address %0d: %h", start_addr + i, read_data);
          end
      end

      // Close the file
      $fclose(file);
      $display("Check complete.");
      if (status === 0) begin
          $display("PASSED!!!!");
      end else begin
          $display("Failed XXXXXX");
      end
  endtask

  

endpackage