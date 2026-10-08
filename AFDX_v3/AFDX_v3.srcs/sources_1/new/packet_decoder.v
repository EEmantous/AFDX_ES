`timescale 1ns / 1ps

// AFDX报文解码器，与TX的packet_builder构成收发对应关系。
// 完成Ethernet/IPv4/UDP拆包和VL序列检查，最终决定候选载荷提交或回滚。
module packet_decoder #(
    parameter integer FRAME_LENGTH_WIDTH = 11,
    parameter integer VL_INDEX_WIDTH = 12,
    parameter [31:0] LOCAL_DEST_IP = 32'hE0_00_00_01,
    parameter [15:0] LOCAL_DEST_PORT = 16'd1001,
    parameter ACCEPT_ANY_DEST = 1'b0
)(
    input  wire       sys_clk,
    input  wire       sys_rst_n,

    input  wire [7:0] rx_data,
    input  wire       rx_valid,
    input  wire       rx_last,
    output wire       rx_ready,

    output wire       frame_capture_start,
    output wire       payload_write_valid,
    output wire [7:0] payload_write_data,
    input  wire       payload_write_ready,
    input  wire       payload_write_overflow,
    input  wire       frame_descriptor_ready,

    output wire       frame_commit,
    output wire       frame_abort,
    output wire [FRAME_LENGTH_WIDTH-1:0] frame_payload_length,
    output reg [15:0] frame_vl_id,
    output reg [7:0] frame_sequence_number,
    output wire [4:0] error_events
);

    wire rx_transfer;
    wire frame_parse_done;
    wire frame_parse_valid;
    wire [FRAME_LENGTH_WIDTH-1:0] parsed_payload_length;
    wire [15:0] parsed_vl_id;
    wire [7:0] parsed_sequence_number;

    wire sequence_check_ready;
    wire sequence_check_busy;
    wire sequence_check_start;
    wire sequence_check_done;
    wire sequence_check_passed;
    wire sequence_error, duplicate_frame;
    assign error_events[0] = frame_parse_done && !frame_parse_valid;
    assign error_events[1] = frame_parse_valid && (payload_write_overflow || !frame_descriptor_ready);
    assign error_events[2] = sequence_check_done && !sequence_check_passed;
    assign error_events[3] = sequence_error;
    assign error_events[4] = duplicate_frame;

    reg [FRAME_LENGTH_WIDTH-1:0] validated_payload_length;

    assign rx_ready = sys_rst_n && sequence_check_ready &&
                      payload_write_ready &&
                      !sequence_check_busy && !sequence_check_done;
    assign rx_transfer = rx_valid && rx_ready;

    assign sequence_check_start = frame_parse_valid &&
                                  !payload_write_overflow &&
                                  frame_descriptor_ready;
    assign frame_commit = sequence_check_done && sequence_check_passed;
    assign frame_abort =
        (frame_parse_done &&
         (!frame_parse_valid || payload_write_overflow ||
          !frame_descriptor_ready)) ||
        (sequence_check_done && !sequence_check_passed);
    assign frame_payload_length = validated_payload_length;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0) begin
            validated_payload_length <= {FRAME_LENGTH_WIDTH{1'b0}};
            frame_vl_id <= 0;
            frame_sequence_number <= 0;
        end else if (sequence_check_start) begin
            validated_payload_length <= parsed_payload_length;
            frame_vl_id <= parsed_vl_id;
            frame_sequence_number <= parsed_sequence_number;
        end
    end

    // 字节级字段提取与Ethernet/IPv4/UDP校验。
    afdx_rx_parser #(
        .FRAME_LENGTH_WIDTH(FRAME_LENGTH_WIDTH),
        .LOCAL_DEST_IP(LOCAL_DEST_IP),
        .LOCAL_DEST_PORT(LOCAL_DEST_PORT),
        .ACCEPT_ANY_DEST(ACCEPT_ANY_DEST)
    ) u_parser (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .rx_transfer(rx_transfer),
        .rx_data(rx_data),
        .rx_last(rx_last),
        .frame_capture_start(frame_capture_start),
        .payload_write_valid(payload_write_valid),
        .payload_write_data(payload_write_data),
        .frame_parse_done(frame_parse_done),
        .frame_parse_valid(frame_parse_valid),
        .parsed_payload_length(parsed_payload_length),
        .parsed_vl_id(parsed_vl_id),
        .parsed_sequence_number(parsed_sequence_number)
    );

    // 最后一个字节是AFDX序列号；按VL独立检查后才能提交候选载荷。
    afdx_rx_sequence_table #(
        .VL_INDEX_WIDTH(VL_INDEX_WIDTH)
    ) u_sequence_table (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .sequence_check_start(sequence_check_start),
        .sequence_check_vl_id(parsed_vl_id),
        .sequence_check_number(parsed_sequence_number),
        .sequence_check_ready(sequence_check_ready),
        .sequence_check_busy(sequence_check_busy),
        .sequence_check_done(sequence_check_done),
        .sequence_check_passed(sequence_check_passed),
        .sequence_error(sequence_error),
        .duplicate_frame(duplicate_frame)
    );

endmodule
