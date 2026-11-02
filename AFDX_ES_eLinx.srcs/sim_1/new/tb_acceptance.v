`timescale 1ns/1ps
module tb_615a_download;
 // 顶层同名IO仅用于观察，使eLinx生成的add wave *能直接找到完整端口。
 // clk/reset：当前用例实际使用的时钟与复位。
 wire clk=scenario.clk,reset=scenario.reset;
 // tx_data：直接观察ES端同名IO。
 wire [7:0] tx_data=scenario.es.tx_data;
 // rx_data：直接观察ES端同名IO。
 wire [7:0] rx_data=scenario.es.rx_data;
 // tx_valid：直接观察ES端同名IO。
 wire tx_valid=scenario.es.tx_valid;
 // rx_valid：直接观察ES端同名IO。
 wire rx_valid=scenario.es.rx_valid;
 // tx_ready：直接观察ES端同名IO。
 wire tx_ready=scenario.es.tx_ready;
 // rx_ready：直接观察ES端同名IO。
 wire rx_ready=scenario.es.rx_ready;
 // gmii_tx_a_txd：直接观察ES端同名IO。
 wire [7:0] gmii_tx_a_txd=scenario.es.gmii_tx_a_txd;
 // gmii_tx_a_en：直接观察ES端同名IO。
 wire gmii_tx_a_en=scenario.es.gmii_tx_a_en;
 // gmii_tx_a_er：直接观察ES端同名IO。
 wire gmii_tx_a_er=scenario.es.gmii_tx_a_er;
 // gmii_tx_b_txd：直接观察ES端同名IO。
 wire [7:0] gmii_tx_b_txd=scenario.es.gmii_tx_b_txd;
 // gmii_tx_b_en：直接观察ES端同名IO。
 wire gmii_tx_b_en=scenario.es.gmii_tx_b_en;
 // gmii_tx_b_er：直接观察ES端同名IO。
 wire gmii_tx_b_er=scenario.es.gmii_tx_b_er;
 // gmii_rx_a_rxd：直接观察ES端同名IO。
 wire [7:0] gmii_rx_a_rxd=scenario.es.gmii_rx_a_rxd;
 // gmii_rx_a_dv：直接观察ES端同名IO。
 wire gmii_rx_a_dv=scenario.es.gmii_rx_a_dv;
 // gmii_rx_a_er：直接观察ES端同名IO。
 wire gmii_rx_a_er=scenario.es.gmii_rx_a_er;
 // gmii_rx_b_rxd：直接观察ES端同名IO。
 wire [7:0] gmii_rx_b_rxd=scenario.es.gmii_rx_b_rxd;
 // gmii_rx_b_dv：直接观察ES端同名IO。
 wire gmii_rx_b_dv=scenario.es.gmii_rx_b_dv;
 // gmii_rx_b_er：直接观察ES端同名IO。
 wire gmii_rx_b_er=scenario.es.gmii_rx_b_er;
 afdx_four_link_case #(.LINK(3),.OPERATION(3),.PREFIX("download")) scenario();
endmodule
module tb_a_disconnected;
 // 顶层同名IO仅用于观察，使eLinx生成的add wave *能直接找到完整端口。
 // clk/reset：当前用例实际使用的时钟与复位。
 wire clk=scenario.clk,reset=scenario.reset;
 // tx_data：直接观察ES端同名IO。
 wire [7:0] tx_data=scenario.es.tx_data;
 // rx_data：直接观察ES端同名IO。
 wire [7:0] rx_data=scenario.es.rx_data;
 // tx_valid：直接观察ES端同名IO。
 wire tx_valid=scenario.es.tx_valid;
 // rx_valid：直接观察ES端同名IO。
 wire rx_valid=scenario.es.rx_valid;
 // tx_ready：直接观察ES端同名IO。
 wire tx_ready=scenario.es.tx_ready;
 // rx_ready：直接观察ES端同名IO。
 wire rx_ready=scenario.es.rx_ready;
 // gmii_tx_a_txd：直接观察ES端同名IO。
 wire [7:0] gmii_tx_a_txd=scenario.es.gmii_tx_a_txd;
 // gmii_tx_a_en：直接观察ES端同名IO。
 wire gmii_tx_a_en=scenario.es.gmii_tx_a_en;
 // gmii_tx_a_er：直接观察ES端同名IO。
 wire gmii_tx_a_er=scenario.es.gmii_tx_a_er;
 // gmii_tx_b_txd：直接观察ES端同名IO。
 wire [7:0] gmii_tx_b_txd=scenario.es.gmii_tx_b_txd;
 // gmii_tx_b_en：直接观察ES端同名IO。
 wire gmii_tx_b_en=scenario.es.gmii_tx_b_en;
 // gmii_tx_b_er：直接观察ES端同名IO。
 wire gmii_tx_b_er=scenario.es.gmii_tx_b_er;
 // gmii_rx_a_rxd：直接观察ES端同名IO。
 wire [7:0] gmii_rx_a_rxd=scenario.es.gmii_rx_a_rxd;
 // gmii_rx_a_dv：直接观察ES端同名IO。
 wire gmii_rx_a_dv=scenario.es.gmii_rx_a_dv;
 // gmii_rx_a_er：直接观察ES端同名IO。
 wire gmii_rx_a_er=scenario.es.gmii_rx_a_er;
 // gmii_rx_b_rxd：直接观察ES端同名IO。
 wire [7:0] gmii_rx_b_rxd=scenario.es.gmii_rx_b_rxd;
 // gmii_rx_b_dv：直接观察ES端同名IO。
 wire gmii_rx_b_dv=scenario.es.gmii_rx_b_dv;
 // gmii_rx_b_er：直接观察ES端同名IO。
 wire gmii_rx_b_er=scenario.es.gmii_rx_b_er;
 afdx_four_link_case #(.FAULT(1),.PREFIX("a_disconnected")) scenario();
endmodule
module tb_a_corrupted;
 // 顶层同名IO仅用于观察，使eLinx生成的add wave *能直接找到完整端口。
 // clk/reset：当前用例实际使用的时钟与复位。
 wire clk=scenario.clk,reset=scenario.reset;
 // tx_data：直接观察ES端同名IO。
 wire [7:0] tx_data=scenario.es.tx_data;
 // rx_data：直接观察ES端同名IO。
 wire [7:0] rx_data=scenario.es.rx_data;
 // tx_valid：直接观察ES端同名IO。
 wire tx_valid=scenario.es.tx_valid;
 // rx_valid：直接观察ES端同名IO。
 wire rx_valid=scenario.es.rx_valid;
 // tx_ready：直接观察ES端同名IO。
 wire tx_ready=scenario.es.tx_ready;
 // rx_ready：直接观察ES端同名IO。
 wire rx_ready=scenario.es.rx_ready;
 // gmii_tx_a_txd：直接观察ES端同名IO。
 wire [7:0] gmii_tx_a_txd=scenario.es.gmii_tx_a_txd;
 // gmii_tx_a_en：直接观察ES端同名IO。
 wire gmii_tx_a_en=scenario.es.gmii_tx_a_en;
 // gmii_tx_a_er：直接观察ES端同名IO。
 wire gmii_tx_a_er=scenario.es.gmii_tx_a_er;
 // gmii_tx_b_txd：直接观察ES端同名IO。
 wire [7:0] gmii_tx_b_txd=scenario.es.gmii_tx_b_txd;
 // gmii_tx_b_en：直接观察ES端同名IO。
 wire gmii_tx_b_en=scenario.es.gmii_tx_b_en;
 // gmii_tx_b_er：直接观察ES端同名IO。
 wire gmii_tx_b_er=scenario.es.gmii_tx_b_er;
 // gmii_rx_a_rxd：直接观察ES端同名IO。
 wire [7:0] gmii_rx_a_rxd=scenario.es.gmii_rx_a_rxd;
 // gmii_rx_a_dv：直接观察ES端同名IO。
 wire gmii_rx_a_dv=scenario.es.gmii_rx_a_dv;
 // gmii_rx_a_er：直接观察ES端同名IO。
 wire gmii_rx_a_er=scenario.es.gmii_rx_a_er;
 // gmii_rx_b_rxd：直接观察ES端同名IO。
 wire [7:0] gmii_rx_b_rxd=scenario.es.gmii_rx_b_rxd;
 // gmii_rx_b_dv：直接观察ES端同名IO。
 wire gmii_rx_b_dv=scenario.es.gmii_rx_b_dv;
 // gmii_rx_b_er：直接观察ES端同名IO。
 wire gmii_rx_b_er=scenario.es.gmii_rx_b_er;
 afdx_four_link_case #(.FAULT(2),.PREFIX("a_corrupted")) scenario();
endmodule
module tb_speed #(parameter integer TRANSFERS=100); // TRANSFERS: 不复位连续传输次数，速度测试默认100次。
 // 顶层同名IO仅用于观察，使eLinx生成的add wave *能直接找到完整端口。
 // clk/reset：当前用例实际使用的时钟与复位。
 wire clk=scenario.clk,reset=scenario.reset;
 // tx_data：直接观察ES端同名IO。
 wire [7:0] tx_data=scenario.es.tx_data;
 // rx_data：直接观察ES端同名IO。
 wire [7:0] rx_data=scenario.es.rx_data;
 // tx_valid：直接观察ES端同名IO。
 wire tx_valid=scenario.es.tx_valid;
 // rx_valid：直接观察ES端同名IO。
 wire rx_valid=scenario.es.rx_valid;
 // tx_ready：直接观察ES端同名IO。
 wire tx_ready=scenario.es.tx_ready;
 // rx_ready：直接观察ES端同名IO。
 wire rx_ready=scenario.es.rx_ready;
 // gmii_tx_a_txd：直接观察ES端同名IO。
 wire [7:0] gmii_tx_a_txd=scenario.es.gmii_tx_a_txd;
 // gmii_tx_a_en：直接观察ES端同名IO。
 wire gmii_tx_a_en=scenario.es.gmii_tx_a_en;
 // gmii_tx_a_er：直接观察ES端同名IO。
 wire gmii_tx_a_er=scenario.es.gmii_tx_a_er;
 // gmii_tx_b_txd：直接观察ES端同名IO。
 wire [7:0] gmii_tx_b_txd=scenario.es.gmii_tx_b_txd;
 // gmii_tx_b_en：直接观察ES端同名IO。
 wire gmii_tx_b_en=scenario.es.gmii_tx_b_en;
 // gmii_tx_b_er：直接观察ES端同名IO。
 wire gmii_tx_b_er=scenario.es.gmii_tx_b_er;
 // gmii_rx_a_rxd：直接观察ES端同名IO。
 wire [7:0] gmii_rx_a_rxd=scenario.es.gmii_rx_a_rxd;
 // gmii_rx_a_dv：直接观察ES端同名IO。
 wire gmii_rx_a_dv=scenario.es.gmii_rx_a_dv;
 // gmii_rx_a_er：直接观察ES端同名IO。
 wire gmii_rx_a_er=scenario.es.gmii_rx_a_er;
 // gmii_rx_b_rxd：直接观察ES端同名IO。
 wire [7:0] gmii_rx_b_rxd=scenario.es.gmii_rx_b_rxd;
 // gmii_rx_b_dv：直接观察ES端同名IO。
 wire gmii_rx_b_dv=scenario.es.gmii_rx_b_dv;
 // gmii_rx_b_er：直接观察ES端同名IO。
 wire gmii_rx_b_er=scenario.es.gmii_rx_b_er;
 afdx_single_file_case #(.CAPACITY(8192),.FILE_NAME("rate.bin"),.TRANSFERS(TRANSFERS),.HEADER_NAME(256'h48554c2e65746172),.DATA_NAME(256'h6e69622e65746172)) scenario();
endmodule
