`timescale 1ns/1ps
// 参数直接提供配置；记录GET统计并排队必要Trap事件。
module snmp_v2_control #(
    parameter integer CLOCK_HZ=12500000, EVENT_DEPTH=16,
    parameter integer COOLDOWN_SLOTS=32,
    parameter [15:0] RESPONSE_VL=16'h0103,BUSINESS_VL=16'h0101,
    parameter [15:0] FIXED_NOTIFY_VL=0,
    parameter [31:0] COUNTER_MAX=32'hffffffff,
    parameter [31:0] DEFAULT_CONTROL=32'h3fe,DEFAULT_TARGET_IP=0,
    parameter integer DEFAULT_WINDOW=CLOCK_HZ,DEFAULT_COOLDOWN=CLOCK_HZ,DEFAULT_RETRY_THRESHOLD=1,
    parameter integer DEFAULT_COMMUNITY_LENGTH=6,parameter [255:0] DEFAULT_COMMUNITY="public"
)(
    input wire clk,reset_n,
    input wire cfg_valid,cfg_write,
    input wire [11:0] cfg_addr,
    input wire [31:0] cfg_wdata,
    output wire cfg_ready,
    output wire cfg_error,
    output wire [31:0] cfg_rdata,
    input wire [191:0] network_counts,
    input wire [31:0] clear_epoch,
    input wire request_event,response_event,rejected_event,busy_event,trap_event,
    input wire load_valid,load_failed,
    input wire [31:0] load_file,load_value,load_reason,
    output wire load_ready,
    output wire event_valid,
    input wire event_ready,
    output wire [31:0] event_class,event_source,event_value,event_threshold,event_detail,
    output wire [31:0] target_ip,
    output wire [15:0] target_vl,
    output wire [255:0] community,
    output wire [5:0] community_length,
    output wire [1055:0] mib_live
);
 localparam PTR=$clog2(EVENT_DEPTH),CNT=$clog2(EVENT_DEPTH+1);
 // queue: 待发事件的类别、来源、数值和细节。
 reg [99:0] queue[0:EVENT_DEPTH-1];
 // head/tail/used: 事件读写位置和待发数量。
 reg [PTR-1:0] head,tail;
 reg [CNT-1:0] used;
 // seen_a/seen_b: 已报告的A/B损坏总数。
 reg [31:0] seen_a,seen_b;
 // counts: SNMP请求、响应、拒绝、忙和Trap发送数。
 reg [31:0] counts[0:4];
 // category/source/value/detail: 本拍新事件的类别、来源、数值和细节。
 reg [3:0] category;
 reg [31:0] source,value,detail;
 // candidate/enabled/push/pop: 本拍存在事件、允许通知、入队和出队。
 wire candidate=category!=0;
 wire enabled=DEFAULT_CONTROL[0] && DEFAULT_CONTROL[category];
 wire pop=event_valid && event_ready;
 wire push=candidate && enabled && used<EVENT_DEPTH;
 assign cfg_ready=reset_n && cfg_valid;
 assign cfg_error=0;
 assign cfg_rdata=0;
 assign target_ip=DEFAULT_TARGET_IP;
 assign target_vl=FIXED_NOTIFY_VL!=0 ? FIXED_NOTIFY_VL : 16'h0104;
 assign community=DEFAULT_COMMUNITY;
 assign community_length=DEFAULT_COMMUNITY_LENGTH;
 assign event_valid=reset_n && used!=0;
 assign {event_class,event_source,event_value,event_detail}={28'd0,queue[head]};
 assign event_threshold=event_class==9 ? DEFAULT_RETRY_THRESHOLD : 1;
 assign load_ready=reset_n && used<EVENT_DEPTH && network_counts[31:0]==seen_a && network_counts[63:32]==seen_b;
 always @*begin
  category=0;source=0;value=0;detail=0;
  if(network_counts[31:0]!=seen_a)begin category=1;value=network_counts[31:0]-seen_a;end
  else if(network_counts[63:32]!=seen_b)begin category=2;source=1;value=network_counts[63:32]-seen_b;end
  else if(load_valid && load_ready)begin
   category=load_failed ? 8 : 9;source=load_file;value=load_failed ? 1 : load_value;detail=load_reason;
  end
 end
 genvar item; // item: 管理MIB中统计和常量的位置。
 generate for(item=0;item<33;item=item+1)begin: mib
  if(item<5)assign mib_live[32*item+:32]=counts[item];
  else if(item==7)assign mib_live[32*item+:32]=clear_epoch;
  else if(item==8)assign mib_live[32*item+:32]=DEFAULT_CONTROL;
  else if(item==9)assign mib_live[32*item+:32]=DEFAULT_WINDOW;
  else if(item==10)assign mib_live[32*item+:32]=DEFAULT_COOLDOWN;
  else if(item==11)assign mib_live[32*item+:32]=DEFAULT_TARGET_IP;
  else if(item==12)assign mib_live[32*item+:32]={16'd0,target_vl};
  else if(item==13)assign mib_live[32*item+:32]=DEFAULT_COMMUNITY_LENGTH;
  else if(item>=14 && item<23)assign mib_live[32*item+:32]=item==22 ? DEFAULT_RETRY_THRESHOLD : 1;
  else if(item>=23 && item<31)assign mib_live[32*item+:32]=DEFAULT_COMMUNITY[32*(item-23)+:32];
  else if(item==31)assign mib_live[32*item+:32]=used;
  else assign mib_live[32*item+:32]=0;
 end endgenerate
 integer counter; // counter: 复位统计数组的位置。
 always @(posedge clk)if(push)queue[tail]<={category,source,value,detail};
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin
   head<=0;tail<=0;used<=0;seen_a<=0;seen_b<=0;
   for(counter=0;counter<5;counter=counter+1)counts[counter]<=0;
  end else begin
   if(request_event)counts[0]<=counts[0]+1'b1;
   if(response_event)counts[1]<=counts[1]+1'b1;
   if(rejected_event)counts[2]<=counts[2]+1'b1;
   if(busy_event)counts[3]<=counts[3]+1'b1;
   if(trap_event)counts[4]<=counts[4]+1'b1;
   if(candidate && (!enabled || push))begin
    if(category==1)seen_a<=network_counts[31:0];
    if(category==2)seen_b<=network_counts[63:32];
   end
   if(push)tail<=tail==EVENT_DEPTH-1 ? 0 : tail+1'b1;
   if(pop)head<=head==EVENT_DEPTH-1 ? 0 : head+1'b1;
   used<=used+push-pop;
  end
 end
endmodule
