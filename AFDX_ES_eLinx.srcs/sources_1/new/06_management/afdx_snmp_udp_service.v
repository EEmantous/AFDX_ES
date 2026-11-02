`timescale 1ns/1ps
// UDP161的GET回复与UDP162的Trap发送。
module afdx_snmp_udp_service #(
 parameter integer CLOCK_HZ=12500000,MANAGEMENT_BAG_CYCLES=CLOCK_HZ/100,
 parameter [15:0] RESPONSE_VL=16'h0103,NOTIFY_VL=16'h0104,BUSINESS_VL=1,
 parameter integer COMMUNITY_LENGTH=6,parameter [255:0] COMMUNITY="public",
 parameter [31:0] DEFAULT_TARGET_IP=0,DEFAULT_CONTROL=32'h3fe,
 parameter integer DEFAULT_WINDOW=CLOCK_HZ,DEFAULT_COOLDOWN=CLOCK_HZ,DEFAULT_RETRY_THRESHOLD=1
)(
 input wire clk,reset,
 input wire [31:0] uptime, // uptime: 共享本地时钟的百分之一秒值。
 input wire [7:0] rx_data,input wire rx_valid,rx_last,output wire rx_ready,
 input wire [31:0] rx_ip,input wire [15:0] rx_port,
 output wire [15:0] tx_data,output wire [1:0] tx_valid,tx_last,input wire [1:0] tx_ready,
 output wire [63:0] tx_ip,output wire [31:0] tx_src,tx_dst,
 input wire [1151:0] live_statistics,input wire [191:0] network_counts,
 input wire load_valid,load_failed,output wire load_ready,
 input wire [31:0] load_file,load_value,load_reason
);
 // in_frame: 当前请求已经开始，用于只在首字节记录回复地址。
 reg in_frame;
 /* reply_ip：接受请求首字节时锁存的源IP/源端口。 */ reg [31:0] reply_ip;/* reply_port：接受请求首字节时锁存的源IP/源端口。 */ reg [15:0] reply_port;
 wire agent_ready,rejected;
 wire allowed=agent_ready;
 assign rx_ready=agent_ready;
 wire request_event=rx_valid && rx_ready && rx_last;
 wire busy_event=0;
 wire snapshot_request;wire snapshot_valid=1;
 wire [7:0] snapshot_addr;wire [1151:0] statistics_snapshot=live_statistics;
 wire [31:0] snapshot_data=statistics_snapshot[32*snapshot_addr[7:2]+:32];
 wire [1055:0] management_live;wire [1055:0] management_snapshot=management_live;
 wire [10:0] response_length;
 wire [15:0] raw_data;wire [1:0] raw_valid,raw_last,raw_ready;
 /* granted：整包输出所有权已锁定/已授权；owner：管理发送授权来源：0响应；started：当前授权消息首字节已经握手；prefer_trap：下一次仲裁的轮询起点/优先来源。 */ reg granted,owner,started,prefer_trap;/* budget：响应和Trap共享的管理入口最小起始间隔剩余周期。 */ reg [31:0] budget;
 // One common payload-admission budget, followed by the original per-VL wire BAG.
 assign tx_data=raw_data;
 assign tx_valid=granted ? (owner ? {raw_valid[1],1'b0} : {1'b0,raw_valid[0]}) : 0;
 assign tx_last=granted ? (owner ? {raw_last[1],1'b0} : {1'b0,raw_last[0]}) : 0;
 assign raw_ready=granted ? (owner ? {tx_ready[1],1'b0} : {1'b0,tx_ready[0]}) : 0;
 always @(posedge clk)begin
  if(reset)begin granted<=0;owner<=0;started<=0;prefer_trap<=0;budget<=0;end
  else begin
   if(budget!=0)budget<=budget-1'b1;
   if(!granted && budget==0 && |raw_valid)begin
    granted<=1;started<=0;owner<=raw_valid[1] && (!raw_valid[0] || prefer_trap);
   end
   if(granted && raw_valid[owner] && raw_ready[owner])begin
    if(!started)begin started<=1;budget<=MANAGEMENT_BAG_CYCLES>0 ? MANAGEMENT_BAG_CYCLES-1 : 0;end
    if(raw_last[owner])begin granted<=0;prefer_trap<=!owner;end
   end
  end
 end
 snmp_agent #(.V2_ENABLE(1),.CLOCK_HZ(CLOCK_HZ),.COMMUNITY_LENGTH(COMMUNITY_LENGTH),.COMMUNITY(COMMUNITY)) agent(
  .clk(clk),.reset_n(!reset),.uptime(uptime),.in_data(rx_data),.in_valid(rx_valid && allowed),.in_last(rx_last),.in_ready(agent_ready),
  .out_data(raw_data[7:0]),.out_valid(raw_valid[0]),.out_last(raw_last[0]),.out_length(response_length),.out_ready(raw_ready[0]),
  .snapshot_request(snapshot_request),.snapshot_valid(snapshot_valid),.snapshot_addr(snapshot_addr),.snapshot_data(snapshot_data),
  .management_snapshot(management_snapshot),.rejected_event(rejected));
 assign tx_ip[31:0]=reply_ip;assign tx_src[15:0]=161;assign tx_dst[15:0]=reply_port;
 wire ev_valid,ev_ready;wire [31:0] ec,es,ev,et,ed,target_ip;
 wire [15:0] target_vl,unused_vl;wire [255:0] community;wire [5:0] clen;
 wire [31:0] route_ip;wire [10:0] trap_length;
 snmp_v2_control #(.CLOCK_HZ(CLOCK_HZ),.RESPONSE_VL(RESPONSE_VL),.BUSINESS_VL(BUSINESS_VL),.FIXED_NOTIFY_VL(NOTIFY_VL),
  .DEFAULT_CONTROL(DEFAULT_CONTROL | (DEFAULT_TARGET_IP!=0 ? 32'd1 : 32'd0)),
  .DEFAULT_TARGET_IP(DEFAULT_TARGET_IP),.DEFAULT_WINDOW(DEFAULT_WINDOW),.DEFAULT_COOLDOWN(DEFAULT_COOLDOWN),
  .DEFAULT_RETRY_THRESHOLD(DEFAULT_RETRY_THRESHOLD),.DEFAULT_COMMUNITY(COMMUNITY),.DEFAULT_COMMUNITY_LENGTH(COMMUNITY_LENGTH)) control(
  .clk(clk),.reset_n(!reset),.cfg_valid(1'b0),.cfg_write(1'b0),.cfg_addr(12'd0),
  .cfg_wdata(32'd0),.cfg_ready(),.cfg_error(),.cfg_rdata(),
  .network_counts(network_counts),.clear_epoch(32'd0),.request_event(request_event),
  .response_event(tx_valid[0] && tx_ready[0] && tx_last[0]),.rejected_event(rejected),.busy_event(busy_event),
  .trap_event(tx_valid[1] && tx_ready[1] && tx_last[1]),
  .load_valid(load_valid),.load_failed(load_failed),.load_file(load_file),.load_value(load_value),.load_reason(load_reason),.load_ready(load_ready),
  .event_valid(ev_valid),.event_ready(ev_ready),.event_class(ec),.event_source(es),.event_value(ev),.event_threshold(et),.event_detail(ed),
  .target_ip(target_ip),.target_vl(target_vl),.community(community),.community_length(clen),.mib_live(management_live));
 snmp_v2_trap #(.CLOCK_HZ(CLOCK_HZ)) trap(
  .clk(clk),.reset_n(!reset),.uptime(uptime),.event_valid(ev_valid),.event_ready(ev_ready),
  .event_class(ec),.event_source(es),.event_value(ev),.event_threshold(et),.event_detail(ed),
  .target_ip(target_ip),.target_vl(target_vl),.community(community),.community_length(clen),
  .out_data(raw_data[15:8]),.out_valid(raw_valid[1]),.out_last(raw_last[1]),.out_ready(raw_ready[1]),
  .out_length(trap_length),.route_ip(route_ip),.route_vl(unused_vl));
 assign tx_ip[63:32]=route_ip;assign tx_src[31:16]=162;assign tx_dst[31:16]=162;
 always @(posedge clk)begin
  if(reset)begin in_frame<=0;reply_ip<=0;reply_port<=0;
end
  else begin
   if(rx_valid && rx_ready)begin
    if(!in_frame)begin reply_ip<=rx_ip;reply_port<=rx_port;end
    in_frame<=!rx_last;
   end
  end
 end
endmodule
