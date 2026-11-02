`timescale 1ns/1ps
// 本地电子时钟：秒数与秒内纳秒。
module afdx_rtc #(
 parameter integer CLOCK_HZ=12500000, // CLOCK_HZ: 每秒输入时钟周期数。
 parameter [31:0] INITIAL_SECONDS=0 // INITIAL_SECONDS: 复位后的起始秒数。
)(input wire clk,reset,output wire [63:0] timestamp); // clk: 时钟；reset: 复位；timestamp: 秒与秒内纳秒。
 localparam NS_BASE=1000000000/CLOCK_HZ,NS_REM=1000000000%CLOCK_HZ;
 // seconds/nanoseconds: 当前秒数及秒内纳秒。
 reg [31:0] seconds;
 reg [29:0] nanoseconds;
 // extra: 非整数纳秒周期累积够一个纳秒时加1。
 wire extra;
 generate if(NS_REM==0)begin: integer_tick
  assign extra=0;
 end else begin: fractional_tick
  localparam WIDTH=$clog2(CLOCK_HZ);
  reg [WIDTH-1:0] phase; // phase: 尚未累计到一个纳秒的余数。
  wire [WIDTH:0] advanced=phase+NS_REM; // advanced: 本拍加入时钟余数后的值。
  assign extra=advanced>=CLOCK_HZ;
  always @(posedge clk)if(reset)phase<=0;else phase<=extra ? advanced-CLOCK_HZ : advanced;
 end endgenerate
 wire [30:0] advanced_ns=nanoseconds+NS_BASE+extra; // advanced_ns: 本拍推进后的纳秒数。
 assign timestamp={seconds,2'b0,nanoseconds};
 always @(posedge clk)begin
  if(reset)begin seconds<=INITIAL_SECONDS;nanoseconds<=0;end
  else begin
   nanoseconds<=advanced_ns>=1000000000 ? advanced_ns-1000000000 : advanced_ns;
   if(advanced_ns>=1000000000)seconds<=seconds+1'b1;
  end
 end
endmodule
