# Project Build and Simulation Guide

This ReadMe provides instructions on how to set up and run the standalone simulation using `make` commands.

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