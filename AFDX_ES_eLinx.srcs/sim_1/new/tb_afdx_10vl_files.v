`timescale 1ns/1ps
// Default 10 TX / 100 RX profile on two complete endpoints. Ten concurrent
// 615A uploads use all service queues and deliver all ten files external.tx_data APP.
module tb_afdx_10vl_files #(parameter integer DALLY=500000);
 /* clk：20ns周期时钟；reset：高有效复位。 */ reg clk=0,reset=1;always #10 clk=~clk;
 tb_app_file_driver #(.CAPACITY(128),.FILES(10)) loader_app(.clk(clk),.reset(reset),.data(es.rx_data),.valid(es.rx_valid),.ready(es.tx_ready),
  .reply_data(es.tx_data),.reply_valid(es.tx_valid),.reply_ready(es.rx_ready));
 tb_app_file_driver #(.CAPACITY(128),.FILES(10)) target_app(.clk(clk),.reset(reset),.data(external.rx_data),.valid(external.rx_valid),.ready(external.tx_ready),
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
  assign gmii_rx_a_dv=external.gmii_tx_a_en;
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
  afdx_test_es #(.LOADER(1),.MAX_FILE_BYTES(128),.LOCAL_IP(32'h0a000001),
  .RETRY_CYCLES(250000),.DALLY_CYCLES(DALLY),.OP_TIMEOUT(5000000),.STATUS_INTERVAL(60000)) dut(
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
  assign gmii_rx_a_rxd=es.gmii_tx_a_txd;
  // gmii_rx_a_dv：A网接收有效。
  wire gmii_rx_a_dv;
  assign gmii_rx_a_dv=es.gmii_tx_a_en;
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
  afdx_test_es #(.LOADER(0),.MAX_FILE_BYTES(128),.LOCAL_IP(32'h0a000002),
  .RETRY_CYCLES(250000),.DALLY_CYCLES(DALLY),.OP_TIMEOUT(5000000),.STATUS_INTERVAL(60000)) dut(
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
 /* data_crc：测试文件的CRC字段；header_crc：测试头的CRC字段。 */ reg [31:0] data_crc[0:9],header_crc[0:9];
 // file_length/source_bytes: 十份真实源文件的长度和各128字节存放区域。
 integer file_length[0:9];reg [7:0] source_bytes[0:1279];
 // files_dir: FILES_DIR指定的工程文件目录；input_fd/input_byte: 当前源文件及读出的字节。
 reg [8191:0] files_dir;integer input_fd,input_byte;
 /* f：当前文件编号；n：当前字节位置；fd：当前输出文件句柄；lidx：加载器物理字节位置；tidx：目标端物理字节位置；ltx：各VL加载器发送帧数；ttx：各VL目标端发送帧数。 */ integer f,n,fd,lidx=0,tidx=0,ltx[0:9],ttx[0:9];/* lp：加载器上拍发送有效位；tp：目标端上拍发送有效位。 */ reg lp=0,tp=0;/* lhi：加载器VL高字节；thi：目标端VL高字节。 */ reg [7:0] lhi,thi;
 /* lframes：加载器物理帧输出文件；tframes：目标端物理帧输出文件；active_count：当前运行的VL任务数；max_active：观察到的最多并行任务数；lf：加载器计数循环位置；tf：目标端计数循环位置。 */ integer lframes,tframes,active_count,max_active=0,lf,tf;/* path：当前测试文件路径。 */ reg [8191:0] path;/* result：当前615A完成记录。 */ reg [63:0] result;
 /* seen：已核对的文件编号标记。 */ reg [9:0] seen;/* size：APP接收文件长度。 */ reg [31:0] size;
 /* l_dally：加载器各会话收尾等待拍数；t_dally：目标端各会话收尾等待拍数。 */ integer l_dally[0:9],t_dally[0:9];real app_finished;
 genvar ch;
 generate for(ch=0;ch<10;ch=ch+1)begin: timing
  always @(posedge clk)if(!reset)begin
   if(es.dut.core.service.vl[ch].node.cvalid && es.dut.core.service.vl[ch].node.engines[0].tftp.state==7)l_dally[ch]=l_dally[ch]+1;
   if(external.dut.core.service.vl[ch].node.cvalid && external.dut.core.service.vl[ch].node.engines[0].tftp.state==7)t_dally[ch]=t_dally[ch]+1;
  end
 end endgenerate
 function [7:0] value(input /* f：当前文件编号；n：当前字节位置。 */ integer f,n);begin value=source_bytes[f*128+n];end endfunction
 function [31:0] crc_byte(input [31:0] old,input [7:0] b);
 /* k：当前文件或字节位置。 */ integer k;/* c：CRC累加临时值。 */ reg [31:0] c;
 begin c=old^b;for(k=0;k<8;k=k+1)c=(c>>1)^(c[0] ? 32'hedb88320 : 0);crc_byte=c;end endfunction
 function [7:0] header(input /* f：当前文件编号；n：当前字节位置。 */ integer f,n);
 begin case(n)
  0:header="T";1:header="B";2:header="L";3:header="U";4:header="H";
  8,9,10,11:header=file_length[f]>>(8*(11-n));
  12,13,14,15:header=data_crc[f]>>(8*(15-n));default:header=n+f;
 endcase end endfunction
 function [255:0] disk_name(input integer f,input h); // f: 源文件编号；h: 选择配套LUH头名。
 begin case(f)
  0:disk_name=h ? "flight_plan.LUH" : "flight_plan.txt";
  1:disk_name=h ? "routes.LUH" : "routes.csv";
  2:disk_name=h ? "radio.LUH" : "radio.cfg";
  3:disk_name=h ? "cabin_msg.LUH" : "cabin_msg.txt";
  4:disk_name=h ? "nav_points.LUH" : "nav_points.csv";
  5:disk_name=h ? "limits.LUH" : "limits.json";
  6:disk_name=h ? "maint_log.LUH" : "maint_log.txt";
  7:disk_name=h ? "sensor_cal.LUH" : "sensor_cal.csv";
  8:disk_name=h ? "status.LUH" : "status.ini";
  9:disk_name=h ? "payload.LUH" : "payload.bin";
 endcase end endfunction
 function [255:0] name(input integer f,input h); // f: 目录文件编号；h: 选择LUH头名。
 // text: 磁盘文件名；length: 名称字节数；character: 转为APP低字节在前格式的位置。
 reg [255:0] text;integer length,character;
 begin
  text=disk_name(f,h);length=0;name=0;
  for(character=0;character<32;character=character+1)if(text[8*character+:8]!=0)length=character+1;
  for(character=0;character<length;character=character+1)name[8*character+:8]=text[8*(length-1-character)+:8];
 end endfunction
 task directory(input /* side：0加载器或1目标端。 */ integer side);
 /* f：当前文件编号；n：当前字节位置。 */ integer f,n;
 begin
  if(side==0)loader_app.directory_begin(2,10,32'h0a000002);else target_app.directory_begin(2,10,32'h0a000001);
  for(f=0;f<10;f=f+1)begin
   if(side==0)loader_app.directory_entry(7,32,file_length[f],header_crc[f],data_crc[f],name(f,1),name(f,0),256'h31);
   else target_app.directory_entry(4,32,file_length[f],header_crc[f],data_crc[f],name(f,1),name(f,0),256'h31);
  end
  if(side==0)begin
   for(f=0;f<10;f=f+1)begin
    for(n=0;n<32;n=n+1)loader_app.send_byte(header(f,n));
    for(n=0;n<file_length[f];n=n+1)loader_app.send_byte(value(f,n));
   end
   loader_app.directory_end(0);
  end else target_app.directory_end(0);
 end endtask
 always @(posedge clk)if(!reset)begin
  active_count=0;for(lf=0;lf<10;lf=lf+1)if(es.dut.core.active[lf])active_count=active_count+1;
  if(active_count>max_active)begin max_active=active_count;$display("MULTI_CONCURRENCY ns=%0d active=%0d",$time,max_active);end
  if(es.gmii_tx_a_en!==es.gmii_tx_b_en || external.gmii_tx_a_en!==external.gmii_tx_b_en || es.gmii_tx_a_er || es.gmii_tx_b_er || external.gmii_tx_a_er || external.gmii_tx_b_er || (es.gmii_tx_a_en && es.gmii_tx_a_txd!==es.gmii_tx_b_txd) || (external.gmii_tx_a_en && external.gmii_tx_a_txd!==external.gmii_tx_b_txd))$fatal(1,"Multi-VL A/B mismatch");
  if(es.gmii_tx_a_en)begin
   $fwrite(lframes,"%02h",es.gmii_tx_a_txd);if(lidx==12)lhi=es.gmii_tx_a_txd;if(lidx==13)begin ltx[{lhi,es.gmii_tx_a_txd}-1]=ltx[{lhi,es.gmii_tx_a_txd}-1]+1;if(lframes && ltx[{lhi,es.gmii_tx_a_txd}-1]==1)$display("MULTI_VL ns=%0d side=loader vl=%0d",$time,{lhi,es.gmii_tx_a_txd});end lidx=lidx+1;
  end else if(lp)begin $fwrite(lframes,"\n");lidx=0;end
  if(external.gmii_tx_a_en)begin
   $fwrite(tframes,"%02h",external.gmii_tx_a_txd);if(tidx==12)thi=external.gmii_tx_a_txd;if(tidx==13)begin ttx[{thi,external.gmii_tx_a_txd}-11]=ttx[{thi,external.gmii_tx_a_txd}-11]+1;if(tframes && ttx[{thi,external.gmii_tx_a_txd}-11]==1)$display("MULTI_VL ns=%0d side=target vl=%0d",$time,{thi,external.gmii_tx_a_txd});end tidx=tidx+1;
  end else if(tp)begin $fwrite(tframes,"\n");tidx=0;end
  lp=es.gmii_tx_a_en;tp=external.gmii_tx_a_en;
 end
 initial begin
  lframes=$fopen("ten_vl_loader.hex","w");tframes=$fopen("ten_vl_target.hex","w");
  if(!$value$plusargs("FILES_DIR=%s",files_dir))files_dir="../../../files";
  for(f=0;f<10;f=f+1)begin
   $sformat(path,"%0s/multi/%0s",files_dir,disk_name(f,0));input_fd=$fopen(path,"rb");
   if(!input_fd)$fatal(1,"Cannot open %0s",path);
   file_length[f]=0;input_byte=$fgetc(input_fd);
   while(input_byte>=0)begin
    if(file_length[f]>=128)$fatal(1,"Multi-file input exceeds configured capacity: %0s",path);
    source_bytes[f*128+file_length[f]]=input_byte;file_length[f]=file_length[f]+1;input_byte=$fgetc(input_fd);
   end
   $fclose(input_fd);
   ltx[f]=0;ttx[f]=0;l_dally[f]=0;t_dally[f]=0;data_crc[f]=32'hffffffff;
   for(n=0;n<file_length[f];n=n+1)data_crc[f]=crc_byte(data_crc[f],value(f,n));data_crc[f]=~data_crc[f];
   header_crc[f]=32'hffffffff;for(n=0;n<32;n=n+1)header_crc[f]=crc_byte(header_crc[f],header(f,n));header_crc[f]=~header_crc[f];
   $display("MULTI_SOURCE file_id=%0d name=%0s bytes=%0d crc32=%08h",f+1,disk_name(f,0),file_length[f],data_crc[f]);
  end
  $dumpfile("multi.vcd");$dumpvars(1,tb_afdx_10vl_files);
  repeat(8)@(negedge clk);reset=0;target_app.slow=1;
  if(es.dut.TX_VL_COUNT!=10 || es.dut.RX_VL_COUNT!=100)$fatal(1,"Wrong default capacity");
  if(es.dut.VL_BAG_CYCLES!={10{32'd1}} || external.dut.VL_BAG_CYCLES!={10{32'd1}})$fatal(1,"Performance default BAG is not one clock");
  directory(1);directory(0);app_finished=$realtime;
  seen=0;
  for(f=0;f<10;f=f+1)begin
   loader_app.result_get(result);
   if(result[31:0]<1 || result[31:0]>10 || result[47:32]!=3 || result[56] || seen[result[31:0]-1])$fatal(1,"Loader result mismatch");
   seen[result[31:0]-1]=1;
  end
  seen=0;
  for(f=0;f<10;f=f+1)begin
   target_app.result_get(result);
   if(result[31:0]<1 || result[31:0]>10 || result[47:32]!=3 || result[56] || seen[result[31:0]-1])$fatal(1,"Target result mismatch");
   seen[result[31:0]-1]=1;
  end
  for(f=0;f<10;f=f+1)begin
   target_app.file_begin(f+1,size);if(size!=file_length[f])$fatal(1,"Ten-VL file size");
   $sformat(path,"received_%0s",disk_name(f,0));fd=$fopen(path,"wb");
   for(n=0;n<file_length[f];n=n+1)begin
    if(target_app.file_bytes[f*128+n]!==value(f,n))$fatal(1,"Ten-VL file corrupt");
    $fwrite(fd,"%c",target_app.file_bytes[f*128+n]);
   end
   $fclose(fd);if(ltx[f]==0 || ttx[f]==0)$fatal(1,"VL not exercised");
  end
  if(max_active!=10 || loader_app.errors || target_app.errors)$fatal(1,"Ten parallel services not exercised");
  $fclose(lframes);$fclose(tframes);
  $display("TEN VL FILE TIMING DALLY_cycles=%0d APP_complete_ns=%.0f all_files_ns=%.0f loader0_dally_wait=%0d target0_dally_wait=%0d",DALLY,app_finished,$realtime,l_dally[0],t_dally[0]);
  $display("TEN VL FILE TEST PASSED files=10 simultaneous=10 RX_capacity=100");$finish;
 end
 initial begin #500000000;$fatal(1,"Ten-file watchdog");end
endmodule
module tb_afdx_10vl_files_short_dally;
 // 顶层同名IO仅用于观察，使eLinx生成的add wave *能直接找到完整端口。
 // clk/reset：当前用例实际使用的时钟与复位。
 wire clk=test.clk,reset=test.reset;
 // tx_data：直接观察ES端同名IO。
 wire [7:0] tx_data=test.es.tx_data;
 // rx_data：直接观察ES端同名IO。
 wire [7:0] rx_data=test.es.rx_data;
 // tx_valid：直接观察ES端同名IO。
 wire tx_valid=test.es.tx_valid;
 // rx_valid：直接观察ES端同名IO。
 wire rx_valid=test.es.rx_valid;
 // tx_ready：直接观察ES端同名IO。
 wire tx_ready=test.es.tx_ready;
 // rx_ready：直接观察ES端同名IO。
 wire rx_ready=test.es.rx_ready;
 // gmii_tx_a_txd：直接观察ES端同名IO。
 wire [7:0] gmii_tx_a_txd=test.es.gmii_tx_a_txd;
 // gmii_tx_a_en：直接观察ES端同名IO。
 wire gmii_tx_a_en=test.es.gmii_tx_a_en;
 // gmii_tx_a_er：直接观察ES端同名IO。
 wire gmii_tx_a_er=test.es.gmii_tx_a_er;
 // gmii_tx_b_txd：直接观察ES端同名IO。
 wire [7:0] gmii_tx_b_txd=test.es.gmii_tx_b_txd;
 // gmii_tx_b_en：直接观察ES端同名IO。
 wire gmii_tx_b_en=test.es.gmii_tx_b_en;
 // gmii_tx_b_er：直接观察ES端同名IO。
 wire gmii_tx_b_er=test.es.gmii_tx_b_er;
 // gmii_rx_a_rxd：直接观察ES端同名IO。
 wire [7:0] gmii_rx_a_rxd=test.es.gmii_rx_a_rxd;
 // gmii_rx_a_dv：直接观察ES端同名IO。
 wire gmii_rx_a_dv=test.es.gmii_rx_a_dv;
 // gmii_rx_a_er：直接观察ES端同名IO。
 wire gmii_rx_a_er=test.es.gmii_rx_a_er;
 // gmii_rx_b_rxd：直接观察ES端同名IO。
 wire [7:0] gmii_rx_b_rxd=test.es.gmii_rx_b_rxd;
 // gmii_rx_b_dv：直接观察ES端同名IO。
 wire gmii_rx_b_dv=test.es.gmii_rx_b_dv;
 // gmii_rx_b_er：直接观察ES端同名IO。
 wire gmii_rx_b_er=test.es.gmii_rx_b_er;
 tb_afdx_10vl_files #(.DALLY(60000)) test();
endmodule
