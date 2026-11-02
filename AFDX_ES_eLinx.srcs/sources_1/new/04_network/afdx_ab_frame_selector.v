`timescale 1ns/1ps
// 直接选择A/B接收队列，每个VL的同一帧只交付一次。
module afdx_ab_frame_selector #(
    parameter integer MAX_FRAME_BYTES = 1471,
    parameter ALLOW_RESET_SN = 0,
    parameter integer POINTER_WIDTH = 11,
    parameter integer DEDUP_WINDOW_CYCLES = 100000,
    parameter integer HISTORY_DEPTH = 64,
    parameter integer VL_COUNT=1, // VL_COUNT: 已订阅VL数量。
    parameter [16*VL_COUNT-1:0] VL_IDS=16'd1 // VL_IDS: 已订阅VL编号。
) (
    input wire sys_clk, sys_rst_n,
    input wire [7:0] a_data,
    input wire a_valid, a_last,
    output wire a_ready,
    input wire [7:0] b_data,
    input wire b_valid, b_last,
    output wire b_ready,
    output wire [7:0] out_data,
    output wire out_valid, out_last,
    input wire out_ready,
    input wire [106:0] a_metadata, b_metadata,
    output wire [106:0] out_metadata,
    input wire [15:0] a_vl_id,
    input wire [7:0] a_sequence_number,
    input wire [15:0] b_vl_id,
    input wire [7:0] b_sequence_number,
    output wire [15:0] out_vl_id,
    output wire [7:0] out_sequence_number,
    output wire duplicate_a_event, duplicate_b_event
);
 localparam IDLE=0,SEND=1,DRAIN=2;
 localparam SLOT_WIDTH=VL_COUNT<=1 ? 1 : $clog2(VL_COUNT);
 // state: 选择下一帧、发送正文或消费另一份副本。
 reg [1:0] state;
 // select_a: 当前帧来自A网。
 reg select_a;
 // slot: 当前帧所属的VL表项。
 reg [SLOT_WIDTH-1:0] slot;
 // seen/last_sn: 每个VL是否交付过帧、最近已交付的帧序号。
 reg [VL_COUNT-1:0] seen;
 reg [7:0] last_sn[0:VL_COUNT-1];
 // candidate_vl/candidate_sn: 等待处理帧的VL和序号，A网同时有帧时先选A。
 wire [15:0] candidate_vl=a_valid ? a_vl_id : b_vl_id;
 wire [7:0] candidate_sn=a_valid ? a_sequence_number : b_sequence_number;
 // candidate_slot/scan: 当前VL在订阅表中的位置及查表索引。
 integer candidate_slot,scan;
 always @*begin
  candidate_slot=0;
  for(scan=0;scan<VL_COUNT;scan=scan+1)
   if(VL_IDS[16*scan+:16]==candidate_vl)candidate_slot=scan;
 end
 assign out_valid=sys_rst_n && state==SEND && (select_a ? a_valid : b_valid);
 assign out_data=select_a ? a_data : b_data;
 assign out_last=select_a ? a_last : b_last;
 assign out_metadata=select_a ? a_metadata : b_metadata;
 assign out_vl_id=select_a ? a_vl_id : b_vl_id;
 assign out_sequence_number=select_a ? a_sequence_number : b_sequence_number;
 assign a_ready=sys_rst_n && select_a && (state==DRAIN || (state==SEND && out_ready));
 assign b_ready=sys_rst_n && !select_a && (state==DRAIN || (state==SEND && out_ready));
 assign duplicate_a_event=state==DRAIN && select_a && a_valid && a_last;
 assign duplicate_b_event=state==DRAIN && !select_a && b_valid && b_last;
 always @(posedge sys_clk or negedge sys_rst_n)begin
  if(!sys_rst_n)begin state<=IDLE;select_a<=1;slot<=0;seen<=0;end
  else case(state)
   IDLE:if(a_valid || b_valid)begin
    select_a<=a_valid;slot<=candidate_slot;
    state<=seen[candidate_slot] && last_sn[candidate_slot]==candidate_sn ? DRAIN : SEND;
   end
   SEND:if(out_valid && out_ready && out_last)begin
    seen[slot]<=1;last_sn[slot]<=out_sequence_number;state<=IDLE;
   end
   DRAIN:if(select_a ? (a_valid && a_last) : (b_valid && b_last))state<=IDLE;
  endcase
 end
endmodule
