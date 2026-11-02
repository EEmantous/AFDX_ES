`timescale 1ns/1ps
// TFTP请求、blksize协商、数据、ACK与超时重发。
module arinc615a_tftp #(
    parameter integer NAME_BYTES=32,
    parameter integer MAX_FILE_BYTES=8192,
    parameter integer MAX_BLOCK_BYTES=1467, // MAX_BLOCK_BYTES: 本地DATA正文容量，另加4字节TFTP头。
    parameter integer RETRY_CYCLES=12500000,
    parameter integer MAX_RETRIES=5,
    parameter integer DALLY_CYCLES=25000000,
    parameter [15:0] LOCAL_TID=16'd41000,
    parameter SERVER_ENABLE=1
)(
    input wire clk,reset,abort,
    input wire cmd_valid,output wire cmd_ready,input wire cmd_write,
    input wire cmd_large_block, // cmd_large_block: 大文件命令请求协商本地最大块长。
    input wire [31:0] cmd_peer_ip,input wire [8*NAME_BYTES-1:0] cmd_name,
    input wire [7:0] rx_data,input wire rx_valid,rx_last,output wire rx_ready,
    input wire [31:0] rx_src_ip,input wire [15:0] rx_src_port,rx_dst_port,
    output wire [7:0] tx_data,output wire tx_valid,tx_last,input wire tx_ready,
    output wire [31:0] tx_dst_ip,output wire [15:0] tx_src_port,tx_dst_port,
    output wire file_open_valid,input wire file_open_ready,
    output wire [8*NAME_BYTES-1:0] file_name,output wire file_write,
    input wire [15:0] file_open_error,input wire [31:0] file_size,
    output wire [31:0] file_read_addr,input wire [7:0] file_read_data,
    output wire file_read_valid, // file_read_valid: DATA组包阶段请求源文件的当前字节。
    input wire file_read_ready, // file_read_ready: 源文件当前字节已经返回。
    output wire file_write_valid,input wire file_write_ready,
    output wire [31:0] file_write_addr,output wire [7:0] file_write_data,
    output  reg file_done,output  reg file_failed,output wire [31:0] transferred,
    output wire busy,output wire [15:0] listen_tid,previous_tid,
    output  reg [15:0] error_code,
    output reg retry_event,output wire [31:0] duplicates,malformed
);
 localparam IDLE=0,OPEN=1,REQUEST=2,DATA_BUILD=3,SEND=4,WAIT=5,WRITE=6,DALLY=7;
 // state/resume_state: 当前阶段及本包发送完成后进入的阶段。
 reg [3:0] state,resume_state;
 // rx_byte/tx_byte: 当前单向文件会话共用的块RAM输出，分别用于写文件和发DATA。
 wire [7:0] rx_byte,tx_byte;
 // tx_kind/tx_block: 待发包类别（请求、DATA、ACK）及其块编号。
 reg [1:0] tx_kind;
 reg [15:0] tx_block;
 // BLOCK_ADDRESS_WIDTH/PACKET_WIDTH: DATA缓存地址及含TFTP头的包长度位宽。
 localparam BLOCK_ADDRESS_WIDTH=$clog2(MAX_BLOCK_BYTES),PACKET_WIDTH=$clog2(MAX_BLOCK_BYTES+5);
 // rx_count/rx_len: 正在接收的包位置和已收包长度。
 reg [PACKET_WIDTH-1:0] rx_count,rx_len;
 // rx_write_position: DATA正文在本地RAM中的写地址。
 wire [BLOCK_ADDRESS_WIDTH-1:0] rx_write_position=rx_count-4;
 // tx_len/tx_index: 待发包长度和当前发送位置。
 reg [PACKET_WIDTH-1:0] tx_len,tx_index;
 // build_index/write_index/data_count: 从文件组包、写回文件的位置和本块正文长度。
 reg [PACKET_WIDTH-1:0] build_index,write_index,data_count;
 // rx_read_position/tx_read_position: 为下一拍输出提前读取的正文地址。
 wire [BLOCK_ADDRESS_WIDTH-1:0] rx_read_position=state!=WRITE ? 0 :
  write_index+((file_write_valid && file_write_ready) ? 1'b1 : 1'b0);
 wire [BLOCK_ADDRESS_WIDTH-1:0] tx_read_position=tx_index<4 ? 0 :
  tx_index-4+((tx_valid && tx_ready && !tx_last) ? 1'b1 : 1'b0);
 // rx_pending: 一包已收齐，等待状态机处理。
 reg rx_pending;
 // packet_ip/packet_src/packet_dst: 当前收到包的源IP及UDP两端端口。
 reg [31:0] packet_ip;
 reg [15:0] packet_src,packet_dst;
 // peer_ip/peer_tid: 当前文件传输的对端IP及UDP端口。
 reg [31:0] peer_ip;
 reg [15:0] peer_tid;
 // block_no/last_rx_block: 当前期待的块编号及最近已写入的块编号。
 reg [15:0] block_no,last_rx_block;
 // name: 当前读写的文件名。
 reg [8*NAME_BYTES-1:0] name;
 // is_client/sending_file/last_data: 本地发起、本地发送正文、当前为最后一块。
 reg is_client,sending_file,last_data;
 // offset/total_size: 已传文件字节数和源文件总长度。
 reg [31:0] offset,total_size;
 // timer/retry_count: 等待回复的周期数及本阶段已重试次数。
 reg [31:0] timer;
 reg [15:0] retry_count;
 // parsed_name: 从当前请求RAM直接取得的文件名。
 reg [8*NAME_BYTES-1:0] parsed_name;
 // name_length/name_end/k: 文件名长度、是否读到结尾及字符串位置。
 integer name_length,k;
 reg name_end;
 // opcode/packet_block: 当前包类型与块编号。
 reg [15:0] opcode,packet_block;
 // block_size/want_large: 本次会话生效的块长及请求或服务端接受的大块选项。
 reg [PACKET_WIDTH-1:0] block_size;
 reg want_large;
 // option_field/option_index/option_match: 请求或OACK的字符串字段、选项名位置和blksize匹配结果。
 reg [1:0] option_field;
 reg [3:0] option_index;
 reg option_match;
 // option_value/packet_blksize: 十进制选项累加值和本包提出的块长。
 reg [15:0] option_value,packet_blksize;
 function [7:0] option_byte;
  input integer position; // position: blksize选项中从0开始的字节位置。
  begin
   case(position)
    0:option_byte="b";1:option_byte="l";2:option_byte="k";3:option_byte="s";
    4:option_byte="i";5:option_byte="z";6:option_byte="e";7:option_byte=0;
    8:option_byte=48+(MAX_BLOCK_BYTES/1000)%10;
    9:option_byte=48+(MAX_BLOCK_BYTES/100)%10;
    10:option_byte=48+(MAX_BLOCK_BYTES/10)%10;
    11:option_byte=48+MAX_BLOCK_BYTES%10;
    default:option_byte=0;
   endcase
  end
 endfunction
 assign listen_tid=LOCAL_TID;
 assign previous_tid=0;
 assign duplicates=0;
 assign malformed=0;
 assign transferred=offset;
 assign busy=state!=IDLE;
 assign cmd_ready=!reset && state==IDLE && !rx_pending && rx_count==0;
 assign rx_ready=!reset && !rx_pending && (state==IDLE || state==WAIT || state==DALLY);
 assign file_open_valid=state==OPEN;
 assign file_name=name;
 assign file_write=!sending_file;
 assign file_read_addr=offset+build_index;
 assign file_read_valid=!reset && state==DATA_BUILD && build_index<block_size && offset+build_index<total_size;
 assign file_write_addr=offset+write_index;
 assign file_write_data=rx_byte;
 assign file_write_valid=state==WRITE && write_index<data_count;
 assign tx_valid=!reset && state==SEND;
 assign tx_last=tx_index==tx_len-1'b1;
 // request_byte: 按发送位置从已保存文件名生成请求字节。
 reg [7:0] request_byte;
 always @*begin
  request_byte=0;
  if(tx_index>=2 && tx_index<2+name_length)request_byte=name[8*(tx_index-2)+:8];
  else if(tx_index==3+name_length)request_byte="o";
  else if(tx_index==4+name_length)request_byte="c";
  else if(tx_index==5+name_length || tx_index==7+name_length)request_byte="t";
  else if(tx_index==6+name_length)request_byte="e";
  else if(want_large && tx_index>=name_length+9)request_byte=option_byte(tx_index-name_length-9);
 end
 assign tx_data=tx_index==0 ? 8'd0 :
  tx_index==1 ? (tx_kind==0 ? (sending_file ? 8'd2 : 8'd1) : tx_kind==1 ? 8'd3 : tx_kind==2 ? 8'd4 : 8'd6) :
  tx_kind==0 ? request_byte : tx_kind==3 ? option_byte(tx_index-2) :
  tx_index==2 ? tx_block[15:8] : tx_index==3 ? tx_block[7:0] : tx_byte;
 assign tx_dst_ip=peer_ip;
 assign tx_src_port=LOCAL_TID;
 assign tx_dst_port=peer_tid;
 always @*begin
  name_length=0;
  for(k=0;k<NAME_BYTES;k=k+1)begin
   if(name[8*k+:8]!=0 && name_length==k)name_length=k+1;
  end
 end
 task ack_block(input [15:0] number,input [3:0] following); // number: 应答块号；following: 应答发完的下一阶段。
  begin tx_kind<=2;tx_block<=number;
   tx_len<=4;tx_index<=0;resume_state<=following;state<=SEND;timer<=0;end
 endtask
 task option_ack;
  begin tx_kind<=3;tx_len<=15;tx_index<=0;resume_state<=WAIT;state<=SEND;timer<=0;end
 endtask
 task receive_request;
  begin
   name<=parsed_name;peer_ip<=packet_ip;peer_tid<=packet_src;
   is_client<=0;sending_file<=opcode==1;offset<=0;block_no<=1;last_rx_block<=0;retry_count<=0;state<=OPEN;
   want_large<=MAX_BLOCK_BYTES>512 && packet_blksize>=MAX_BLOCK_BYTES;
   block_size<=MAX_BLOCK_BYTES>512 && packet_blksize>=MAX_BLOCK_BYTES ? MAX_BLOCK_BYTES : 512;
  end
 endtask
 // buffer_write/buffer_write_address/buffer_read_address/buffer_data: 单向正文缓存的写使能、读写地址和源字节。
 wire buffer_write=sending_file ? file_read_valid && file_read_ready : rx_valid && rx_ready && opcode==3 && rx_count>=4;
 wire [BLOCK_ADDRESS_WIDTH-1:0] buffer_write_address=sending_file ? build_index[BLOCK_ADDRESS_WIDTH-1:0] : rx_write_position;
 wire [BLOCK_ADDRESS_WIDTH-1:0] buffer_read_address=sending_file ? tx_read_position : rx_read_position;
 wire [7:0] buffer_data=sending_file ? file_read_data : rx_data;
 assign rx_byte=tx_byte;
 afdx_byte_ram #(.WORDS(MAX_BLOCK_BYTES),.ADDRESS_WIDTH(BLOCK_ADDRESS_WIDTH)) block_mem(
  .clk(clk),.write_enable(buffer_write),.write_address(buffer_write_address),.write_data(buffer_data),
  .read_enable(1'b1),.read_address(buffer_read_address),.read_data(tx_byte));
 always @(posedge clk)begin
  if(reset)begin
   state<=IDLE;resume_state<=IDLE;rx_count<=0;rx_len<=0;rx_pending<=0;
   tx_len<=0;tx_index<=0;build_index<=0;write_index<=0;data_count<=0;
   packet_ip<=0;packet_src<=0;packet_dst<=0;peer_ip<=0;peer_tid<=69;
   block_no<=1;last_rx_block<=0;name<=0;is_client<=0;sending_file<=0;last_data<=0;
   offset<=0;total_size<=0;timer<=0;retry_count<=0;
   file_done<=0;file_failed<=0;error_code<=0;retry_event<=0;
   parsed_name<=0;name_end<=0;opcode<=0;packet_block<=0;tx_kind<=0;tx_block<=0;
   block_size<=512;want_large<=0;option_field<=0;option_index<=0;option_match<=1;option_value<=0;packet_blksize<=0;
  end else begin
   file_done<=0;file_failed<=0;retry_event<=0;
   if(rx_valid && rx_ready)begin
    if(rx_count==0)begin
     packet_ip<=rx_src_ip;packet_src<=rx_src_port;packet_dst<=rx_dst_port;
     opcode[15:8]<=rx_data;parsed_name<=0;name_end<=0;
     option_field<=0;option_index<=0;option_match<=1;option_value<=0;packet_blksize<=0;
    end
    if(rx_count==1)begin opcode[7:0]<=rx_data;option_field<=rx_data==6 ? 2 : 0;end
    if(rx_count==2)packet_block[15:8]<=rx_data;
    if(rx_count==3)packet_block[7:0]<=rx_data;
    if(rx_count>=2 && rx_count<NAME_BYTES+2 && !name_end)begin
     if(rx_data==0)name_end<=1;
     else parsed_name[8*(rx_count-2)+:8]<=rx_data;
    end
    if(rx_count>=2 && (opcode==1 || opcode==2 || opcode==6))begin
     case(option_field)
      0,1:if(rx_data==0)option_field<=option_field+1'b1;
      2:if(rx_data==0)begin
       option_field<=3;option_match<=option_match && option_index==7;option_value<=0;
      end else begin
       option_match<=option_match && (rx_data|8'h20)==option_byte(option_index);
       option_index<=option_index+1'b1;
      end
      3:if(rx_data==0)begin
       if(option_match)packet_blksize<=option_value;
       option_field<=2;option_index<=0;option_match<=1;
      end else option_value<=option_value*10+rx_data-48;
     endcase
    end
    if(rx_last)begin rx_len<=rx_count+1'b1;rx_pending<=1;rx_count<=0;end
    else rx_count<=rx_count+1'b1;
   end
   if(abort && state!=IDLE && state!=SEND)begin
    file_done<=1;file_failed<=1;error_code<=16'hffff;state<=IDLE;rx_pending<=0;
   end else case(state)
    IDLE:begin
     timer<=0;
     if(cmd_valid && cmd_ready)begin
      name<=cmd_name;peer_ip<=cmd_peer_ip;peer_tid<=69;is_client<=1;sending_file<=cmd_write;
      offset<=0;block_no<=1;last_rx_block<=0;retry_count<=0;error_code<=0;state<=OPEN;
      block_size<=512;want_large<=cmd_large_block && MAX_BLOCK_BYTES>512;
     end else if(rx_pending)begin
      rx_pending<=0;
      if(SERVER_ENABLE && packet_dst==69)receive_request;
      else if(SERVER_ENABLE && last_data && packet_dst==LOCAL_TID && opcode==3 &&
       packet_block==last_rx_block && packet_src==peer_tid)ack_block(last_rx_block,IDLE);
     end
    end
    OPEN:if(file_open_ready)begin
     total_size<=file_size;build_index<=0;
     if(is_client)state<=REQUEST;
     else if(want_large)option_ack;
     else if(sending_file)state<=DATA_BUILD;
     else ack_block(0,WAIT);
    end
    REQUEST:begin
     tx_kind<=0;
     tx_len<=name_length+9+(want_large ? 13 : 0);tx_index<=0;resume_state<=WAIT;state<=SEND;
    end
    DATA_BUILD:begin
     if(build_index<block_size && offset+build_index<total_size)begin
      if(file_read_ready)build_index<=build_index+1'b1;
     end else begin
      tx_kind<=1;tx_block<=block_no;
      data_count<=build_index;last_data<=build_index<block_size;
      tx_len<=build_index+4;tx_index<=0;resume_state<=WAIT;state<=SEND;
     end
    end
    SEND:if(tx_ready)begin
     if(tx_last)begin tx_index<=0;timer<=0;state<=resume_state;end
     else tx_index<=tx_index+1'b1;
    end
    WAIT,DALLY:begin
     if(rx_pending)begin
      rx_pending<=0;
      if(SERVER_ENABLE && packet_dst==69 && (opcode==1 || opcode==2))begin
       if(state==DALLY)receive_request;
       else if(parsed_name==name && packet_src==peer_tid && offset==0)begin
        tx_index<=0;resume_state<=state;state<=SEND;
       end
      end
      else if(opcode==5)begin error_code<=packet_block;file_done<=1;file_failed<=1;state<=IDLE;end
      else if(is_client && want_large && opcode==6 && offset==0 && block_no==1 &&
       packet_blksize>=8 && packet_blksize<=MAX_BLOCK_BYTES)begin
       peer_tid<=packet_src;block_size<=packet_blksize;retry_count<=0;timer<=0;
       if(sending_file)begin build_index<=0;state<=DATA_BUILD;end
       else ack_block(0,WAIT);
      end
      else if(sending_file && opcode==4 && state==WAIT)begin
       if(packet_block==0 && (peer_tid==69 || tx_kind==3))begin peer_tid<=packet_src;build_index<=0;retry_count<=0;state<=DATA_BUILD;end
       else if(packet_block==block_no)begin
        timer<=0;retry_count<=0;offset<=offset+data_count;
        if(last_data)begin file_done<=1;state<=IDLE;end
        else begin block_no<=block_no+1'b1;build_index<=0;state<=DATA_BUILD;end
       end
      end else if(!sending_file && opcode==3)begin
       if(packet_block==last_rx_block)ack_block(last_rx_block,state);
       else if(state==WAIT && packet_block==block_no)begin
        peer_tid<=packet_src;data_count<=rx_len-4;last_data<=rx_len<block_size+4;
        write_index<=0;timer<=0;retry_count<=0;state<=WRITE;
       end
      end
     end else if(timer>=(state==DALLY ? DALLY_CYCLES-1 : RETRY_CYCLES-1))begin
      timer<=0;
      if(state==DALLY)state<=IDLE;
      else if(retry_count==MAX_RETRIES)begin file_done<=1;file_failed<=1;error_code<=16'hfffe;state<=IDLE;end
      else begin retry_count<=retry_count+1'b1;retry_event<=1;tx_index<=0;resume_state<=WAIT;state<=SEND;end
     end else timer<=timer+1'b1;
    end
    WRITE:begin
     if(write_index==data_count)begin
      last_rx_block<=block_no;offset<=offset+data_count;block_no<=block_no+1'b1;
      if(last_data)begin file_done<=1;ack_block(block_no,DALLY);end
      else ack_block(block_no,WAIT);
     end else if(file_write_ready)write_index<=write_index+1'b1;
    end
   endcase
  end
 end
endmodule
