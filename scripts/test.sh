#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v iverilog >/dev/null || { echo "ERROR: install iverilog"; exit 2; }
command -v vvp >/dev/null || { echo "ERROR: install vvp"; exit 2; }
mkdir -p build
for tb in tb_npu_core tb_npu_random; do
    echo "Running $tb ..."
    iverilog -g2012 -Wall -s "$tb" -o "build/${tb}.vvp" rtl/npu_core.sv "tb/${tb}.sv"
    vvp "build/${tb}.vvp"
done
