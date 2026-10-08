`timescale 1ns/1ps
// Bound the MAC-side candidate before the protocol parser sees any bytes.
// A rejected stream is drained to last or an idle boundary. Idle timeout only
// runs while accepting an unfinished frame, never while output is stalled.
module afdx_rx_ingress_guard #(
    parameter integer MAX_FRAME_BYTES = 1514,
    parameter integer MIN_FRAME_BYTES = 60,
    parameter integer IDLE_TIMEOUT_CYCLES = 12500,
    parameter integer POINTER_WIDTH = 11
)(
    input wire sys_clk, sys_rst_n,
    input wire [7:0] in_data,
    input wire in_valid, in_last,
    output wire in_ready,
    output wire [7:0] out_data,
    output wire out_valid, out_last,
    input wire out_ready,
    output wire complete_event, oversize_event, timeout_event, short_event
);
    reg [7:0] memory [0:MAX_FRAME_BYTES-1];
    reg [POINTER_WIDTH-1:0] capture_count, frame_length, read_pointer;
    reg capturing, dropping, complete;
    localparam integer TIMEOUT_WIDTH = IDLE_TIMEOUT_CYCLES <= 1 ? 1 : $clog2(IDLE_TIMEOUT_CYCLES);
    reg [TIMEOUT_WIDTH-1:0] idle_count;
    wire transfer = in_valid && in_ready;
    wire idle_expired = sys_rst_n && capturing && !complete && !in_valid &&
                        (idle_count == IDLE_TIMEOUT_CYCLES-1);
    assign in_ready = sys_rst_n && !complete;
    assign out_valid = sys_rst_n && complete;
    assign out_data = memory[read_pointer];
    assign out_last = out_valid && (read_pointer == frame_length-1'b1);
    // The MAXth byte without last already proves that this frame is too long.
    assign oversize_event = transfer && !dropping && !in_last &&
                            (capture_count == MAX_FRAME_BYTES-1);
    assign short_event = transfer && !dropping && in_last &&
                         (capture_count < MIN_FRAME_BYTES-1);
    assign timeout_event = idle_expired && !dropping;
    assign complete_event = transfer && !dropping && in_last &&
                            (capture_count >= MIN_FRAME_BYTES-1);
    always @(posedge sys_clk) begin
        if (transfer && !dropping) memory[capture_count] <= in_data;
    end
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            capture_count <= 0; frame_length <= 0; read_pointer <= 0;
            capturing <= 0; dropping <= 0; complete <= 0; idle_count <= 0;
        end else begin
            if (out_valid && out_ready) begin
                if (out_last) begin complete <= 0; read_pointer <= 0; end
                else read_pointer <= read_pointer+1'b1;
            end
            if (transfer) begin
                idle_count <= 0;
                if (in_last) begin
                    capturing <= 0; dropping <= 0; capture_count <= 0;
                    if (complete_event) begin
                        complete <= 1; frame_length <= capture_count+1'b1;
                        read_pointer <= 0;
                    end
                end else begin
                    capturing <= 1;
                    if (oversize_event) begin dropping <= 1; capture_count <= 0; end
                    else if (!dropping) capture_count <= capture_count+1'b1;
                end
            end else if (idle_expired) begin
                // Oversize was counted on entry to drain: do not count it twice.
                capturing <= 0; dropping <= 0; capture_count <= 0; idle_count <= 0;
            end else if (capturing && !complete && !in_valid)
                idle_count <= idle_count+1'b1;
        end
    end
endmodule
