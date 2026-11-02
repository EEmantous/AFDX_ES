`timescale 1ns/1ps
// 生成IPv4/UDP头、填充和AFDX序号。
module afdx_udp_tx #(
    parameter integer MAX_PAYLOAD=1471, // MAX_PAYLOAD: AFDX必须支持的UDP正文最大字节数，不随TFTP分块缩小。
    parameter integer INPUT_TIMEOUT=12500,
    parameter [47:0] SRC_MAC=48'h020000000001,
    parameter [47:0] DEST_MAC=48'h030000000101,
    parameter [31:0] LOCAL_IP=32'hc0a80001
)(
    input wire clk,reset,
    input wire [7:0] in_data,input wire in_valid,in_last,output wire in_ready,
    input wire [31:0] in_dst_ip,input wire [15:0] in_src_port,in_dst_port,
    output wire [7:0] out_data,output wire out_valid,out_last,input wire out_ready,
    output /* drop_event：对应错误/拒绝/溢出/丢弃事件指示。 */ wire drop_event
);
 assign drop_event=0;

    /* count：当前载荷输入字节位置；length：完整UDP载荷字节数；index：当前字节或表项位置。 */ reg [11:0] count,length,index;
    // dst_ip: 当前报文的目标IP。
    reg [31:0] dst_ip;
    /* src_port：首载荷字节握手时锁存的目的IP及UDP端口；dst_port：首载荷字节握手时锁存的目的IP及UDP端口。 */ reg [15:0] src_port,dst_port;
    /* sn：本VL发送SN。 */ reg [7:0] sn;
    /* payload_high：计算UDP校验和时暂存16位字的高字节。 */ reg [7:0] payload_high;
    /* payload_sum：当前UDP正文的累加和。 */ reg [31:0] payload_sum;
    /* sending：当前帧正在输出。 */ reg sending;
    wire [15:0] udp_len=16'd8+length;
    wire [15:0] ip_len=16'd20+udp_len;
    wire [15:0] physical_len=length<17 ? 16'd60 : 16'd43+length;
    wire [31:0] sum=32'h4500+ip_len+32'h4000+32'h4011+
                         LOCAL_IP[31:16]+LOCAL_IP[15:0]+dst_ip[31:16]+dst_ip[15:0];
    wire [16:0] folded=sum[15:0]+sum[31:16];
    wire [15:0] checksum=~(folded[15:0]+folded[16]);
    wire [31:0] udp_sum=payload_sum+LOCAL_IP[31:16]+LOCAL_IP[15:0]+
      dst_ip[31:16]+dst_ip[15:0]+32'd17+udp_len+src_port+dst_port+udp_len;
    wire [16:0] udp_fold1={1'b0,udp_sum[15:0]}+{1'b0,udp_sum[31:16]};
    wire [15:0] udp_complement=~(udp_fold1[15:0]+udp_fold1[16]);
    wire [15:0] udp_checksum=udp_complement==0 ? 16'hffff : udp_complement;
    /* header：按index组合生成的以太网/IPv4/UDP头字节。 */ reg [7:0] header;
    assign in_ready=!reset && !sending;
    assign out_valid=!reset && sending;
    assign out_last=out_valid && index==physical_len-1;
    // PAYLOAD_ADDRESS_WIDTH: UDP载荷RAM的地址位数。
    localparam PAYLOAD_ADDRESS_WIDTH=$clog2(MAX_PAYLOAD);
    // payload_write_address/payload_read_address: 待写字节和下一拍待发送字节的位置。
    wire [PAYLOAD_ADDRESS_WIDTH-1:0] payload_write_address=count;
    wire [PAYLOAD_ADDRESS_WIDTH-1:0] payload_read_address=index<42 ? 0 :
     index-42+((out_valid && out_ready && !out_last) ? 1'b1 : 1'b0);
    // payload_byte: 载荷RAM同步读出的当前发送字节。
    wire [7:0] payload_byte;
    afdx_byte_ram #(.WORDS(MAX_PAYLOAD),.ADDRESS_WIDTH(PAYLOAD_ADDRESS_WIDTH)) memory(
     .clk(clk),.write_enable(in_valid && in_ready),.write_address(payload_write_address),.write_data(in_data),
     .read_enable(1'b1),.read_address(payload_read_address),.read_data(payload_byte));
    assign out_data=index<42 ? header : out_last ? sn :
                    index<42+length ? payload_byte : 8'h00;
    always @* begin
        header=0;
        case(index)
        0:header=DEST_MAC[47:40];1:header=DEST_MAC[39:32];2:header=DEST_MAC[31:24];
        3:header=DEST_MAC[23:16];4:header=DEST_MAC[15:8];5:header=DEST_MAC[7:0];
        6:header=SRC_MAC[47:40];7:header=SRC_MAC[39:32];8:header=SRC_MAC[31:24];
        9:header=SRC_MAC[23:16];10:header=SRC_MAC[15:8];11:header=SRC_MAC[7:0];
        12:header=8'h08;14:header=8'h45;16:header=ip_len[15:8];17:header=ip_len[7:0];
        20:header=8'h40;22:header=8'h40;23:header=17;
        24:header=checksum[15:8];25:header=checksum[7:0];
        26:header=LOCAL_IP[31:24];27:header=LOCAL_IP[23:16];28:header=LOCAL_IP[15:8];29:header=LOCAL_IP[7:0];
        30:header=dst_ip[31:24];31:header=dst_ip[23:16];32:header=dst_ip[15:8];33:header=dst_ip[7:0];
        34:header=src_port[15:8];35:header=src_port[7:0];36:header=dst_port[15:8];37:header=dst_port[7:0];
        38:header=udp_len[15:8];39:header=udp_len[7:0];
        40:header=udp_checksum[15:8];41:header=udp_checksum[7:0];
        default:header=0;
        endcase
    end
    always @(posedge clk) begin
        if(reset) begin
            count<=0;length<=0;index<=0;sending<=0;
            dst_ip<=0;src_port<=0;dst_port<=0;sn<=1;
            payload_high<=0;payload_sum<=0;
        end else begin
            
            if(in_valid && in_ready) begin
                begin
                    if(!count[0])payload_high<=in_data;
                    else payload_sum<=payload_sum+{payload_high,in_data};
                end
                if(count==0) begin dst_ip<=in_dst_ip;src_port<=in_src_port;dst_port<=in_dst_port;end
                if(in_last) begin
                    count<=0;
                    begin
                        length<=count+1'b1;sending<=1;index<=0;
                        payload_sum<=payload_sum+(count[0] ? {payload_high,in_data} : {in_data,8'h00});
                    end
                end else count<=count+1'b1;
            end
            if(out_valid && out_ready) begin
                if(out_last) begin sending<=0;index<=0;payload_sum<=0;sn<=sn==255 ? 1 : sn+1'b1;end
                else index<=index+1'b1;
            end
        end
    end
endmodule
