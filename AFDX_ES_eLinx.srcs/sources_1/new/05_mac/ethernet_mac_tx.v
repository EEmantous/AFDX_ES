`timescale 1ns/1ps
// 连续发出前导码、核心字节和FCS。
module ethernet_mac_tx #(
 parameter integer MAX_CORE_BYTES=1578,MIN_CORE_BYTES=60, // MAX_CORE_BYTES: 不含前导码和FCS的核心帧容量，覆盖标准最大帧及要求的1578字节。
 parameter integer BAG_CYCLES=125000,IFG_BYTES=12,INPUT_TIMEOUT=125000
)(
 input wire clk,reset,
 input wire [7:0] in_data,input wire in_valid,in_last,output wire in_ready,
 output wire [7:0] gmii_txd,output wire gmii_tx_en,gmii_tx_er,
 output /* drop_event：对应错误/拒绝/溢出/丢弃事件指示。 */ wire drop_event,output /* frame_count：累计成功发出的物理帧数。 */ reg [31:0] frame_count,
 output wire [11:0] saved_length
);
 assign drop_event=0;
 localparam CAPTURE=0,WAIT_BAG=1,PREAMBLE=2,BODY=3,FCS=4,GAP=5;
 /* state：当前步骤。 */ reg [2:0] state;
 /* count：核心帧采集位置、保存长度及输出位置；length：核心帧采集位置、保存长度及输出位置；index：当前字节或表项位置。 */ reg [10:0] count,length,index;
 /* pre_index：当前前导码字节位置。 */ reg [2:0] pre_index;/* fcs_index：4字节FCS位置。 */ reg [1:0] fcs_index;
 /* crc：采集核心帧时的CRC32未取反累加状态；fcs：CRC的反码，直接用于发送；gap_count：FCS完成后的IFG剩余周期。 */ reg [31:0] crc;
 reg [3:0] gap_count; // gap_count: 帧间隔还需等待的字节周期。
 wire [31:0] fcs=~crc; // fcs: 当前帧CRC的取反值，直接用于发送。
 wire [31:0] crc_next;
 ethernet_crc32 checksum(.current(crc),.data(in_data),.next(crc_next));
 assign in_ready=!reset && state==CAPTURE;
 assign gmii_tx_en=!reset && (state==PREAMBLE || state==BODY || state==FCS);
 assign gmii_tx_er=1'b0;
 // ADDRESS_WIDTH: 核心帧缓存的地址位数。
 localparam ADDRESS_WIDTH=$clog2(MAX_CORE_BYTES);
 // write_address/read_address: 当前采集位置和下一拍发送位置。
 wire [ADDRESS_WIDTH-1:0] write_address=count;
 wire [ADDRESS_WIDTH-1:0] read_address=state==BODY ? index+1'b1 : 0;
 // frame_byte: 块RAM同步读出的核心帧字节。
 wire [7:0] frame_byte;
 afdx_byte_ram #(.WORDS(MAX_CORE_BYTES),.ADDRESS_WIDTH(ADDRESS_WIDTH)) memory(
  .clk(clk),.write_enable(in_valid && in_ready),.write_address(write_address),.write_data(in_data),
  .read_enable(1'b1),.read_address(read_address),.read_data(frame_byte));
 assign gmii_txd=state==PREAMBLE ? (pre_index==7 ? 8'hd5 : 8'h55) :
                 state==BODY ? frame_byte : state==FCS ? fcs[8*fcs_index+:8] : 8'd0;
 assign saved_length=length;
 always @(posedge clk or posedge reset)begin
  if(reset)begin
   state<=CAPTURE;count<=0;length<=0;index<=0;pre_index<=0;fcs_index<=0;
   crc<=32'hffffffff;gap_count<=0;
   frame_count<=0;
  end else begin
   
   case(state)
    CAPTURE:begin
     if(in_valid && in_ready)begin
      crc<=crc_next;
      if(in_last)begin count<=0;length<=count+1'b1;pre_index<=0;state<=PREAMBLE;end
      else count<=count+1'b1;
     end
    end
    PREAMBLE:begin
     if(pre_index==7)begin index<=0;state<=BODY;end
     else pre_index<=pre_index+1'b1;
    end
    BODY:if(index==length-1'b1)begin fcs_index<=0;state<=FCS;end
         else index<=index+1'b1;
    FCS:if(fcs_index==3)begin
          frame_count<=frame_count+1'b1;gap_count<=IFG_BYTES<12 ? 12 : IFG_BYTES;state<=GAP;
        end else fcs_index<=fcs_index+1'b1;
    GAP:if(gap_count<=1)begin gap_count<=0;crc<=32'hffffffff;state<=CAPTURE;end
        else gap_count<=gap_count-1'b1;
    default:state<=CAPTURE;
   endcase
  end
 end
endmodule
