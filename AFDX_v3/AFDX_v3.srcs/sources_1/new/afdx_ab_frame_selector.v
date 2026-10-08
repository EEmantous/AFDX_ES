`timescale 1ns/1ps

// Merge validated payload frames using their full (VLID,SN) identity.
// Each plane owns one complete-frame buffer; unrelated frames are preserved.
// First complete candidate wins (A on a tie), including during APP stalls.
// History is reserved BEFORE delivery. Live history is never evicted: a full
// table backpressures new identities until an entry expires. Duplicates drain.
// Lookup scans HISTORY_DEPTH entries (one per cycle), with early duplicate exit.
// WINDOW must be shorter than the minimum time to reuse an SN on the same VL.
module afdx_ab_frame_selector #(
    parameter integer MAX_FRAME_BYTES = 1471,
    parameter integer POINTER_WIDTH = 11,
    parameter integer DEDUP_WINDOW_CYCLES = 100000,
    parameter integer HISTORY_DEPTH = 64
) (
    input wire sys_clk, sys_rst_n,
    input wire [7:0] a_data,
    input wire a_valid, a_last,
    output wire a_ready,
    input wire [7:0] b_data,
    input wire b_valid, b_last,
    output wire b_ready,
    output wire [7:0] out_data,
    output wire out_valid, out_last,
    input wire out_ready,
    input wire [15:0] a_vl_id,
    input wire [7:0] a_sequence_number,
    input wire [15:0] b_vl_id,
    input wire [7:0] b_sequence_number,
    output wire [15:0] out_vl_id,
    output wire [7:0] out_sequence_number,
    output wire duplicate_a_event, duplicate_b_event
);
    reg [7:0] a_memory [0:MAX_FRAME_BYTES-1];
    reg [7:0] b_memory [0:MAX_FRAME_BYTES-1];
    reg [POINTER_WIDTH-1:0] a_count, b_count, a_length, b_length, out_pointer;
    reg a_full, b_full, a_discard, b_discard;
    reg [15:0] a_vl, b_vl;
    reg [7:0] a_sn, b_sn;
    reg output_active, select_a;
    reg [31:0] cycle_count;
    reg [31:0] a_arrival, b_arrival;
    reg [HISTORY_DEPTH-1:0] history_valid;
    reg [15:0] history_vl [0:HISTORY_DEPTH-1];
    reg [7:0] history_sn [0:HISTORY_DEPTH-1];
    reg [31:0] history_time [0:HISTORY_DEPTH-1];
    localparam HISTORY_INDEX_WIDTH = HISTORY_DEPTH <= 1 ? 1 : $clog2(HISTORY_DEPTH);
    reg [HISTORY_INDEX_WIDTH-1:0] sweep_index, search_index, free_index, active_slot;
    reg search_active, search_a, search_duplicate, free_valid;
    reg [15:0] search_vl;
    reg [7:0] search_sn;
    reg candidate_a, candidate_valid;
    reg [15:0] candidate_vl;
    reg [7:0] candidate_sn;
    wire scan_live = history_valid[search_index] &&
        ((output_active && search_index == active_slot) ||
         (cycle_count-history_time[search_index]) < DEDUP_WINDOW_CYCLES);
    wire scan_match = scan_live && history_vl[search_index] == search_vl &&
                      history_sn[search_index] == search_sn;
    wire search_reject = search_duplicate || scan_match || search_sn == 0;
    assign duplicate_a_event = sys_rst_n && search_active && (search_duplicate || scan_match) && search_a;
    assign duplicate_b_event = sys_rst_n && search_active && (search_duplicate || scan_match) && !search_a;
    wire reserve_history = search_active && !search_reject &&
        search_index == HISTORY_DEPTH-1 && !output_active && (free_valid || !scan_live);
    wire [HISTORY_INDEX_WIDTH-1:0] reserve_index = free_valid ? free_index : search_index;
    wire a_candidate = a_full && !(output_active && select_a);
    wire b_candidate = b_full && !(output_active && !select_a);
    assign a_ready = sys_rst_n && !a_full;
    assign b_ready = sys_rst_n && !b_full;
    assign out_valid = sys_rst_n && output_active;
    assign out_data = select_a ? a_memory[out_pointer] : b_memory[out_pointer];
    // Sideband follows the same locked buffer as the payload for the full frame.
    assign out_vl_id = select_a ? a_vl : b_vl;
    assign out_sequence_number = select_a ? a_sn : b_sn;
    assign out_last = out_valid && (out_pointer ==
                     (select_a ? a_length : b_length)-1'b1);
    always @(posedge sys_clk) begin
        if (a_valid && a_ready && !a_discard && a_count < MAX_FRAME_BYTES)
            a_memory[a_count] <= a_data;
        if (b_valid && b_ready && !b_discard && b_count < MAX_FRAME_BYTES)
            b_memory[b_count] <= b_data;
    end
    always @* begin
        candidate_a = a_candidate && (!b_candidate ||
                      (cycle_count-a_arrival) >= (cycle_count-b_arrival));
        candidate_valid = a_candidate || b_candidate;
        candidate_vl = candidate_a ? a_vl : b_vl;
        candidate_sn = candidate_a ? a_sn : b_sn;
    end

    // One history entry per clock, instead of a 64-way timestamp/priority
    // combinational chain. Payload buffers remain locked during the lookup.
    // Two asynchronous timestamp reads support lookup and background expiry.
    always @(posedge sys_clk) begin
        if (sys_rst_n && reserve_history) begin
            history_vl[reserve_index] <= search_vl;
            history_sn[reserve_index] <= search_sn;
            history_time[reserve_index] <= cycle_count;
        end else if (out_valid && out_ready && out_last)
            history_time[active_slot] <= cycle_count;
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            a_count <= 0; b_count <= 0; a_length <= 0; b_length <= 0;
            a_full <= 0; b_full <= 0; a_discard <= 0; b_discard <= 0;
            a_vl <= 0; b_vl <= 0; a_sn <= 0; b_sn <= 0;
            output_active <= 0; select_a <= 1; out_pointer <= 0;
            cycle_count <= 0; history_valid <= 0;
            a_arrival <= 0; b_arrival <= 0;
            active_slot <= 0; sweep_index <= 0; search_index <= 0; free_index <= 0;
            search_active <= 0; search_a <= 0; search_duplicate <= 0;
            free_valid <= 0; search_vl <= 0; search_sn <= 0;
        end else begin
            cycle_count <= cycle_count + 1'b1;
            // Background expiry prevents stale timestamps resurrecting after
            // counter wrap, even with no arriving candidate frames.
            if (history_valid[sweep_index] && !(output_active && sweep_index == active_slot) &&
                (cycle_count-history_time[sweep_index]) >= DEDUP_WINDOW_CYCLES)
                history_valid[sweep_index] <= 0;
            sweep_index <= sweep_index == HISTORY_DEPTH-1 ? 0 : sweep_index+1'b1;
            if (a_valid && a_ready) begin
                if (a_count == 0 && !a_discard) begin a_vl <= a_vl_id; a_sn <= a_sequence_number; end
                if (a_last) begin
                    a_count <= 0; a_discard <= 0;
                    if (!a_discard && a_count < MAX_FRAME_BYTES) begin
                        a_length <= a_count+1'b1; a_full <= 1; a_arrival <= cycle_count;
                    end
                end else if (!a_discard) begin
                    if (a_count == MAX_FRAME_BYTES-1) a_discard <= 1;
                    else a_count <= a_count+1'b1;
                end
            end
            if (b_valid && b_ready) begin
                if (b_count == 0 && !b_discard) begin b_vl <= b_vl_id; b_sn <= b_sequence_number; end
                if (b_last) begin
                    b_count <= 0; b_discard <= 0;
                    if (!b_discard && b_count < MAX_FRAME_BYTES) begin
                        b_length <= b_count+1'b1; b_full <= 1; b_arrival <= cycle_count;
                    end
                end else if (!b_discard) begin
                    if (b_count == MAX_FRAME_BYTES-1) b_discard <= 1;
                    else b_count <= b_count+1'b1;
                end
            end
            if (!search_active && candidate_valid) begin
                search_active <= 1;
                search_index <= 0;
                free_valid <= 0;
                search_a <= candidate_a;
                search_vl <= candidate_vl;
                search_sn <= candidate_sn;
                search_duplicate <= output_active &&
                    candidate_vl == (select_a ? a_vl : b_vl) &&
                    candidate_sn == (select_a ? a_sn : b_sn);
            end else if (search_active) begin
                if (search_reject) begin
                    search_active <= 0;
                    if (search_a) a_full <= 0;
                    else b_full <= 0;
                end else if (search_index == HISTORY_DEPTH-1) begin
                    search_active <= 0;
                    if (reserve_history) begin
                        history_valid[reserve_index] <= 1;
                        active_slot <= reserve_index;
                        output_active <= 1;
                        select_a <= search_a;
                        out_pointer <= 0;
                    end
                end else begin
                    if (!scan_live && !free_valid) begin free_index <= search_index; free_valid <= 1; end
                    search_index <= search_index+1'b1;
                end
            end
            if (out_valid && out_ready) begin
                if (out_last) begin
                    // Window starts at the completed APP delivery; admission
                    // remains protected for the entire stalled output frame.
                    output_active <= 0;
                    if (select_a) a_full <= 0;
                    else b_full <= 0;
                end else out_pointer <= out_pointer+1'b1;
            end
        end
    end
endmodule
