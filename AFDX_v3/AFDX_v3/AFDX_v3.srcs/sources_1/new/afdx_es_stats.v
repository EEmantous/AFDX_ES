`timescale 1ns/1ps
// Internal, read-only 32-bit saturating event counters. Clear has priority.
// TX APP monitor reports malformed input; it does not discard/repair TX frames.
module afdx_es_stats #(
    parameter integer APP_IDLE_TIMEOUT_CYCLES = 12500
)(
    input wire sys_clk, sys_rst_n,
    input wire [35:0] events,
    input wire app_tx_valid, app_tx_ready, app_tx_last,
    input wire clear,
    input wire [7:0] read_addr,
    output reg [31:0] read_data,
    output wire read_error
);
    localparam integer COUNTER_COUNT = 36;
    localparam integer TIMEOUT_WIDTH = APP_IDLE_TIMEOUT_CYCLES <= 1 ? 1 : $clog2(APP_IDLE_TIMEOUT_CYCLES);
    reg [31:0] counters [0:COUNTER_COUNT-1];
    reg [10:0] tx_app_bytes;
    reg tx_partial, tx_oversize_seen, tx_timeout_seen;
    reg [TIMEOUT_WIDTH-1:0] tx_idle_count;
    wire tx_transfer = app_tx_valid && app_tx_ready;
    wire tx_oversize_event = tx_transfer && !tx_oversize_seen && tx_app_bytes == 1471;
    wire tx_timeout_event = tx_partial && !tx_timeout_seen && app_tx_ready &&
                            !app_tx_valid && tx_idle_count == APP_IDLE_TIMEOUT_CYCLES-1;
    wire [35:0] all_events = events | {28'd0,tx_timeout_event,tx_oversize_event,6'd0};
    integer i;
    assign read_error = (read_addr[1:0] != 0) || (read_addr[7:2] >= COUNTER_COUNT);
    always @* begin
        read_data = 0;
        if (!read_error) read_data = counters[read_addr[7:2]];
    end
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            for (i=0;i<COUNTER_COUNT;i=i+1) counters[i] <= 0;
        end else if (clear) begin
            for (i=0;i<COUNTER_COUNT;i=i+1) counters[i] <= 0;
        end else begin
            for (i=0;i<COUNTER_COUNT;i=i+1)
                if (all_events[i] && counters[i] != 32'hffffffff)
                    counters[i] <= counters[i]+1'b1;
        end
    end
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            tx_app_bytes <= 0; tx_partial <= 0;
            tx_oversize_seen <= 0; tx_timeout_seen <= 0; tx_idle_count <= 0;
        end else if (tx_transfer) begin
            tx_idle_count <= 0;
            if (app_tx_last) begin
                tx_app_bytes <= 0; tx_partial <= 0;
                tx_oversize_seen <= 0; tx_timeout_seen <= 0;
            end else begin
                tx_partial <= 1;
                if (tx_app_bytes < 1472) tx_app_bytes <= tx_app_bytes+1'b1;
                if (tx_oversize_event) tx_oversize_seen <= 1;
            end
        end else if (tx_timeout_event) tx_timeout_seen <= 1;
        else if (tx_partial && !tx_timeout_seen && app_tx_ready && !app_tx_valid)
            tx_idle_count <= tx_idle_count+1'b1;
    end
endmodule
