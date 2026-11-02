`timescale 1ns/1ps
// 一份文件目录和一份文件RAM；仲裁APP与TFTP的字节读写。
module afdx_file_service #(
 parameter LOADER=1,parameter integer VL_COUNT=2,CHANNEL_COUNT=6,MAP_ENTRIES=3,MAX_FILE_BYTES=8192,
 parameter integer MAX_HEADER_BYTES=32, // MAX_HEADER_BYTES: 现有仿真实例使用的LUH头缓存长度。
 parameter [32*MAP_ENTRIES-1:0] FILE_IDS={32'd3,32'd2,32'd1},
 parameter [8*MAP_ENTRIES-1:0] FILE_VLS={8'd1,8'd0,8'd0},
 parameter [255:0] TARGET_NAME=256'h4c5f5345
)(
 input wire clk,reset,
 // One current catalog entry, never a broadcast copy of the directory.
 input wire [7:0] host_slot,catalog_index,catalog_data,input wire catalog_write,
 output wire [7:0] catalog_read_data,output wire [2:0] entry_flags,
 output wire [31:0] entry_file_id,entry_header_size,entry_data_size,output wire [31:0] entry_read_size,
 output wire entry_locked,entry_readable,
 input wire [2:0] host_operation,
 input wire [31:0] host_offset,input wire host_header,host_begin,host_write,host_valid,
 input wire [7:0] host_wdata,output wire [7:0] host_rdata,output wire host_ready,host_error,
 input wire [MAP_ENTRIES-1:0] cancel_files,
 output wire [31:0] locked_count,output wire any_locked,file0_locked,
 input wire reserve_file,input wire [2:0] reserve_operation,output wire start_error,
 input wire [32*VL_COUNT-1:0] file_ids,input wire [VL_COUNT-1:0] done,failed,header_pending,data_pending,
 output wire [256*VL_COUNT-1:0] header_name,data_name,part_number,
 output wire [32*VL_COUNT-1:0] header_size,data_size,output wire [8*VL_COUNT-1:0] task_slots,
 output wire [VL_COUNT-1:0] header_ok,header_bad,data_commit,data_bad,
 output wire [VL_COUNT-1:0] abort_tasks,task_commit_bad,output wire fault_event,
 input wire [8*CHANNEL_COUNT-1:0] channel_file_slots,
 input wire [32*CHANNEL_COUNT-1:0] read_addr,write_addr,
 input wire [CHANNEL_COUNT-1:0] is_header,write_valid,output reg [CHANNEL_COUNT-1:0] write_ready,
 input wire [8*CHANNEL_COUNT-1:0] write_data,output reg [8*CHANNEL_COUNT-1:0] read_data,
 input wire [CHANNEL_COUNT-1:0] read_valid, // read_valid: 各TFTP通道请求读取当前文件字节。
 output reg [CHANNEL_COUNT-1:0] read_ready // read_ready: 对应文件字节已经读出，等待通道接收。
);
 // header_names/data_names/part_numbers: 各文件的头名、数据名和部件号。
 reg [255:0] header_names[0:MAP_ENTRIES-1],data_names[0:MAP_ENTRIES-1],part_numbers[0:MAP_ENTRIES-1];
 // header_sizes/data_sizes: 目录声明的两种文件长度。
 reg [31:0] header_sizes[0:MAP_ENTRIES-1],data_sizes[0:MAP_ENTRIES-1];
 // source_flags: APP提供哪些文件、是否提交615A任务。
 reg [2:0] source_flags[0:MAP_ENTRIES-1];
 // HEADER_BYTES/FILE_BYTES: 每文件的头缓存长度和头、数据合计占用的字节数。
 localparam HEADER_BYTES=MAX_FILE_BYTES<MAX_HEADER_BYTES ? MAX_FILE_BYTES : MAX_HEADER_BYTES;
 localparam FILE_BYTES=MAX_FILE_BYTES+HEADER_BYTES;
 // ADDRESS_WIDTH: 文件RAM实际地址位数。
 localparam ADDRESS_WIDTH=$clog2(MAP_ENTRIES*FILE_BYTES);
 // read_busy: 已经发给RAM、尚未被通道接收的请求，最后一位对应APP。
 reg [CHANNEL_COUNT:0] read_busy;
 // read_round_robin: 下一次文件读取的轮询起点。
 reg [$clog2(CHANNEL_COUNT+1)-1:0] read_round_robin;
 // CHOICE_WIDTH/NO_CHANNEL: 授权编号的位数和无授权时的编号。
 localparam CHOICE_WIDTH=$clog2(CHANNEL_COUNT+2),NO_CHANNEL=(1<<CHOICE_WIDTH)-1;
 // read_choice/read_wrap_choice: 轮询起点之后和回绕后的读取授权。
 reg [CHOICE_WIDTH-1:0] read_choice,read_wrap_choice;
 // read_scan: 遍历各个固定读取通道的位置。
 integer read_scan;
 // read_requests: 尚未占用返回缓存的文件读取请求，最高位对应APP。
 wire [CHANNEL_COUNT:0] read_requests={host_valid && !host_write,read_valid} & ~read_busy;
 // ram_read_address/ram_write_address: 本拍唯一的RAM读地址和写地址。
 reg [ADDRESS_WIDTH-1:0] ram_read_address,ram_write_address;
 // ram_write/ram_write_data: 本拍是否写RAM及待写字节。
 reg ram_write;
 reg [7:0] ram_write_data;
 // ram_data: 同步RAM读出的字节；read_owner/read_pending: 对应通道和读出状态。
 wire [7:0] ram_data;
 reg [$clog2(CHANNEL_COUNT+1)-1:0] read_owner;
 reg read_pending;
 // host_response/host_response_valid: APP读回字节及其有效位。
 reg [7:0] host_response;
 reg host_response_valid;
 // response_channel: 清除各通道已接收字节的遍历位置。
 integer response_channel;
 // file_locked: 已提交、尚未完成的文件任务。

 // round_robin: 下一次网络写入从哪个通道开始。
 reg [$clog2(CHANNEL_COUNT+1)-1:0] round_robin;
 // grant/write_wrap_choice: 轮询起点之后和回绕后的写入授权。
 reg [CHOICE_WIDTH-1:0] grant,write_wrap_choice;
 // scan: 遍历各个固定写入通道的位置。
 integer scan;
 // lock_index/lock_total: 求和任务占用的文件数量。

 // SLOT_WIDTH: 文件槽编号的实际位数。
 localparam SLOT_WIDTH=MAP_ENTRIES<=1 ? 1 : $clog2(MAP_ENTRIES);
 // finished_slot: 当前已完成任务的文件槽。

 // write_ready: RAM本拍允许写入的通道。

 function integer lookup_file(input [31:0] id); // id: 任务中的文件编号。
  integer slot; // slot: 查找文件表的位置。
  begin lookup_file=0;for(slot=0;slot<MAP_ENTRIES;slot=slot+1)
   if(FILE_IDS[32*slot+:32]==id)lookup_file=slot;end
 endfunction
 function integer mapped_count(input integer vl_index); // vl_index: 任务路由选择的VL编号。
  integer slot; // slot: 静态文件映射表的位置。
  begin
   mapped_count=0;
   for(slot=0;slot<MAP_ENTRIES;slot=slot+1)
    if(FILE_VLS[8*slot+:8]==vl_index)mapped_count=mapped_count+1;
  end
 endfunction
 function integer mapped_slot(input integer vl_index); // vl_index: 任务路由选择的VL编号。
  integer slot; // slot: 静态文件映射表的位置。
  begin
   mapped_slot=0;
   for(slot=0;slot<MAP_ENTRIES;slot=slot+1)
    if(FILE_VLS[8*slot+:8]==vl_index)mapped_slot=slot;
  end
 endfunction
 function [255:0] default_name(input [31:0] id,input header);
 /* k：当前字节或表项位置；length：当前字节或表项位置。 */ integer k,length;/* value：本次计算值。 */ reg [31:0] value;/* digits：将文件ID转十进制文件名时的数字字节临时缓存。 */ reg [79:0] digits;/* name：由文件ID生成的默认文件名临时值。 */ reg [255:0] name;
 begin
  value=id;digits=0;length=1;name=0;name[31:0]=32'h74786574;
  for(k=0;k<10;k=k+1)begin
   if(k==0 || value!=0)begin digits[8*k+:8]="0"+value%10;length=k+1;end
   value=value/10;
  end
  for(k=0;k<10;k=k+1)if(k<length)name[8*(4+k)+:8]=digits[8*(length-1-k)+:8];
  name[8*(4+length)+:8]=".";
  name[8*(5+length)+:8]=header ? "L" : "t";
  name[8*(6+length)+:8]=header ? "U" : "x";
  name[8*(7+length)+:8]=header ? "H" : "t";
  default_name=name;
 end endfunction
 function [255:0] default_part(input [31:0] id);
 begin default_part=256'h2d5458542d4e50;
  default_part[63:56]="0"+(id/10)%10;default_part[71:64]="0"+id%10;end endfunction

 assign entry_flags=source_flags[host_slot];
 assign entry_file_id=FILE_IDS[32*host_slot+:32];
 assign entry_header_size=header_sizes[host_slot];
 assign entry_data_size=data_sizes[host_slot];
 assign entry_read_size=data_sizes[host_slot];
 assign entry_locked=0;
 assign entry_readable=1'b1;
 assign start_error=1'b0;
 assign catalog_read_data=0;
 assign host_error=0;
 assign host_ready=!reset && (host_write ? grant==NO_CHANNEL : host_response_valid);
 assign host_rdata=host_response;
 assign locked_count=0;
 assign any_locked=0;
 assign file0_locked=0;
 assign header_ok=header_pending;
 assign data_commit=data_pending;
 assign header_bad=0;
 assign data_bad=0;
 assign abort_tasks=0;
 assign task_commit_bad=0;
 assign fault_event=0;
 always @*begin
  grant=NO_CHANNEL;write_wrap_choice=NO_CHANNEL;
  for(scan=CHANNEL_COUNT-1;scan>=0;scan=scan-1)begin
   if(write_valid[scan])begin
    write_wrap_choice=scan;
    if(scan>=round_robin)grant=scan;
   end
  end
  if(grant==NO_CHANNEL)grant=write_wrap_choice;
  write_ready=0;
  if(grant!=NO_CHANNEL)write_ready[grant]=1;
 end
 // task_vl: 路由器分配任务的固定VL；一VL一文件时直接接目录，避免复制整张目录的选择器。
 genvar task_vl;
 generate for(task_vl=0;task_vl<VL_COUNT;task_vl=task_vl+1)begin: task_catalog
  // task_slot: 多文件共用VL时按任务ID选择，单文件VL由FILE_VLS在综合时确定。
  wire [SLOT_WIDTH-1:0] task_slot=mapped_count(task_vl)==1 ? mapped_slot(task_vl) : lookup_file(file_ids[32*task_vl+:32]);
  assign task_slots[8*task_vl+:8]=task_slot;
  assign header_name[256*task_vl+:256]=header_names[task_slot];
  assign data_name[256*task_vl+:256]=data_names[task_slot];
  assign part_number[256*task_vl+:256]=part_numbers[task_slot];
  assign header_size[32*task_vl+:32]=header_sizes[task_slot];
  assign data_size[32*task_vl+:32]=data_sizes[task_slot];
 end endgenerate
 always @*begin
  read_choice=NO_CHANNEL;read_wrap_choice=NO_CHANNEL;
  for(read_scan=CHANNEL_COUNT;read_scan>=0;read_scan=read_scan-1)begin
   if(read_requests[read_scan])begin
    read_wrap_choice=read_scan;
    if(read_scan>=read_round_robin)read_choice=read_scan;
   end
  end
  if(read_choice==NO_CHANNEL)read_choice=read_wrap_choice;
  ram_read_address=0;
  if(read_choice==CHANNEL_COUNT)
   ram_read_address=host_slot*FILE_BYTES+(host_header ? MAX_FILE_BYTES : 0)+host_offset;
  else if(read_choice!=NO_CHANNEL)
   ram_read_address=channel_file_slots[8*read_choice+:8]*FILE_BYTES+(is_header[read_choice] ? MAX_FILE_BYTES : 0)+read_addr[32*read_choice+:32];
  ram_write=0;ram_write_address=0;ram_write_data=0;
  if(grant!=NO_CHANNEL)begin
   ram_write=!reset;
   ram_write_address=channel_file_slots[8*grant+:8]*FILE_BYTES+(is_header[grant] ? MAX_FILE_BYTES : 0)+write_addr[32*grant+:32];
   ram_write_data=write_data[8*grant+:8];
  end else if(host_valid && host_write)begin
   ram_write=!reset;
   ram_write_address=host_slot*FILE_BYTES+(host_header ? MAX_FILE_BYTES : 0)+host_offset;
   ram_write_data=host_wdata;
  end
 end
 afdx_byte_ram #(.WORDS(MAP_ENTRIES*FILE_BYTES),.ADDRESS_WIDTH(ADDRESS_WIDTH)) memory(
  .clk(clk),.write_enable(ram_write),.write_address(ram_write_address),.write_data(ram_write_data),
  .read_enable(read_choice!=NO_CHANNEL),.read_address(ram_read_address),.read_data(ram_data));
 always @(posedge clk)begin
  if(reset)begin
   read_busy<=0;read_ready<=0;read_data<=0;read_round_robin<=0;
   read_owner<=0;read_pending<=0;host_response<=0;host_response_valid<=0;
  end else begin
   for(response_channel=0;response_channel<CHANNEL_COUNT;response_channel=response_channel+1)
    if(read_ready[response_channel])begin
     read_ready[response_channel]<=0;read_busy[response_channel]<=0;
    end
   if(host_valid && !host_write && host_response_valid)begin
    host_response_valid<=0;read_busy[CHANNEL_COUNT]<=0;
   end
   if(read_pending)begin
    if(read_owner==CHANNEL_COUNT)begin host_response<=ram_data;host_response_valid<=1;end
    else begin read_data[8*read_owner+:8]<=ram_data;read_ready[read_owner]<=1;end
   end
   read_pending<=read_choice!=NO_CHANNEL;
   if(read_choice!=NO_CHANNEL)begin
    read_owner<=read_choice;read_busy[read_choice]<=1;
    read_round_robin<=read_choice==CHANNEL_COUNT ? 0 : read_choice+1;
   end
  end
 end
 always @(posedge clk)begin
  if(reset)round_robin<=0;
  else if(grant!=NO_CHANNEL)round_robin<=grant==CHANNEL_COUNT-1 ? 0 : grant+1;
 end
 // catalog_slot/catalog_byte: 目录中固定的文件槽和字节位置。
 genvar catalog_slot,catalog_byte;
 generate for(catalog_slot=0;catalog_slot<MAP_ENTRIES;catalog_slot=catalog_slot+1)begin: catalog
  // DEFAULT_HEADER/DEFAULT_DATA/DEFAULT_PART: 本槽复位时的名称和部件号。
  localparam [255:0] DEFAULT_HEADER=default_name(FILE_IDS[32*catalog_slot+:32],1);
  localparam [255:0] DEFAULT_DATA=default_name(FILE_IDS[32*catalog_slot+:32],0);
  localparam [255:0] DEFAULT_PART=default_part(FILE_IDS[32*catalog_slot+:32]);
  // selected: APP正在写入本文件的目录字段。
  wire selected=catalog_write && host_slot==catalog_slot;
  always @(posedge clk)begin
   if(reset)source_flags[catalog_slot]<=0;
   else if(selected && catalog_index==0)source_flags[catalog_slot]<=catalog_data[2:0];
  end
  for(catalog_byte=0;catalog_byte<32;catalog_byte=catalog_byte+1)begin: bytes
   always @(posedge clk)begin
    if(reset)begin
     header_names[catalog_slot][8*catalog_byte+:8]<=DEFAULT_HEADER[8*catalog_byte+:8];
     data_names[catalog_slot][8*catalog_byte+:8]<=DEFAULT_DATA[8*catalog_byte+:8];
     part_numbers[catalog_slot][8*catalog_byte+:8]<=DEFAULT_PART[8*catalog_byte+:8];
    end else begin
     if(selected && catalog_index==17+catalog_byte)header_names[catalog_slot][8*catalog_byte+:8]<=catalog_data;
     if(selected && catalog_index==49+catalog_byte)data_names[catalog_slot][8*catalog_byte+:8]<=catalog_data;
     if(selected && catalog_index==81+catalog_byte)part_numbers[catalog_slot][8*catalog_byte+:8]<=catalog_data;
    end
   end
   if(catalog_byte<4)begin: sizes
    always @(posedge clk)begin
     if(reset)begin
      header_sizes[catalog_slot][8*catalog_byte+:8]<=0;
      data_sizes[catalog_slot][8*catalog_byte+:8]<=0;
     end else begin
      if(selected && catalog_index==1+catalog_byte)header_sizes[catalog_slot][8*catalog_byte+:8]<=catalog_data;
      if(selected && catalog_index==5+catalog_byte)data_sizes[catalog_slot][8*catalog_byte+:8]<=catalog_data;
     end
    end
   end
  end
 end endgenerate
endmodule

// 两个独立地址端口的字节RAM；综合直接使用eLinx支持的M4K，避免先展开成寄存器再识别。
module afdx_byte_ram #(
 parameter integer WORDS=512, // WORDS: RAM可保存的字节数。
 parameter integer ADDRESS_WIDTH=9 // ADDRESS_WIDTH: RAM地址位数。
)(
 input wire clk, // clk: 读写使用的时钟。
 input wire write_enable, // write_enable: 本拍写入一个字节。
 input wire [ADDRESS_WIDTH-1:0] write_address, // write_address: 待写字节位置。
 input wire [7:0] write_data, // write_data: 待写字节。
 input wire read_enable, // read_enable: 本拍发起同步读取。
 input wire [ADDRESS_WIDTH-1:0] read_address, // read_address: 待读字节位置。
 output wire [7:0] read_data // read_data: 上次读取的字节。
);
// Quartus 13预定义ALTERA_RESERVED_QIS；eLinx原生综合器预定义SYNTHESIS。
`ifdef ALTERA_RESERVED_QIS
`define AFDX_M4K_RAM
`elsif SYNTHESIS
`define AFDX_M4K_RAM
`endif
`ifdef AFDX_M4K_RAM
 // BANKS/BANK_WIDTH: 每块512字节的M4K数量及块编号位数。
 localparam BANKS=(WORDS+511)/512,BANK_WIDTH=BANKS<=1 ? 1 : $clog2(BANKS);
 // read_bank/write_bank: 当前地址所在的M4K块；saved_bank: 上次读取的块编号。
 wire [BANK_WIDTH-1:0] read_bank=read_address>>9,write_bank=write_address>>9;
 reg [BANK_WIDTH-1:0] saved_bank;
 // local_read_address/local_write_address: 单块M4K内部的字节地址。
 wire [8:0] local_read_address=read_address,local_write_address=write_address;
 // bank_data: 各块M4K同步读取后的字节。
 wire [8*BANKS-1:0] bank_data;
 assign read_data=bank_data[8*saved_bank+:8];
 always @(posedge clk)if(read_enable)saved_bank<=read_bank;
 genvar bank; // bank: 当前实例化的M4K块编号。
 generate for(bank=0;bank<BANKS;bank=bank+1)begin: blocks
  altsyncram #(
   .operation_mode("DUAL_PORT"),.intended_device_family("Stratix"),.ram_block_type("M4K"),
   .width_a(8),.widthad_a(9),.numwords_a(512),.width_b(8),.widthad_b(9),.numwords_b(512),
   .address_reg_b("CLOCK1"),.rdcontrol_reg_b("CLOCK1"),.outdata_reg_b("UNREGISTERED"),
   .read_during_write_mode_mixed_ports("OLD_DATA")) storage(
   .clock0(clk),.clock1(clk),.clocken0(1'b1),.clocken1(1'b1),.clocken2(1'b1),.clocken3(1'b1),
   .aclr0(1'b0),.aclr1(1'b0),.addressstall_a(1'b0),.addressstall_b(1'b0),
   .address_a(local_write_address),.data_a(write_data),.wren_a(write_enable && write_bank==bank),.rden_a(1'b1),.byteena_a(1'b1),
   .address_b(local_read_address),.data_b(8'd0),.wren_b(1'b0),.rden_b(read_enable && read_bank==bank),.byteena_b(1'b1),
   .q_b(bank_data[8*bank+:8]),.q_a(),.eccstatus());
 end endgenerate
`else
 // contents: 仿真中对应块RAM的字节存储；saved_byte: 同步读取输出。
 reg [7:0] contents[0:WORDS-1];
 reg [7:0] saved_byte;
 assign read_data=saved_byte;
 always @(posedge clk)begin
  if(write_enable)contents[write_address]<=write_data;
  if(read_enable)saved_byte<=contents[read_address];
 end
`endif
`undef AFDX_M4K_RAM
endmodule
