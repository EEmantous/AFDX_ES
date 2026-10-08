`timescale 1ns / 1ps

// AFDX网络帧解析与协议校验模块。
// 只负责识别字段、产生候选载荷字节和帧尾校验结果，不保存可交付帧。
module afdx_rx_parser #(
    parameter integer FRAME_LENGTH_WIDTH = 11,
    parameter [31:0] LOCAL_DEST_IP = 32'hE0_00_00_01,
    parameter [15:0] LOCAL_DEST_PORT = 16'd1001,
    // Optional destination filter bypass for explicitly configured RX use.
    parameter ACCEPT_ANY_DEST = 1'b0
)(
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    input  wire       rx_transfer,
    input  wire [7:0] rx_data,
    input  wire       rx_last,

    output wire       frame_capture_start,
    output wire       payload_write_valid,
    output wire [7:0] payload_write_data,
    output wire       frame_parse_done,
    output wire       frame_parse_valid,
    output wire [FRAME_LENGTH_WIDTH-1:0] parsed_payload_length,
    output wire [15:0] parsed_vl_id,
    output wire [7:0]  parsed_sequence_number
);

    localparam [15:0] MIN_UDP_LENGTH  = 16'd26;
    localparam [15:0] MAX_UDP_LENGTH  = 16'd1480;
    localparam [15:0] MAX_CORE_LENGTH = 16'd1514;

    function [16:0] checksum_add;
        input [16:0] current_sum;
        input [15:0] next_word;
        reg [17:0] add_result;
        begin
            add_result = {1'b0, current_sum[15:0]} +
                         current_sum[16] + next_word;
            checksum_add = add_result[16:0];
        end
    endfunction

    function [15:0] checksum_fold;
        input [16:0] current_sum;
        reg [16:0] fold_1;
        reg [16:0] fold_2;
        begin
            fold_1 = current_sum[15:0] + current_sum[16];
            fold_2 = fold_1[15:0] + fold_1[16];
            checksum_fold = fold_2[15:0];
        end
    endfunction

    reg        frame_active;
    reg [11:0] rx_byte_index;
    reg        frame_length_exceeded;
    reg [FRAME_LENGTH_WIDTH-1:0] payload_byte_count;

    reg [47:0] destination_mac;
    reg [15:0] ether_type;
    reg [7:0]  ip_version_ihl;
    reg [15:0] ip_total_length;
    reg [7:0]  ip_protocol;
    reg [31:0] source_ip;
    reg [31:0] destination_ip;
    reg [15:0] udp_destination_port;
    reg [15:0] udp_length;
    reg [15:0] udp_checksum_field;

    reg [7:0]  ip_word_high;
    reg [16:0] ip_checksum_sum;
    reg [7:0]  udp_word_high;
    reg [16:0] udp_checksum_sum;

    wire active_frame_end;
    wire [15:0] received_frame_length;
    wire [15:0] expected_ip_frame_length;
    wire [15:0] expected_udp_frame_length;
    wire [15:0] decoded_payload_length;
    wire protocol_valid;
    wire length_valid;
    wire checksum_valid;
    wire ip_checksum_valid;
    wire udp_checksum_valid;
    wire [15:0] udp_last_word;
    wire [16:0] udp_sum_with_last;
    wire [16:0] udp_sum_pseudo_1;
    wire [16:0] udp_sum_pseudo_2;
    wire [16:0] udp_sum_pseudo_3;
    wire [16:0] udp_sum_pseudo_4;
    wire [16:0] udp_sum_pseudo_5;
    wire [16:0] udp_sum_pseudo_6;

    assign frame_capture_start = rx_transfer && !frame_active;
    assign payload_write_valid = rx_transfer && frame_active &&
                                 (rx_byte_index >= 12'd42) && !rx_last;
    assign payload_write_data = rx_data;
    assign frame_parse_done = rx_transfer && rx_last;
    assign active_frame_end = frame_parse_done && frame_active;

    assign parsed_payload_length = payload_byte_count;
    assign parsed_vl_id = destination_mac[15:0];
    assign parsed_sequence_number = rx_data;

    assign received_frame_length = {4'd0, rx_byte_index} + 16'd1;
    assign expected_ip_frame_length = 16'd14 + ip_total_length;
    assign expected_udp_frame_length = 16'd34 + udp_length;
    assign decoded_payload_length = udp_length - 16'd9;

    assign protocol_valid =
        (destination_mac[47:16] == 32'h03_00_00_00) &&
        (ether_type == 16'h0800) &&
        (ip_version_ihl == 8'h45) &&
        (ip_protocol == 8'd17) &&
        (ACCEPT_ANY_DEST || ((destination_ip == LOCAL_DEST_IP) &&
                             (udp_destination_port == LOCAL_DEST_PORT)));

    assign length_valid = active_frame_end &&
        (received_frame_length >= 16'd60) &&
        (received_frame_length <= MAX_CORE_LENGTH) &&
        (received_frame_length == expected_ip_frame_length) &&
        (received_frame_length == expected_udp_frame_length) &&
        (ip_total_length == (16'd20 + udp_length)) &&
        (udp_length >= MIN_UDP_LENGTH) &&
        (udp_length <= MAX_UDP_LENGTH) &&
        (decoded_payload_length == payload_byte_count) &&
        !frame_length_exceeded;

    assign ip_checksum_valid =
        (checksum_fold(ip_checksum_sum) == 16'hffff);

    assign udp_last_word = rx_byte_index[0] ?
                           {udp_word_high, rx_data} : {rx_data, 8'h00};
    assign udp_sum_with_last = checksum_add(udp_checksum_sum,
                                            udp_last_word);
    assign udp_sum_pseudo_1 = checksum_add(udp_sum_with_last,
                                           source_ip[31:16]);
    assign udp_sum_pseudo_2 = checksum_add(udp_sum_pseudo_1,
                                           source_ip[15:0]);
    assign udp_sum_pseudo_3 = checksum_add(udp_sum_pseudo_2,
                                           destination_ip[31:16]);
    assign udp_sum_pseudo_4 = checksum_add(udp_sum_pseudo_3,
                                           destination_ip[15:0]);
    assign udp_sum_pseudo_5 = checksum_add(udp_sum_pseudo_4,
                                           16'h0011);
    assign udp_sum_pseudo_6 = checksum_add(udp_sum_pseudo_5,
                                           udp_length);
    assign udp_checksum_valid = (udp_checksum_field == 16'h0000) ||
                                (checksum_fold(udp_sum_pseudo_6) ==
                                 16'hffff);
    assign checksum_valid = active_frame_end &&
                            ip_checksum_valid && udp_checksum_valid;

    assign frame_parse_valid = active_frame_end && protocol_valid &&
                               length_valid && checksum_valid;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0) begin
            frame_active         <= 1'b0;
            rx_byte_index        <= 12'd0;
            frame_length_exceeded <= 1'b0;
            payload_byte_count   <= {FRAME_LENGTH_WIDTH{1'b0}};
            destination_mac      <= 48'd0;
            ether_type           <= 16'd0;
            ip_version_ihl       <= 8'd0;
            ip_total_length      <= 16'd0;
            ip_protocol          <= 8'd0;
            source_ip            <= 32'd0;
            destination_ip       <= 32'd0;
            udp_destination_port <= 16'd0;
            udp_length           <= 16'd0;
            udp_checksum_field   <= 16'd0;
            ip_word_high         <= 8'd0;
            ip_checksum_sum      <= 17'd0;
            udp_word_high        <= 8'd0;
            udp_checksum_sum     <= 17'd0;
        end
        else if (rx_transfer == 1'b1) begin
            if (frame_active == 1'b0) begin
                frame_active         <= !rx_last;
                rx_byte_index        <= rx_last ? 12'd0 : 12'd1;
                frame_length_exceeded <= 1'b0;
                payload_byte_count   <= {FRAME_LENGTH_WIDTH{1'b0}};
                destination_mac      <= {40'd0, rx_data};
                ether_type           <= 16'd0;
                ip_version_ihl       <= 8'd0;
                ip_total_length      <= 16'd0;
                ip_protocol          <= 8'd0;
                source_ip            <= 32'd0;
                destination_ip       <= 32'd0;
                udp_destination_port <= 16'd0;
                udp_length           <= 16'd0;
                udp_checksum_field   <= 16'd0;
                ip_word_high         <= 8'd0;
                ip_checksum_sum      <= 17'd0;
                udp_word_high        <= 8'd0;
                udp_checksum_sum     <= 17'd0;
            end
            else begin
                if (rx_last == 1'b1) begin
                    frame_active       <= 1'b0;
                    rx_byte_index      <= 12'd0;
                    payload_byte_count <= {FRAME_LENGTH_WIDTH{1'b0}};
                end
                else begin
                    rx_byte_index <= rx_byte_index + 1'b1;
                    if (rx_byte_index >= (MAX_CORE_LENGTH - 1'b1))
                        frame_length_exceeded <= 1'b1;
                    if (rx_byte_index >= 12'd42)
                        payload_byte_count <= payload_byte_count + 1'b1;
                end

                if (rx_byte_index <= 12'd5)
                    destination_mac <= {destination_mac[39:0], rx_data};

                case (rx_byte_index)
                    12'd12: ether_type[15:8] <= rx_data;
                    12'd13: ether_type[7:0]  <= rx_data;
                    12'd14: ip_version_ihl   <= rx_data;
                    12'd16: ip_total_length[15:8] <= rx_data;
                    12'd17: ip_total_length[7:0]  <= rx_data;
                    12'd23: ip_protocol <= rx_data;
                    12'd26: source_ip[31:24] <= rx_data;
                    12'd27: source_ip[23:16] <= rx_data;
                    12'd28: source_ip[15:8]  <= rx_data;
                    12'd29: source_ip[7:0]   <= rx_data;
                    12'd30: destination_ip[31:24] <= rx_data;
                    12'd31: destination_ip[23:16] <= rx_data;
                    12'd32: destination_ip[15:8]  <= rx_data;
                    12'd33: destination_ip[7:0]   <= rx_data;
                    12'd36: udp_destination_port[15:8] <= rx_data;
                    12'd37: udp_destination_port[7:0]  <= rx_data;
                    12'd38: udp_length[15:8] <= rx_data;
                    12'd39: udp_length[7:0]  <= rx_data;
                    12'd40: udp_checksum_field[15:8] <= rx_data;
                    12'd41: udp_checksum_field[7:0]  <= rx_data;
                    default: begin
                    end
                endcase

                if ((rx_byte_index >= 12'd14) &&
                    (rx_byte_index <= 12'd33)) begin
                    if (rx_byte_index[0] == 1'b0)
                        ip_word_high <= rx_data;
                    else
                        ip_checksum_sum <= checksum_add(
                            ip_checksum_sum, {ip_word_high, rx_data});
                end

                if (rx_byte_index >= 12'd34) begin
                    if (rx_byte_index[0] == 1'b0)
                        udp_word_high <= rx_data;
                    else
                        udp_checksum_sum <= checksum_add(
                            udp_checksum_sum, {udp_word_high, rx_data});
                end
            end
        end
    end

endmodule
