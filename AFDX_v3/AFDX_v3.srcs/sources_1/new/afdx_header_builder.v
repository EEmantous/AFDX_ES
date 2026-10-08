`timescale 1ns / 1ps

module afdx_header_builder #(
    parameter FRAME_LENGTH_WIDTH = 11,
    parameter [47:0] DEST_MAC = 48'h03_00_00_00_00_01,
    parameter [47:0] SRC_MAC  = 48'h00_11_22_33_44_55,
    parameter [31:0] SRC_IP   = 32'hC0_A8_00_01,
    parameter [31:0] DEST_IP  = 32'hE0_00_00_01,
    parameter [15:0] SRC_PORT = 16'd1000,
    parameter [15:0] DEST_PORT = 16'd1001
)(
    input  wire [FRAME_LENGTH_WIDTH-1:0] payload_frame_length,
    input  wire [5:0]                    header_byte_index,
    output reg  [7:0]                    header_byte_data
);

    // UDP数据由应用数据、短帧填充和最后一个8位AFDX序列号组成。
    wire [15:0] padded_payload_length;
    wire [15:0] udp_length;
    wire [15:0] ip_total_length;

    // 当前简化设计使用固定20字节IPv4头，并设置Don't Fragment标志。
    wire [31:0] ip_checksum_sum;
    wire [16:0] ip_checksum_fold_1;
    wire [16:0] ip_checksum_fold_2;
    wire [15:0] ip_header_checksum;

    // AFDX应用载荷不足17字节时，在序列号前补零到17字节。
    assign padded_payload_length = (payload_frame_length < 17) ?
                                   16'd17 : payload_frame_length;
    assign udp_length      = 16'd8 + padded_payload_length + 16'd1;
    assign ip_total_length = 16'd20 + udp_length;

    // IPv4头校验和：先累加除校验和字段外的所有16位字，
    // 再把高位进位折回低16位，最后按位取反。
    assign ip_checksum_sum = 32'h0000_4500 +
                             {16'd0, ip_total_length} +
                             32'h0000_0000 +
                             32'h0000_4000 +
                             32'h0000_4011 +
                             {16'd0, SRC_IP[31:16]} +
                             {16'd0, SRC_IP[15:0]} +
                             {16'd0, DEST_IP[31:16]} +
                             {16'd0, DEST_IP[15:0]};

    assign ip_checksum_fold_1 = ip_checksum_sum[15:0] +
                                ip_checksum_sum[31:16];
    assign ip_checksum_fold_2 = ip_checksum_fold_1[15:0] +
                                ip_checksum_fold_1[16];
    assign ip_header_checksum = ~ip_checksum_fold_2[15:0];

    // 42字节固定头部：14字节Ethernet + 20字节IPv4 + 8字节UDP。
    // header_byte_index每增加1，输出下一个头部字节。
    always @(*) begin
        case (header_byte_index)
            // Ethernet头：目的MAC、源MAC、EtherType=IPv4。
            6'd0:  header_byte_data = DEST_MAC[47:40];
            6'd1:  header_byte_data = DEST_MAC[39:32];
            6'd2:  header_byte_data = DEST_MAC[31:24];
            6'd3:  header_byte_data = DEST_MAC[23:16];
            6'd4:  header_byte_data = DEST_MAC[15:8];
            6'd5:  header_byte_data = DEST_MAC[7:0];
            6'd6:  header_byte_data = SRC_MAC[47:40];
            6'd7:  header_byte_data = SRC_MAC[39:32];
            6'd8:  header_byte_data = SRC_MAC[31:24];
            6'd9:  header_byte_data = SRC_MAC[23:16];
            6'd10: header_byte_data = SRC_MAC[15:8];
            6'd11: header_byte_data = SRC_MAC[7:0];
            6'd12: header_byte_data = 8'h08;
            6'd13: header_byte_data = 8'h00;

            // IPv4头：Version/IHL、长度、DF、TTL、UDP、校验和和地址。
            6'd14: header_byte_data = 8'h45;
            6'd15: header_byte_data = 8'h00;
            6'd16: header_byte_data = ip_total_length[15:8];
            6'd17: header_byte_data = ip_total_length[7:0];
            6'd18: header_byte_data = 8'h00;
            6'd19: header_byte_data = 8'h00;
            6'd20: header_byte_data = 8'h40;
            6'd21: header_byte_data = 8'h00;
            6'd22: header_byte_data = 8'h40;
            6'd23: header_byte_data = 8'h11;
            6'd24: header_byte_data = ip_header_checksum[15:8];
            6'd25: header_byte_data = ip_header_checksum[7:0];
            6'd26: header_byte_data = SRC_IP[31:24];
            6'd27: header_byte_data = SRC_IP[23:16];
            6'd28: header_byte_data = SRC_IP[15:8];
            6'd29: header_byte_data = SRC_IP[7:0];
            6'd30: header_byte_data = DEST_IP[31:24];
            6'd31: header_byte_data = DEST_IP[23:16];
            6'd32: header_byte_data = DEST_IP[15:8];
            6'd33: header_byte_data = DEST_IP[7:0];

            // UDP头。当前仿真模型暂时把UDP校验和设为0。
            6'd34: header_byte_data = SRC_PORT[15:8];
            6'd35: header_byte_data = SRC_PORT[7:0];
            6'd36: header_byte_data = DEST_PORT[15:8];
            6'd37: header_byte_data = DEST_PORT[7:0];
            6'd38: header_byte_data = udp_length[15:8];
            6'd39: header_byte_data = udp_length[7:0];
            6'd40: header_byte_data = 8'h00;
            6'd41: header_byte_data = 8'h00;

            default: header_byte_data = 8'h00;
        endcase
    end

endmodule
