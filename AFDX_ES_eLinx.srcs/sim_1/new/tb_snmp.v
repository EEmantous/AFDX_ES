`timescale 1ns/1ps
// Public APP/GMII integration. No force/deposit or fabricated loading events.
module tb_afdx_es_snmp_v2;
 // 顶层同名IO仅用于观察，使eLinx生成的add wave *能直接找到完整端口。
 // tx_data：直接观察ES端同名IO。
 wire [7:0] tx_data=es.tx_data;
 // rx_data：直接观察ES端同名IO。
 wire [7:0] rx_data=es.rx_data;
 // tx_valid：直接观察ES端同名IO。
 wire tx_valid=es.tx_valid;
 // rx_valid：直接观察ES端同名IO。
 wire rx_valid=es.rx_valid;
 // tx_ready：直接观察ES端同名IO。
 wire tx_ready=es.tx_ready;
 // rx_ready：直接观察ES端同名IO。
 wire rx_ready=es.rx_ready;
 // gmii_tx_a_txd：直接观察ES端同名IO。
 wire [7:0] gmii_tx_a_txd=es.gmii_tx_a_txd;
 // gmii_tx_a_en：直接观察ES端同名IO。
 wire gmii_tx_a_en=es.gmii_tx_a_en;
 // gmii_tx_a_er：直接观察ES端同名IO。
 wire gmii_tx_a_er=es.gmii_tx_a_er;
 // gmii_tx_b_txd：直接观察ES端同名IO。
 wire [7:0] gmii_tx_b_txd=es.gmii_tx_b_txd;
 // gmii_tx_b_en：直接观察ES端同名IO。
 wire gmii_tx_b_en=es.gmii_tx_b_en;
 // gmii_tx_b_er：直接观察ES端同名IO。
 wire gmii_tx_b_er=es.gmii_tx_b_er;
 // gmii_rx_a_rxd：直接观察ES端同名IO。
 wire [7:0] gmii_rx_a_rxd=es.gmii_rx_a_rxd;
 // gmii_rx_a_dv：直接观察ES端同名IO。
 wire gmii_rx_a_dv=es.gmii_rx_a_dv;
 // gmii_rx_a_er：直接观察ES端同名IO。
 wire gmii_rx_a_er=es.gmii_rx_a_er;
 // gmii_rx_b_rxd：直接观察ES端同名IO。
 wire [7:0] gmii_rx_b_rxd=es.gmii_rx_b_rxd;
 // gmii_rx_b_dv：直接观察ES端同名IO。
 wire gmii_rx_b_dv=es.gmii_rx_b_dv;
 // gmii_rx_b_er：直接观察ES端同名IO。
 wire gmii_rx_b_er=es.gmii_rx_b_er;
 /* clk：20ns周期时钟；reset：高有效复位。 */ reg clk=0,reset=1;wire rx_a_clk=clk,rx_b_clk=clk;
 always #10 clk=~clk;
 tb_app_file_driver #(.CAPACITY(2048),.FILES(1)) host(.clk(clk),.reset(reset),
  .data(es.rx_data),.valid(es.rx_valid),.ready(es.tx_ready),
  .reply_data(es.tx_data),.reply_valid(es.tx_valid),.reply_ready(es.rx_ready));
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
  reg [7:0] gmii_rx_a_rxd=0;
  // gmii_rx_a_dv：A网接收有效。
  reg gmii_rx_a_dv=0;
  // gmii_rx_a_er：A网接收错误。
  wire gmii_rx_a_er;
  assign gmii_rx_a_er=1'b0;
  // gmii_rx_b_rxd：B网接收字节。
  reg [7:0] gmii_rx_b_rxd=0;
  // gmii_rx_b_dv：B网接收有效。
  reg gmii_rx_b_dv=0;
  // gmii_rx_b_er：B网接收错误。
  wire gmii_rx_b_er;
  assign gmii_rx_b_er=1'b0;
  afdx_test_es #(.LOADER(1),.VL_COUNT(1),.RX_VL_COUNT(1),.MAP_ENTRIES(1),.MAX_FILE_BYTES(2048),.FILE_IDS(32'd1),.FILE_VLS(8'd0),
  .TX_VL_IDS(16'd1),.RX_VL_IDS(16'd3),.VL_BAG_CYCLES(32'd2000),.SNMP_BAG_CYCLES(3000),
  .SNMP_TARGET_IP(32'hc0a80010),.SNMP_CONTROL(32'h303),.SNMP_WINDOW_CYCLES(1000),.SNMP_COOLDOWN_CYCLES(12500000),.SNMP_RETRY_THRESHOLD(2),
  .RETRY_CYCLES(4000),.OP_TIMEOUT(30000),.DALLY_CYCLES(8000),.STATUS_INTERVAL(6000)) dut(
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
 // frame: 一个含物理前导码和FCS的GET请求，第0项是字节数。
 reg [31:0] frame[0:2047];
 // vector_dir/path: 测试报文目录和当前请求路径。
 reg [8191:0] vector_dir,path;
 // fd/starts: 实际发送帧及起始时间文件。
 integer fd,starts;
 // index/responses/traps/cycles/start_cycle: 帧字节位置、回复数、Trap数、周期数和起帧周期。
 integer index=0,responses=0,traps=0,cycles=0,start_cycle;
 // previous_en/vl_hi/vl: 上拍有效位与当前帧VL编号。
 reg previous_en=0;
 /* vl_hi：当前帧VL高字节。 */ reg [7:0] vl_hi;
 /* vl：当前帧的VL编号。 */ reg [15:0] vl;
 // result: APP返回的真实615A失败结果。
 reg [63:0] result;
 // n: 发送测试文件时的字节位置。
 integer n;
 always @(posedge clk)if(!reset)begin
  cycles=cycles+1;
  if(es.gmii_tx_a_en)begin
   if(!previous_en)begin index=0;start_cycle=cycles;end
   $fwrite(fd,"%02h",es.gmii_tx_a_txd);
   if(index==12)vl_hi=es.gmii_tx_a_txd;
   if(index==13)vl={vl_hi,es.gmii_tx_a_txd};
   index=index+1;
  end else if(previous_en)begin
   $fwrite(fd,"\n");$fdisplay(starts,"%0d,%0d",start_cycle,vl);
   if(vl==16'h0103)responses=responses+1;
   if(vl==16'h0104)traps=traps+1;
  end
  previous_en=es.gmii_tx_a_en;
 end
 task inject;
  /* byte_index：GET请求字节位置。 */ integer byte_index; // byte_index: 请求帧中的物理字节位置。
  begin
   for(byte_index=0;byte_index<frame[0];byte_index=byte_index+1)begin
    @(negedge clk);es.gmii_rx_a_dv=1;es.gmii_rx_a_rxd=frame[byte_index+1][7:0];
   end
   @(negedge clk);es.gmii_rx_a_dv=0;
  end
 endtask
 initial begin
  fd=$fopen("snmp_frames.hex","w");starts=$fopen("snmp_starts.csv","w");
  if(!$value$plusargs("ES_VECTORS=%s",vector_dir))vector_dir="../../../files/snmp"; // eLinx的sim_1/behav工作目录。
  repeat(8)@(negedge clk);reset=0;
  $sformat(path,"%0s/request1.hex",vector_dir);$readmemh(path,frame);inject;
  wait(responses==1);
  host.directory_begin(2,1,32'h0a000063);
  host.directory_entry(7,32,16,0,0,256'h48554c2e3174786574,256'h7478742e3174786574,256'h31302d4e50);
  for(n=0;n<32;n=n+1)host.send_byte(n);
  for(n=0;n<16;n=n+1)host.send_byte(n+128);
  host.directory_end(0);host.result_get(result);
  if(!result[56])$fatal(1,"Expected 615A failure from unreachable peer");
  repeat(20000)@(negedge clk);
  $sformat(path,"%0s/request2.hex",vector_dir);$readmemh(path,frame);inject;
  wait(responses==2);repeat(20)@(negedge clk);
  if(traps==0)$fatal(1,"No real loading Trap");
  $fclose(fd);$fclose(starts);
  $display("SNMP TEST PASSED GET=%0d Trap=%0d end_ns=%0t",responses,traps,$time);$finish;
 end
 initial begin #15000000;$fatal(1,"SNMP test timeout");end
endmodule
