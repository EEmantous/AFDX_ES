`timescale 1ns/1ps
// 读取一个BER字段的类型、正文长度和位置。
module snmp_ber_reader (
    input wire clk, reset_n, start,
    input wire [10:0] start_addr, limit_addr,
    output  reg [10:0] read_addr,
    input wire [7:0] read_data,
    output  reg done, valid,
    output  reg [7:0] tag,
    output  reg [10:0] value_addr, value_length, end_addr
);
 // state: 等待、类型、长度、长长度及完成阶段。
 reg [2:0] state;
 // remaining: BER长长度字段还需读取的字节数。
 reg [6:0] remaining;
 // accumulator: 当前字段正文长度。
 reg [10:0] accumulator;
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin
   state<=0;done<=0;valid<=0;read_addr<=0;remaining<=0;accumulator<=0;
   tag<=0;value_addr<=0;value_length<=0;end_addr<=0;
  end else begin
   done<=0;
   case(state)
    0:if(start)begin read_addr<=start_addr;state<=1;end
    1:begin tag<=read_data;read_addr<=read_addr+1'b1;state<=2;end
    2:begin
     if(!read_data[7])begin
      value_addr<=read_addr+1'b1;value_length<=read_data;
      end_addr<=read_addr+1'b1+read_data;state<=4;
     end else begin remaining<=read_data[6:0];accumulator<=0;read_addr<=read_addr+1'b1;state<=3;end
    end
    3:begin
     accumulator<={accumulator[2:0],read_data};
     read_addr<=read_addr+1'b1;remaining<=remaining-1'b1;
     if(remaining==1)begin
      value_addr<=read_addr+1'b1;value_length<={accumulator[2:0],read_data};
      end_addr<=read_addr+1'b1+{accumulator[2:0],read_data};state<=4;
     end
    end
    4:begin done<=1;valid<=1;state<=0;end
   endcase
  end
 end
endmodule
