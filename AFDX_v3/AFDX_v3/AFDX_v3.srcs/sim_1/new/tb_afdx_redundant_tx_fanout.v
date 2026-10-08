`timescale 1ns/1ps
module tb_afdx_redundant_tx_fanout;
reg clk=0,rst=0;always #5 clk=~clk;
reg valid=0,last=0,ar=1,br=0;
reg [7:0] data=0;wire ready,av,al,bv,bl;wire [7:0] a,b;
afdx_redundant_tx_fanout #(.MAX_FRAME_BYTES(16),.POINTER_WIDTH(5),.BAG_CYCLES(50)) dut(
 .sys_clk(clk),.sys_rst_n(rst),
 .in_data(data),.in_valid(valid),.in_last(last),.in_ready(ready),
 .a_data(a),.a_valid(av),.a_last(al),.a_ready(ar),
 .b_data(b),.b_valid(bv),.b_last(bl),.b_ready(br));
reg [7:0] ea[0:2047],eb[0:2047];reg ela[0:2047],elb[0:2047];
integer wa=0,wb=0,ra=0,rb=0,ac=0,bc=0,cycle=0;
integer a_start=-10000,b_start=-10000;
reg astall=0,bstall=0;reg [8:0] ahold,bhold;
always @(posedge clk)begin
 cycle=cycle+1;
 if(!rst)begin astall=0;bstall=0;end
 else begin
  if(astall&&(!av||{al,a}!==ahold))$fatal(1,"A hold");
  if(bstall&&(!bv||{bl,b}!==bhold))$fatal(1,"B hold");
  astall=av&&!ar;bstall=bv&&!br;ahold={al,a};bhold={bl,b};
  if(av&&ar)begin
   if(dut.a_pointer==0)begin if(cycle-a_start<50)$fatal(1,"A actual BAG shortened");a_start=cycle;end
   if(ra>=wa||a!==ea[ra]||al!==ela[ra])$fatal(1,"A byte repeated/lost at %0d",ra);
   ra=ra+1;if(al)ac=ac+1;
  end
  if(bv&&br)begin
   if(dut.b_pointer==0)begin if(cycle-b_start<50)$fatal(1,"B actual BAG shortened");b_start=cycle;end
   if(rb>=wb||b!==eb[rb]||bl!==elb[rb])$fatal(1,"B byte repeated/lost at %0d",rb);
   rb=rb+1;if(bl)bc=bc+1;
  end
 end
end
task automatic frame(input integer seed,input integer len,input integer target_a,input integer target_b);
 integer k;begin
  for(k=0;k<len;k=k+1)begin
   if(target_a)begin ea[wa]=seed+k;ela[wa]=(k==len-1);wa=wa+1;end
   if(target_b)begin eb[wb]=seed+k;elb[wb]=(k==len-1);wb=wb+1;end
  end
  for(k=0;k<len;k=k+1)begin
   @(negedge clk);data=seed+k;valid=1;last=(k==len-1);
   @(posedge clk);while(!ready)@(posedge clk);
  end
  @(negedge clk);valid=0;last=0;
 end
endtask
task drain;begin wait(ra==wa&&rb==wb);repeat(4)@(negedge clk);end endtask
integer n;
reg random_ready=0;
always @(negedge clk)if(random_ready)begin
 ar=((cycle*7)%11)<7;br=((cycle*5)%13)<5;
end
initial begin
 repeat(3)@(negedge clk);rst=1;
 frame('h10,8,1,1);wait(ac==1);repeat(20)@(negedge clk);
 if(ra!=8||rb!=0||ready)$fatal(1,"fast A was repeated or slow B overwritten");
 br=1;drain;
 // Reverse the slow/fast roles; both copies remain pending until accepted.
 ar=0;br=1;frame('h30,3,1,1);wait(rb==wb);repeat(20)@(negedge clk);
 if(ra==wa||ready)$fatal(1,"slow A was overwritten");
 ar=1;drain;
 frame('h40,1,1,1);drain;
 // Pause B in the middle of its copy and resume at the exact byte.
 fork frame('h50,6,1,1);begin wait(dut.b_pointer==2);@(negedge clk);br=0;end join
 wait(ra==wa);repeat(20)@(negedge clk);if(rb==wb||ready)$fatal(1,"B partial not retained");
 br=1;drain;
 ar=0;br=0;frame('h58,4,1,1);wait(av&&bv);repeat(20)@(negedge clk);
 if(ready)$fatal(1,"both stalled buffer reused");ar=1;br=1;drain;
 random_ready=1;
 for(n=0;n<60;n=n+1)frame(n*9,(n%16)+1,1,1);
 drain;random_ready=0;ar=1;br=1;
 // Oversize guard drains to last and preserves the next legal frame.
 frame('h80,17,0,0);drain;frame('h90,16,1,1);drain;
 $display("REDUNDANT TX FANOUT PASSED: A=%0d B=%0d independent complete copies",ac,bc);$finish;
end
initial begin #200000;$fatal(1,"TIMEOUT fanout");end
endmodule
