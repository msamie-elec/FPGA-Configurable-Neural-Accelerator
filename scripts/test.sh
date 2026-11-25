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

echo 'Testing host protocol and parsing Python GUI modules ...'
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 -m py_compile host/gui.py host/npu_serial.py host/reference_scalable.py

echo 'Testing hardware benchmark reference and reporting logic (mock only) ...'
python3 -m unittest discover -s tests -p 'test_benchmark_npu.py' -v
python3 -m py_compile host/benchmark_npu.py

echo 'Verifying standalone IP wrapper with independent 48-vector Python oracle ...'
iverilog -g2012 -Wall -s tb_npu_accelerator_ip -o build/tb_npu_accelerator_ip.vvp \
    rtl/npu_weight_bank.sv rtl/npu_scalable_core.sv \
    rtl/npu_accelerator_ip.sv tb/tb_npu_accelerator_ip.sv
vvp build/tb_npu_accelerator_ip.vvp

echo 'Verifying hardware benchmark report calculations and producing artifacts ...'
python3 -m unittest discover -s tests -p 'test_performance_analysis.py' -v
python3 scripts/analyze_npu_performance.py \
    --input docs/results/arty_a7_benchmark_2026-11-25.json \
    --output build/performance
python3 -m py_compile scripts/analyze_npu_performance.py

echo 'Simulating self-contained packaged-IP consumer control and memory programming ...'
iverilog -g2012 -Wall -DNPU_CONSUMER_SIM -s tb_ip_consumer_top \
    -o build/tb_ip_consumer_top.vvp \
    rtl/npu_weight_bank.sv rtl/npu_scalable_core.sv \
    rtl/npu_accelerator_ip.sv rtl/arty_a7_ip_consumer_top.sv tb/tb_ip_consumer_top.sv
vvp build/tb_ip_consumer_top.vvp

echo 'UART robustness: corrupt writes, illegal commands/topology and parser reset ...'
iverilog -g2012 -Wall -s tb_npu_uart_robustness -o build/tb_npu_uart_robustness.vvp \
    rtl/npu_weight_bank.sv rtl/npu_scalable_core.sv rtl/uart_8n1.sv \
    rtl/npu_uart_bridge.sv tb/tb_npu_uart_robustness.sv
vvp build/tb_npu_uart_robustness.vvp

echo 'Checking endurance runner and measured-power analyser syntax ...'
python3 -m py_compile host/reliability_campaign.py scripts/assess_power.py

echo 'Elaborating RTL for three-phase SAIF power characterization ...'
iverilog -g2012 -Wall -s tb_npu_power_activity -o build/tb_npu_power_activity.vvp \
    rtl/npu_weight_bank.sv rtl/npu_scalable_core.sv tb/tb_npu_power_activity.sv
# XSim-specific $stop power windows are intentionally not executed in vvp.
python3 -m py_compile scripts/summarize_saif_power.py
