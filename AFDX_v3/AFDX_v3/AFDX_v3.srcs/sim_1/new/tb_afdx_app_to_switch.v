`timescale 1ns / 1ps

// 通路一：APP -> afdx_es_tx -> AFDX交换机发送接口。
module tb_afdx_app_to_switch;
    localparam integer MAX_EXPECTED_FRAMES = 64;
    localparam integer STRESS_FRAME_COUNT = 32;
    localparam integer WAIT_LIMIT = 200000;

    reg sys_clk;
    reg sys_rst_n;
    reg [7:0] app_tx_data;
    reg app_tx_valid;
    reg app_tx_last;
    wire app_tx_ready;
    wire [7:0] tx_data;
    wire tx_valid;
    wire tx_last;
    reg tx_ready;

    reg [10:0] expected_payload_length [0:MAX_EXPECTED_FRAMES-1];
    integer expected_frame_count;
    integer transmitted_frame_count;
    integer network_byte_index;
    integer current_frame_number;
    integer stress_index;
    integer wait_cycles;
    integer error_count;
    integer padded_payload_length;
    integer expected_network_length;

    reg [3:0] switch_backpressure_cycle;
    reg previous_cycle_stalled;
    reg [7:0] stalled_tx_data;
    reg stalled_tx_last;
    reg [7:0] expected_network_data;
    reg expected_network_last;

    afdx_es_tx #(
        .BAG_CYCLES(4)
    ) dut (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .app_tx_data(app_tx_data),
        .app_tx_valid(app_tx_valid),
        .app_tx_last(app_tx_last),
        .app_tx_ready(app_tx_ready),
        .tx_data(tx_data),
        .tx_valid(tx_valid),
        .tx_last(tx_last),
        .tx_ready(tx_ready)
    );

    initial begin
        sys_clk = 1'b0;
        forever #5 sys_clk = ~sys_clk;
    end

    always @(negedge sys_clk) begin
        if (!sys_rst_n) begin
            switch_backpressure_cycle <= 4'd0;
            tx_ready <= 1'b0;
        end else begin
            if (switch_backpressure_cycle == 4'd10)
                switch_backpressure_cycle <= 4'd0;
            else
                switch_backpressure_cycle <=
                    switch_backpressure_cycle + 1'b1;
            tx_ready <= !((switch_backpressure_cycle == 4'd2) ||
                          (switch_backpressure_cycle == 4'd3) ||
                          (switch_backpressure_cycle == 4'd8));
        end
    end

    function [7:0] payload_pattern;
        input integer frame_number;
        input integer byte_number;
        begin
            payload_pattern = 8'h5A + frame_number * 8'd29 +
                              byte_number * 8'd17;
        end
    endfunction

    function [15:0] calculate_ip_checksum;
        input integer raw_payload_length;
        integer padded_length;
        reg [15:0] udp_length;
        reg [15:0] ip_total_length;
        reg [31:0] checksum_sum;
        reg [16:0] checksum_fold_1;
        reg [16:0] checksum_fold_2;
        begin
            padded_length = (raw_payload_length < 17) ?
                            17 : raw_payload_length;
            udp_length = 16'd8 + padded_length + 16'd1;
            ip_total_length = 16'd20 + udp_length;
            checksum_sum = 32'h0000_4500 + {16'd0, ip_total_length} +
                           32'h0000_0000 + 32'h0000_4000 +
                           32'h0000_4011 + 32'h0000_C0A8 +
                           32'h0000_0001 + 32'h0000_E000 +
                           32'h0000_0001;
            checksum_fold_1 = checksum_sum[15:0] + checksum_sum[31:16];
            checksum_fold_2 = checksum_fold_1[15:0] +
                              checksum_fold_1[16];
            calculate_ip_checksum = ~checksum_fold_2[15:0];
        end
    endfunction

    function [7:0] expected_header_byte;
        input integer header_byte_index;
        input integer raw_payload_length;
        integer padded_length;
        reg [15:0] udp_length;
        reg [15:0] ip_total_length;
        reg [15:0] ip_checksum;
        begin
            padded_length = (raw_payload_length < 17) ?
                            17 : raw_payload_length;
            udp_length = 16'd8 + padded_length + 16'd1;
            ip_total_length = 16'd20 + udp_length;
            ip_checksum = calculate_ip_checksum(raw_payload_length);
            case (header_byte_index)
                0: expected_header_byte=8'h03;  1: expected_header_byte=8'h00;
                2: expected_header_byte=8'h00;  3: expected_header_byte=8'h00;
                4: expected_header_byte=8'h00;  5: expected_header_byte=8'h01;
                6: expected_header_byte=8'h00;  7: expected_header_byte=8'h11;
                8: expected_header_byte=8'h22;  9: expected_header_byte=8'h33;
                10: expected_header_byte=8'h44; 11: expected_header_byte=8'h55;
                12: expected_header_byte=8'h08; 13: expected_header_byte=8'h00;
                14: expected_header_byte=8'h45; 15: expected_header_byte=8'h00;
                16: expected_header_byte=ip_total_length[15:8];
                17: expected_header_byte=ip_total_length[7:0];
                18: expected_header_byte=8'h00; 19: expected_header_byte=8'h00;
                20: expected_header_byte=8'h40; 21: expected_header_byte=8'h00;
                22: expected_header_byte=8'h40; 23: expected_header_byte=8'h11;
                24: expected_header_byte=ip_checksum[15:8];
                25: expected_header_byte=ip_checksum[7:0];
                26: expected_header_byte=8'hC0; 27: expected_header_byte=8'hA8;
                28: expected_header_byte=8'h00; 29: expected_header_byte=8'h01;
                30: expected_header_byte=8'hE0; 31: expected_header_byte=8'h00;
                32: expected_header_byte=8'h00; 33: expected_header_byte=8'h01;
                34: expected_header_byte=8'h03; 35: expected_header_byte=8'hE8;
                36: expected_header_byte=8'h03; 37: expected_header_byte=8'hE9;
                38: expected_header_byte=udp_length[15:8];
                39: expected_header_byte=udp_length[7:0];
                40: expected_header_byte=8'h00; 41: expected_header_byte=8'h00;
                default: expected_header_byte=8'h00;
            endcase
        end
    endfunction

    task fail_and_finish;
        input [8*160-1:0] failure_message;
        begin
            $display("ERROR APP-TO-SWITCH: %0s", failure_message);
            error_count = error_count + 1;
            $finish;
        end
    endtask

    task register_expected_frame;
        input integer payload_length;
        begin
            if (expected_frame_count >= MAX_EXPECTED_FRAMES)
                fail_and_finish("expected frame table overflow");
            current_frame_number = expected_frame_count;
            expected_payload_length[current_frame_number] =
                payload_length[10:0];
            expected_frame_count = expected_frame_count + 1;
        end
    endtask

    // valid在一个片段内部连续保持，只有ready反压才能插入空闲周期。
    task send_payload_segment;
        input integer frame_number;
        input integer first_byte_index;
        input integer segment_byte_count;
        input integer asserted_last_index;
        integer segment_index;
        integer absolute_byte_index;
        begin
            @(negedge sys_clk);
            app_tx_valid = 1'b1;
            for (segment_index = 0;
                 segment_index < segment_byte_count;
                 segment_index = segment_index + 1) begin
                absolute_byte_index = first_byte_index + segment_index;
                app_tx_data = payload_pattern(frame_number,
                                              absolute_byte_index);
                app_tx_last =
                    (absolute_byte_index == asserted_last_index);
                wait_cycles = 0;
                begin : wait_for_payload_transfer
                    while (1) begin
                        @(posedge sys_clk);
                        if (app_tx_valid && app_tx_ready)
                            disable wait_for_payload_transfer;
                        wait_cycles = wait_cycles + 1;
                        if (wait_cycles > WAIT_LIMIT)
                            fail_and_finish("APP payload timeout");
                    end
                end
                if (segment_index != segment_byte_count - 1)
                    @(negedge sys_clk);
            end
            @(negedge sys_clk);
            app_tx_valid = 1'b0;
            app_tx_last = 1'b0;
        end
    endtask

    task send_complete_frame;
        input integer payload_length;
        integer frame_number;
        begin
            register_expected_frame(payload_length);
            frame_number = current_frame_number;
            send_payload_segment(frame_number, 0,
                                 payload_length, payload_length - 1);
        end
    endtask

    task wait_for_all_frames;
        begin
            wait_cycles = 0;
            while (transmitted_frame_count < expected_frame_count) begin
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > WAIT_LIMIT)
                    fail_and_finish("switch output completion timeout");
                @(posedge sys_clk);
            end
        end
    endtask

    always @(posedge sys_clk) begin
        if (!sys_rst_n) begin
            transmitted_frame_count = 0;
            network_byte_index = 0;
            previous_cycle_stalled = 1'b0;
            stalled_tx_data = 8'd0;
            stalled_tx_last = 1'b0;
        end else begin
            if (previous_cycle_stalled &&
                ((tx_valid !== 1'b1) ||
                 (tx_data !== stalled_tx_data) ||
                 (tx_last !== stalled_tx_last))) begin
                $display("ERROR APP-TO-SWITCH: output changed while tx_ready=0");
                error_count = error_count + 1;
            end

            previous_cycle_stalled = tx_valid && !tx_ready;
            if (tx_valid && !tx_ready) begin
                stalled_tx_data = tx_data;
                stalled_tx_last = tx_last;
            end

            if (tx_valid && tx_ready) begin
                if (transmitted_frame_count >= expected_frame_count)
                    fail_and_finish("unexpected switch output frame");

                padded_payload_length =
                    (expected_payload_length[transmitted_frame_count] < 17) ?
                    17 : expected_payload_length[transmitted_frame_count];
                expected_network_length = 42 + padded_payload_length + 1;

                if (network_byte_index < 42)
                    expected_network_data = expected_header_byte(
                        network_byte_index,
                        expected_payload_length[transmitted_frame_count]);
                else if (network_byte_index <
                         42 + expected_payload_length[transmitted_frame_count])
                    expected_network_data = payload_pattern(
                        transmitted_frame_count, network_byte_index - 42);
                else if (network_byte_index <
                         42 + padded_payload_length)
                    expected_network_data = 8'h00;
                else
                    expected_network_data =
                        (transmitted_frame_count % 255) + 1;

                expected_network_last =
                    (network_byte_index == expected_network_length - 1);
                if ((tx_data !== expected_network_data) ||
                    (tx_last !== expected_network_last)) begin
                    $display("ERROR APP-TO-SWITCH: frame=%0d byte=%0d expected=%02h/%b actual=%02h/%b",
                             transmitted_frame_count, network_byte_index,
                             expected_network_data, expected_network_last,
                             tx_data, tx_last);
                    error_count = error_count + 1;
                end

                if (tx_last) begin
                    transmitted_frame_count = transmitted_frame_count + 1;
                    network_byte_index = 0;
                end else
                    network_byte_index = network_byte_index + 1;
            end
        end
    end

    initial begin
        sys_rst_n = 1'b0;
        app_tx_data = 8'd0;
        app_tx_valid = 1'b0;
        app_tx_last = 1'b0;
        tx_ready = 1'b0;
        switch_backpressure_cycle = 4'd0;
        expected_frame_count = 0;
        error_count = 0;

        repeat (12) @(posedge sys_clk);
        @(negedge sys_clk);
        sys_rst_n = 1'b1;

        // 没有app_tx_last时帧尚未完成，不能提前提交或输出。
        register_expected_frame(8);
        send_payload_segment(current_frame_number, 0, 3, -1);
        repeat (30) @(posedge sys_clk);
        if (tx_valid !== 1'b0)
            fail_and_finish("incomplete APP frame was transmitted");
        send_payload_segment(current_frame_number, 3, 5, 7);
        wait_for_all_frames;

        // 输入长度和last合法性由APP保证；发送端不再测试或丢弃超长帧。
        send_complete_frame(4);

        // app_tx_last是唯一帧界，第三字节拉高即形成合法3字节帧。
        send_complete_frame(3);

        send_complete_frame(1);
        send_complete_frame(16);
        send_complete_frame(17);
        send_complete_frame(18);
        send_complete_frame(1471);

        // 大量连续数据：连续32帧，每帧内部valid无主动气泡。
        for (stress_index = 0;
             stress_index < STRESS_FRAME_COUNT;
             stress_index = stress_index + 1)
            send_complete_frame(32 + ((stress_index * 23) % 97));

        wait_for_all_frames;
        repeat (20) @(posedge sys_clk);
        if (tx_valid === 1'b1)
            fail_and_finish("unexpected output after all frames");

        if (error_count == 0)
            $display("ALL APP-TO-SWITCH TESTS PASSED: frames=%0d stress_frames=%0d",
                     transmitted_frame_count, STRESS_FRAME_COUNT);
        else
            $display("APP-TO-SWITCH TEST FAILED: errors=%0d", error_count);
        $finish;
    end

    initial begin
        #20000000;
        $display("ERROR APP-TO-SWITCH: simulation timeout");
        $finish;
    end
endmodule
