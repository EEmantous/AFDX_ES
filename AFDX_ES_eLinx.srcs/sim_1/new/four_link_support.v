`timescale 1ns/1ps
module afdx_four_link_case #(parameter integer LINK=1,OPERATION=2,FAULT=0,parameter PREFIX="app_to_es");
 localparam CAPACITY=2048,HEADER_BYTES=32;
 /* clk：20ns周期时钟；reset：高有效复位。 */ reg clk=0,reset=1;wire peer_clk=clk;always #10 clk=~clk;
 /* cut_a：断开A网的测试开关；corrupt_once：翻转一次A网字节的测试开关；injected：A网翻转已发生；damage_frame：本帧需要翻转一个A网字节。 */ reg cut_a=0,corrupt_once=0,injected=0,damage_frame=0;
 /* wire_index：当前发送帧的物理字节位置。 */ integer wire_index=0;/* op_hi：TFTP操作码高字节。 */ reg [7:0] op_hi=0;
 wire damage_byte=corrupt_once && damage_frame && wire_index==60;
 tb_app_file_driver loader_app(.clk(clk),.reset(reset),.data(es.rx_data),.valid(es.rx_valid),.ready(es.tx_ready),
  .reply_data(es.tx_data),.reply_valid(es.tx_valid),.reply_ready(es.rx_ready));
 tb_app_file_driver target_app(.clk(clk),.reset(reset),.data(external.rx_data),.valid(external.rx_valid),.ready(external.tx_ready),
  .reply_data(external.tx_data),.reply_valid(external.tx_valid),.reply_ready(external.rx_ready));
 generate if(1) begin : es
  // ES端：作用域区分位置，IO变量严格使用原始端口名。
  // tx_data：向APP端输出的文件字节。
  wire [7:0] tx_data;
  // rx_data：APP端输入的文件字节。
  wire [7:0] rx_data;
  // tx_valid：向APP端输出的字节有效。
  wire tx_valid;
  // rx_valid：APP端输入字节有效。
  wire rx_valid;
  // tx_ready：ES端可以接受APP端字节。
  wire tx_ready;
  // rx_ready：APP端可以接受ES端字节。
  wire rx_ready;
  // gmii_tx_a_txd：A网发送字节。
  wire [7:0] gmii_tx_a_txd;
  // gmii_tx_a_en：A网发送有效。
  wire gmii_tx_a_en;
  // gmii_tx_a_er：A网发送错误。
  wire gmii_tx_a_er;
  // gmii_tx_b_txd：B网发送字节。
  wire [7:0] gmii_tx_b_txd;
  // gmii_tx_b_en：B网发送有效。
  wire gmii_tx_b_en;
  // gmii_tx_b_er：B网发送错误。
  wire gmii_tx_b_er;
  // gmii_rx_a_rxd：A网接收字节。
  wire [7:0] gmii_rx_a_rxd;
  assign gmii_rx_a_rxd=external.gmii_tx_a_txd;
  // gmii_rx_a_dv：A网接收有效。
  wire gmii_rx_a_dv;
  assign gmii_rx_a_dv=external.gmii_tx_a_en && !cut_a;
  // gmii_rx_a_er：A网接收错误。
  wire gmii_rx_a_er;
  assign gmii_rx_a_er=external.gmii_tx_a_er;
  // gmii_rx_b_rxd：B网接收字节。
  wire [7:0] gmii_rx_b_rxd;
  assign gmii_rx_b_rxd=external.gmii_tx_b_txd;
  // gmii_rx_b_dv：B网接收有效。
  wire gmii_rx_b_dv;
  assign gmii_rx_b_dv=external.gmii_tx_b_en;
  // gmii_rx_b_er：B网接收错误。
  wire gmii_rx_b_er;
  assign gmii_rx_b_er=external.gmii_tx_b_er;
  afdx_test_es #(.TX_VL_COUNT(2),.RX_VL_COUNT(2),.LOADER(1),.MAP_ENTRIES(2),.FILE_IDS({32'd2,32'd1}),.FILE_VLS({8'd1,8'd0}),
  .MAX_FILE_BYTES(CAPACITY),.EVENT_DEPTH(4),.LOCAL_IP(32'h0a000001),
  .VL_BAG_CYCLES({32'd3000,32'd2000}),.RETRY_CYCLES(60000),.DALLY_CYCLES(120000),
  .OP_TIMEOUT(1000000),.STATUS_INTERVAL(60000),.TASK_GUARD_CYCLES(12000),
  .RTC_PEER_IP(0)) dut(
   .clk(clk),
   .reset(reset),
   .tx_data(tx_data),
   .rx_data(rx_data),
   .tx_valid(tx_valid),
   .rx_valid(rx_valid),
   .tx_ready(tx_ready),
   .rx_ready(rx_ready),
   .gmii_tx_a_txd(gmii_tx_a_txd),
   .gmii_tx_a_en(gmii_tx_a_en),
   .gmii_tx_a_er(gmii_tx_a_er),
   .gmii_tx_b_txd(gmii_tx_b_txd),
   .gmii_tx_b_en(gmii_tx_b_en),
   .gmii_tx_b_er(gmii_tx_b_er),
   .gmii_rx_a_rxd(gmii_rx_a_rxd),
   .gmii_rx_a_dv(gmii_rx_a_dv),
   .gmii_rx_a_er(gmii_rx_a_er),
   .gmii_rx_b_rxd(gmii_rx_b_rxd),
   .gmii_rx_b_dv(gmii_rx_b_dv),
   .gmii_rx_b_er(gmii_rx_b_er)
  );
 end endgenerate
 generate if(1) begin : external
  // 外部端：作用域区分位置，IO变量严格使用原始端口名。
  // tx_data：向APP端输出的文件字节。
  wire [7:0] tx_data;
  // rx_data：APP端输入的文件字节。
  wire [7:0] rx_data;
  // tx_valid：向APP端输出的字节有效。
  wire tx_valid;
  // rx_valid：APP端输入字节有效。
  wire rx_valid;
  // tx_ready：ES端可以接受APP端字节。
  wire tx_ready;
  // rx_ready：APP端可以接受ES端字节。
  wire rx_ready;
  // gmii_tx_a_txd：A网发送字节。
  wire [7:0] gmii_tx_a_txd;
  // gmii_tx_a_en：A网发送有效。
  wire gmii_tx_a_en;
  // gmii_tx_a_er：A网发送错误。
  wire gmii_tx_a_er;
  // gmii_tx_b_txd：B网发送字节。
  wire [7:0] gmii_tx_b_txd;
  // gmii_tx_b_en：B网发送有效。
  wire gmii_tx_b_en;
  // gmii_tx_b_er：B网发送错误。
  wire gmii_tx_b_er;
  // gmii_rx_a_rxd：A网接收字节。
  wire [7:0] gmii_rx_a_rxd;
  assign gmii_rx_a_rxd=es.gmii_tx_a_txd^(damage_byte ? 8'h01 : 8'h00);
  // gmii_rx_a_dv：A网接收有效。
  wire gmii_rx_a_dv;
  assign gmii_rx_a_dv=es.gmii_tx_a_en && !cut_a;
  // gmii_rx_a_er：A网接收错误。
  wire gmii_rx_a_er;
  assign gmii_rx_a_er=es.gmii_tx_a_er;
  // gmii_rx_b_rxd：B网接收字节。
  wire [7:0] gmii_rx_b_rxd;
  assign gmii_rx_b_rxd=es.gmii_tx_b_txd;
  // gmii_rx_b_dv：B网接收有效。
  wire gmii_rx_b_dv;
  assign gmii_rx_b_dv=es.gmii_tx_b_en;
  // gmii_rx_b_er：B网接收错误。
  wire gmii_rx_b_er;
  assign gmii_rx_b_er=es.gmii_tx_b_er;
  afdx_test_es #(.TX_VL_COUNT(2),.RX_VL_COUNT(2),.LOADER(0),.MAP_ENTRIES(2),.FILE_IDS({32'd2,32'd1}),.FILE_VLS({8'd1,8'd0}),
  .MAX_FILE_BYTES(CAPACITY),.EVENT_DEPTH(4),.LOCAL_IP(32'h0a000002),
  .VL_BAG_CYCLES({32'd3000,32'd2000}),.RETRY_CYCLES(60000),.DALLY_CYCLES(120000),
  .OP_TIMEOUT(1000000),.STATUS_INTERVAL(60000),.TASK_GUARD_CYCLES(12000),
  .RTC_PEER_IP(0)) dut(
   .clk(clk),
   .reset(reset),
   .tx_data(tx_data),
   .rx_data(rx_data),
   .tx_valid(tx_valid),
   .rx_valid(rx_valid),
   .tx_ready(tx_ready),
   .rx_ready(rx_ready),
   .gmii_tx_a_txd(gmii_tx_a_txd),
   .gmii_tx_a_en(gmii_tx_a_en),
   .gmii_tx_a_er(gmii_tx_a_er),
   .gmii_tx_b_txd(gmii_tx_b_txd),
   .gmii_tx_b_en(gmii_tx_b_en),
   .gmii_tx_b_er(gmii_tx_b_er),
   .gmii_rx_a_rxd(gmii_rx_a_rxd),
   .gmii_rx_a_dv(gmii_rx_a_dv),
   .gmii_rx_a_er(gmii_rx_a_er),
   .gmii_rx_b_rxd(gmii_rx_b_rxd),
   .gmii_rx_b_dv(gmii_rx_b_dv),
   .gmii_rx_b_er(gmii_rx_b_er)
  );
 end endgenerate
 tb_files_gmii_monitor #(.LOADER(1),.OUTPUT_PREFIX({PREFIX,"_loader"})) loader_wire_check(
  .clk(clk),.reset(reset),.data(es.gmii_tx_a_txd),.valid(es.gmii_tx_a_en),.error(es.gmii_tx_a_er),.test_case_id(LINK));
 tb_files_gmii_monitor #(.LOADER(0),.OUTPUT_PREFIX({PREFIX,"_target"})) target_wire_check(
  .clk(clk),.reset(reset),.data(external.gmii_tx_a_txd),.valid(external.gmii_tx_a_en),.error(external.gmii_tx_a_er),.test_case_id(LINK));
 /* input_bytes：从实际文件读到的发送字节。 */ reg [7:0] input_bytes[0:2*CAPACITY-1];
 /* sizes：实际输入文件长度。 */ integer sizes[0:1];/* data_crc：测试文件的CRC字段；header_crc：测试头的CRC字段。 */ reg [31:0] data_crc[0:1],header_crc[0:1];/* files_dir：实际传输文件目录。 */ reg [8191:0] files_dir;
 /* f：当前文件编号；first：首个测试文件编号；last：各VL输入帧尾位；checks：已完成的文件比较次数。 */ integer f,first,last,checks=0;/* drops：接收损坏帧数量；retries：615A重试次数。 */ reg [31:0] drops,retries;
 function [31:0] crc_step(input [31:0] old,input [7:0] value);
 /* b：当前CRC位位置。 */ integer b;/* c：CRC累加临时值。 */ reg [31:0] c;
 begin c=old^value;for(b=0;b<8;b=b+1)c=(c>>1)^(c[0] ? 32'hedb88320 : 0);crc_step=c;end endfunction
 function [7:0] header_byte(input /* f：当前文件编号；n：当前字节位置。 */ integer f,n);
 begin case(n)
  0:header_byte="T";1:header_byte="B";2:header_byte="L";3:header_byte="U";4:header_byte="H";
  8,9,10,11:header_byte=sizes[f]>>(8*(11-n));
  12,13,14,15:header_byte=data_crc[f]>>(8*(15-n));default:header_byte=n+16*f;
 endcase end endfunction
 function [255:0] name_value(input /* f：当前文件编号。 */ integer f,input header);
 begin name_value=header ? 256'h48554c2e3174786574 : 256'h7478742e3174786574;name_value[39:32]="1"+f;end endfunction
 task automatic load_file(input /* f：当前文件编号。 */ integer f);
 /* fd：当前输出文件句柄；ch：从文件读取的字符；n：当前字节位置。 */ integer fd,ch,n;/* c：CRC累加临时值。 */ reg [31:0] c;/* path：当前测试文件路径。 */ reg [8191:0] path;
 begin
  if(f==0)path={files_dir,"/text1.txt"};else path={files_dir,"/text2.txt"};
  fd=$fopen(path,"rb");if(!fd)$fatal(1,"Cannot read fixture %s",path);
  n=0;ch=$fgetc(fd);c=32'hffffffff;
  while(ch!=-1)begin
   if(n>=CAPACITY)$fatal(1,"Input too large");input_bytes[f*CAPACITY+n]=ch;c=crc_step(c,ch);n=n+1;ch=$fgetc(fd);
  end
  $fclose(fd);if(n==0)$fatal(1,"Empty fixture");sizes[f]=n;data_crc[f]=~c;c=32'hffffffff;
  for(n=0;n<HEADER_BYTES;n=n+1)c=crc_step(c,header_byte(f,n));header_crc[f]=~c;
 end endtask
 task automatic send_directory(input /* side：0加载器或1目标端。 */ integer side,input [1:0] mask,input store_only);
 /* f：当前文件编号；n：当前字节位置。 */ integer f,n;/* flags：目录数据来源和提交标志。 */ reg [2:0] flags;
 begin
  if(side==0)loader_app.directory_begin(store_only ? 0 : OPERATION,2,32'h0a000002);
  else target_app.directory_begin(store_only ? 0 : OPERATION,2,32'h0a000001);
  for(f=0;f<2;f=f+1)begin
   flags=(store_only || mask[f]) && (side==0 ? OPERATION==2 : OPERATION!=2) ? 3 : 0;
   if(!store_only && mask[f])flags=flags|4;
   if(side==0)loader_app.directory_entry(flags,HEADER_BYTES,sizes[f],header_crc[f],data_crc[f],name_value(f,1),name_value(f,0),256'h31302d4e50);
   else target_app.directory_entry(flags,HEADER_BYTES,sizes[f],header_crc[f],data_crc[f],name_value(f,1),name_value(f,0),256'h31302d4e50);
  end
  if(side==0 ? OPERATION==2 : OPERATION!=2)for(f=0;f<2;f=f+1)if(store_only || mask[f])begin
   for(n=0;n<HEADER_BYTES;n=n+1)if(side==0)loader_app.send_byte(header_byte(f,n));else target_app.send_byte(header_byte(f,n));
   for(n=0;n<sizes[f];n=n+1)if(side==0)loader_app.send_byte(input_bytes[f*CAPACITY+n]);else target_app.send_byte(input_bytes[f*CAPACITY+n]);
  end
  if(side==0)loader_app.directory_end(0);else target_app.directory_end(0);
 end endtask
 task automatic compare(input /* side：0加载器或1目标端；f：当前文件编号。 */ integer side,f);
 /* n：当前字节位置；fd：当前输出文件句柄。 */ integer n,fd;/* length：当前文件或帧长度。 */ reg [31:0] length;/* value：当前测试字节或结果。 */ reg [7:0] value;/* output_path：当前接收文件路径。 */ reg [8191:0] output_path;
 begin
  $sformat(output_path,"%s_received_%0d.txt",PREFIX,f+1);fd=$fopen(output_path,"wb");if(!fd)$fatal(1,"Output open");
  if(side==0)loader_app.file_begin(f+1,length);else target_app.file_begin(f+1,length);
  if(length!=sizes[f])$fatal(1,"APP automatic file length mismatch");
  for(n=0;n<sizes[f];n=n+1)begin
   value=side==0 ? loader_app.file_bytes[f*CAPACITY+n] : target_app.file_bytes[f*CAPACITY+n];
   if(value!==input_bytes[f*CAPACITY+n])$fatal(1,"File mismatch side=%0d f=%0d n=%0d",side,f,n);
   $fwrite(fd,"%c",value);
  end
  $fclose(fd);checks=checks+1;
 end endtask
 task automatic results(input /* side：0加载器或1目标端；count：本次文件数量。 */ integer side,count,input [1:0] mask);
 /* n：当前字节位置。 */ integer n;/* value：当前测试字节或结果。 */ reg [63:0] value;/* seen：已核对的文件编号标记。 */ reg [1:0] seen;
 begin seen=0;
  for(n=0;n<count;n=n+1)begin
   if(side==0)loader_app.result_get(value);else target_app.result_get(value);
   if(value[31:0]<1 || value[31:0]>2 || !mask[value[31:0]-1] || seen[value[31:0]-1] || value[47:32]!=3 || value[56])$fatal(1,"Bad completion %h",value);
   seen[value[31:0]-1]=1;
  end
  if(seen!=mask)$fatal(1,"Missing result");checks=checks+1;
 end endtask
 initial begin
  if(!$value$plusargs("FILES_DIR=%s",files_dir))files_dir="../../../files"; // eLinx的sim_1/behav工作目录。
  $dumpfile("transfer.vcd");$dumpvars(1);
  load_file(0);load_file(1);repeat(8)@(negedge clk);reset=0;
  if(LINK==1 || LINK==3)target_app.slow=1;
  if(LINK==3)loader_app.slow=1;
  begin
   first=0;last=LINK==3 ? 1 : 0;
   cut_a=FAULT==1;corrupt_once=FAULT==2;
   send_directory(1,LINK==3 ? 3 : 1<<first,0);
   send_directory(0,LINK==3 ? 3 : 1<<first,0);
   results(0,last-first+1,LINK==3 ? 3 : 1<<first);results(1,last-first+1,LINK==3 ? 3 : 1<<first);
   for(f=first;f<=last;f=f+1)compare(OPERATION==2 ? 1 : 0,f);
   if(FAULT==2 && (!injected || external.dut.core.network.mac_rx_a.drop_frames==0))$fatal(1,"A corruption was not exercised");
   if(FAULT==1 && (external.dut.core.network.mac_rx_a.good_frames!=0 || external.dut.core.network.mac_rx_b.good_frames==0))$fatal(1,"B-only transfer was not exercised");
   if(loader_wire_check.frame_count==0 || target_wire_check.frame_count==0)$fatal(1,"No wire traffic");
  end
  if(loader_app.errors || target_app.errors)$fatal(1,"Unexpected APP error");
  $display("A_RESULT ns=%0d good_a=%0d drop_a=%0d good_b=%0d",$time,external.dut.core.network.mac_rx_a.good_frames,external.dut.core.network.mac_rx_a.drop_frames,external.dut.core.network.mac_rx_b.good_frames);
  $display("TRANSFER_END ns=%0t fault=%0d",$time,FAULT);
  $display("FOUR LINK PASSED link=%0d checks=%0d bytes1=%0d bytes2=%0d",LINK,checks,sizes[0],sizes[1]);$finish;
 end
 always @(posedge clk)if(!reset)begin
  if(!es.gmii_tx_a_en)begin wire_index<=0;damage_frame<=0;end
  else begin
   if(wire_index==50)op_hi<=es.gmii_tx_a_txd;
   if(wire_index==51 && corrupt_once && !injected && op_hi==0 && es.gmii_tx_a_txd==3)damage_frame<=1;
   if(damage_byte)begin injected<=1;$display("A_DAMAGE ns=%0d",$time);end
   wire_index<=wire_index+1;
  end
  if(es.gmii_tx_a_en && (es.gmii_tx_a_txd!==es.gmii_tx_b_txd || !es.gmii_tx_b_en))$fatal(1,"A/B TX copies differ");
 end
 initial begin #300000000;$fatal(1,"Four-link watchdog");end
endmodule
