`timescale 1ns/1ps

// Store one complete core frame once; both planes have independent cursors.
// Each legal frame must finish on both outputs before the buffer is reused.
module afdx_redundant_tx_fanout #(
    parameter integer MAX_FRAME_BYTES = 1514,
    parameter integer POINTER_WIDTH = 11,
    parameter integer BAG_CYCLES = 400000
) (
    input wire sys_clk, sys_rst_n,
    input wire [7:0] in_data,
    input wire in_valid, in_last,
    output wire in_ready,
    output wire [7:0] a_data,
    output wire a_valid, a_last,
    input wire a_ready,
    output wire [7:0] b_data,
    output wire b_valid, b_last,
    input wire b_ready,
    output wire oversize_event
);
    reg [7:0] memory [0:MAX_FRAME_BYTES-1];
    reg [POINTER_WIDTH-1:0] capture_count, frame_length;
    reg [POINTER_WIDTH-1:0] a_pointer, b_pointer;
    reg a_pending, b_pending, complete, discard;
    localparam BAG_WIDTH = BAG_CYCLES <= 1 ? 1 : $clog2(BAG_CYCLES);
    reg [BAG_WIDTH-1:0] a_cooldown, b_cooldown;
    assign oversize_event = sys_rst_n && in_valid && in_ready && !discard &&
        capture_count == MAX_FRAME_BYTES-1 && !in_last;
    assign in_ready = sys_rst_n && !complete;
    // Recheck BAG at each actual plane's first handshake. Store-and-forward
    // capture latency varies with length and must not shorten the wire BAG.
    assign a_valid = sys_rst_n && complete && a_pending &&
                     (a_pointer != 0 || a_cooldown == 0);
    assign b_valid = sys_rst_n && complete && b_pending &&
                     (b_pointer != 0 || b_cooldown == 0);
    assign a_data = memory[a_pointer];
    assign b_data = memory[b_pointer];
    assign a_last = a_valid && (a_pointer == frame_length-1'b1);
    assign b_last = b_valid && (b_pointer == frame_length-1'b1);
    // Keep RAM writes in a clock-only process; asynchronous reset applies to
    // ownership/pointers, never to payload RAM, so EDA can infer memory.
    always @(posedge sys_clk)
        if (in_valid && in_ready && !discard && capture_count < MAX_FRAME_BYTES)
            memory[capture_count] <= in_data;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            capture_count <= 0; frame_length <= 0;
            a_pointer <= 0; b_pointer <= 0;
            a_pending <= 0; b_pending <= 0; complete <= 0; discard <= 0;
            a_cooldown <= 0; b_cooldown <= 0;
        end else begin
            if (a_cooldown != 0) a_cooldown <= a_cooldown-1'b1;
            if (b_cooldown != 0) b_cooldown <= b_cooldown-1'b1;
            if (in_valid && in_ready) begin
                if (in_last) begin
                    capture_count <= 0;
                    discard <= 0;
                    if (!discard && capture_count < MAX_FRAME_BYTES) begin
                        frame_length <= capture_count + 1'b1;
                        a_pointer <= 0; b_pointer <= 0;
                        a_pending <= 1;
                        b_pending <= 1;
                        complete <= 1;
                    end
                end else if (!discard) begin
                    if (capture_count == MAX_FRAME_BYTES-1) discard <= 1;
                    else capture_count <= capture_count + 1'b1;
                end
            end
            if (a_valid && a_ready) begin
                if (a_pointer == 0) a_cooldown <= BAG_CYCLES-1;
                if (a_last) a_pending <= 0;
                else a_pointer <= a_pointer + 1'b1;
            end
            if (b_valid && b_ready) begin
                if (b_pointer == 0) b_cooldown <= BAG_CYCLES-1;
                if (b_last) b_pending <= 0;
                else b_pointer <= b_pointer + 1'b1;
            end
            if (complete && !a_pending && !b_pending) complete <= 0;
        end
    end
endmodule
