# Official Digilent Arty-A7-35 USB-UART + 100 MHz + 4 LEDs.
# FPGA RX receives serial data transmitted from the onboard FTDI bridge.
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports clk100]
create_clock -name sys_clk -period 10.000 [get_ports clk100]
set_property -dict { PACKAGE_PIN A9 IOSTANDARD LVCMOS33 } [get_ports uart_rx]
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports uart_tx]
set_property -dict { PACKAGE_PIN C9 IOSTANDARD LVCMOS33 } [get_ports {btn[1]}]
# BTN0 is unused on this experimental serial-only top; no pin assignment needed.
set_property -dict { PACKAGE_PIN H5 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN J5 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN T9 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
# UART receive is asynchronous to internal FPGA clock: synchronised by uart_rx two-stage FF.
# Do not apply a fictitious synchronous input delay to asynchronous UART data.
set_false_path -from [get_ports uart_rx]
set_false_path -from [get_ports {btn[1]}]
