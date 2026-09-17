#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p "${1:-output_pcie_stream}"
vivado -nojournal -nolog -mode batch -source tcl/prj.tcl \
    -tclargs "$(realpath "${1:-output_pcie_stream}")" "${2:-8}"
