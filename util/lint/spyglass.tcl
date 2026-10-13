# Copyright 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

set PROJECT $env(LINT_TOP)

new_project ${PROJECT} -force
current_methodology $env(SPYGLASS_HOME)/GuideWare/latest/block/rtl_handoff

# Read the RTL
read_file -type sourcelist sources.f

set_option top ${PROJECT}
set_option enableSV09 yes
set_option allow_module_override yes
set_option designread_disable_flatten no
set_option nopreserve yes
set_parameter handle_large_bus yes
# The element buffer holds 32768 flip-flops in one variable
set_option mthresh 65536

compile_design
run_goal -goal lint/lint_rtl

exit -force
