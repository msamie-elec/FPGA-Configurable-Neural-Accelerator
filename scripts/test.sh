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

echo 'Elaborating complete Arty A7 RTL top ...'
iverilog -g2012 -Wall -s arty_a7_top -o build/arty_a7_top.vvp rtl/npu_core.sv rtl/arty_a7_top.sv
echo 'BOARD TOP ELABORATION PASS'

python3 host/reference_mlp.py build/mlp_vectors.hex
echo 'Testing multilayer inference engine with 1/4/8 MAC lanes ...'
for lanes in 1 4 8; do
    iverilog -g2012 -Wall -s tb_mlp_engine -Ptb_mlp_engine.LANES="$lanes" \
        -o "build/tb_mlp_${lanes}.vvp" rtl/mlp_engine.sv tb/tb_mlp_engine.sv
    vvp "build/tb_mlp_${lanes}.vvp"
done

echo 'Testing scalable banked NPU against independent Python reference ...'
python3 host/reference_scalable.py build
iverilog -g2012 -Wall -s tb_npu_scalable -o build/tb_npu_scalable.vvp \
    rtl/npu_weight_bank.sv rtl/npu_scalable_core.sv tb/tb_npu_scalable.sv
vvp build/tb_npu_scalable.vvp

echo 'Testing UART model programming, inference and response framing ...'
iverilog -g2012 -Wall -s tb_npu_uart_bridge -o build/tb_npu_uart_bridge.vvp \
    rtl/npu_weight_bank.sv rtl/npu_scalable_core.sv rtl/uart_8n1.sv \
    rtl/npu_uart_bridge.sv tb/tb_npu_uart_bridge.sv
vvp build/tb_npu_uart_bridge.vvp
echo 'Elaborating integrated Arty A7 UART top ...'
iverilog -g2012 -Wall -s arty_a7_uart_npu_top -o build/arty_a7_uart_npu_top.vvp \
    rtl/npu_weight_bank.sv rtl/npu_scalable_core.sv rtl/uart_8n1.sv \
    rtl/npu_uart_bridge.sv rtl/arty_a7_uart_npu_top.sv
