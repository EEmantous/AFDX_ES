`timescale 1ns/1ps
// 按615A控制文件推进上传、下载及完成状态。
module arinc615a_controller #(
 parameter LOADER=0,TARGET_TASK_FILTER=0,
 parameter integer OP_TIMEOUT=125000000,
 parameter integer STATUS_INTERVAL=12500000,
 parameter integer NAME_BYTES=32
)(
 input wire clk,reset,abort,
 input wire cmd_valid,output wire cmd_ready,input wire [2:0] cmd_operation,
 input wire [31:0] cmd_peer_ip,
 input wire [8*NAME_BYTES-1:0] header_name,data_name,
 input wire header_ok,header_bad,data_commit,data_bad,
 output wire header_pending,data_pending,
 input wire srv_open,input wire [3:0] srv_kind,input wire [31:0] srv_peer,
 output wire [15:0] admission_status,
 input wire event_valid,event_ok,event_failed,input wire [3:0] event_kind,
 input wire [15:0] event_status,input wire [8*NAME_BYTES-1:0] event_name,
 input wire c_ready,c_done,c_failed,
 output wire c_valid,output /* c_write：主动命令方向：1发WRQ并发送文件。 */ reg c_write,output /* c_kind：主动传输文件类别1..14。 */ reg [3:0] c_kind,
 output /* c_name：主动传输应用文件名。 */ reg [8*NAME_BYTES-1:0] c_name,
 input wire s_ready,s_done,s_failed,
 output wire s_valid,output wire [3:0] s_kind,output wire [15:0] s_status,
 output wire [15:0] status_counter,output wire [7:0] percent,
 output /* peer_ip：当前615A操作锁定的对端IPv4地址。 */ reg [31:0] peer_ip,
 output /* done：一次操作完成指示；failed：本次操作失败标志。 */ reg done,failed,output /* result：最终615。 */ reg [15:0] result,
 output wire busy,output wire abort_transfers,output wire [2:0] operation
);
 localparam IDLE=0,L_INIT=1,L_LIST=2,L_WAIT_LIST=3,L_WAIT_FINAL=4,
 T_INIT=5,T_WAIT_LIST=6,T_HEAD=7,T_VERIFY_HEAD=8,T_DATA=9,T_COMMIT=10,T_LIST=11,
 ISSUE=12,FINISH=13;
 /* state：当前步骤；next_state：当前命令结束后的步骤。 */ reg [3:0] state,next_state;
 /* op：当前业务操作1信息、2上传、3下载、4操作者下载。 */ reg [2:0] op;
 /* status_timer：距上次发送615A状态的周期数。 */ reg [31:0] status_timer;
 /* seq：成功交给状态发送引擎的状态计数器；status：准备发送的615。 */ reg [15:0] seq,status;
 /* status_pending：有一份状态控制文件等待提交给独立状态TFTP引擎；status_inflight：状态控制文件已经提交。 */ reg status_pending,status_inflight;
 assign operation=op;
 assign busy=state!=IDLE;
 assign cmd_ready=LOADER && state==IDLE;
 assign header_pending=state==T_VERIFY_HEAD;
 assign data_pending=state==T_COMMIT;
 wire target_allowed=!TARGET_TASK_FILTER || (cmd_valid && srv_kind[2:0]==cmd_operation &&
   (cmd_peer_ip==0 || srv_peer==cmd_peer_ip));
 assign admission_status=(state==IDLE && srv_kind>=1 && srv_kind<=4 && target_allowed) ? 16'h0001 : 16'h1000;
 assign c_valid=state==ISSUE;
 assign s_valid=!LOADER && status_pending && !status_inflight;
 assign s_kind=op==1 ? 6 : op==2 ? 8 : 10;
 assign s_status=status;
 assign status_counter=seq;
 assign percent=status==3 ? 100 : 0;
 assign abort_transfers=abort || (state!=IDLE && ((c_done && c_failed) || event_failed || (s_done && s_failed)));
 task issue;
 input wr;input [3:0] kind;input [8*NAME_BYTES-1:0] name;input [3:0] following;
 begin c_write<=wr;c_kind<=kind;c_name<=name;next_state<=following;state<=ISSUE;end
 endtask
 task finish;
 input [15:0] code;
 begin result<=code;
  if(LOADER)begin done<=1;failed<=code!=3;state<=IDLE;end
  else begin status<=code;status_pending<=1;state<=FINISH;end
 end
 endtask
 always @(posedge clk)begin
  if(reset)begin
   state<=IDLE;next_state<=IDLE;op<=0;status_timer<=0;seq<=0;status<=1;
   status_pending<=0;status_inflight<=0;peer_ip<=0;
   c_write<=0;c_kind<=0;c_name<=0;done<=0;failed<=0;result<=0;
  end else begin
   done<=0;failed<=0;
   if(state==IDLE)status_timer<=0;else status_timer<=status_timer+1'b1;
   if(s_valid && s_ready)begin status_pending<=0;status_inflight<=1;seq<=seq+1'b1;status_timer<=0;end
   if(s_done)status_inflight<=0;
   if(!LOADER && state!=IDLE && state!=T_INIT && state!=FINISH &&
      status_timer>=STATUS_INTERVAL-1 && !status_inflight)begin
    status<=2;status_pending<=1;status_timer<=0;
   end
   if(abort_transfers)begin
    done<=1;failed<=1;result<=16'h1003;state<=IDLE;status_pending<=0;status_inflight<=0;
   end else if((c_done && c_failed) || event_failed || (s_done && s_failed))begin
    if(state!=IDLE)begin
     done<=1;failed<=1;result<=16'h1003;state<=IDLE;status_pending<=0;status_inflight<=0;
    end
   end else case(state)
   IDLE:begin
    if(LOADER && cmd_valid && cmd_ready)begin
     begin op<=cmd_operation;peer_ip<=cmd_peer_ip;result<=0;seq<=0;
      issue(0,{1'b0,cmd_operation},0,L_INIT);
     end
    end else if(!LOADER && srv_open && srv_kind>=1 && srv_kind<=4 && target_allowed)begin
     op<=srv_kind[2:0];peer_ip<=srv_peer;state<=T_INIT;result<=0;seq<=0;status<=1;
    end
   end
   ISSUE:if(c_ready)state<=next_state;
   L_INIT:if(event_valid && event_kind==op)begin
    if(event_status!=1)finish(event_status);
    else if(op==1)state<=L_WAIT_FINAL;
    else if(op==2)issue(1,7,header_name,L_LIST);
    else if(op==3)issue(1,9,data_name,L_LIST);
    else state<=L_WAIT_LIST;
   end
   L_LIST:if(c_done)state<=L_WAIT_FINAL;
   L_WAIT_LIST:if(event_valid && event_kind==11)begin
    issue(1,12,event_name,L_LIST);
   end
   L_WAIT_FINAL:if(event_valid && event_kind==(op==1 ? 6 : op==2 ? 8 : 10))begin
    if(event_status==3 || event_status>=16'h1000)finish(event_status);
   end
   T_INIT:if(event_valid && event_kind==op)begin
    status<=1;status_pending<=1;
    if(op==1)issue(1,5,0,T_LIST);
    else if(op==4)issue(1,11,data_name,T_LIST);
    else state<=T_WAIT_LIST;
   end
   T_LIST:if(c_done)begin
    if(op==1)finish(3);else state<=T_WAIT_LIST;
   end
   T_WAIT_LIST:if(event_valid && event_kind==(op==2 ? 7 : op==3 ? 9 : 12))begin
    if(op==2)begin issue(0,14,event_name,T_HEAD);end
    else begin issue(1,13,event_name,T_DATA);end
   end
   T_HEAD:if(c_done)state<=T_VERIFY_HEAD;
   T_VERIFY_HEAD:begin
    if(header_bad)finish(16'h1007);
    else if(header_ok)issue(0,13,data_name,T_DATA);
   end
   T_DATA:if(c_done)begin if(op==2)state<=T_COMMIT;else finish(3);end
   T_COMMIT:begin if(data_bad)finish(16'h1007);else if(data_commit)finish(3);end
   FINISH:if(!status_pending && !status_inflight && !s_valid)begin
    done<=1;failed<=result!=3;state<=IDLE;
   end
   default:state<=IDLE;
   endcase
  end
 end
endmodule
