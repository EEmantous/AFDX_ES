`timescale 1ns / 1ps

// TX报文输出器：完成报文构建、序列号维护和交换机ready/valid输出适配。
module afdx_tx_packet_output #(
    parameter integer FRAME_LENGTH_WIDTH = 11,
    parameter [47:0] DEST_MAC = 48'h03_00_00_00_00_01,
    parameter [47:0] SRC_MAC  = 48'h00_11_22_33_44_55,
    parameter [31:0] SRC_IP   = 32'hC0_A8_00_01,
    parameter [31:0] DEST_IP  = 32'hE0_00_00_01,
    parameter [15:0] SRC_PORT = 16'd1000,
    parameter [15:0] DEST_PORT = 16'd1001
)(
    input  wire                          sys_clk,
    input  wire                          sys_rst_n,

    input  wire                          scheduled_frame_grant,
    input  wire [FRAME_LENGTH_WIDTH-1:0] scheduled_frame_length,
    output wire                          frame_transmit_start,
    output wire                          frame_transmit_busy,

    input  wire [7:0]                    payload_read_data,
    input  wire                          payload_read_last,
    input  wire                          payload_fifo_empty,
    output wire                          payload_read_enable,

    output wire [7:0]                    tx_data,
    output wire                          tx_valid,
    output wire                          tx_last,
    input  wire                          tx_ready
);
    wire builder_frame_done;
    wire [7:0] sequence_number;
    wire builder_read_request;
    wire builder_read_ready;
    wire [7:0] builder_data;
    wire builder_valid;
    wire builder_last;
    reg output_frame_active;
    reg first_output_byte_sent;
    wire tx_transfer;

    assign tx_transfer = tx_valid && tx_ready;
    // BAG从交换机接口真正接收首字节的时钟沿开始计时。
    assign frame_transmit_start = sys_rst_n && tx_transfer &&
                                  !first_output_byte_sent;
    // builder完成后仍可能有字节在途或滞留于弹性缓存。
    // 必须等外部帧尾握手后才允许调度下一帧。
    assign frame_transmit_busy = output_frame_active;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0) begin
            output_frame_active <= 1'b0;
            first_output_byte_sent <= 1'b0;
        end else if (scheduled_frame_grant == 1'b1) begin
            output_frame_active <= 1'b1;
            first_output_byte_sent <= 1'b0;
        end else begin
            if (tx_transfer)
                first_output_byte_sent <= 1'b1;
            if (tx_transfer && tx_last)
                output_frame_active <= 1'b0;
        end
    end

    sequence_counter u_sequence_counter (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .frame_transmit_done(builder_frame_done),
        .sequence_number(sequence_number)
    );

    packet_builder #(
        .FRAME_LENGTH_WIDTH(FRAME_LENGTH_WIDTH),
        .DEST_MAC(DEST_MAC),
        .SRC_MAC(SRC_MAC),
        .SRC_IP(SRC_IP),
        .DEST_IP(DEST_IP),
        .SRC_PORT(SRC_PORT),
        .DEST_PORT(DEST_PORT)
    ) u_packet_builder (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .bag_grant(scheduled_frame_grant),
        .payload_frame_length(scheduled_frame_length),
        .sequence_number(sequence_number),
        .payload_read_data(payload_read_data),
        .payload_read_last(payload_read_last),
        .payload_fifo_empty(payload_fifo_empty),
        .payload_read_enable(payload_read_enable),
        .builder_read_request(builder_read_request),
        .builder_read_ready(builder_read_ready),
        .builder_data(builder_data),
        .builder_valid(builder_valid),
        .builder_last(builder_last),
        .frame_transmit_start(),
        .frame_transmit_done(builder_frame_done),
        .frame_transmit_busy()
    );

    afdx_tx_switch_stream u_switch_stream (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .builder_read_request(builder_read_request),
        .builder_read_ready(builder_read_ready),
        .builder_data(builder_data),
        .builder_valid(builder_valid),
        .builder_last(builder_last),
        .tx_data(tx_data),
        .tx_valid(tx_valid),
        .tx_last(tx_last),
        .tx_ready(tx_ready)
    );

endmodule
