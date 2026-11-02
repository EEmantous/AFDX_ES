`timescale 1ns/1ps
// 按文件编号选择VL，在各VL的RAM队列保存任务。
module arinc615a_task_router #(
 parameter integer VL_COUNT=2,DEPTH=4,MAP_ENTRIES=3,DESC_WIDTH=67,
 parameter [32*MAP_ENTRIES-1:0] FILE_IDS={32'd3,32'd2,32'd1},
 parameter [8*MAP_ENTRIES-1:0] FILE_VLS={8'd1,8'd0,8'd0}
)(
 input wire clk,reset,input wire in_valid,output wire in_ready,
 input wire [31:0] in_file_id,input wire [DESC_WIDTH-1:0] in_descriptor,
 output /* rejected：当前输入文件ID无法映射合法VL时的拒绝组合结果。 */ wire rejected,output wire [VL_COUNT-1:0] out_valid,
 input wire [VL_COUNT-1:0] out_ready,
 output wire [VL_COUNT*DESC_WIDTH-1:0] out_descriptor,
 output wire [VL_COUNT*32-1:0] queue_levels
);
 /* route：输入文件ID查FILE_IDS/FILE_VLS所得目标VL组合索引；k：当前字节或表项位置。 */ integer route,k;
 always @* begin
  route=0;
  for(k=0;k<MAP_ENTRIES;k=k+1)
   if(in_file_id==FILE_IDS[32*k+:32])
    route=FILE_VLS[8*k+:8];
 end
 wire [VL_COUNT-1:0] space;
 assign in_ready=!reset && space[route];
 assign rejected=0;
 genvar g;
 generate for(g=0;g<VL_COUNT;g=g+1)begin: queues
  /* memory：各VL独立任务FIFO描述符存储。 */ reg [DESC_WIDTH-1:0] memory[0:DEPTH-1];
  /* head：FIFO队头读指针；tail：FIFO队尾写指针；used：当前FIFO已保存的项目数或载荷字节数。 */ reg [$clog2(DEPTH+1)-1:0] head,tail,used;
  wire push=in_valid && in_ready && route==g;
  wire pop=out_valid[g] && out_ready[g];
  assign out_descriptor[DESC_WIDTH*g+:DESC_WIDTH]=memory[head];
  assign out_valid[g]=!reset && used!=0;
  assign space[g]=used<DEPTH;
  assign queue_levels[32*g+:32]=used;
  always @(posedge clk)begin
   if(reset)begin head<=0;tail<=0;used<=0;end
   else begin
    if(push)begin memory[tail]<=in_descriptor;tail<=tail==DEPTH-1 ? 0 : tail+1;end
    if(pop)head<=head==DEPTH-1 ? 0 : head+1;
    case({push,pop})
     2'b10:used<=used+1;2'b01:used<=used-1;default:used<=used;
    endcase
   end
  end
 end endgenerate
endmodule
