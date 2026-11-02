`timescale 1ns/1ps
// 一份正文RAM和一份打包帧信息队列。
module afdx_rx_frame_manager #(
    parameter integer FRAME_LENGTH_WIDTH       = 11,
    parameter integer PAYLOAD_FIFO_DEPTH       = 4096,
    parameter integer PAYLOAD_POINTER_WIDTH    = 12,
    parameter integer DESCRIPTOR_FIFO_DEPTH    = 8,
    parameter integer DESCRIPTOR_POINTER_WIDTH = 3
)(
    input  wire       sys_clk,
    input  wire       sys_rst_n,

    input  wire       frame_capture_start,
    input  wire       payload_write_valid,
    input  wire [7:0] payload_write_data,
    output wire       payload_write_ready,
    output wire payload_write_overflow,
    output wire       frame_descriptor_ready,

    input  wire       frame_commit,
    input  wire       frame_abort,
    input  wire [FRAME_LENGTH_WIDTH-1:0] frame_payload_length,
    input wire [106:0] frame_metadata,
    input wire [15:0] frame_vl_id,
    input wire [7:0] frame_sequence_number,

    output wire [7:0] app_rx_data,
    output wire       app_rx_valid,
    output wire       app_rx_last,
    input  wire       app_rx_ready,
    output wire [106:0] app_rx_metadata,
    output wire [15:0] app_rx_vl_id,
    output wire [7:0] app_rx_sequence_number
);
 // descriptors: 每帧的地址、端口、长度、VL和序号；长度已包含在metadata中。
 reg [130:0] descriptors[0:DESCRIPTOR_FIFO_DEPTH-1];
 // write_pointer/read_pointer: RAM写入位置和当前输出字节位置。
 reg [PAYLOAD_POINTER_WIDTH-1:0] write_pointer,read_pointer;
 // frame_start: 当前候选帧的起点，未订阅VL时退回这里。
 reg [PAYLOAD_POINTER_WIDTH-1:0] frame_start;
 // stored: RAM内尚未消费的字节数。
 reg [PAYLOAD_POINTER_WIDTH:0] stored;
 // head/tail: 已完成帧的读写位置。
 reg [DESCRIPTOR_POINTER_WIDTH-1:0] head,tail;
 // count: 已完成帧的数量。
 reg [DESCRIPTOR_POINTER_WIDTH:0] count;
 // offset: 当前输出帧已送出的字节数。
 reg [FRAME_LENGTH_WIDTH-1:0] offset;
 // written/read_byte/pop/push: 本拍正文写入、读出以及整帧出入队。
 wire written=payload_write_valid && payload_write_ready;
 wire read_byte=app_rx_valid && app_rx_ready;
 wire pop=read_byte && app_rx_last;
 wire push=frame_commit;
 // rollback: 未订阅VL已经写入的正文数量。
 wire [PAYLOAD_POINTER_WIDTH-1:0] rollback=write_pointer-frame_start;
 assign payload_write_ready=stored<PAYLOAD_FIFO_DEPTH;
 assign payload_write_overflow=0;
 assign frame_descriptor_ready=count<DESCRIPTOR_FIFO_DEPTH;
 assign app_rx_valid=sys_rst_n && count!=0;
 // payload_read_address: 当前字节被接收时提前读取下一个字节。
 wire [PAYLOAD_POINTER_WIDTH-1:0] payload_read_address=read_pointer+read_byte;
 afdx_byte_ram #(.WORDS(PAYLOAD_FIFO_DEPTH),.ADDRESS_WIDTH(PAYLOAD_POINTER_WIDTH)) bytes(
  .clk(sys_clk),.write_enable(written),.write_address(write_pointer),.write_data(payload_write_data),
  .read_enable(1'b1),.read_address(payload_read_address),.read_data(app_rx_data));
 assign {app_rx_metadata,app_rx_vl_id,app_rx_sequence_number}=descriptors[head];
 assign app_rx_last=app_rx_valid && offset==app_rx_metadata[10:0]-1'b1;
 always @(posedge sys_clk)begin
  if(push)descriptors[tail]<={frame_metadata,frame_vl_id,frame_sequence_number};
 end
 always @(posedge sys_clk or negedge sys_rst_n)begin
  if(!sys_rst_n)begin
   write_pointer<=0;read_pointer<=0;frame_start<=0;stored<=0;
   head<=0;tail<=0;count<=0;offset<=0;
  end else begin
   if(frame_capture_start)frame_start<=write_pointer;
   if(frame_abort)write_pointer<=frame_start;
   else if(written)write_pointer<=write_pointer+1'b1;
   if(read_byte)begin read_pointer<=read_pointer+1'b1;offset<=app_rx_last ? 0 : offset+1'b1;end
   stored<=stored+written-read_byte-(frame_abort ? rollback : 0);
   if(push)tail<=tail==DESCRIPTOR_FIFO_DEPTH-1 ? 0 : tail+1'b1;
   if(pop)head<=head==DESCRIPTOR_FIFO_DEPTH-1 ? 0 : head+1'b1;
   count<=count+push-pop;
  end
 end
endmodule
