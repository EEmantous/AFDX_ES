`timescale 1ns/1ps
// 从固定IPv4/UDP头取得路由、长度和VL。
module afdx_rx_parser #(
    parameter integer FRAME_LENGTH_WIDTH = 11,
    parameter [31:0] LOCAL_DEST_IP = 32'hE0_00_00_01,
    parameter [15:0] LOCAL_DEST_PORT = 16'd1001,
    // Optional destination filter bypass for explicitly configured RX use.
    parameter STANDARD_UDP = 1'b0,
    parameter ACCEPT_ANY_DEST = 1'b0,
    parameter VL_FILTER = 1'b0,CHECK_LOCAL_IP = 1'b0,
    parameter [15:0] RX_VL_ID = 16'h0001,
    parameter integer RX_VL_COUNT=1,
    parameter [16*RX_VL_COUNT-1:0] RX_VL_IDS=RX_VL_ID
)(
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    input  wire       rx_transfer,
    input  wire [7:0] rx_data,
    input  wire       rx_last,

    output wire       frame_capture_start,
    output wire       payload_write_valid,
    output wire [7:0] payload_write_data,
    output wire       frame_parse_done,
    output wire       frame_parse_valid,
    output wire [FRAME_LENGTH_WIDTH-1:0] parsed_payload_length,
    output wire [15:0] parsed_vl_id,
    output wire [106:0] parsed_metadata,
    output wire [7:0]  parsed_sequence_number
);
 // index: 当前帧的字节位置，0表示等待首字节。
 reg [10:0] index;
 // vl: 目的MAC最后两个字节，即VL编号。
 reg [15:0] vl;
 // source_ip/destination_ip: 交给615A回复路由的两端地址。
 reg [31:0] source_ip,destination_ip;
 // source_port/destination_port: 交给615A和SNMP的UDP端口。
 reg [15:0] source_port,destination_port;
 // udp_length: UDP头和正文总长度，用来去掉填充字节。
 reg [15:0] udp_length;
 // subscribed: 当前VL是否有接收通道。
 reg subscribed;
 // slot: 遍历固定VL表的组合索引。
 integer slot;
 always @*begin
  subscribed=!VL_FILTER;
  for(slot=0;slot<RX_VL_COUNT;slot=slot+1)
   if(RX_VL_IDS[16*slot+:16]==vl)subscribed=1;
 end
 assign frame_capture_start=rx_transfer && index==0;
 assign payload_write_valid=rx_transfer && index>=42 && !rx_last &&
  (!STANDARD_UDP || index<34+udp_length);
 assign payload_write_data=rx_data;
 assign frame_parse_done=rx_transfer && rx_last;
 assign frame_parse_valid=frame_parse_done && subscribed;
 assign parsed_payload_length=udp_length-(STANDARD_UDP ? 8 : 9);
 assign parsed_vl_id=vl;
 assign parsed_metadata={source_ip,destination_ip,source_port,destination_port,parsed_payload_length};
 assign parsed_sequence_number=rx_data;
 always @(posedge sys_clk or negedge sys_rst_n)begin
  if(!sys_rst_n)begin
   index<=0;vl<=0;source_ip<=0;destination_ip<=0;
   source_port<=0;destination_port<=0;udp_length<=0;
  end else if(rx_transfer)begin
   index<=rx_last ? 0 : index+1'b1;
   case(index)
    4:vl[15:8]<=rx_data;5:vl[7:0]<=rx_data;
    26:source_ip[31:24]<=rx_data;27:source_ip[23:16]<=rx_data;
    28:source_ip[15:8]<=rx_data;29:source_ip[7:0]<=rx_data;
    30:destination_ip[31:24]<=rx_data;31:destination_ip[23:16]<=rx_data;
    32:destination_ip[15:8]<=rx_data;33:destination_ip[7:0]<=rx_data;
    34:source_port[15:8]<=rx_data;35:source_port[7:0]<=rx_data;
    36:destination_port[15:8]<=rx_data;37:destination_port[7:0]<=rx_data;
    38:udp_length[15:8]<=rx_data;39:udp_length[7:0]<=rx_data;
   endcase
  end
 end
endmodule
