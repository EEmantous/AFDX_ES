`timescale 1ns/1ps
// 将真实615A失败和重试事件送给SNMP。
module afdx_snmp_load_events #(parameter integer VL_COUNT=2,DEPTH=16)(
 input wire clk,reset, // clk: 时钟；reset: 复位。
 input wire [VL_COUNT-1:0] active,done,failed, // active/done/failed: 当前任务、完成及失败。
 input wire [32*VL_COUNT-1:0] file_ids, // file_ids: 每VL当前文件编号。
 input wire [16*VL_COUNT-1:0] results, // results: 每VL的615A完成码。
 input wire [3*VL_COUNT-1:0] retry_events, // retry_events: 三个TFTP会话的实际重试脉冲。
 output wire valid,input wire ready,output wire is_failure, // valid/ready: 通知握手；is_failure: 加载失败通知。
 output wire [31:0] file_id,value,reason, // file_id/value/reason: 通知文件、次数和原因。
 output wire [31:0] overflow_count, // overflow_count: 保留的MIB位置，固定0。
 output reg [31:0] success_count,failure_count,retry_total // success_count/failure_count/retry_total: 三个实际统计。
);
 localparam PTR=$clog2(DEPTH),CNT=$clog2(DEPTH+1);
 // queue: 待发失败/重试通知，含失败位、文件编号、次数和原因。
 reg [96:0] queue[0:DEPTH-1];
 // head/tail/used: 通知读写位置和待发数量。
 reg [PTR-1:0] head,tail;
 reg [CNT-1:0] used;
 // operation_retries: 每个VL当前任务的重试次数。
 reg [31:0] operation_retries[0:VL_COUNT-1];
 // index/next_tail/added: 遍历的VL、下一写位置和本拍入队数。
 integer index,added;
 // next_tail: 本拍连续写入加载通知时的下一FIFO位置。
 reg [PTR-1:0] next_tail;
 // delta/total/successes/failures/retried: 当前VL新增和总重试数、本拍成功、失败和总重试数。
 integer delta,total,successes,failures,retried;
 // pop: SNMP已取走一个通知。
 wire pop=valid && ready;
 assign valid=!reset && used!=0;
 assign {is_failure,file_id,value,reason}=queue[head];
 assign overflow_count=0;
 always @(posedge clk)begin
  if(reset)begin
   head<=0;tail<=0;used<=0;success_count<=0;failure_count<=0;retry_total<=0;
   for(index=0;index<VL_COUNT;index=index+1)operation_retries[index]<=0;
  end else begin
   next_tail=tail;added=0;successes=0;failures=0;retried=0;
   for(index=0;index<VL_COUNT;index=index+1)begin
    delta={31'd0,retry_events[3*index]}+retry_events[3*index+1]+retry_events[3*index+2];
    total=operation_retries[index]+delta;
    operation_retries[index]<=done[index] || !active[index] ? 0 : total;
    retried=retried+delta;
    if(done[index])begin
     if(failed[index])failures=failures+1;else successes=successes+1;
    end
    if(done[index] && failed[index])begin
     queue[next_tail]<={1'b1,file_ids[32*index+:32],32'd1,16'd0,results[16*index+:16]};
     next_tail=next_tail==DEPTH-1 ? 0 : next_tail+1;added=added+1;
    end
    if(delta!=0)begin
     queue[next_tail]<={1'b0,file_ids[32*index+:32],total[31:0],32'd0};
     next_tail=next_tail==DEPTH-1 ? 0 : next_tail+1;added=added+1;
    end
   end
   if(pop)head<=head==DEPTH-1 ? 0 : head+1'b1;
   tail<=next_tail;used<=used+added-pop;
   success_count<=success_count+successes;failure_count<=failure_count+failures;retry_total<=retry_total+retried;
  end
 end
endmodule
