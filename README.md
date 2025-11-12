# Project Build and Simulation Guide

This readme provides instructions on how to set up and run the standalone simulation using `make` commands.

## On the parametrization

Configure the hardware and testbench parameters in `config.mk`.

### Hardware parameter
`BANDWIDTH` = total bandwidth of the HWPE towards TCDM, expressed in bits
`NUM_ELEM_WORD` = number of elements (e.g., bytes) in a single word of a memory bank
`ELEM_WIDTH` = width of an element, expressed in bits (e.g., 8 for bytes)

**Constraints**
- `NUM_ELEM_WORD * ELEM_WIDTH` is the width of a memory bank word. `BANDWIDTH` must be divisible by such word width, as `BANDWIDTH / (NUM_ELEM_WORD * ELEM_WIDTH)` is the number of banks accessed in parallel by the HWPE in one memory access.
- `NUM_ELEM_WORD` must be a power of two due to memory addressing. Currently, the configurations `NUM_ELEM_WORD` = 2,4 support the datamover's transposition mode (1 elem, 2 elems, 4 elems). `NUM_ELEM_WORD` = 1 and `NUM_ELEM_WORD` > 4 is not supported.

### Testbench parameters

The following parameters are used to generate the testbench stimuli and to configure the datamover registers.

`STIM_*_BASE_ADDR` = start address of the read/write access bursts (element-addressed)
`STIM_*_LENGTH` = number of read/write accesses for the d0/d1 dimensions and in total (it is not an address offset!)
`STIM_*_STRIDE` = stride between element across dimensions d0/d1 (element-addressed, e.g., stride d1 would be the distance in an element-addressed offset between A[row=0][col=0] and A[row=1][col=0])
`STIM_MEM_SIZE` = number of words of the testbench memory
`STIM_TRANSP_MODE` = transposition mode to configure for the datamover (`3'b000` = none, `3'b001` = 1 elem, `3'b010` = 2 elem, `3'b100` = 4 elem)
`STIM_TRANSP_LEN` = transposition length (if set to 0: transp_len = BANDWIDTH_ALIGNED / ELEM_WIDTH)

For the complete list of the datamover configuration registers, cf. `datamover_package.sv`.

The parameters `STIM_*_BASE_ADDR` and `STIM_*_STRIDE`, exactly like memory addresses, are element-addressed. In a classical configuration of `NUM_ELEM_WORD` and `ELEM_WIDTH` (i.e., 32-bit words made of 4 8-bit bytes each), they are byte-addressed and their least significant 2 bits are dedicated to the byte offset. In general, however, the least `$clog2(NUM_ELEM_WORD)` bits of these addresses are dedicated to the offset for the elements in a word.
This impacts the generation of the stimuli in `verif/python/generate_stimuli.py` and the memory addressing in the hardware (i.e., the `testbench_memory` employed in this simulation or the memory sub-system of a real system where the datamover is integrated).

Note: `STIM_*_D0_STRIDE` is a element-addressed offset. This means that subsequent accesses advance of `STIM_*_D0_STRIDE << $clog2(NUM_ELEM_WORD)` in memory, independently on `BANDWIDTH`. `BANDWIDTH` only indicates the accessed number of subsequent words, given the base word of that access. Therefore, depending on the configuration of the stride, subsequent accesses of `BANDWIDTH` bits can also access overlapping words.

**Constraints**
- Currently, only `STIM_TRANSP_MODE` = `000` (i.e., no transposition) is supported by `verif/python/generate_stimuli.py`; it is not possible, therefore, to test the transpose functionality of the datamover in this standalone testbench

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

## Testing and Validation

The datamover HWPE provides several test targets for comprehensive validation:

### Configuration Testing
```sh
# Test all configuration presets
make test-all-presets

# Test all transpose modes
make test-transpose-modes

# Test configuration parameter combinations (grid testing)
make test-transpose-grid
make test-cim-grid

# Show available configurations
make help
```

### Configuration Presets
The system includes predefined test configurations:
- `small-matrix`: 4×4 matrix (quick testing)
- `medium-matrix`: 64×64 matrix (moderate testing)
- `large-matrix`: 448×448 matrix (stress testing)
- `transpose-test`: 32×32 matrix (transpose focus)
- `rect-wide`: 64×256 matrix (4-element transpose)
- `rect-tall`: 256×64 matrix (2-element transpose)
- `rect-narrow`: 16×128 matrix (1-element transpose)
- `rect-elongated`: 128×32 matrix (2-element transpose)
- `copy-small`: 4×4 matrix (copy mode testing)
- `copy-medium`: 64×64 matrix (copy mode testing)
- `cim-small`: 32×128 matrix (CIM mode, 32 inner_dim, 128-bit bandwidth)
- `cim-medium`: 64×256 matrix (CIM mode, 64 inner_dim, 256-bit bandwidth)
- `cim-large`: 128×512 matrix (CIM mode, 64 inner_dim, 512-bit bandwidth)

For detailed configuration documentation, see `CONFIG_USAGE.md`.

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
