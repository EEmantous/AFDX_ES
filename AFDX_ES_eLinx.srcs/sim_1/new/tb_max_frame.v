`timescale 1ns/1ps
// 验证实际网络默认配置的1471字节UDP收发，以及调度/MAC的1578字节边界。
module tb_max_frame;
 // clk/reset/cycles: 20ns时钟、复位和下游暂停节拍。
 reg clk=0,reset=1;integer cycles=0;always #10 clk=~clk;
 // tx_data/tx_valid/tx_last/tx_ready: 两条UDP发送入口及握手。
 reg [15:0] tx_data=0;reg [1:0] tx_valid=0,tx_last=0;wire [1:0] tx_ready;
 // tx_ip/tx_src/tx_dst: 每条发送入口的目标IP和UDP端口。
 reg [63:0] tx_ip={2{32'h0a000001}};reg [31:0] tx_src=0,tx_dst=0;
 // rx_data/rx_valid/rx_last/rx_ready/rx_channel: 去重后的UDP正文与暂停控制。
 wire [7:0] rx_data,rx_channel;wire rx_valid,rx_last;reg [1:0] rx_ready=0;
 // rx_ip/rx_src/rx_dst: 接收元数据，端口同时标识当前测试报文。
 wire [31:0] rx_ip;wire [15:0] rx_src,rx_dst;
 // gmii_a/gmii_b/en_a/en_b/er_a/er_b: 真实A/B发送字节，直接接回本网络的接收端。
 wire [7:0] gmii_a,gmii_b;wire en_a,en_b,er_a,er_b;
 afdx_network #(.VL_COUNT(2),.RX_VL_COUNT(2),.TX_VL_IDS({16'd2,16'd1}),.RX_VL_IDS({16'd2,16'd1}),.LOCAL_IP(32'h0a000001)) network(
  .clk(clk),.reset(reset),.tx_data(tx_data),.tx_valid(tx_valid),.tx_last(tx_last),.tx_ready(tx_ready),
  .tx_dst_ip(tx_ip),.tx_src_port(tx_src),.tx_dst_port(tx_dst),
  .rx_data(rx_data),.rx_valid(rx_valid),.rx_last(rx_last),.rx_ready(rx_ready),.rx_channel(rx_channel),
  .rx_src_ip(rx_ip),.rx_src_port(rx_src),.rx_dst_port(rx_dst),.stat_select(8'd0),.stat_value(),.drop_event(),.snmp_statistics(),.snmp_alarm_counts(),
  .gmii_tx_a_clk(),.gmii_tx_a_txd(gmii_a),.gmii_tx_a_en(en_a),.gmii_tx_a_er(er_a),
  .gmii_tx_b_clk(),.gmii_tx_b_txd(gmii_b),.gmii_tx_b_en(en_b),.gmii_tx_b_er(er_b),
  .gmii_rx_a_clk(clk),.gmii_rx_a_rxd(gmii_a),.gmii_rx_a_dv(en_a),.gmii_rx_a_er(er_a),
  .gmii_rx_b_clk(clk),.gmii_rx_b_rxd(gmii_b),.gmii_rx_b_dv(en_b),.gmii_rx_b_er(er_b));

 // raw_data/raw_valid/raw_last/raw_ready: 向实际帧调度器输入接近1578字节的核心帧。
 reg [15:0] raw_data=0;reg [1:0] raw_valid=0,raw_last=0;wire [1:0] raw_ready;
 // scheduled_data/scheduled_valid/scheduled_last/mac_ready: 调度器到MAC的核心字节。
 wire [7:0] scheduled_data;wire scheduled_valid,scheduled_last,mac_ready;
 // raw_wire/raw_en/raw_er/raw_previous/raw_start: MAC物理输出及BAG起帧事件。
 wire [7:0] raw_wire;wire raw_en,raw_er;reg raw_previous=0;wire raw_start=raw_en && !raw_previous;
 // raw_received/raw_received_valid/raw_received_last/raw_sink_ready: MAC去掉前导码和FCS后的完整正文。
 wire [7:0] raw_received;wire raw_received_valid,raw_received_last;reg raw_sink_ready=0;
 // raw_good/raw_drop/raw_tx_count/raw_saved: MAC统计及已收核心帧长度。
 wire [31:0] raw_good,raw_drop,raw_tx_count;wire [11:0] raw_saved;
 afdx_multivl_scheduler raw_scheduler(
  .clk(clk),.reset(reset),.in_data(raw_data),.in_valid(raw_valid),.in_last(raw_last),.in_ready(raw_ready),
  .out_data(scheduled_data),.out_valid(scheduled_valid),.out_last(scheduled_last),.out_ready(mac_ready),
  .mac_start_a(raw_start),.mac_start_b(raw_start),.selected_vl(),.saved_length(),.queue_levels(),.drop_event());
 ethernet_mac_tx raw_mac_tx(
  .clk(clk),.reset(reset),.in_data(scheduled_data),.in_valid(scheduled_valid),.in_last(scheduled_last),.in_ready(mac_ready),
  .gmii_txd(raw_wire),.gmii_tx_en(raw_en),.gmii_tx_er(raw_er),.drop_event(),.frame_count(raw_tx_count),.saved_length());
 ethernet_mac_rx raw_mac_rx(
  .rx_clk(clk),.clk(clk),.reset(reset),.gmii_rxd(raw_wire),.gmii_rx_dv(raw_en),.gmii_rx_er(raw_er),
  .out_data(raw_received),.out_valid(raw_received_valid),.out_last(raw_received_last),.out_ready(raw_sink_ready),
  .good_frames(raw_good),.drop_frames(raw_drop),.saved_length(raw_saved));

 function integer payload_length(input integer id); // id: UDP报文测试编号。
 begin case(id)
  0:payload_length=1;1:payload_length=17;2:payload_length=511;3:payload_length=512;
  4:payload_length=516;5:payload_length=517;6:payload_length=1023;7:payload_length=1024;
  8:payload_length=1470;default:payload_length=1471;
 endcase end endfunction
 function integer core_length(input integer id); // id: MAC边界场景编号。
 begin case(id)0:core_length=1566;1:core_length=1574;default:core_length=1578;endcase end endfunction
 function [7:0] pattern(input integer id,input integer position); // id/position: 报文编号及字节位置，跨RAM块时改变内容。
 begin pattern=(id*53)^(position*29)^(position>>8);end endfunction
 task automatic send_udp(input integer id); // id: 待发送的UDP报文编号。
  integer lane,position; // lane/position: 发送VL入口和当前正文偏移。
  begin
   lane=id%2;
   @(negedge clk);tx_src[16*lane+:16]=30000+id;tx_dst[16*lane+:16]=40000+id;
   for(position=0;position<payload_length(id);position=position+1)begin
    tx_data[8*lane+:8]=pattern(id,position);tx_valid[lane]=1;tx_last[lane]=position==payload_length(id)-1;
    @(posedge clk);while(!tx_ready[lane])@(posedge clk);
    @(negedge clk);
   end
   tx_valid[lane]=0;tx_last[lane]=0;
  end
 endtask
 task automatic send_raw(input integer id); // id: 待发送的核心帧场景。
  integer lane,position; // lane/position: 帧队列入口及核心字节位置。
  begin
   lane=id%2;@(negedge clk);
   for(position=0;position<core_length(id);position=position+1)begin
    raw_data[8*lane+:8]=pattern(id+20,position);raw_valid[lane]=1;raw_last[lane]=position==core_length(id)-1;
    @(posedge clk);while(!raw_ready[lane])@(posedge clk);
    @(negedge clk);
   end
   raw_valid[lane]=0;raw_last[lane]=0;
  end
 endtask

 // seen/received_frames/rx_position/rx_id/rx_fd: 已收报文、总数、当前偏移、编号及输出文件。
 reg [11:0] seen=0;integer received_frames=0,rx_position=0,rx_id,rx_fd;
 // raw_received_frames/raw_position/raw_fd: MAC场景的接收帧数、正文位置及输出文件。
 integer raw_received_frames=0,raw_position=0,raw_fd;
 // udp_trace/raw_trace/events/file_path: 物理帧、事件CSV文件和接收文件名。
 integer udp_trace,raw_trace,events;reg [8191:0] file_path;
 // udp_previous/udp_position/udp_frames/udp_id/udp_high/udp_start/udp_end: 网络物理帧采样和编号。
 reg udp_previous=0;integer udp_position=0,udp_frames=0,udp_id;reg [7:0] udp_high;real udp_start,udp_end;
 // raw_wire_position/raw_wire_frames/raw_wire_start/raw_wire_end: MAC边界物理帧的长度、编号和时刻。
 integer raw_wire_position=0,raw_wire_frames=0;real raw_wire_start,raw_wire_end;
 always @(negedge clk)begin
  rx_ready=!reset && cycles%7!=0 && cycles%11!=0 ? 2'b11 : 0;
  raw_sink_ready=!reset && cycles%5!=0 && cycles%13!=0;
 end
 always @(posedge clk)begin
  if(reset)begin cycles=0;raw_previous=0;end
  else begin
   cycles=cycles+1;
   if(en_a!==en_b || er_a || er_b || (en_a && gmii_a!==gmii_b))$fatal(1,"Maximum frame A/B mismatch");
   if(en_a)begin
    if(!udp_previous)udp_start=$realtime;
    if(udp_position==42)udp_high=gmii_a;
    if(udp_position==43)udp_id={udp_high,gmii_a}-30000;
    $fwrite(udp_trace,"%02h",gmii_a);udp_position=udp_position+1;udp_end=$realtime;
   end else if(udp_previous)begin
    $fwrite(udp_trace,"\n");
    if(udp_position!=12+(payload_length(udp_id)+43<60 ? 60 : payload_length(udp_id)+43))$fatal(1,"UDP physical length mismatch");
    $fwrite(events,"UDP,%0d,%0d,%0d,%0d,%.0f,%.0f\n",udp_id,payload_length(udp_id),udp_position-12,udp_position,udp_start,udp_end);
    udp_position=0;udp_frames=udp_frames+1;
   end
   udp_previous=en_a;
   if(rx_valid && rx_ready[rx_channel])begin
    rx_id=rx_src-30000;
    if(rx_id<0 || rx_id>11 || rx_channel!=rx_id%2 || rx_dst!=40000+rx_id || rx_ip!=32'h0a000001)$fatal(1,"UDP metadata mismatch");
    if(rx_position==0)begin
     if(seen[rx_id])$fatal(1,"A/B duplicate delivered to UDP sink");
     $sformat(file_path,"udp_received_%0d.bin",rx_id);rx_fd=$fopen(file_path,"wb");
    end
    if(rx_data!==pattern(rx_id,rx_position) || rx_last!==(rx_position==payload_length(rx_id)-1))$fatal(1,"UDP payload or last mismatch id=%0d offset=%0d",rx_id,rx_position);
    $fwrite(rx_fd,"%c",rx_data);rx_position=rx_position+1;
    if(rx_last)begin
     $fclose(rx_fd);seen[rx_id]=1;received_frames=received_frames+1;rx_position=0;
     $display("UDP_LENGTH PASS id=%0d bytes=%0d vl=%0d end_ns=%0d",rx_id,payload_length(rx_id),rx_channel+1,$time);
    end
   end
   if(raw_en)begin
    if(!raw_previous)raw_wire_start=$realtime;
    $fwrite(raw_trace,"%02h",raw_wire);raw_wire_position=raw_wire_position+1;raw_wire_end=$realtime;
   end else if(raw_previous)begin
    $fwrite(raw_trace,"\n");
    if(raw_wire_position!=core_length(raw_wire_frames)+12)$fatal(1,"Raw physical length mismatch");
    $fwrite(events,"MAC,%0d,0,%0d,%0d,%.0f,%.0f\n",raw_wire_frames,core_length(raw_wire_frames),raw_wire_position,raw_wire_start,raw_wire_end);
    raw_wire_position=0;raw_wire_frames=raw_wire_frames+1;
   end
   raw_previous=raw_en;
   if(raw_received_valid && raw_sink_ready)begin
    if(raw_position==0)begin $sformat(file_path,"mac_received_%0d.bin",raw_received_frames);raw_fd=$fopen(file_path,"wb");end
    if(raw_received!==pattern(raw_received_frames+20,raw_position) || raw_received_last!==(raw_position==core_length(raw_received_frames)-1))$fatal(1,"MAC maximum payload mismatch case=%0d offset=%0d",raw_received_frames,raw_position);
    $fwrite(raw_fd,"%c",raw_received);raw_position=raw_position+1;
    if(raw_received_last)begin
     if(raw_saved!=core_length(raw_received_frames))$fatal(1,"MAC receive saved length mismatch");
     $fclose(raw_fd);$display("MAC_LENGTH PASS core=%0d wire=%0d end_ns=%0d",core_length(raw_received_frames),core_length(raw_received_frames)+12,$time);
     raw_position=0;raw_received_frames=raw_received_frames+1;
    end
   end
  end
 end
 // scenario: 串行长度验证及最后两个最大报文并发写入的场景编号。
 integer scenario;
 initial begin
  udp_trace=$fopen("udp_frames.hex","w");raw_trace=$fopen("mac_frames.hex","w");events=$fopen("frame_events.csv","w");
  $fwrite(events,"kind,index,payload_bytes,core_bytes,wire_bytes,start_ns,end_ns\n");
  repeat(8)@(negedge clk);reset=0;
  for(scenario=0;scenario<10;scenario=scenario+1)begin
   send_udp(scenario);wait(received_frames==scenario+1);repeat(80)@(negedge clk);
  end
  fork send_udp(10);send_udp(11);join
  wait(received_frames==12);repeat(80)@(negedge clk);
  for(scenario=0;scenario<3;scenario=scenario+1)begin
   send_raw(scenario);wait(raw_received_frames==scenario+1);repeat(80)@(negedge clk);
  end
  if(seen!==12'hfff || udp_frames!=12 || raw_good!=3 || raw_drop!=0 || raw_tx_count!=3 || raw_wire_frames!=3)$fatal(1,"Maximum frame totals mismatch");
  $fclose(udp_trace);$fclose(raw_trace);$fclose(events);
  $display("MAX FRAME PASS UDP_payload=1471 MAC_frame=1518 wire=1526 wire_1578=PASS MAC_1578=PASS core_1578=PASS udp_frames=12 raw_frames=3");$finish;
 end
 initial begin #100000000;$fatal(1,"Maximum frame watchdog");end
endmodule
