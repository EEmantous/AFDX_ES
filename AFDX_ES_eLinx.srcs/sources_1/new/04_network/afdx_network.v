`timescale 1ns/1ps
// 封装UDP，调度VL并发送A/B副本；接收后输出正文和路由信息。
module afdx_network #(
 parameter integer VL_COUNT=2,FRAME_DEPTH=1,RX_VL_COUNT=VL_COUNT,
 parameter integer MAX_UDP_PAYLOAD=1471,MAX_CORE_BYTES=1578, // MAX_UDP_PAYLOAD: UDP正文容量；MAX_CORE_BYTES: 调度和MAC统一的核心帧容量。
 parameter integer RX_CHANNEL_WIDTH=RX_VL_COUNT<=256 ? 8 : $clog2(RX_VL_COUNT),
 parameter integer DEDUP_HISTORY_DEPTH=64,DEDUP_WINDOW_CYCLES=1250,
 parameter [16*VL_COUNT-1:0] TX_VL_IDS={16'd2,16'd1},
 parameter [16*RX_VL_COUNT-1:0] RX_VL_IDS={16'd4,16'd3},
 parameter [32*VL_COUNT-1:0] VL_BAG_CYCLES={VL_COUNT{32'd1}},
 parameter [31:0] LOCAL_IP=32'hc0a80003,
 parameter [47:0] SRC_MAC={16'h0200,LOCAL_IP}
)(
 input wire clk,reset,
 // 每VL一条独立发送入口。首字节接受时锁存IP/端口，直到last。
 input wire [8*VL_COUNT-1:0] tx_data,
 input wire [VL_COUNT-1:0] tx_valid,tx_last,output wire [VL_COUNT-1:0] tx_ready,
 input wire [32*VL_COUNT-1:0] tx_dst_ip,
 input wire [16*VL_COUNT-1:0] tx_src_port,tx_dst_port,
 // 接收完成检查/去重后，rx_channel指明目标VL槽。
 output wire [7:0] rx_data,output wire rx_valid,rx_last,
 input wire [RX_VL_COUNT-1:0] rx_ready,output /* rx_channel：订阅VLID匹配得到的接收槽号。 */ reg [RX_CHANNEL_WIDTH-1:0] rx_channel,
 output wire [31:0] rx_src_ip,output wire [15:0] rx_src_port,rx_dst_port,
 // 慢速诊断读取；详细计数留在本模块，不向业务层广播。
 input wire [7:0] stat_select,output /* stat_value：旧诊断位置，固定为0。 */ wire [31:0] stat_value,
 output wire drop_event,
 output wire [1023:0] snmp_statistics,output wire [191:0] snmp_alarm_counts,
 output wire gmii_tx_a_clk,output wire [7:0] gmii_tx_a_txd,output wire gmii_tx_a_en,gmii_tx_a_er,
 output wire gmii_tx_b_clk,output wire [7:0] gmii_tx_b_txd,output wire gmii_tx_b_en,gmii_tx_b_er,
 input wire gmii_rx_a_clk,input wire [7:0] gmii_rx_a_rxd,input wire gmii_rx_a_dv,gmii_rx_a_er,
 input wire gmii_rx_b_clk,input wire [7:0] gmii_rx_b_rxd,input wire gmii_rx_b_dv,gmii_rx_b_er
);
 wire [8*VL_COUNT-1:0] frame_data;
 wire [VL_COUNT-1:0] frame_valid,frame_last,frame_ready,core_drop,queue_drop;
 wire [32*VL_COUNT-1:0] frame_queue_levels;
 genvar g;
 generate for(g=0;g<VL_COUNT;g=g+1)begin: transmit
  afdx_udp_tx #(.MAX_PAYLOAD(MAX_UDP_PAYLOAD),.LOCAL_IP(LOCAL_IP),.SRC_MAC(SRC_MAC),.DEST_MAC({32'h03000000,TX_VL_IDS[16*g+:16]})) packet(
   .clk(clk),.reset(reset),.in_data(tx_data[8*g+:8]),.in_valid(tx_valid[g]),.in_last(tx_last[g]),.in_ready(tx_ready[g]),
   .in_dst_ip(tx_dst_ip[32*g+:32]),.in_src_port(tx_src_port[16*g+:16]),.in_dst_port(tx_dst_port[16*g+:16]),
   .out_data(frame_data[8*g+:8]),.out_valid(frame_valid[g]),.out_last(frame_last[g]),.out_ready(frame_ready[g]),.drop_event(core_drop[g]));
 end endgenerate
 wire [7:0] ra,rb;wire rav,ral,rar,rbv,rbl,rbr;
 wire [15:0] udp_rx_vl;wire [106:0] udp_rx_metadata;
 wire [23:0] rx_events;/* selected_rx_ready：按接收槽号选择的下游UDP ready。 */ reg selected_rx_ready;/* rx_vl：接收订阅VL表的组合遍历索引。 */ integer rx_vl;
 always @*begin
  rx_channel=0;selected_rx_ready=1;
  for(rx_vl=0;rx_vl<RX_VL_COUNT;rx_vl=rx_vl+1)
   if(udp_rx_vl==RX_VL_IDS[16*rx_vl+:16])begin rx_channel=rx_vl;selected_rx_ready=rx_ready[rx_vl];end
 end
 assign rx_src_ip=udp_rx_metadata[106:75];
 assign rx_src_port=udp_rx_metadata[42:27];assign rx_dst_port=udp_rx_metadata[26:11];
 afdx_network_rx #(.VL_COUNT(RX_VL_COUNT),.RX_VL_IDS(RX_VL_IDS),.LOCAL_IP(LOCAL_IP),.DEDUP_HISTORY_DEPTH(DEDUP_HISTORY_DEPTH),.DEDUP_WINDOW_CYCLES(DEDUP_WINDOW_CYCLES)) receive(
  .clk(clk),.reset(reset),.a_data(ra),.a_valid(rav),.a_last(ral),.a_ready(rar),
  .b_data(rb),.b_valid(rbv),.b_last(rbl),.b_ready(rbr),
  .udp_data(rx_data),.udp_valid(rx_valid),.udp_last(rx_last),.udp_ready(selected_rx_ready),
  .udp_vl_id(udp_rx_vl),.udp_metadata(udp_rx_metadata),.events(rx_events));
 wire [7:0] scheduled_data;wire scheduled_valid,scheduled_last,mac_ready,mac_drop;
 wire [63:0] mac_rx_good,mac_rx_drop;wire [31:0] mac_tx_count;
 // 两网TX是同一输出的副本，因此只需一份边沿检测状态。
 /* previous_tx：上一拍GMII发送使能。 */ reg previous_tx;wire mac_start=gmii_tx_a_en && !previous_tx;
 always @(posedge clk)if(reset)previous_tx<=0;else previous_tx<=gmii_tx_a_en;
 assign gmii_tx_a_clk=clk;assign gmii_tx_b_clk=clk;
 assign gmii_tx_b_txd=gmii_tx_a_txd;assign gmii_tx_b_en=gmii_tx_a_en;assign gmii_tx_b_er=gmii_tx_a_er;
 assign drop_event=(|core_drop) || (|queue_drop) || mac_drop;
 afdx_multivl_scheduler #(.VL_COUNT(VL_COUNT),.DEPTH(FRAME_DEPTH),.MAX_BYTES(MAX_CORE_BYTES),.VL_BAG_CYCLES(VL_BAG_CYCLES)) scheduler(
  .clk(clk),.reset(reset),.in_data(frame_data),.in_valid(frame_valid),.in_last(frame_last),.in_ready(frame_ready),
  .out_data(scheduled_data),.out_valid(scheduled_valid),.out_last(scheduled_last),.out_ready(mac_ready),
  .mac_start_a(mac_start),.mac_start_b(mac_start),.selected_vl(),.saved_length(),
  .queue_levels(frame_queue_levels),.drop_event(queue_drop));
 ethernet_mac_tx #(.MAX_CORE_BYTES(MAX_CORE_BYTES),.BAG_CYCLES(1)) mac_tx_a(
  .clk(clk),.reset(reset),.in_data(scheduled_data),.in_valid(scheduled_valid && mac_ready),.in_last(scheduled_last),.in_ready(mac_ready),
  .gmii_txd(gmii_tx_a_txd),.gmii_tx_en(gmii_tx_a_en),.gmii_tx_er(gmii_tx_a_er),.drop_event(mac_drop),
  .frame_count(mac_tx_count),.saved_length());
 ethernet_mac_rx #(.MAX_CORE_BYTES(MAX_CORE_BYTES)) mac_rx_a(
  .rx_clk(gmii_rx_a_clk),.clk(clk),.reset(reset),.gmii_rxd(gmii_rx_a_rxd),.gmii_rx_dv(gmii_rx_a_dv),.gmii_rx_er(gmii_rx_a_er),
  .out_data(ra),.out_valid(rav),.out_last(ral),.out_ready(rar),.good_frames(mac_rx_good[31:0]),.drop_frames(mac_rx_drop[31:0]),.saved_length());
 ethernet_mac_rx #(.MAX_CORE_BYTES(MAX_CORE_BYTES)) mac_rx_b(
  .rx_clk(gmii_rx_b_clk),.clk(clk),.reset(reset),.gmii_rxd(gmii_rx_b_rxd),.gmii_rx_dv(gmii_rx_b_dv),.gmii_rx_er(gmii_rx_b_er),
  .out_data(rb),.out_valid(rbv),.out_last(rbl),.out_ready(rbr),.good_frames(mac_rx_good[63:32]),.drop_frames(mac_rx_drop[63:32]),.saved_length());

 // MAC统计只有一份；未提供的检查项目直接为0。
 assign snmp_alarm_counts={128'd0,mac_rx_drop};
 assign snmp_statistics={768'd0,32'd0,mac_rx_drop,64'd0,mac_rx_good,mac_tx_count};
 assign stat_value=0;

endmodule
