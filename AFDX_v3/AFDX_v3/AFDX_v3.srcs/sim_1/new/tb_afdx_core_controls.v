`timescale 1ns/1ps
module tb_afdx_core_controls;
reg clk=0,rst=0; always #5 clk=~clk;
reg we=0,re=0; reg [10:0] din=0;
wire [10:0] dout; wire full,empty; wire [2:0] count;
frame_descriptor_fifo fifo(clk,rst,we,din,re,dout,full,empty,count);
reg available=0,start=0,busy=0; wire grant;
bag_timer #(.BAG_CYCLES(8)) timer(clk,rst,available,start,busy,grant);
reg done=0; wire [7:0] sn; sequence_counter seq(clk,rst,done,sn);
task step; begin @(posedge clk); #1; @(negedge clk); end endtask
task push; input [10:0] value; begin din=value;we=1;step;we=0;end endtask
integer n;
initial begin
 repeat(3)step;rst=1;step;
 if(!empty||sn!==1)$fatal(1,"reset state");
 re=1;step;re=0;if(count!==0)$fatal(1,"empty underflow");
 for(n=1;n<=4;n=n+1)push(n);
 if(!full||count!==4||dout!==1)$fatal(1,"fill/order");
 push(99);if(count!==4||dout!==1)$fatal(1,"full protection");
 re=1;we=1;din=5;step;we=0;re=0;
 if(count!==4||dout!==2)$fatal(1,"full simultaneous pop/push");
 for(n=2;n<=5;n=n+1)begin if(dout!==n)$fatal(1,"FIFO order");re=1;step;re=0;end
 if(!empty)$fatal(1,"drain");
 available=1;step;if(!grant)$fatal(1,"first BAG grant");
 busy=1;start=1;step;start=0;busy=0;
 repeat(7)begin if(grant)$fatal(1,"early BAG grant");step;end
 step;if(!grant)$fatal(1,"BAG expiry");available=0;step;
 done=1;repeat(254)step;if(sn!==255)$fatal(1,"sequence 255");
 step;if(sn!==1)$fatal(1,"sequence wrap");done=0;step;if(sn!==1)$fatal(1,"sequence hold");
 $display("CORE CONTROLS PASSED");$finish;
end
initial begin #100000;$fatal(1,"TIMEOUT core controls");end
endmodule
