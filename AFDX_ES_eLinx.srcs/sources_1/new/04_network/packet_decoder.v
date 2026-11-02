`timescale 1ns/1ps
// 将帧字段直接连到接收队列，提交已订阅VL的正文。
module packet_decoder #(
    parameter integer FRAME_LENGTH_WIDTH = 11,
    parameter integer VL_INDEX_WIDTH = 12,
    parameter [31:0] LOCAL_DEST_IP = 32'hE0_00_00_01,
    parameter [15:0] LOCAL_DEST_PORT = 16'd1001,
    parameter STANDARD_UDP = 1'b0,
    parameter ACCEPT_ANY_DEST = 1'b0,
    parameter VL_FILTER = 1'b0,CHECK_LOCAL_IP = 1'b0,
    parameter [15:0] RX_VL_ID = 16'h0001,
    parameter integer RX_VL_COUNT=1,
    parameter [16*RX_VL_COUNT-1:0] RX_VL_IDS=RX_VL_ID
)(
    input  wire       sys_clk,
    input  wire       sys_rst_n,

    input  wire [7:0] rx_data,
    input  wire       rx_valid,
    input  wire       rx_last,
    output wire       rx_ready,

    output wire       frame_capture_start,
    output wire       payload_write_valid,
    output wire [7:0] payload_write_data,
    input  wire       payload_write_ready,
    input  wire       payload_write_overflow,
    input  wire       frame_descriptor_ready,

    output wire       frame_commit,
    output wire       frame_abort,
    output wire [FRAME_LENGTH_WIDTH-1:0] frame_payload_length,
    output wire [106:0] frame_metadata,
    output wire [15:0] frame_vl_id,
    output wire [7:0] frame_sequence_number,
    output wire [4:0] error_events
);
 // parsed: 帧尾字段是否属于已订阅VL。
 wire parsed;
 // ended: 当前输入字节是帧尾。
 wire ended;
 assign rx_ready=sys_rst_n && payload_write_ready && frame_descriptor_ready;
 assign frame_commit=parsed;
 assign frame_abort=ended && !parsed;
 assign error_events={4'b0,frame_abort};
 afdx_rx_parser #(.FRAME_LENGTH_WIDTH(FRAME_LENGTH_WIDTH),
  .STANDARD_UDP(STANDARD_UDP),.VL_FILTER(VL_FILTER),
  .RX_VL_COUNT(RX_VL_COUNT),.RX_VL_IDS(RX_VL_IDS)) u_parser(
  .sys_clk(sys_clk),.sys_rst_n(sys_rst_n),.rx_transfer(rx_valid && rx_ready),
  .rx_data(rx_data),.rx_last(rx_last),.frame_capture_start(frame_capture_start),
  .payload_write_valid(payload_write_valid),.payload_write_data(payload_write_data),
  .frame_parse_done(ended),.frame_parse_valid(parsed),
  .parsed_payload_length(frame_payload_length),.parsed_vl_id(frame_vl_id),
  .parsed_metadata(frame_metadata),.parsed_sequence_number(frame_sequence_number));
endmodule
