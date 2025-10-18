# Project Build and Simulation Guide

This readme provides instructions on how to set up and run the standalone simulation using `make` commands.

## On the hardware parameters

`BANDWIDTH` = total bandwidth of the HWPE towards TCDM, expressed in bits
`NUM_ELEM_WORD` = number of elements (e.g., bytes) in a single word of a memory bank
`ELEM_WIDTH` = width of an element, expressed in bits (e.g., 8 for bytes)

The width of a memory bank word in bits is therefore `NUM_ELEM_WORD * ELEM_WIDTH`.
`BANDWIDTH` must be divisible by such word width (i.e., the bandwidth is how many adjacent memory banks the HWPE accesses in parallel).
`NUM_ELEM_WORD` must be a power of two. Currently, the configurations `NUM_ELEM_WORD` = 2,4 support the datamover's transposition mode (1 elem, 2 elems, 4 elems). `NUM_ELEM_WORD` = 1 and `NUM_ELEM_WORD` > 4 is not supported.

The parameters used for stimuli generation and HWPE Datamover configuration (e.g., `read_base_addr`, `write_d0_stride`, `write_d1_length`, ... see `datamover_package.sv`), exactly like memory addresses, are element-addressed. In a classical configuration of `NUM_ELEM_WORD` and `ELEM_WIDTH` (i.e., different from 32-bit words made of 4 8-bit bytes each), they are byte-addressed and their least significant 2 bits are dedicated to the byte offset. In general, however, the least `$clog2(NUM_ELEM_WORD)` bits of these addresses are dedicated to the offset for the elements in a word.
This impacts the generation of the stimuli in `verif/python/generate_stimuli.py` and the memory addressing in the hardware (i.e., the `testbench_memory` employed in this simulation or the memory sub-system of a real system where the datamover is integrated).

Also take into account that `verif/python/generate_stimuli.py` does not support yet transposition modes different from `none`, therefore, the test is not gonna pass if `DATAMOVER_REG_TRANSP_MODE` is set to something different than `000`.

## Available Make Commands

### 1. To clone the dependencies, run:
```sh
make bender
```

### 2. Generate Stimuli and Golden Files
To generate the stimuli and golden reference using a Python script, run:
```sh
make stimuli
```

### 3. Create Compilation Script
To create a compilation script for compiling the hardware, run:
```sh
make sim-script
```

### 4. Simulate the Design
To simulate the RTL, execute:
```sh
make sim
```
By default QuestaSim GUI is active. You can simulate the RTL in CLI mode with `GUI=0 make sim`.

## Test Results
If the tests pass successfully, you should see the following message displayed at the end:
```
PASSED!!!!
```

## Contributors
- Francesco Conti, University of Bologna (*f.conti@unibo.it*)
- Arpan Suravi Prasad, ETH Zurich (*prasadar@iis.ee.ethz.ch*)

## License
This repository makes use of two licenses:
- for all *software*: Apache License Version 2.0
- for all *hardware*: Solderpad Hardware License Version 0.51
 
For further information have a look at the license files: `LICENSE.hw`, `LICENSE.sw`