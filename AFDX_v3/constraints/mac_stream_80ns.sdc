# eLinx/SDC starting constraint; tool/device porting still needs real validation.
create_clock -name mac_stream_clk -period 80.000 [get_ports clk]
