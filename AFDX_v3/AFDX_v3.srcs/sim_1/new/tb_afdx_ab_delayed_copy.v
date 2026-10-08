`timescale 1ns/1ps
// Requirement test: two identical replicas arriving at different times must
// deliver only one frame. This is now a required normal-regression test.
module tb_afdx_ab_delayed_copy;
reg clk=0,rst=0;always #5 clk=~clk;
reg [7:0] a=0,b=0;reg av=0,bv=0,al=0,bl=0;wire ar,br;
wire [7:0] data;wire valid,last;
afdx_ab_frame_selector dut(
 .sys_clk(clk),.sys_rst_n(rst),.a_data(a),.a_valid(av),.a_last(al),.a_ready(ar),
 .b_data(b),.b_valid(bv),.b_last(bl),.b_ready(br),
 .out_data(data),.out_valid(valid),.out_last(last),.out_ready(1'b1),
 .a_vl_id(16'h0101),.a_sequence_number(8'd1),
 .b_vl_id(16'h0101),.b_sequence_number(8'd1));
integer deliveries=0;
always @(posedge clk)if(rst&&valid&&last)deliveries=deliveries+1;
initial begin
 repeat(3)@(negedge clk);rst=1;
 a=8'h41;av=1;@(negedge clk);a=8'h42;al=1;
 @(negedge clk);av=0;al=0;wait(deliveries==1);repeat(5)@(negedge clk);
 b=8'h41;bv=1;@(negedge clk);b=8'h42;bl=1;
 @(negedge clk);bv=0;bl=0;repeat(200)@(negedge clk);
 if(deliveries!=1)$fatal(1,"delayed redundant replica delivered twice: deliveries=%0d",deliveries);
 $display("AB DELAYED COPY PASSED");$finish;
end
initial begin #10000;$fatal(1,"TIMEOUT delayed copy");end
endmodule
