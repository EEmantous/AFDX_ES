`timescale 1ns/1ps
// Direct public-pin stream stimulus and record sink; no bus/address adapter.
// WAIT_CYCLES：APP端等待文件或完成记录的最长周期数，大容量测试按协议等待时间设置。
module tb_app_file_driver #(parameter CAPACITY=2048,FILES=2,WAIT_CYCLES=2000000)(
 input wire clk,reset,output /* data：各VL输入字节。 */ reg [7:0] data=0,output /* valid：各VL输入有效位。 */ reg valid=0,input wire ready,
 input wire [7:0] reply_data,input wire reply_valid,output reg reply_ready=1
);
 /* slow：接收端每17拍停顿一拍。 */ reg slow=0;/* cycles：当前仿真周期；acks：目录接受记录数；errors：APP错误记录数；last_error：APP最近错误码；expected_ack：等待的目录接受次数。 */ integer cycles=0,acks=0,errors=0,last_error=0,expected_ack=0;
 /* header_index：输出记录头的位置；payload_index：输出记录正文位置；kind：输出记录类型；handle：文件句柄；length：当前文件或帧长度；k：当前文件或字节位置。 */ integer header_index=0,payload_index=0,kind=0,handle=0,length=0,k;
 /* file_lengths：各文件接收长度；file_done：各文件完成次数。 */ integer file_lengths[0:FILES-1],file_done[0:FILES-1];
 /* file_bytes：APP实际收到的文件字节。 */ reg [7:0] file_bytes[0:FILES*CAPACITY-1];
 /* results：保存全部文件的完成记录供APP端读取。 */ reg [63:0] results[0:FILES+3];
 /* result_count：已收完成记录数；result_read：已取完成记录数。 */ integer result_count=0,result_read=0;
 /* assembling：正在拼接的64位完成记录。 */ reg [63:0] assembling;
 /* stalled：上拍APP发生停顿。 */ reg stalled=0;/* held：上拍呈现的APP字节。 */ reg [7:0] held;
 initial for(k=0;k<FILES;k=k+1)begin file_lengths[k]=0;file_done[k]=0;end
 always @(negedge clk)reply_ready=!reset && (!slow || cycles%17!=0);
 always @(posedge clk)if(!reset)begin
  cycles=cycles+1;
  if(stalled && (!reply_valid || reply_data!==held))$fatal(1,"APP output changed under backpressure");
  stalled=reply_valid && !reply_ready;held=reply_data;
  if(reply_valid && reply_ready)begin
   if(header_index<6)begin
    case(header_index)
     0:kind=reply_data;
     1:handle=reply_data;
     2:length=reply_data;
     3,4,5:length=length | (reply_data<<(8*(header_index-2)));
    endcase
    header_index=header_index+1;
    if(header_index==6)begin
     payload_index=0;assembling=0;
     if(kind==16 && (handle<1 || handle>FILES || length>CAPACITY))$fatal(1,"APP file record bounds");
     if(length==0)begin
      if(kind==16)begin file_lengths[handle-1]=0;file_done[handle-1]=file_done[handle-1]+1;end
      header_index=0;
     end
    end
   end else begin
    if(kind==16)file_bytes[(handle-1)*CAPACITY+payload_index]=reply_data;
    else if(kind==32 && payload_index<8)assembling[8*payload_index+:8]=reply_data;
    else if(kind==224)last_error=reply_data;
    payload_index=payload_index+1;
    if(payload_index==length)begin
     $display("APP_RECORD ns=%0d scope=%m kind=%0d handle=%0d length=%0d",$time,kind,handle,length);
     case(kind)
      16:begin file_lengths[handle-1]=length;file_done[handle-1]=file_done[handle-1]+1;end
      32:begin results[result_count]=assembling;result_count=result_count+1;end
      48:acks=acks+1;
      224:errors=errors+1;
      default:$fatal(1,"Unexpected APP output kind %h",kind);
     endcase
     header_index=0;
    end
   end
  end
 end
 task automatic send_byte(input [7:0] value);
 /* waits：等待APP准备的周期数。 */ integer waits;
 begin
  @(negedge clk);data=value;valid=1;waits=0;
  @(posedge clk);while(!ready)begin @(posedge clk);waits=waits+1;if(waits>2000000)$fatal(1,"APP stream input blocked");end
 end endtask
 task automatic stop_input;begin @(negedge clk);valid=0;end endtask
 task automatic send_u32(input [31:0] value);
 /* n：当前字节位置。 */ integer n;begin for(n=0;n<4;n=n+1)send_byte(value[8*n+:8]);end endtask
 task automatic directory_begin(input [2:0] operation,input [7:0] count,input [31:0] peer);
 begin expected_ack=acks+1;send_byte(1);send_byte(operation);send_byte(count);send_u32(peer);end endtask
 task automatic directory_entry(input [2:0] flags,input [31:0] header_size,data_size,header_crc,data_crc,
  input [255:0] header_name,data_name,part_number);
 /* n：当前字节位置。 */ integer n;
 begin
  send_byte(flags);send_u32(header_size);send_u32(data_size);send_u32(header_crc);send_u32(data_crc);
  for(n=0;n<32;n=n+1)send_byte(header_name[8*n+:8]);
  for(n=0;n<32;n=n+1)send_byte(data_name[8*n+:8]);
  for(n=0;n<32;n=n+1)send_byte(part_number[8*n+:8]);
 end endtask
 task automatic directory_end(input expect_failure);
 /* n：当前字节位置；start_errors：开始等待前的APP错误数。 */ integer n,start_errors;
 begin
  start_errors=errors;stop_input;n=0;
  if(expect_failure)begin
   while(errors==start_errors)begin @(negedge clk);n=n+1;if(n>200000)$fatal(1,"Missing APP failure");end
  end else begin
   while(acks<expected_ack)begin @(negedge clk);n=n+1;if(n>200000 || errors!=start_errors)$fatal(1,"APP directory rejected code=%0d",last_error);end
  end
 end endtask
 task automatic file_begin(input [7:0] slot,output [31:0] size);
 /* n：当前字节位置。 */ integer n;
 begin n=0;while(file_done[slot-1]==0)begin @(negedge clk);n=n+1;if(n>WAIT_CYCLES)$fatal(1,"Missing automatic APP file delivery");end
  size=file_lengths[slot-1];end endtask
 task automatic result_get(output [63:0] value);
 /* n：当前字节位置。 */ integer n;
 begin n=0;while(result_read==result_count)begin @(negedge clk);n=n+1;if(n>WAIT_CYCLES)$fatal(1,"Missing 615A completion");end
  value=results[result_read];result_read=result_read+1;end endtask
endmodule

// 独立GMII检查器：校验完整FCS、IPv4/UDP checksum、长度、SN、IFG与每VL BAG。
// 从实际头解析UDP起点/长度，不使用HELLO示例的固定72字节/固定载荷位置。
module tb_files_gmii_monitor #(parameter LOADER=1,parameter OUTPUT_PREFIX="loader")(
 input wire clk,reset,input wire [7:0] data,input wire valid,error,input wire signed [31:0] test_case_id);
 /* bytes：当前物理帧的实际字节。 */ reg [7:0] bytes[0:2047];/* length：当前文件或帧长度；cycle：当前仿真周期；frame_count：已核对的物理帧数；frame_start：本帧起始周期；last_end：上帧结束周期。 */ integer length=0,cycle=0,frame_count=0,frame_start=0,last_end=-1000;
 /* vl_frames：各VL已发送帧数；last_start：各VL上次起帧周期。 */ integer vl_frames[0:1],last_start[0:1];/* last_sn：各VL上个帧序号。 */ reg [7:0] last_sn[0:1];
 /* frames_fd：物理帧摘要文件；bytes_fd：物理字节时间文件。 */ integer frames_fd,bytes_fd;/* previous：上拍发送有效位。 */ reg previous=0;
 function [31:0] crc_reference(input [31:0] previous_crc,input [7:0] value);
 /* bit_number：CRC计算位位置。 */ integer bit_number;/* crc：当前CRC计算值。 */ reg [31:0] crc;
 begin crc=previous_crc^value;for(bit_number=0;bit_number<8;bit_number=bit_number+1)
  crc=(crc>>1)^(crc[0] ? 32'hedb88320 : 0);crc_reference=crc;end endfunction
 task automatic check_frame;
 /* n：当前字节位置；vl：当前帧的VL编号；ihl：IPv4头字节数；udp：UDP头起始位置；udp_length：UDP头与正文总长度；ip_length：IPv4头与正文总长度；sum：校验和累加值；folded：进位折回后的校验和。 */ integer n,vl,ihl,udp,udp_length,ip_length,sum,folded;/* crc：当前CRC计算值；fcs：物理帧尾CRC。 */ reg [31:0] crc,fcs;/* sn：当前帧序号；next_sn：下一帧应使用的序号。 */ reg [7:0] sn,next_sn;
 begin
  if(length<72 || length>1526)$fatal(1,"GMII length %0d",length);
  for(n=0;n<7;n=n+1)if(bytes[n]!=8'h55)$fatal(1,"Preamble");if(bytes[7]!=8'hd5)$fatal(1,"SFD");
  crc=32'hffffffff;for(n=8;n<length-4;n=n+1)crc=crc_reference(crc,bytes[n]);
  fcs={bytes[length-1],bytes[length-2],bytes[length-3],bytes[length-4]};if(fcs!==~crc)$fatal(1,"Wire FCS");
  if({bytes[20],bytes[21]}!=16'h0800 || bytes[22][7:4]!=4 || bytes[31]!=17)$fatal(1,"Wire IPv4/UDP");
  ihl=4*bytes[22][3:0];ip_length={bytes[24],bytes[25]};udp=22+ihl;
  if(ihl<20 || udp+8>length-5 || 22+ip_length>length-5)$fatal(1,"IP length");
  sum=0;for(n=22;n<22+ihl;n=n+2)sum=sum+{bytes[n],bytes[n+1]};
  folded=(sum&65535)+(sum>>16);folded=(folded&65535)+(folded>>16);if(folded!=65535)$fatal(1,"IPv4 checksum");
  udp_length={bytes[udp+4],bytes[udp+5]};
  if(udp_length<8 || udp_length+ihl!=ip_length || {bytes[udp+6],bytes[udp+7]}==0)$fatal(1,"UDP length/checksum field");
  sum=17+udp_length;for(n=34;n<42;n=n+2)sum=sum+{bytes[n],bytes[n+1]};
  for(n=0;n<udp_length;n=n+2)sum=sum+(256*bytes[udp+n])+(n+1<udp_length ? bytes[udp+n+1] : 0);
  folded=(sum&65535)+(sum>>16);folded=(folded&65535)+(folded>>16);if(folded!=65535)$fatal(1,"UDP checksum");
  if({bytes[12],bytes[13]}==(LOADER ? 1 : 3))vl=0;
  else if({bytes[12],bytes[13]}==(LOADER ? 2 : 4))vl=1;else $fatal(1,"Unexpected TX VLID");
  sn=bytes[length-5];next_sn=last_sn[vl]==255 ? 1 : last_sn[vl]+1'b1;
  if((vl_frames[vl]==0 && sn!=1) || (vl_frames[vl]!=0 && sn!=next_sn))$fatal(1,"TX SN continuity");
  if(vl_frames[vl]!=0 && frame_start-last_start[vl]<(vl==0 ? 2000 : 3000))$fatal(1,"VL BAG violation");
  last_sn[vl]=sn;last_start[vl]=frame_start;vl_frames[vl]=vl_frames[vl]+1;
  $fwrite(frames_fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%08h\n",test_case_id,frame_count,frame_start,length,vl,sn,{bytes[udp],bytes[udp+1]},{bytes[udp+2],bytes[udp+3]},udp_length,fcs);
  frame_count=frame_count+1;
 end endtask
 initial begin
  vl_frames[0]=0;vl_frames[1]=0;last_start[0]=0;last_start[1]=0;last_sn[0]=0;last_sn[1]=0;
  frames_fd=$fopen({OUTPUT_PREFIX,"_frames.csv"},"w");bytes_fd=$fopen({OUTPUT_PREFIX,"_gmii_bytes.csv"},"w");
  if(!frames_fd || !bytes_fd)$fatal(1,"Cannot open GMII CSV");
  $fwrite(frames_fd,"case,frame,start_cycle,wire_bytes,vl_index,sn,src_port,dst_port,udp_bytes,fcs\n");
  $fwrite(bytes_fd,"time_ps,case,frame,byte_index,data_hex\n");
 end
 always @(posedge clk)begin
  cycle=cycle+1;
  if(reset)begin length=0;previous=0;end
  else begin
   if(error)$fatal(1,"TX MAC error");
   if(valid)begin
    if(!previous)begin if(cycle-last_end<12)$fatal(1,"IFG violation");frame_start=cycle;end
    if(length>=2048)$fatal(1,"Frame monitor overflow");bytes[length]=data;
    $fwrite(bytes_fd,"%0t,%0d,%0d,%0d,%02h\n",$time,test_case_id,frame_count,length,data);length=length+1;
   end else if(previous)begin check_frame;length=0;last_end=cycle;end
   previous=valid;
  end
 end
endmodule
