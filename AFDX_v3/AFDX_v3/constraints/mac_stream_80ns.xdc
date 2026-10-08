# 12.5 MHz byte-stream reference: peak 8/80ns = 100 Mbps.
# No input/output delays yet: this checks internal paths only, not a real MAC.
create_clock -name mac_stream_clk -period 80.000 [get_ports clk]
