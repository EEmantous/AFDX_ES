`timescale 1ns / 1ps

// MAC-side complete-frame guard, protocol/sequence checks, transactional APP output.
module afdx_es_rx #(
    parameter [31:0] LOCAL_DEST_IP = 32'hE0_00_00_01,
    parameter [15:0] LOCAL_DEST_PORT = 16'd1001,
    parameter ACCEPT_ANY_DEST = 1'b0,
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
    wire [15:0] frame_vl_id;
    wire [7:0] frame_sequence_number;
    wire [7:0] guarded_data;
    wire guarded_valid, guarded_last, guarded_ready;
    wire ingress_complete, ingress_oversize, ingress_timeout, ingress_short;
    wire [4:0] decoder_errors;
    afdx_rx_ingress_guard #(.IDLE_TIMEOUT_CYCLES(RX_IDLE_TIMEOUT_CYCLES)) u_ingress_guard (
        .sys_clk(sys_clk),.sys_rst_n(sys_rst_n),
        .in_data(rx_data),.in_valid(rx_valid),.in_last(rx_last),.in_ready(rx_ready),
        .out_data(guarded_data),.out_valid(guarded_valid),.out_last(guarded_last),.out_ready(guarded_ready),
        .complete_event(ingress_complete),.oversize_event(ingress_oversize),
        .timeout_event(ingress_timeout),.short_event(ingress_short));
    assign rx_events = {rx_valid && !rx_ready && sys_rst_n, decoder_errors[4],
        decoder_errors[3],decoder_errors[2],decoder_errors[1],decoder_errors[0],
        ingress_short,ingress_timeout,ingress_oversize,
        frame_abort || ingress_short || ingress_timeout || ingress_oversize,
        frame_commit,ingress_complete};

    packet_decoder #(
        .LOCAL_DEST_IP(LOCAL_DEST_IP),
        .LOCAL_DEST_PORT(LOCAL_DEST_PORT),
        .ACCEPT_ANY_DEST(ACCEPT_ANY_DEST)
    ) u_packet_decoder (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .rx_data(guarded_data),
        .rx_valid(guarded_valid),
        .rx_last(guarded_last),
        .rx_ready(guarded_ready),
        .frame_capture_start(frame_capture_start),
        .payload_write_valid(payload_write_valid),
        .payload_write_data(payload_write_data),
        .payload_write_ready(payload_write_ready),
        .payload_write_overflow(payload_write_overflow),
        .frame_descriptor_ready(frame_descriptor_ready),
        .frame_commit(frame_commit),
        .frame_abort(frame_abort),
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
        .frame_vl_id(frame_vl_id),
        .frame_sequence_number(frame_sequence_number),
        .frame_payload_length(frame_payload_length),
        .app_rx_data(app_rx_data),
        .app_rx_valid(app_rx_valid),
        .app_rx_last(app_rx_last),
        .app_rx_vl_id(app_rx_vl_id),
        .app_rx_sequence_number(app_rx_sequence_number),
        .app_rx_ready(app_rx_ready)
    );

endmodule
