`timescale 1ns/1ps
// 缓存物理帧；通过FCS识别A网损坏后再交付。
module ethernet_mac_rx #(
 parameter integer MAX_CORE_BYTES=1578,MIN_CORE_BYTES=60 // MAX_CORE_BYTES: 不含前导码和FCS的核心帧容量，接收RAM另保存4字节FCS。
)(
 input wire rx_clk,clk,reset,
 input wire [7:0] gmii_rxd,input wire gmii_rx_dv,gmii_rx_er,
 output wire [7:0] out_data,output wire out_valid,out_last,input wire out_ready,
 output wire [31:0] good_frames,drop_frames,
 output wire [11:0] saved_length
);
 // previous_dv: 上拍物理有效位，用于识别帧结束。
 reg previous_dv;
 // preamble: 前导码和SFD已接收的字节数。
 reg [3:0] preamble;
 // received: 核心字节和FCS已接收的数量。
 reg [10:0] received;
 // length/pointer: 已完成帧的核心长度和当前输出位置。
 reg [10:0] length,pointer;
 // active: 已完成帧正在等待下游读出。
 reg active;
 // discard: 接收开始时槽仍被占用，当前输入帧不写入。
 reg discard;
 // bad: 当前帧出现物理错误标志。
 reg bad;
 // crc: 帧字节与FCS的CRC累加值。
 reg [31:0] crc;
 // good/drop: SNMP读取的有效帧及丢帧数量。
 reg [31:0] good,drop;
 // next_crc: 当前物理字节加入后的CRC值。
 wire [31:0] next_crc;
 ethernet_crc32 checksum(.current(crc),.data(gmii_rxd),.next(next_crc));
 assign good_frames=good;
 assign drop_frames=drop;
 assign saved_length={1'b0,length};
 assign out_valid=!reset && active;
 assign out_last=out_valid && pointer==length-1'b1;
 // ADDRESS_WIDTH: 包含FCS的物理帧缓存地址位数。
 localparam ADDRESS_WIDTH=$clog2(MAX_CORE_BYTES+4);
 // write_address/read_address: 当前接收位置和下一拍需要交付的位置。
 wire [ADDRESS_WIDTH-1:0] write_address=received;
 wire [ADDRESS_WIDTH-1:0] read_address=pointer+((out_valid && out_ready && !out_last) ? 1'b1 : 1'b0);
 afdx_byte_ram #(.WORDS(MAX_CORE_BYTES+4),.ADDRESS_WIDTH(ADDRESS_WIDTH)) memory(
  .clk(clk),.write_enable(!reset && gmii_rx_dv && previous_dv && preamble==8 && !discard),
  .write_address(write_address),.write_data(gmii_rxd),.read_enable(1'b1),.read_address(read_address),.read_data(out_data));
 always @(posedge clk or posedge reset)begin
  if(reset)begin
   previous_dv<=0;preamble<=0;received<=0;length<=0;pointer<=0;
   active<=0;discard<=0;bad<=0;crc<=32'hffffffff;good<=0;drop<=0;
  end else begin
   previous_dv<=gmii_rx_dv;
   if(gmii_rx_dv)begin
    if(!previous_dv)begin
     preamble<=1;received<=0;crc<=32'hffffffff;discard<=active;bad<=gmii_rx_er;
    end else begin
     bad<=bad || gmii_rx_er;
     if(preamble<8)preamble<=preamble+1'b1;
     else begin received<=received+1'b1;crc<=next_crc;end
    end
   end else if(previous_dv)begin
    if(!discard && !bad && crc==32'hdebb20e3)begin
     length<=received-4;pointer<=0;active<=1;good<=good+1'b1;
    end else drop<=drop+1'b1;
   end
   if(out_valid && out_ready)begin
    if(out_last)begin active<=0;pointer<=0;end
    else pointer<=pointer+1'b1;
   end
  end
 end
endmodule

