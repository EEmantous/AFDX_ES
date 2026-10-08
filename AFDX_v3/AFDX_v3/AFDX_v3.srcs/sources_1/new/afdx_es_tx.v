`timescale 1ns / 1ps

// TX结构顶层：只连接帧管理器和报文输出器，不包含行为逻辑。
module afdx_es_tx #(
    parameter integer BAG_CYCLES = 400_000,
    parameter integer FRAME_LENGTH_WIDTH = 11,
    parameter integer DESCRIPTOR_FIFO_DEPTH = 4,
    parameter integer DESCRIPTOR_POINTER_WIDTH = 2,
    parameter [47:0] DEST_MAC = 48'h03_00_00_00_00_01,
    parameter [47:0] SRC_MAC  = 48'h00_11_22_33_44_55,
    parameter [31:0] SRC_IP   = 32'hC0_A8_00_01,
    parameter [31:0] DEST_IP  = 32'hE0_00_00_01,
    parameter [15:0] SRC_PORT = 16'd1000,
    parameter [15:0] DEST_PORT = 16'd1001
)(
    input  wire                          sys_clk,
    input  wire                          sys_rst_n,
    input  wire [7:0]                    app_tx_data,
    input  wire                          app_tx_valid,
    input  wire                          app_tx_last,
    output wire                          app_tx_ready,
    output wire [7:0]                    tx_data,
    output wire                          tx_valid,
    output wire                          tx_last,
    input  wire                          tx_ready
);
    wire scheduled_frame_grant;
    wire [FRAME_LENGTH_WIDTH-1:0] scheduled_frame_length;
    wire frame_transmit_start;
    wire frame_transmit_busy;
    wire payload_read_enable;
    wire [7:0] payload_read_data;
    wire payload_read_last;
    wire payload_fifo_empty;

    afdx_tx_frame_manager #(
        .BAG_CYCLES(BAG_CYCLES),
        .FRAME_LENGTH_WIDTH(FRAME_LENGTH_WIDTH),
        .DESCRIPTOR_FIFO_DEPTH(DESCRIPTOR_FIFO_DEPTH),
        .DESCRIPTOR_POINTER_WIDTH(DESCRIPTOR_POINTER_WIDTH)
    ) u_frame_manager (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .app_tx_data(app_tx_data),
        .app_tx_valid(app_tx_valid),
        .app_tx_last(app_tx_last),
        .app_tx_ready(app_tx_ready),
        .scheduled_frame_grant(scheduled_frame_grant),
        .scheduled_frame_length(scheduled_frame_length),
        .frame_transmit_start(frame_transmit_start),
        .frame_transmit_busy(frame_transmit_busy),
        .payload_read_enable(payload_read_enable),
        .payload_read_data(payload_read_data),
        .payload_read_last(payload_read_last),
        .payload_fifo_empty(payload_fifo_empty)
    );

    afdx_tx_packet_output #(
        .FRAME_LENGTH_WIDTH(FRAME_LENGTH_WIDTH),
        .DEST_MAC(DEST_MAC),
        .SRC_MAC(SRC_MAC),
        .SRC_IP(SRC_IP),
        .DEST_IP(DEST_IP),
        .SRC_PORT(SRC_PORT),
        .DEST_PORT(DEST_PORT)
    ) u_packet_output (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .scheduled_frame_grant(scheduled_frame_grant),
        .scheduled_frame_length(scheduled_frame_length),
        .frame_transmit_start(frame_transmit_start),
        .frame_transmit_busy(frame_transmit_busy),
        .payload_read_data(payload_read_data),
        .payload_read_last(payload_read_last),
        .payload_fifo_empty(payload_fifo_empty),
        .payload_read_enable(payload_read_enable),
        .tx_data(tx_data),
        .tx_valid(tx_valid),
        .tx_last(tx_last),
        .tx_ready(tx_ready)
    );

endmodule
