#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p "${1:-output_pcie_ddr4}"
vivado -nojournal -nolog -mode batch -source tcl/prj.tcl \
    -tclargs "$(realpath "${1:-output_pcie_ddr4}")" "${2:-8}"
