`timescale 1ns/1ps
// 单一场景：APP输入指定的目录和文件，两个真实端系统经A/B直连完成615A UPLOAD。
// 仅用公开 IO 激励/检查；内部信号只用于波形观察。时钟周期 20 ns。
// 两个AFDX_top公开引脚直连A/B；APP输入文件，目标端回传给APP；逐字节比较并保存波形和接收文件。
module afdx_single_file_case #(
 parameter CAPACITY=2048,parameter FILE_NAME="text2.txt", // CAPACITY: 输入容量；FILE_NAME: 实际磁盘文件名。
 parameter [255:0] HEADER_NAME=256'h48554c2e656c6966, // HEADER_NAME: APP目录和TFTP中的测试头名，低字节先传。
 parameter [255:0] DATA_NAME=256'h7478742e656c6966, // DATA_NAME: APP目录和TFTP中的数据名，低字节先传。
 parameter integer TRANSFERS=1 // TRANSFERS: 同一对端系统不复位连续完成的文件传输次数。
);
 localparam HEADER_BYTES=32;
 /* REGDOC: clk：仿真20ns周期时钟及高有效复位，160ns释放。 reset：仿真20ns周期时钟及高有效复位，160ns释放。 */ reg clk=0,reset=1;
 always #10 clk=~clk;

 generate if(1) begin : es
  // ES端：作用域区分位置，IO变量严格使用原始端口名。
  // tx_data：向APP端输出的文件字节。
  wire [7:0] tx_data;
  // rx_data：APP端输入的文件字节。
  reg [7:0] rx_data=0;
  // tx_valid：向APP端输出的字节有效。
  wire tx_valid;
  // rx_valid：APP端输入字节有效。
  reg rx_valid=0;
  // tx_ready：ES端可以接受APP端字节。
  wire tx_ready;
  // rx_ready：APP端可以接受ES端字节。
  wire rx_ready;
  assign rx_ready=1'b1;
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
  afdx_test_es #(.LOADER(1),.TX_VL_COUNT(1),.RX_VL_COUNT(1),.MAP_ENTRIES(1),
  .FILE_IDS(32'd1),.FILE_VLS(8'd0),.LOCAL_IP(32'h0a000001),.MAX_FILE_BYTES(CAPACITY),
  .RETRY_CYCLES(60000),.DALLY_CYCLES(4000),.OP_TIMEOUT(1000000),
  .STATUS_INTERVAL(60000),.TASK_GUARD_CYCLES(12000)) dut(
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
  reg [7:0] rx_data=0;
  // tx_valid：向APP端输出的字节有效。
  wire tx_valid;
  // rx_valid：APP端输入字节有效。
  reg rx_valid=0;
  // tx_ready：ES端可以接受APP端字节。
  wire tx_ready;
  // rx_ready：APP端可以接受ES端字节。
  wire rx_ready;
  assign rx_ready=1'b1;
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
  afdx_test_es #(.LOADER(0),.TX_VL_COUNT(1),.RX_VL_COUNT(1),.MAP_ENTRIES(1),
  .FILE_IDS(32'd1),.FILE_VLS(8'd0),.LOCAL_IP(32'h0a000002),.MAX_FILE_BYTES(CAPACITY),
  .RETRY_CYCLES(60000),.DALLY_CYCLES(4000),.OP_TIMEOUT(1000000),
  .STATUS_INTERVAL(60000),.TASK_GUARD_CYCLES(12000)) dut(
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

 /* source: 从files/FILE_NAME读取的原始文件字节，用于发送及逐字节独立比较。 */ reg [7:0] source[0:CAPACITY-1];
 /* REGDOC: files_dir：FILES_DIR plusarg给出的输入文件目录字符串。 */ reg [8191:0] files_dir;
 /* REGDOC: input_fd：输入文件、接收文件和逐拍IO CSV的仿真文件句柄。 output_fd：输入文件、接收文件和逐拍IO CSV的仿真文件句柄。 trace_fd：输入文件、接收文件和逐拍IO CSV的仿真文件句柄。 ch：从二进制源文件读取的当前字符，-1表示到文件末尾。 file_length：从真实输入文件读取的字节数，不含32字节测试头。 n：索引/地址/长度或组合计算临时变量；有非阻塞赋值时才承担跨拍状态，具体用途见本模块赋值。 */ integer input_fd,output_fd,trace_fd,ch,file_length=0,n;
 /* REGDOC: data_crc：原文件及32字节测试头的标准取反CRC32。 header_crc：原文件及32字节测试头的标准取反CRC32。 */ reg [31:0] data_crc,header_crc;
 // 端系统按低字节先传字符串，字符串总宽度固定为 32 字节。
 localparam [255:0] PART_NUMBER=256'h31302d4e50;      // PN-01
 function [31:0] crc_byte(input [31:0] previous,input [7:0] value);
  /* REGDOC: bit_index：索引/地址/长度或组合计算临时变量；有非阻塞赋值时才承担跨拍状态，具体用途见本模块赋值。 */ integer bit_index;/* REGDOC: crc：TB独立CRC函数的32位累加临时值。 */ reg [31:0] crc;
  begin crc=previous^value;
   for(bit_index=0;bit_index<8;bit_index=bit_index+1)crc=(crc>>1)^(crc[0] ? 32'hedb88320 : 0);
   crc_byte=crc;
  end
 endfunction
 // 本工程把 LUH 当作应用提供的不透明对象；这里的 32 字节只是测试夹具。
 function [7:0] header_byte(input /* REGDOC: index：索引/地址/长度或组合计算临时变量；有非阻塞赋值时才承担跨拍状态，具体用途见本模块赋值。 */ integer index);
  begin case(index)
   0:header_byte="T";1:header_byte="B";2:header_byte="L";3:header_byte="U";4:header_byte="H";
   8,9,10,11:header_byte=file_length>>(8*(11-index));
   12,13,14,15:header_byte=data_crc>>(8*(15-index));
   default:header_byte=index;
  endcase end
 endfunction
 task send_byte(input /* REGDOC: side：0加载器、1目标机的TB任务/解析循环选择。 */ integer side,input [7:0] value);
  begin
   @(negedge clk);
   if(side==0)begin es.rx_data=value;es.rx_valid=1;end
   else begin external.rx_data=value;external.rx_valid=1;end
   @(posedge clk);
   while(!(side==0 ? es.tx_ready : external.tx_ready))@(posedge clk);
  end
 endtask
 task send_u32(input /* REGDOC: side：0加载器、1目标机的TB任务/解析循环选择。 */ integer side,input [31:0] value);
  /* REGDOC: i：索引/地址/长度或组合计算临时变量；有非阻塞赋值时才承担跨拍状态，具体用途见本模块赋值。 */ integer i;begin for(i=0;i<4;i=i+1)send_byte(side,value[8*i+:8]);end
 endtask
 task send_directory(input /* REGDOC: side：0加载器、1目标机的TB任务/解析循环选择。 */ integer side);
  /* REGDOC: i：索引/地址/长度或组合计算临时变量；有非阻塞赋值时才承担跨拍状态，具体用途见本模块赋值。 */ integer i;
  begin
   send_byte(side,1);send_byte(side,2);send_byte(side,1); // version, UPLOAD, entry_count
   send_u32(side,side==0 ? 32'h0a000002 : 32'h0a000001);
   send_byte(side,side==0 ? 7 : 4); // bits 0/1: APP supplies header/data; bit 2: submit task
   send_u32(side,HEADER_BYTES);send_u32(side,file_length);
   send_u32(side,header_crc);send_u32(side,data_crc);
   for(i=0;i<32;i=i+1)send_byte(side,HEADER_NAME[8*i+:8]);
   for(i=0;i<32;i=i+1)send_byte(side,DATA_NAME[8*i+:8]);
   for(i=0;i<32;i=i+1)send_byte(side,PART_NUMBER[8*i+:8]);
   if(side==0)begin
    for(i=0;i<HEADER_BYTES;i=i+1)send_byte(side,header_byte(i));
    for(i=0;i<file_length;i=i+1)send_byte(side,source[i]);
   end
   @(negedge clk);
   if(side==0)es.rx_valid=0;else external.rx_valid=0;
  end
 endtask

 // 输出记录解析：6 字节记录头（类型、句柄、LE32 长度），随后是正文。
 /* REGDOC: record_index[0:1]：各端APP输出记录头已解析的字节位置0..6。 record_kind[0:1]：各端当前APP输出记录类型。 record_handle[0:1]：各端当前APP输出记录文件句柄。 record_length[0:1]：各端当前APP输出记录正文长度。 payload_index[0:1]：各端当前APP输出正文已经消费的字节数。 */ integer record_index[0:1],record_kind[0:1],record_handle[0:1],record_length[0:1],payload_index[0:1];
 /* REGDOC: result_word[0:1]：两端615A完成记录的64位重组值。 */ reg [63:0] result_word[0:1];
 /* REGDOC: accepted：两端目录接受记录已收到：bit0加载器、bit1目标端。 completed：两端615A成功完成记录已收到：bit0加载器、bit1目标端。 */ reg [1:0] accepted=0,completed=0;
 /* REGDOC: file_received：目标APP已交付全部文件字节且每字节与source一致。 */ reg file_received=0;
 // iteration: 当前连续传输序号，从0开始；metrics_fd: 每次传输的原始计数CSV。
 integer iteration=0,metrics_fd;
 // wire_fd/wire_count/frame_count: ES-A、外部-A、ES-B、外部-B四路的逐帧文件、有效字节数及帧数。
 integer wire_fd[0:3],wire_count[0:3],frame_count[0:3];
 // stream: 逐路采样索引；previous_enable: 各发送有效位上一次采样值，用于划定完整帧。
 integer stream;
 reg [3:0] previous_enable=0;
 // measured_enable/measured_data: 两端四路GMII公开发送信号按同一顺序组合。
 wire [3:0] measured_enable={external.gmii_tx_b_en,es.gmii_tx_b_en,external.gmii_tx_a_en,es.gmii_tx_a_en};
 wire [31:0] measured_data={external.gmii_tx_b_txd,es.gmii_tx_b_txd,external.gmii_tx_a_txd,es.gmii_tx_a_txd};
 // first_wire_ns/last_wire_end_ns/command_start_ns: 本次首个网络字节、末字节结束和提交APP目录的时刻。
 time first_wire_ns=0,last_wire_end_ns=0,command_start_ns;
 always @(posedge clk)if(!reset && TRANSFERS>1)begin
  for(stream=0;stream<4;stream=stream+1)begin
   if(measured_enable[stream])begin
    if(first_wire_ns==0)first_wire_ns=$time;
    last_wire_end_ns=$time+20;
    wire_count[stream]=wire_count[stream]+1;
    if(!previous_enable[stream])begin
     frame_count[stream]=frame_count[stream]+1;
     $fwrite(wire_fd[stream],"%0d,%0d,",iteration+1,$time);
    end
    $fwrite(wire_fd[stream],"%02h",measured_data[8*stream+:8]);
   end else if(previous_enable[stream])$fwrite(wire_fd[stream],",%0d\n",$time-20);
  end
  previous_enable=measured_enable;
 end
 /* REGDOC: side：0加载器、1目标机的TB任务/解析循环选择。 */ integer side;/* REGDOC: output_byte：本拍选中端的APP输出字节临时值。 */ reg [7:0] output_byte;
 always @(posedge clk)if(!reset)begin
  for(side=0;side<2;side=side+1)if(side==0 ? es.tx_valid : external.tx_valid)begin
   output_byte=side==0 ? es.tx_data : external.tx_data;
   if(record_index[side]<6)begin
    case(record_index[side])
     0:record_kind[side]=output_byte;
     1:record_handle[side]=output_byte;
     2:record_length[side]=output_byte;
     3,4,5:record_length[side]=record_length[side] | (output_byte<<(8*(record_index[side]-2)));
    endcase
    record_index[side]=record_index[side]+1;
    if(record_index[side]==6)begin
     payload_index[side]=0;result_word[side]=0;
     if(record_kind[side]==16 && (side!=1 || record_handle[side]!=1 || record_length[side]!=file_length))
      $fatal(1,"Unexpected file record");
     if(record_length[side]==0)$fatal(1,"Unexpected empty record");
    end
   end else begin
    case(record_kind[side])
     16:begin
      if(output_byte!==source[payload_index[side]])$fatal(1,"File byte mismatch at %0d",payload_index[side]);
      $fwrite(output_fd,"%c",output_byte);
     end
     32:begin
      if(record_length[side]!=8)$fatal(1,"Bad result length");
      result_word[side][8*payload_index[side]+:8]=output_byte;
     end
     48:if(record_length[side]!=1 || output_byte!=0)$fatal(1,"Directory rejected");
     224:$fatal(1,"APP error side=%0d code=%0d",side,output_byte);
     default:$fatal(1,"Unexpected APP record %h",record_kind[side]);
    endcase
    payload_index[side]=payload_index[side]+1;
    if(payload_index[side]==record_length[side])begin
     case(record_kind[side])
      16:file_received=1;
      32:begin
       if(result_word[side][31:0]!=1 || result_word[side][47:32]!=3 || result_word[side][56])
        $fatal(1,"615A completion failed side=%0d result=%h",side,result_word[side]);
       completed[side]=1;
      end
      48:accepted[side]=1;
     endcase
     record_index[side]=0;
    end
   end
  end
  if(es.gmii_tx_a_er || es.gmii_tx_b_er || external.gmii_tx_a_er || external.gmii_tx_b_er)$fatal(1,"MAC TX error");
  if(es.gmii_tx_a_en!==es.gmii_tx_b_en || (es.gmii_tx_a_en && es.gmii_tx_a_txd!==es.gmii_tx_b_txd))$fatal(1,"Loader A/B differ");
  if(external.gmii_tx_a_en!==external.gmii_tx_b_en || (external.gmii_tx_a_en && external.gmii_tx_a_txd!==external.gmii_tx_b_txd))$fatal(1,"Target A/B differ");
 end

 // 每拍采样所有公开 IO。CSV 是该上升沿握手前的稳定值；VCD 还记录 NBA 更新后的变化。
 always @(posedge clk)if(iteration==0)begin
  $fwrite(trace_fd,"%0d,%b,%b,%02h,%b,%b,%02h,%b,%b,%02h,%b,%b,%02h,%b,%02h,%b,%b,%02h,%b,%b,%02h,%b,%b,%02h,%b,%b\n",
   $time,reset,es.rx_valid,es.rx_data,es.tx_ready,es.tx_valid,es.tx_data,
   external.rx_valid,external.tx_ready,external.rx_data,external.tx_valid,external.rx_ready,external.tx_data,
   es.rx_ready,es.gmii_tx_a_txd,es.gmii_tx_a_en,es.gmii_tx_a_er,es.gmii_tx_b_txd,es.gmii_tx_b_en,es.gmii_tx_b_er,
   external.gmii_tx_a_txd,external.gmii_tx_a_en,external.gmii_tx_a_er,external.gmii_tx_b_txd,external.gmii_tx_b_en,external.gmii_tx_b_er);
 end
 initial begin
  trace_fd=$fopen("io_cycles.csv","w");output_fd=$fopen("received_file.txt","wb");
  if(!trace_fd || !output_fd)$fatal(1,"Cannot open output files");
  $fwrite(trace_fd,"time_ns,reset,es.rx_valid,es.rx_data,es.tx_ready,es.tx_valid,es.tx_data,external.rx_valid,external.tx_ready,external.rx_data,external.tx_valid,external.rx_ready,external.tx_data,es.rx_ready,es.gmii_tx_a_txd,es.gmii_tx_a_en,es.gmii_tx_a_er,es.gmii_tx_b_txd,es.gmii_tx_b_en,es.gmii_tx_b_er,external.gmii_tx_a_txd,external.gmii_tx_a_en,external.gmii_tx_a_er,external.gmii_tx_b_txd,external.gmii_tx_b_en,external.gmii_tx_b_er\n");
  $dumpfile("single_file.vcd");$dumpvars(1);
  if(TRANSFERS>1)begin
   metrics_fd=$fopen("speed_iterations.csv","w");
   $fwrite(metrics_fd,"run,file_bytes,command_start_ns,first_wire_ns,last_wire_end_ns,completed_ns,es_a_bytes,peer_a_bytes,es_b_bytes,peer_b_bytes,es_a_frames,peer_a_frames,es_b_frames,peer_b_frames\n");
   wire_fd[0]=$fopen("wire_stream_0.csv","w");wire_fd[1]=$fopen("wire_stream_1.csv","w");
   wire_fd[2]=$fopen("wire_stream_2.csv","w");wire_fd[3]=$fopen("wire_stream_3.csv","w");
   for(n=0;n<4;n=n+1)$fwrite(wire_fd[n],"run,start_ns,hex,end_ns\n");
  end
  for(n=0;n<2;n=n+1)begin record_index[n]=0;record_kind[n]=0;record_handle[n]=0;
   record_length[n]=0;payload_index[n]=0;result_word[n]=0;end
  if(!$value$plusargs("FILES_DIR=%s",files_dir))files_dir="../../../files"; // eLinx的sim_1/behav工作目录。
  input_fd=$fopen({files_dir,"/",FILE_NAME},"rb");if(!input_fd)$fatal(1,"Cannot open %0s/%0s",files_dir,FILE_NAME);
  data_crc=32'hffffffff;ch=$fgetc(input_fd);
  while(ch!=-1)begin
   if(file_length==CAPACITY)$fatal(1,"Input exceeds CAPACITY");
   source[file_length]=ch;data_crc=crc_byte(data_crc,ch);file_length=file_length+1;ch=$fgetc(input_fd);
  end
  $fclose(input_fd);data_crc=~data_crc;
  if(file_length==0)$fatal(1,"Empty input");
  header_crc=32'hffffffff;
  for(n=0;n<HEADER_BYTES;n=n+1)header_crc=crc_byte(header_crc,header_byte(n));header_crc=~header_crc;
  repeat(8)@(negedge clk);reset=0;
  for(iteration=0;iteration<TRANSFERS;iteration=iteration+1)begin
   accepted=0;completed=0;file_received=0;
   first_wire_ns=0;last_wire_end_ns=0;command_start_ns=$time;
   for(n=0;n<4;n=n+1)begin wire_count[n]=0;frame_count[n]=0;end
   send_directory(1);wait(accepted[1]);send_directory(0);
   wait(accepted==3 && completed==3 && file_received);
   repeat(20)@(negedge clk);
   if(TRANSFERS>1)begin
    $fwrite(metrics_fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",iteration+1,file_length,command_start_ns,first_wire_ns,last_wire_end_ns,$time,wire_count[0],wire_count[1],wire_count[2],wire_count[3],frame_count[0],frame_count[1],frame_count[2],frame_count[3]);
    $display("SPEED ITERATION PASS run=%0d bytes=%0d wire_a=%0d wire_b=%0d start_ns=%0d end_ns=%0d",iteration+1,file_length,wire_count[0]+wire_count[1],wire_count[2]+wire_count[3],first_wire_ns,last_wire_end_ns);
    if(iteration==0)$dumpoff;
   end
  end
  if(TRANSFERS>1)begin
   $fclose(metrics_fd);
   for(n=0;n<4;n=n+1)$fclose(wire_fd[n]);
  end
  $fclose(output_fd);$fclose(trace_fd);
  $display("SINGLE FILE PASS bytes=%0d transfers=%0d crc32=%08h end_ns=%0d",file_length,TRANSFERS,data_crc,$time);$finish;
 end
 initial begin #(20000000.0*TRANSFERS);$fatal(1,"Single-file watchdog expired");end
endmodule

module tb_single_file;
 // 顶层同名IO仅用于观察，使eLinx生成的add wave *能直接找到完整端口。
 // clk/reset：当前用例实际使用的时钟与复位。
 wire clk=scenario.clk,reset=scenario.reset;
 // tx_data：直接观察ES端同名IO。
 wire [7:0] tx_data=scenario.es.tx_data;
 // rx_data：直接观察ES端同名IO。
 wire [7:0] rx_data=scenario.es.rx_data;
 // tx_valid：直接观察ES端同名IO。
 wire tx_valid=scenario.es.tx_valid;
 // rx_valid：直接观察ES端同名IO。
 wire rx_valid=scenario.es.rx_valid;
 // tx_ready：直接观察ES端同名IO。
 wire tx_ready=scenario.es.tx_ready;
 // rx_ready：直接观察ES端同名IO。
 wire rx_ready=scenario.es.rx_ready;
 // gmii_tx_a_txd：直接观察ES端同名IO。
 wire [7:0] gmii_tx_a_txd=scenario.es.gmii_tx_a_txd;
 // gmii_tx_a_en：直接观察ES端同名IO。
 wire gmii_tx_a_en=scenario.es.gmii_tx_a_en;
 // gmii_tx_a_er：直接观察ES端同名IO。
 wire gmii_tx_a_er=scenario.es.gmii_tx_a_er;
 // gmii_tx_b_txd：直接观察ES端同名IO。
 wire [7:0] gmii_tx_b_txd=scenario.es.gmii_tx_b_txd;
 // gmii_tx_b_en：直接观察ES端同名IO。
 wire gmii_tx_b_en=scenario.es.gmii_tx_b_en;
 // gmii_tx_b_er：直接观察ES端同名IO。
 wire gmii_tx_b_er=scenario.es.gmii_tx_b_er;
 // gmii_rx_a_rxd：直接观察ES端同名IO。
 wire [7:0] gmii_rx_a_rxd=scenario.es.gmii_rx_a_rxd;
 // gmii_rx_a_dv：直接观察ES端同名IO。
 wire gmii_rx_a_dv=scenario.es.gmii_rx_a_dv;
 // gmii_rx_a_er：直接观察ES端同名IO。
 wire gmii_rx_a_er=scenario.es.gmii_rx_a_er;
 // gmii_rx_b_rxd：直接观察ES端同名IO。
 wire [7:0] gmii_rx_b_rxd=scenario.es.gmii_rx_b_rxd;
 // gmii_rx_b_dv：直接观察ES端同名IO。
 wire gmii_rx_b_dv=scenario.es.gmii_rx_b_dv;
 // gmii_rx_b_er：直接观察ES端同名IO。
 wire gmii_rx_b_er=scenario.es.gmii_rx_b_er;
 afdx_single_file_case #(.FILE_NAME("text.txt"),.HEADER_NAME(256'h48554c2e74786574),.DATA_NAME(256'h7478742e74786574)) scenario();
endmodule
