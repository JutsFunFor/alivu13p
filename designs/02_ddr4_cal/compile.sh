#!/bin/bash
# Build the four-channel DDR4 calibration and BIST design.
#
#   ./compile.sh [outdir] [jobs]
#
# NOTE: vivado must be on PATH.
set -e

DATE=$(date +%m%d_%H%M)
OUTDIR=${1:-./output_ddr4_cal_${DATE}}
JOBS=${2:-8}

mkdir -p "$OUTDIR"
vivado -nojournal -nolog -mode batch \
       -source ./tcl/prj.tcl \
       -tclargs "$(readlink -f "$OUTDIR")" "$JOBS"
