`timescale 1ns/1ps
// 计算一个字节加入后的以太网CRC32。
module ethernet_crc32(
 input wire [31:0] current,input wire [7:0] data,output /* next：当前CRC与输入字节按EDB88320进行8轮更新后的组合结果。 */ reg [31:0] next
);
 /* i：当前通道或表项位置。 */ integer i;
 always @*begin
  next=current;
  for(i=0;i<8;i=i+1)
   next=(next[0]^data[i]) ? (next>>1)^32'hedb88320 : next>>1;
 end
endmodule
