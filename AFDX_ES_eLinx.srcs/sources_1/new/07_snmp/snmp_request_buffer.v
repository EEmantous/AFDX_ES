`timescale 1ns/1ps
// 保存当前GET请求直到回复完成。
module snmp_request_buffer #(
    parameter integer MAX_BYTES = 256 // MAX_BYTES: 当前SNMP请求用例所需的缓存长度。
)(
    input  wire        clk,
    input  wire        reset_n,

    // Input: one complete SNMP message, byte by byte.
    input  wire [7:0]  in_data,
    input  wire        in_valid,
    input  wire        in_last,
    output wire        in_ready,

    // A complete request is available for reading.
    output  reg         request_valid,
    output  reg  [10:0] request_length,

    // Parser reads the stored request by address.
    input  wire [10:0] read_addr,
    output wire [7:0]  read_data,

    // Parser releases the request after processing.
    input  wire        request_release,

    // One-cycle pulse when an oversized request is detected.
    output wire oversize_event
);
 // memory: 一条完整GET请求，直到回复结束才释放。
 reg [7:0] memory[0:MAX_BYTES-1];
 // write_count: 已收请求字节数。
 reg [10:0] write_count;
 assign in_ready=reset_n && !request_valid;
 assign read_data=memory[read_addr];
 assign oversize_event=0;
 always @(posedge clk)if(in_valid && in_ready)memory[write_count]<=in_data;
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin write_count<=0;request_valid<=0;request_length<=0;end
  else begin
   if(request_release)request_valid<=0;
   if(in_valid && in_ready)begin
    write_count<=in_last ? 0 : write_count+1'b1;
    if(in_last)begin request_valid<=1;request_length<=write_count+1'b1;end
   end
  end
 end
endmodule
