`timescale 1ns/1ps
// 直接使用任务RAM队首，完成记录保存到APP取走。
module arinc615a_tasks #(
 parameter LOADER=1,parameter integer VL_COUNT=2,TASK_DEPTH=4,EVENT_DEPTH=16,MAP_ENTRIES=3,
 parameter integer OP_TIMEOUT=125000000,TASK_GUARD_CYCLES=12500,
 parameter [32*MAP_ENTRIES-1:0] FILE_IDS={32'd3,32'd2,32'd1},
 parameter [8*MAP_ENTRIES-1:0] FILE_VLS={8'd1,8'd0,8'd0}
)(
 input wire clk,reset,
 input wire [66:0] submit_data,input wire submit_valid,output wire submit_ready,submit_error,
 input wire [VL_COUNT-1:0] cancel,
 input wire file_start_error,
 input wire [31:0] locked_count,
 output wire reserve_file,output wire [2:0] reserve_operation,
 input wire [VL_COUNT-1:0] file_abort,commit_bad,
 output wire [VL_COUNT-1:0] abort,active,done,failed,cmd_valid,
 output wire [32*VL_COUNT-1:0] file_ids,peer_ips,output wire [3*VL_COUNT-1:0] operations,
 input wire [VL_COUNT-1:0] cmd_ready,service_done,service_failed,
 input wire [16*VL_COUNT-1:0] service_result,
 input wire find_done,
 output wire [63:0] result_data,output wire result_valid,input wire result_pop,
 output wire result_pending,output wire [3:0] events,
 input wire [7:0] stat_select,output wire [31:0] stat_value
);
 // queued_valid/queued_ready: 各VL队首有效及当前任务完成出队。
 wire [VL_COUNT-1:0] queued_valid,queued_ready;
 // queued: 每VL队首的文件ID、操作和对端IP。
 wire [67*VL_COUNT-1:0] queued;
 // accepted: APP目录中的任务已交给对应VL队列。
 wire accepted=submit_valid && submit_ready;
 assign submit_error=0;
 assign reserve_file=accepted;
 assign reserve_operation=submit_data[34:32];
 assign abort=cancel;
 assign active=queued_valid;
 assign done=service_done & queued_valid;
 assign failed=service_failed & queued_valid;
 assign queued_ready=done;
 assign events={find_done,1'b0,|(done & failed),|(done & ~failed)};
 assign stat_value=0;
 arinc615a_task_router #(.VL_COUNT(VL_COUNT),.DEPTH(TASK_DEPTH),.MAP_ENTRIES(MAP_ENTRIES),
  .FILE_IDS(FILE_IDS),.FILE_VLS(FILE_VLS),.DESC_WIDTH(67)) queue(
  .clk(clk),.reset(reset),.in_valid(submit_valid),.in_ready(submit_ready),.in_file_id(submit_data[66:35]),
  .in_descriptor(submit_data),.rejected(),.out_valid(queued_valid),.out_ready(queued_ready),
  .out_descriptor(queued),.queue_levels());
 genvar vl; // vl: 当前业务VL通道。
 generate for(vl=0;vl<VL_COUNT;vl=vl+1)begin: channels
  reg started; // started: 当前加载器任务已被615A接收。
  assign {file_ids[32*vl+:32],operations[3*vl+:3],peer_ips[32*vl+:32]}=queued[67*vl+:67];
  assign cmd_valid[vl]=queued_valid[vl] && (!LOADER || !started);
  always @(posedge clk)begin
   if(reset || done[vl])started<=0;
   else if(cmd_valid[vl] && cmd_ready[vl])started<=1;
  end
 end endgenerate
 localparam PTR=EVENT_DEPTH<=1 ? 1 : $clog2(EVENT_DEPTH),CNT=$clog2(EVENT_DEPTH+1);
 // results: 完成记录，包含失败位、VL、615A结果和文件ID。
 reg [63:0] results[0:EVENT_DEPTH-1];
 // head/tail/used: 结果读写位置和待取数量。
 reg [PTR-1:0] head,tail;
 reg [CNT-1:0] used;
 // added/next_tail/index: 本拍完成数、下一写位置及遍历通道。
 integer added,index;
 // next_tail: 本拍连续写入完成记录时的下一FIFO位置。
 reg [PTR-1:0] next_tail;
 // pop: APP本拍取走一个完成记录。
 wire pop=result_valid && result_pop;
 assign result_valid=!reset && used!=0;
 assign result_pending=used!=0;
 assign result_data=results[head];
 always @(posedge clk)begin
  if(reset)begin head<=0;tail<=0;used<=0;end
  else begin
   added=0;next_tail=tail;
   if(pop)head<=head==EVENT_DEPTH-1 ? 0 : head+1'b1;
   for(index=0;index<VL_COUNT;index=index+1)if(done[index])begin
    results[next_tail]<={7'd0,failed[index],index[7:0],service_result[16*index+:16],file_ids[32*index+:32]};
    next_tail=next_tail==EVENT_DEPTH-1 ? 0 : next_tail+1;added=added+1;
   end
   tail<=next_tail;used<=used+added-pop;
  end
 end
endmodule
