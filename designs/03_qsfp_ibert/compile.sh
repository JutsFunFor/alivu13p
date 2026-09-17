#!/bin/bash
# Build the QSFP28 IBERT loopback test.
# NOTES: add your vivado path to environment !
#
#   ./compile.sh [outdir] [jobs]
set -e

DATE=$(date +%m%d_%H%M)
OUTDIR=${1:-./output_ibert_${DATE}}
JOBS=${2:-16}

mkdir -p "$OUTDIR"
vivado -nojournal -nolog -mode batch \
       -source ./tcl/prj.tcl \
       -tclargs "$(readlink -f "$OUTDIR")" "$JOBS"
