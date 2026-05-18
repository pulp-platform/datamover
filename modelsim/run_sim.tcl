# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

if {[batch_mode]} {
    set DEBUG OFF
} else {
    set DEBUG ON
}
set LIB work

quit -sim

if {$DEBUG == "ON"} {
    vsim -voptargs="+acc +nosparse" -debugdb -lib $LIB -suppress 12003 tb_datamover
} else {
    vopt +acc=r +nosparse -suppress 12003 -o vopt_tb -work $LIB tb_datamover
    vsim -suppress 12003 vopt_tb
}

if {$DEBUG == "ON"} {
    add log -r /*
}

run -a
