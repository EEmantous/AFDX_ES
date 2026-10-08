`timescale 1ns/1ps
// V3 standalone end system: one APP interface, one shared TX/SN generator,
// two MAC-side streams, two independent validated RX paths, one identity merge.
// No switch or peer end system is synthesized here. reset is active-high.
module AFDX_top #(
    // 1 ms at the documented 80 ns MAC-stream clock; retune with clock changes.
    parameter integer BAG_CYCLES = 12500,//发送帧之间的最小间隔 单位为时钟周期
    parameter integer DEDUP_WINDOW_CYCLES = 100000,// 冗余消重记录的保留时间？
    parameter integer HISTORY_DEPTH = 64,//消重历史表
    parameter integer RX_IDLE_TIMEOUT_CYCLES = 12500,//RX收到一部分帧后允许没有新数据的最长时间
    parameter integer TX_IDLE_TIMEOUT_CYCLES = 12500,//TX
    parameter [47:0] DEST_MAC = 48'h0300_0000_0101,//目的MAC地址
    parameter [47:0] SRC_MAC = 48'h0200_0000_0001,//源MAC地址
    parameter [31:0] SRC_IP = 32'hC0A8_0001,//源IP地址
    parameter [31:0] DEST_IP = 32'hC0A8_0003,//目的IP地址
    parameter [15:0] SRC_PORT = 16'd10001,//发出port端口
    parameter [15:0] DEST_PORT = 16'd20003,//目的port端口
    parameter [31:0] LOCAL_DEST_IP = 32'hC0A_80003,//接收时允许的目的IP
    parameter [15:0] LOCAL_DEST_PORT = 16'd20003,//接收时允许的UDP
    parameter ACCEPT_ANY_DEST = 1'b0
) (
    input wire clk, reset,
    input wire [7:0] app_tx_data,
    input wire app_tx_valid, app_tx_last,
    output wire app_tx_ready,
    output wire [7:0] app_rx_data,
    output wire app_rx_valid, app_rx_last,
    input wire app_rx_ready,
    output wire [15:0] app_rx_vl_id,//当前帧所属的VL号
    output wire [7:0] app_rx_sequence_number,//当前帧所属的序列号

    output wire [7:0] tx_a_data,
    output wire tx_a_valid, tx_a_last,
    input wire tx_a_ready,
    input wire [7:0] rx_a_data,
    input wire rx_a_valid, rx_a_last,
    output wire rx_a_ready,
    output wire [7:0] tx_b_data,
    output wire tx_b_valid, tx_b_last,
    input wire tx_b_ready,
    input wire [7:0] rx_b_data,
    input wire rx_b_valid, rx_b_last,
    output wire rx_b_ready,
    input wire [7:0] stats_addr,
    input wire stats_clear,
    output wire [31:0] stats_rdata,
    output wire stats_error
);
    wire sys_rst_n = !reset;
    wire shared_app_ready;
    wire [7:0] core_data;
    wire core_valid, core_last, core_ready;
    wire [7:0] a_payload, b_payload;
    wire a_valid, a_last, a_ready, b_valid, b_last, b_ready;
    wire [15:0] a_vl_id, b_vl_id;
    wire [7:0] a_sn, b_sn;
    wire [11:0] a_rx_events, b_rx_events;
    wire tx_oversize, merge_duplicate_a, merge_duplicate_b;
    wire [35:0] stats_events;
    assign stats_events = {app_tx_valid && !app_tx_ready && sys_rst_n,
        app_rx_valid && app_rx_ready && app_rx_last,merge_duplicate_b,merge_duplicate_a,
        b_rx_events,a_rx_events,2'b00,tx_oversize,2'b00,
        tx_b_valid && tx_b_ready && tx_b_last,tx_a_valid && tx_a_ready && tx_a_last,
        app_tx_valid && app_tx_ready && app_tx_last};
    afdx_es_stats #(.APP_IDLE_TIMEOUT_CYCLES(TX_IDLE_TIMEOUT_CYCLES)) u_stats (
        .sys_clk(clk),.sys_rst_n(sys_rst_n),.events(stats_events),
        .app_tx_valid(app_tx_valid),.app_tx_ready(app_tx_ready),.app_tx_last(app_tx_last),
        .clear(stats_clear),.read_addr(stats_addr),.read_data(stats_rdata),.read_error(stats_error));
    // A/B always participate; only the common reset controls their lifetime.
    // Statistics addresses 0x0C/0x10 remain reserved and receive no events.
    assign app_tx_ready = shared_app_ready;

    afdx_redundant_tx_fanout #(.BAG_CYCLES(BAG_CYCLES)) u_fanout (
        .sys_clk(clk),.sys_rst_n(sys_rst_n),
        .in_data(core_data),.in_valid(core_valid),.in_last(core_last),.in_ready(core_ready),
        .a_data(tx_a_data),.a_valid(tx_a_valid),.a_last(tx_a_last),.a_ready(tx_a_ready),
        .b_data(tx_b_data),.b_valid(tx_b_valid),.b_last(tx_b_last),.b_ready(tx_b_ready),
        .oversize_event(tx_oversize));

    afdx_es_tx #(.BAG_CYCLES(BAG_CYCLES),.DEST_MAC(DEST_MAC),.SRC_MAC(SRC_MAC),
        .SRC_IP(SRC_IP),.DEST_IP(DEST_IP),.SRC_PORT(SRC_PORT),.DEST_PORT(DEST_PORT)) u_tx (
        .sys_clk(clk),.sys_rst_n(sys_rst_n),.app_tx_data(app_tx_data),
        .app_tx_valid(app_tx_valid),
        .app_tx_last(app_tx_last),.app_tx_ready(shared_app_ready),
        .tx_data(core_data),.tx_valid(core_valid),.tx_last(core_last),.tx_ready(core_ready));
    afdx_es_rx #(.LOCAL_DEST_IP(LOCAL_DEST_IP),.LOCAL_DEST_PORT(LOCAL_DEST_PORT),.ACCEPT_ANY_DEST(ACCEPT_ANY_DEST),.RX_IDLE_TIMEOUT_CYCLES(RX_IDLE_TIMEOUT_CYCLES)) u_rx_a (
        .sys_clk(clk),.sys_rst_n(sys_rst_n),.rx_data(rx_a_data),.rx_valid(rx_a_valid),.rx_last(rx_a_last),.rx_ready(rx_a_ready),
        .app_rx_data(a_payload),.app_rx_valid(a_valid),.app_rx_last(a_last),.app_rx_ready(a_ready),
        .app_rx_vl_id(a_vl_id),.app_rx_sequence_number(a_sn),.rx_events(a_rx_events));
    afdx_es_rx #(.LOCAL_DEST_IP(LOCAL_DEST_IP),.LOCAL_DEST_PORT(LOCAL_DEST_PORT),.ACCEPT_ANY_DEST(ACCEPT_ANY_DEST),.RX_IDLE_TIMEOUT_CYCLES(RX_IDLE_TIMEOUT_CYCLES)) u_rx_b (
        .sys_clk(clk),.sys_rst_n(sys_rst_n),.rx_data(rx_b_data),.rx_valid(rx_b_valid),.rx_last(rx_b_last),.rx_ready(rx_b_ready),
        .app_rx_data(b_payload),.app_rx_valid(b_valid),.app_rx_last(b_last),.app_rx_ready(b_ready),
        .app_rx_vl_id(b_vl_id),.app_rx_sequence_number(b_sn),.rx_events(b_rx_events));
    afdx_ab_frame_selector #(.DEDUP_WINDOW_CYCLES(DEDUP_WINDOW_CYCLES),.HISTORY_DEPTH(HISTORY_DEPTH)) u_merge (
        .sys_clk(clk),.sys_rst_n(sys_rst_n),
        .a_data(a_payload),.a_valid(a_valid),.a_last(a_last),.a_ready(a_ready),.a_vl_id(a_vl_id),.a_sequence_number(a_sn),
        .b_data(b_payload),.b_valid(b_valid),.b_last(b_last),.b_ready(b_ready),.b_vl_id(b_vl_id),.b_sequence_number(b_sn),
        .out_data(app_rx_data),.out_valid(app_rx_valid),.out_last(app_rx_last),.out_ready(app_rx_ready),
        .out_vl_id(app_rx_vl_id),.out_sequence_number(app_rx_sequence_number),
        .duplicate_a_event(merge_duplicate_a),.duplicate_b_event(merge_duplicate_b));
endmodule
