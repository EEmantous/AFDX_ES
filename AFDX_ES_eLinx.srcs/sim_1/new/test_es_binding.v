`timescale 1ns/1ps
// ES端测试绑定：参数和端口采用真实ES端格式，所有端口直接连接core的同名端口。
module afdx_test_es #(
 parameter integer CLOCK_HZ=50000000,
 // 独立配置业务TX/RX数量；默认10 TX、100 RX，不计SNMP专用VL。
 parameter LOADER=1,
 parameter SNMP_ENABLE=1,
 parameter [15:0] SNMP_RX_VL=16'h0102,SNMP_RESPONSE_VL=16'h0103,SNMP_NOTIFY_VL=16'h0104,
 parameter integer SNMP_COMMUNITY_LENGTH=6,parameter [255:0] SNMP_COMMUNITY="public",
 parameter [31:0] SNMP_TARGET_IP=0,SNMP_CONTROL=32'h3fe,
 parameter integer SNMP_WINDOW_CYCLES=CLOCK_HZ,SNMP_COOLDOWN_CYCLES=CLOCK_HZ,SNMP_RETRY_THRESHOLD=1,
 parameter RTC_MASTER=LOADER,parameter [31:0] RTC_PEER_IP=0,
 parameter [31:0] RTC_INITIAL_SECONDS=0,parameter integer RTC_POLL_CYCLES=CLOCK_HZ,
 parameter integer VL_COUNT=10,TX_VL_COUNT=VL_COUNT,RX_VL_COUNT=100,
 // TASK_DEPTH/FRAME_DEPTH: 与实际综合入口一致的任务、发送帧缓存深度。
 parameter integer TASK_DEPTH=2,FRAME_DEPTH=1,MAP_ENTRIES=TX_VL_COUNT,
 // Synchronous A/B simulation profile: track recent copies for 100 us.
 // History capacity covers recent frames, not the number of RX subscriptions.
 parameter integer RX_DEDUP_HISTORY=64,
 parameter integer RX_DEDUP_WINDOW_CYCLES=(CLOCK_HZ+9999)/10000,
 parameter integer MAX_FILE_BYTES=8192,EVENT_DEPTH=MAP_ENTRIES+4,
 parameter integer SNMP_BAG_CYCLES=CLOCK_HZ/100,
 // 以下超时和BAG均以clk周期计；改变CLOCK_HZ时需同步检查覆盖参数。
 parameter integer RETRY_CYCLES=CLOCK_HZ,DALLY_CYCLES=2*CLOCK_HZ,
 parameter integer OP_TIMEOUT=10*CLOCK_HZ,STATUS_INTERVAL=CLOCK_HZ,
 parameter integer TASK_GUARD_CYCLES=CLOCK_HZ/1000,
 parameter integer RTC_TIMEOUT_CYCLES=CLOCK_HZ,
 parameter [31:0] RTC_HOLDOVER_CYCLES=32'd30*CLOCK_HZ,
 // 打包数组低位对应索引0；文件ID经FILE_VLS映射到独立任务/BAG队列。
 parameter [16*TX_VL_COUNT-1:0] TX_VL_IDS=default_tx_ids(LOADER),
 parameter [16*RX_VL_COUNT-1:0] RX_VL_IDS=default_rx_ids(LOADER),
 // Each RX subscription selects one of the TX/615A service channels.
 parameter [8*RX_VL_COUNT-1:0] RX_SERVICE_MAP=default_rx_services(0),
 // Simulation performance default: one cycle adds no intentional VL throttling.
 parameter [32*TX_VL_COUNT-1:0] VL_BAG_CYCLES={TX_VL_COUNT{32'd1}},
 parameter [32*MAP_ENTRIES-1:0] FILE_IDS=default_file_ids(0),
 parameter [8*MAP_ENTRIES-1:0] FILE_VLS=default_file_services(0),
 parameter [31:0] LOCAL_IP=32'hc0a80003,
 parameter [47:0] SRC_MAC={16'h0200,LOCAL_IP},
 parameter [255:0] TARGET_NAME=256'h4c5f5345
)(
 // Competition template + complete A/B physical byte streams, 62 IO bits.
 input wire clk,reset,
 // tx_data/rx_data：ES端向APP端输出/从APP端接收的文件字节。
 output wire [7:0] tx_data,input wire [7:0] rx_data,
 // tx_valid/rx_valid：ES端输出字节有效/APP端输入字节有效。
 output wire tx_valid,input wire rx_valid,
 // tx_ready/rx_ready：ES端可接收APP端字节/APP端可接收ES端字节。
 output wire tx_ready,input wire rx_ready,
 // gmii_tx_a_txd/en/er：A网实际发送字节、有效位、错误位。
 output wire [7:0] gmii_tx_a_txd,output wire gmii_tx_a_en,gmii_tx_a_er,
 // gmii_tx_b_txd/en/er：B网实际发送字节、有效位、错误位。
 output wire [7:0] gmii_tx_b_txd,output wire gmii_tx_b_en,gmii_tx_b_er,
 // gmii_rx_a_rxd/dv/er：A网实际接收字节、有效位、错误位。
 input wire [7:0] gmii_rx_a_rxd,input wire gmii_rx_a_dv,gmii_rx_a_er,
 // gmii_rx_b_rxd/dv/er：B网实际接收字节、有效位、错误位。
 input wire [7:0] gmii_rx_b_rxd,input wire gmii_rx_b_dv,gmii_rx_b_er
);
 // Generated default tables avoid zero/FFFF and the reserved management VLs.
 function [15:0] business_id(input /* index：当前字节或表项位置。 */ integer index,input /* base：默认业务VL编号函数的起始值。 */ integer base);
 /* value：本次计算值。 */ integer value;begin value=base+index;if(value>=16'h0102)value=value+3;business_id=value;end endfunction
 function [16*TX_VL_COUNT-1:0] default_tx_ids(input /* role：默认VL表函数的角色参数。 */ integer role);
 /* k：当前字节或表项位置。 */ integer k;begin for(k=0;k<TX_VL_COUNT;k=k+1)default_tx_ids[16*k+:16]=business_id(k,role ? 1 : TX_VL_COUNT+1);end endfunction
 function [16*RX_VL_COUNT-1:0] default_rx_ids(input /* role：默认VL表函数的角色参数。 */ integer role);
 /* k：当前字节或表项位置。 */ integer k;begin for(k=0;k<RX_VL_COUNT;k=k+1)default_rx_ids[16*k+:16]=business_id(k,role ? TX_VL_COUNT+1 : 1);end endfunction
 function [8*RX_VL_COUNT-1:0] default_rx_services(input /* unused：默认文件/服务映射函数的占位参数。 */ integer unused);
 /* k：当前字节或表项位置。 */ integer k;begin for(k=0;k<RX_VL_COUNT;k=k+1)default_rx_services[8*k+:8]=k%(TX_VL_COUNT>0 ? TX_VL_COUNT : 1);end endfunction
 function [32*MAP_ENTRIES-1:0] default_file_ids(input /* unused：默认文件/服务映射函数的占位参数。 */ integer unused);
 /* k：当前字节或表项位置。 */ integer k;begin for(k=0;k<MAP_ENTRIES;k=k+1)default_file_ids[32*k+:32]=k+1;end endfunction
 function [8*MAP_ENTRIES-1:0] default_file_services(input /* unused：默认文件/服务映射函数的占位参数。 */ integer unused);
 /* k：当前字节或表项位置。 */ integer k;begin for(k=0;k<MAP_ENTRIES;k=k+1)default_file_services[8*k+:8]=k%(TX_VL_COUNT>0 ? TX_VL_COUNT : 1);end endfunction

 AFDX_top #(
  .CLOCK_HZ(CLOCK_HZ),
  .LOADER(LOADER),
  .SNMP_ENABLE(SNMP_ENABLE),
  .SNMP_RX_VL(SNMP_RX_VL),
  .SNMP_RESPONSE_VL(SNMP_RESPONSE_VL),
  .SNMP_NOTIFY_VL(SNMP_NOTIFY_VL),
  .SNMP_COMMUNITY_LENGTH(SNMP_COMMUNITY_LENGTH),
  .SNMP_COMMUNITY(SNMP_COMMUNITY),
  .SNMP_TARGET_IP(SNMP_TARGET_IP),
  .SNMP_CONTROL(SNMP_CONTROL),
  .SNMP_WINDOW_CYCLES(SNMP_WINDOW_CYCLES),
  .SNMP_COOLDOWN_CYCLES(SNMP_COOLDOWN_CYCLES),
  .SNMP_RETRY_THRESHOLD(SNMP_RETRY_THRESHOLD),
  .RTC_MASTER(RTC_MASTER),
  .RTC_PEER_IP(RTC_PEER_IP),
  .RTC_INITIAL_SECONDS(RTC_INITIAL_SECONDS),
  .RTC_POLL_CYCLES(RTC_POLL_CYCLES),
  .VL_COUNT(VL_COUNT),
  .TX_VL_COUNT(TX_VL_COUNT),
  .RX_VL_COUNT(RX_VL_COUNT),
  .TASK_DEPTH(TASK_DEPTH),
  .FRAME_DEPTH(FRAME_DEPTH),
  .MAP_ENTRIES(MAP_ENTRIES),
  .RX_DEDUP_HISTORY(RX_DEDUP_HISTORY),
  .RX_DEDUP_WINDOW_CYCLES(RX_DEDUP_WINDOW_CYCLES),
  .MAX_FILE_BYTES(MAX_FILE_BYTES),
  .EVENT_DEPTH(EVENT_DEPTH),
  .SNMP_BAG_CYCLES(SNMP_BAG_CYCLES),
  .RETRY_CYCLES(RETRY_CYCLES),
  .DALLY_CYCLES(DALLY_CYCLES),
  .OP_TIMEOUT(OP_TIMEOUT),
  .STATUS_INTERVAL(STATUS_INTERVAL),
  .TASK_GUARD_CYCLES(TASK_GUARD_CYCLES),
  .RTC_TIMEOUT_CYCLES(RTC_TIMEOUT_CYCLES),
  .RTC_HOLDOVER_CYCLES(RTC_HOLDOVER_CYCLES),
  .TX_VL_IDS(TX_VL_IDS),
  .RX_VL_IDS(RX_VL_IDS),
  .RX_SERVICE_MAP(RX_SERVICE_MAP),
  .VL_BAG_CYCLES(VL_BAG_CYCLES),
  .FILE_IDS(FILE_IDS),
  .FILE_VLS(FILE_VLS),
  .LOCAL_IP(LOCAL_IP),
  .SRC_MAC(SRC_MAC),
  .TARGET_NAME(TARGET_NAME)
 ) core(
  .clk(clk),
  .reset(reset),
  .tx_data(tx_data),
  .rx_data(rx_data),
  .tx_valid(tx_valid),
  .rx_valid(rx_valid),
  .tx_ready(tx_ready),
  .rx_ready(rx_ready),
  .gmii_tx_a_txd(gmii_tx_a_txd),
  .gmii_tx_a_en(gmii_tx_a_en),
  .gmii_tx_a_er(gmii_tx_a_er),
  .gmii_tx_b_txd(gmii_tx_b_txd),
  .gmii_tx_b_en(gmii_tx_b_en),
  .gmii_tx_b_er(gmii_tx_b_er),
  .gmii_rx_a_rxd(gmii_rx_a_rxd),
  .gmii_rx_a_dv(gmii_rx_a_dv),
  .gmii_rx_a_er(gmii_rx_a_er),
  .gmii_rx_b_rxd(gmii_rx_b_rxd),
  .gmii_rx_b_dv(gmii_rx_b_dv),
  .gmii_rx_b_er(gmii_rx_b_er)
 );
endmodule
