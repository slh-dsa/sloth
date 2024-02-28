#!/bin/bash

# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# This script drives the experimental Ibex synthesis flow. More details can be
# found in README.md

set -e
set -o pipefail

error () {
    echo >&2 "$@"
    exit 1
}

teelog () {
    tee "$LR_SYNTH_OUT_DIR/log/$1.log"
}

if [ ! -f syn_setup.sh ]; then
    error "No syn_setup.sh file: see README.md for instructions"
fi

#-------------------------------------------------------------------------
# setup flow variables
#-------------------------------------------------------------------------
source syn_setup.sh

#-------------------------------------------------------------------------
# use sv2v to convert all SystemVerilog files to Verilog
#-------------------------------------------------------------------------

#	here the original script coverts sv to v. we just copy our verilog

mkdir -p "$LR_SYNTH_OUT_DIR/generated"
mkdir -p "$LR_SYNTH_OUT_DIR/log"
mkdir -p "$LR_SYNTH_OUT_DIR/reports/timing"

cp ../../rtl/*.v ../../rtl/*.vh "$LR_SYNTH_OUT_DIR"/generated

#rm "$LR_SYNTH_OUT_DIR"/generated/fpga_*.v

##	back to original

yosys -c ./tcl/yosys_run_synth.tcl |& teelog syn || {
    error "Failed to synthesize RTL with Yosys"
}

sta ./tcl/sta_run_reports.tcl |& teelog sta || {
    error "Failed to run static timing analysis"
}

./translate_timing_rpts.sh

python/get_kge.py "$LR_SYNTH_CELL_LIBRARY_PATH" "$LR_SYNTH_OUT_DIR"/reports/area.rpt
