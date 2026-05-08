# Copyright 2023 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

set DEBUG ON

set TCL_DIR [file dirname [file normalize [info script]]]

set LIB work

if {$DEBUG == "ON"} {
    set VOPT_ARG "+acc"
    echo $VOPT_ARG
    set DB_SW "-debugdb"
} else {
    set DB_SW ""
}

quit -sim

vsim -voptargs=$VOPT_ARG $DB_SW -pedanticerrors -lib $LIB tb_datamover_top_wrap

if {$DEBUG == "ON"} {
    add log -r /*
    source $TCL_DIR/waves.tcl
    run -a
}

# run -a