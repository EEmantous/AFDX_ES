`timescale 1ns/1ps
module tb_afdx_ab_selector;
reg clk=0,rst=0; always #5 clk=~clk;
reg [7:0] a=0,b=0,asn=1,bsn=1;
reg [15:0] avl=0,bvl=0;
reg av=0,bv=0,al=0,bl=0,ready=1;
wire ar,br; wire [7:0] data; wire valid,last;
afdx_ab_frame_selector #(.MAX_FRAME_BYTES(32),.POINTER_WIDTH(6),.DEDUP_WINDOW_CYCLES(80),.HISTORY_DEPTH(4)) dut(
 .sys_clk(clk),.sys_rst_n(rst),.a_data(a),.a_valid(av),.a_last(al),.a_ready(ar),
 .b_data(b),.b_valid(bv),.b_last(bl),.b_ready(br),.out_data(data),.out_valid(valid),.out_last(last),.out_ready(ready),
 .a_vl_id(avl),.a_sequence_number(asn),.b_vl_id(bvl),.b_sequence_number(bsn));
reg [7:0] expected_data [0:8191];
reg expected_last [0:8191];
integer written=0,read_count=0,deliveries=0,phase=0;
reg stalled=0; reg [7:0] held_data; reg held_last;
always @(posedge clk) begin
 if(!rst) stalled=0;
 else begin
  if(stalled && (!valid || data!==held_data || last!==held_last))
   $fatal(1,"APP hold violation phase=%0d",phase);
  stalled=valid&&!ready; held_data=data; held_last=last;
  if(valid&&ready) begin
   if(read_count>=written || data!==expected_data[read_count] || last!==expected_last[read_count])
    $fatal(1,"merge scoreboard phase=%0d byte=%0d got=%h last=%b expected=%h last=%b",phase,read_count,data,last,expected_data[read_count],expected_last[read_count]);
   read_count=read_count+1; if(last)deliveries=deliveries+1;
  end
 end
end
task automatic expect_frame(input integer seed,input integer len);
 integer k; begin for(k=0;k<len;k=k+1)begin
  expected_data[written]=seed+k; expected_last[written]=(k==len-1); written=written+1;
 end end
endtask
task automatic send(input integer plane,input [15:0] vl,input [7:0] sn,input integer seed,input integer len);
 integer k; begin
  for(k=0;k<len;k=k+1) begin
   @(negedge clk);
   if(plane==0)begin a=seed+k;av=1;al=(k==len-1);avl=vl;asn=sn;end
   else begin b=seed+k;bv=1;bl=(k==len-1);bvl=vl;bsn=sn;end
   @(posedge clk); while(plane==0 ? !ar : !br) @(posedge clk);
  end
  @(negedge clk); if(plane==0)begin av=0;al=0;end else begin bv=0;bl=0;end
 end
endtask
task drain;
 begin wait(read_count==written);repeat(5)@(negedge clk);end
endtask
task reset_history;
 begin @(negedge clk);rst=0;repeat(2)@(negedge clk);rst=1;end
endtask
integer n,base;
initial begin
 repeat(3)@(negedge clk);rst=1;
 phase=1; expect_frame('h10,2);
 fork send(0,16'h0101,1,'h10,2);send(1,16'h0101,1,'h80,2);join drain;
 phase=2; expect_frame('h20,1);expect_frame('h30,2);ready=0;
 send(0,16'h0102,1,'h20,1); wait(valid);
 send(1,16'h0202,1,'h30,2);repeat(5)@(negedge clk);ready=1;drain;
 phase=3;expect_frame('h40,3);send(1,16'h0103,1,'h40,3);drain;
 send(0,16'h0103,1,'h40,3);repeat(6)@(negedge clk);
 phase=4;reset_history;expect_frame('h50,2);
 send(0,16'h0104,1,'h50,2);drain;expect_frame('h60,2);send(0,16'h0104,2,'h60,2);drain;
 send(1,16'h0104,1,'h50,2);repeat(6)@(negedge clk);
 phase=5;expect_frame('h70,2);ready=0;send(0,16'h0105,1,'h70,2);wait(valid);
 repeat(100)@(negedge clk);send(1,16'h0105,1,'h70,2);repeat(5)@(negedge clk);ready=1;drain;
 phase=6;repeat(90)@(negedge clk);expect_frame('h90,2);send(1,16'h0105,1,'h90,2);drain;
 phase=7;reset_history;
 for(n=1;n<=4;n=n+1)begin expect_frame(n*10,1);send(0,16'h0106,n,n*10,1);drain;end
 base=read_count;expect_frame('hA0,1);send(1,16'h0107,1,'hA0,1);
 repeat(5)@(negedge clk);if(read_count!=base)$fatal(1,"live history evicted early");drain;
 phase=8;reset_history;
 for(n=1;n<=260;n=n+1)begin
  expect_frame(n,1);
  fork send(0,16'h0108,((n-1)%255)+1,n,1);send(1,16'h0108,((n-1)%255)+1,n,1);join
  drain;
 end
 // A starts first but B completes first: choose B for the whole frame.
 phase=9;reset_history;expect_frame('hB8,3);
 @(negedge clk);a='hB0;av=1;al=0;avl='h0109;asn=1;
 @(negedge clk);a='hB1;@(negedge clk);av=0;
 send(1,16'h0109,1,'hB8,3);drain;
 @(negedge clk);a='hB2;av=1;al=1;
 @(posedge clk);while(!ar)@(posedge clk);
 @(negedge clk);av=0;al=0;repeat(12)@(negedge clk);
 // Drain oversized captures and recover for a legal next frame.
 send(0,16'h0110,1,'hC0,33);repeat(5)@(negedge clk);
 expect_frame('hD0,2);send(0,16'h0110,2,'hD0,2);drain;
 phase=10;reset_history;
 force dut.cycle_count=32'hFFFFFFF8;@(negedge clk);release dut.cycle_count;
 expect_frame('hE0,2);send(0,16'h0111,1,'hE0,2);drain;
 send(1,16'h0111,1,'hE0,2);repeat(10)@(negedge clk);
 // SN0 is rejected by the merge even if an upstream caller violates RX policy.
 send(1,16'h0108,0,'hFF,1);repeat(10)@(negedge clk);
 if(read_count!=written)$fatal(1,"missing merged payload");
 $display("AB SELECTOR PASSED: %0d unique frames, tie/B-first/delay/VL/hold/window/full/wrap",deliveries);$finish;
end
initial begin #1000000;$fatal(1,"TIMEOUT selector phase=%0d bytes=%0d/%0d a_full=%b b_full=%b active=%b candidates=%b sn=%0d duplicate=%b free=%0d",phase,read_count,written,dut.a_full,dut.b_full,dut.output_active,dut.candidate_valid,dut.candidate_sn,dut.search_reject,dut.free_valid);end
endmodule
