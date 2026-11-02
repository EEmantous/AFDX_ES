`timescale 1ns/1ps
// 提取帧字段并将正文写入接收队列。
module afdx_es_rx #(
    parameter [31:0] LOCAL_DEST_IP = 32'hE0_00_00_01,
    parameter [15:0] LOCAL_DEST_PORT = 16'd1001,
    parameter STANDARD_UDP = 1'b0,
    parameter ACCEPT_ANY_DEST = 1'b0,
    parameter VL_FILTER = 1'b0,CHECK_LOCAL_IP = 1'b0,
    parameter [15:0] RX_VL_ID = 16'h0001,
    parameter integer RX_VL_COUNT=1,
    parameter [16*RX_VL_COUNT-1:0] RX_VL_IDS=RX_VL_ID,
    parameter integer RX_IDLE_TIMEOUT_CYCLES = 12500
)(
    input  wire       sys_clk,
    input  wire       sys_rst_n,

    input  wire [7:0] rx_data,
    input  wire       rx_valid,
    input  wire       rx_last,
    output wire       rx_ready,

    output wire [7:0] app_rx_data,
    output wire       app_rx_valid,
    output wire       app_rx_last,
    input  wire       app_rx_ready,
    output wire [106:0] app_rx_metadata,
    output wire [15:0] app_rx_vl_id,
    output wire [7:0] app_rx_sequence_number,
    output wire [11:0] rx_events
);

    wire frame_capture_start;
    wire payload_write_valid;
    wire [7:0] payload_write_data;
    wire payload_write_ready;
    wire payload_write_overflow;
    wire frame_descriptor_ready;
    wire frame_commit;
    wire frame_abort;
    wire [10:0] frame_payload_length;
    wire [106:0] frame_metadata;
    wire [15:0] frame_vl_id;
    wire [7:0] frame_sequence_number;
    // decoder_errors: VL未订阅事件；其余旧检查事件固定为0。
    wire [4:0] decoder_errors;
    assign rx_events={rx_valid && !rx_ready && sys_rst_n,4'b0,decoder_errors[0],
                      3'b0,frame_abort,frame_commit,rx_valid && rx_ready && rx_last};

    packet_decoder #(
        .VL_INDEX_WIDTH(VL_FILTER ? (RX_VL_COUNT<=1 ? 1 : $clog2(RX_VL_COUNT)) : 12),
        .STANDARD_UDP(STANDARD_UDP),
        .LOCAL_DEST_IP(LOCAL_DEST_IP),
        .LOCAL_DEST_PORT(LOCAL_DEST_PORT),
        .ACCEPT_ANY_DEST(ACCEPT_ANY_DEST),
        .VL_FILTER(VL_FILTER),.RX_VL_ID(RX_VL_ID),.RX_VL_COUNT(RX_VL_COUNT),.RX_VL_IDS(RX_VL_IDS),.CHECK_LOCAL_IP(CHECK_LOCAL_IP)
    ) u_packet_decoder (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .rx_last(rx_last),
        .rx_ready(rx_ready),
        .frame_capture_start(frame_capture_start),
        .payload_write_valid(payload_write_valid),
        .payload_write_data(payload_write_data),
        .payload_write_ready(payload_write_ready),
        .payload_write_overflow(payload_write_overflow),
        .frame_descriptor_ready(frame_descriptor_ready),
        .frame_commit(frame_commit),
        .frame_abort(frame_abort),
        .frame_metadata(frame_metadata),
        .frame_vl_id(frame_vl_id),
        .frame_sequence_number(frame_sequence_number),
        .frame_payload_length(frame_payload_length),
        .error_events(decoder_errors)
    );

    afdx_rx_frame_manager u_frame_manager (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .frame_capture_start(frame_capture_start),
        .payload_write_valid(payload_write_valid),
        .payload_write_data(payload_write_data),
        .payload_write_ready(payload_write_ready),
        .payload_write_overflow(payload_write_overflow),
        .frame_descriptor_ready(frame_descriptor_ready),
        .frame_commit(frame_commit),
        .frame_abort(frame_abort),
        .frame_metadata(frame_metadata),
        .frame_vl_id(frame_vl_id),
        .frame_sequence_number(frame_sequence_number),
        .frame_payload_length(frame_payload_length),
        .app_rx_data(app_rx_data),
        .app_rx_valid(app_rx_valid),
        .app_rx_last(app_rx_last),
        .app_rx_metadata(app_rx_metadata),
        .app_rx_vl_id(app_rx_vl_id),
        .app_rx_sequence_number(app_rx_sequence_number),
        .app_rx_ready(app_rx_ready)
    );

endmodule
