# Copyright 2025-2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Disable DEBUG in command-line mode.
if {[batch_mode]} {
    set DEBUG OFF
} else {
    set DEBUG ON
}

set LIB work

set top tb_datamover
if {[info exists TOP_MODULE]} {
    if {$TOP_MODULE ne ""} {
        set top $TOP_MODULE
    }
}

quit -sim

if {$DEBUG == "ON"} {
    vsim -voptargs="+acc +nosparse" -debugdb -lib $LIB -suppress 12003 $top
    add log -r /*
} else {
    vsim -suppress 12003 vopt_$top
}

run -a
