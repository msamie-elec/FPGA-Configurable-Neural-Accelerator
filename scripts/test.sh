#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v iverilog >/dev/null || { echo "ERROR: install iverilog"; exit 2; }
command -v vvp >/dev/null || { echo "ERROR: install vvp"; exit 2; }
mkdir -p build
iverilog -g2012 -s tb_npu_core -o build/npu_tb.vvp rtl/npu_core.sv tb/tb_npu_core.sv
vvp build/npu_tb.vvp
