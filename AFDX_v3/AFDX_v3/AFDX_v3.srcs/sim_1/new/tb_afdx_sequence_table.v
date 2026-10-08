`timescale 1ns/1ps
module tb_afdx_sequence_table;
reg clk=0,rst=0;always #5 clk=~clk;
reg start=0;reg [15:0] vl=0;reg [7:0] sn=0;
wire ready,busy,done,passed,error,duplicate;
afdx_rx_sequence_table #(.VL_INDEX_WIDTH(2)) dut(clk,rst,start,vl,sn,ready,busy,done,passed,error,duplicate);
task check;
input [15:0] id; input [7:0] number;input pass_expected,error_expected,dup_expected;
begin
 @(negedge clk);if(!ready||busy)$fatal(1,"not ready");vl=id;sn=number;start=1;
 @(negedge clk);start=0;wait(done);#1;
 if({passed,error,duplicate}!=={pass_expected,error_expected,dup_expected})$fatal(1,"sequence id=%h sn=%d got=%b%b%b",id,number,passed,error,duplicate);
 @(negedge clk);
end endtask
initial begin
 repeat(3)@(negedge clk);rst=1;if(ready)$fatal(1,"initialization barrier");wait(ready);
 check(16'h101,1,1,0,0);check(16'h101,1,0,0,1);check(16'h101,2,1,0,0);
 check(16'h101,0,0,1,0);check(16'h101,3,1,0,0);
 check(16'h102,255,1,0,0);check(16'h102,1,1,0,0);
 check(16'h101,7,1,1,0);check(16'h101,8,1,0,0);
 // A colliding tag replaces the direct-map entry; record the existing contract.
 check(16'h105,8,1,0,0);check(16'h101,8,1,0,0);
 $display("SEQUENCE TABLE PASSED");$finish;
end
initial begin #10000;$fatal(1,"TIMEOUT sequence");end
endmodule
