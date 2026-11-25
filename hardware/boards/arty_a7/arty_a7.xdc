# Pin mapping from Digilent Arty A7-35 and A7-100 master pin tables.
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk100]
create_clock -name clk100 -period 10.000 [get_ports clk100]
set_property -dict {PACKAGE_PIN D9 IOSTANDARD LVCMOS33} [get_ports reset_btn]
set_property -dict {PACKAGE_PIN A9 IOSTANDARD LVCMOS33} [get_ports uart_rx]
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports uart_tx]
set_property -dict {PACKAGE_PIN H5 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN T9 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
# These external inputs are asynchronous; downstream synchronous paths remain timed.
set_false_path -from [get_ports uart_rx] -to [get_cells -hier -filter {NAME =~ */rx_meta_reg}]
set_false_path -from [get_ports reset_btn] -to [get_cells -hier -filter {NAME =~ *reset_pipe_reg*}]
