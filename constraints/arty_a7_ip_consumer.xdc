# Representative Arty A7-35T pinout for independent NPU IP consumer.
# This is NOT the UART board demo and is not intended to be programmed
# unless full top-level board testing is explicitly requested.
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk100]
create_clock -name sys_clk -period 10.000 [get_ports clk100]
set_property -dict {PACKAGE_PIN C9 IOSTANDARD LVCMOS33} [get_ports btn_reset]
set_property -dict {PACKAGE_PIN H5 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN T9 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
# Pushbutton is asynchronous and passed through reset_sync[1:0].
set_false_path -from [get_ports btn_reset]
