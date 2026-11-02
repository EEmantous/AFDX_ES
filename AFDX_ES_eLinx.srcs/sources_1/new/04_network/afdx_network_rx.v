`timescale 1ns/1ps
// A/B分别解析，统一去掉重复副本。
module afdx_network_rx #(
 parameter integer VL_COUNT=2,DEDUP_HISTORY_DEPTH=64,DEDUP_WINDOW_CYCLES=1250,
 parameter [16*VL_COUNT-1:0] RX_VL_IDS={16'd4,16'd3},
 parameter [31:0] LOCAL_IP=32'hc0a80003
)(
 input wire clk,reset,
 input wire [7:0] a_data,b_data,input wire a_valid,a_last,b_valid,b_last,
 output wire a_ready,b_ready,
 output wire [7:0] udp_data,output wire udp_valid,udp_last,input wire udp_ready,
 output wire [15:0] udp_vl_id,output wire [106:0] udp_metadata,
 output wire [23:0] events
);
 wire [7:0] a_payload,b_payload,a_sn,b_sn;
 wire a_payload_valid,a_payload_last,a_payload_ready,b_payload_valid,b_payload_last,b_payload_ready;
 wire [15:0] a_vl,b_vl;wire [106:0] a_metadata,b_metadata;
 afdx_es_rx #(.STANDARD_UDP(1),.ACCEPT_ANY_DEST(1),.VL_FILTER(1),
  .RX_VL_COUNT(VL_COUNT),.RX_VL_IDS(RX_VL_IDS),.CHECK_LOCAL_IP(1),.LOCAL_DEST_IP(LOCAL_IP)) plane_a(
  .sys_clk(clk),.sys_rst_n(!reset),.rx_data(a_data),.rx_valid(a_valid),.rx_last(a_last),.rx_ready(a_ready),
  .app_rx_data(a_payload),.app_rx_valid(a_payload_valid),.app_rx_last(a_payload_last),.app_rx_ready(a_payload_ready),
  .app_rx_metadata(a_metadata),.app_rx_vl_id(a_vl),.app_rx_sequence_number(a_sn),.rx_events(events[11:0]));
 afdx_es_rx #(.STANDARD_UDP(1),.ACCEPT_ANY_DEST(1),.VL_FILTER(1),
  .RX_VL_COUNT(VL_COUNT),.RX_VL_IDS(RX_VL_IDS),.CHECK_LOCAL_IP(1),.LOCAL_DEST_IP(LOCAL_IP)) plane_b(
  .sys_clk(clk),.sys_rst_n(!reset),.rx_data(b_data),.rx_valid(b_valid),.rx_last(b_last),.rx_ready(b_ready),
  .app_rx_data(b_payload),.app_rx_valid(b_payload_valid),.app_rx_last(b_payload_last),.app_rx_ready(b_payload_ready),
  .app_rx_metadata(b_metadata),.app_rx_vl_id(b_vl),.app_rx_sequence_number(b_sn),.rx_events(events[23:12]));
 afdx_ab_frame_selector #(.VL_COUNT(VL_COUNT),.VL_IDS(RX_VL_IDS),.ALLOW_RESET_SN(0),.HISTORY_DEPTH(DEDUP_HISTORY_DEPTH),.DEDUP_WINDOW_CYCLES(DEDUP_WINDOW_CYCLES)) redundancy(
  .sys_clk(clk),.sys_rst_n(!reset),
  .a_data(a_payload),.a_valid(a_payload_valid),.a_last(a_payload_last),.a_ready(a_payload_ready),
  .a_vl_id(a_vl),.a_sequence_number(a_sn),.a_metadata(a_metadata),
  .b_data(b_payload),.b_valid(b_payload_valid),.b_last(b_payload_last),.b_ready(b_payload_ready),
  .b_vl_id(b_vl),.b_sequence_number(b_sn),.b_metadata(b_metadata),
  .out_data(udp_data),.out_valid(udp_valid),.out_last(udp_last),.out_ready(udp_ready),
  .out_vl_id(udp_vl_id),.out_sequence_number(),.out_metadata(udp_metadata),
  .duplicate_a_event(),.duplicate_b_event());
endmodule
