#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p output_sim
cd output_sim
xvlog --sv ../../rtl/ecc_init.v ../tb_ecc_init.sv
xelab tb_ecc_init -s tb_ecc_init_sim
xsim tb_ecc_init_sim -runall -log simulation.log
rg -q "^PASS:" simulation.log
