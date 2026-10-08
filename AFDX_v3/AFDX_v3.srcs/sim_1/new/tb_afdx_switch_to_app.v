`timescale 1ns / 1ps

// 通路二：AFDX交换机接收接口 -> afdx_es_rx -> APP。
module tb_afdx_switch_to_app;
    localparam integer MAX_EXPECTED_FRAMES = 64;
    localparam integer STRESS_FRAME_COUNT = 32;
    localparam integer WAIT_LIMIT = 300000;

    reg sys_clk;
    reg sys_rst_n;
    reg [7:0] rx_data;
    reg rx_valid;
    reg rx_last;
    wire rx_ready;
    wire [7:0] app_rx_data;
    wire app_rx_valid;
    wire app_rx_last;
    reg app_rx_ready;

    reg [10:0] expected_payload_length [0:MAX_EXPECTED_FRAMES-1];
    integer expected_source_frame [0:MAX_EXPECTED_FRAMES-1];
    integer expected_frame_count;
    integer received_frame_count;
    integer app_byte_index;
    integer stress_index;
    integer next_valid_sequence;
    integer wait_cycles;
    integer error_count;

    reg [3:0] app_backpressure_cycle;
    reg previous_cycle_stalled;
    reg [7:0] stalled_app_data;
    reg stalled_app_last;
    reg [7:0] expected_app_data;

    afdx_es_rx dut (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .rx_last(rx_last),
        .rx_ready(rx_ready),
        .app_rx_data(app_rx_data),
        .app_rx_valid(app_rx_valid),
        .app_rx_last(app_rx_last),
        .app_rx_ready(app_rx_ready)
    );

    initial begin
        sys_clk = 1'b0;
        forever #5 sys_clk = ~sys_clk;
    end

    always @(negedge sys_clk) begin
        if (!sys_rst_n) begin
            app_backpressure_cycle <= 4'd0;
            app_rx_ready <= 1'b0;
        end else begin
            if (app_backpressure_cycle == 4'd10)
                app_backpressure_cycle <= 4'd0;
            else
                app_backpressure_cycle <= app_backpressure_cycle + 1'b1;
            app_rx_ready <= !((app_backpressure_cycle == 4'd3) ||
                              (app_backpressure_cycle == 4'd4) ||
                              (app_backpressure_cycle == 4'd5));
        end
    end

    function [7:0] payload_pattern;
        input integer source_frame_number;
        input integer byte_number;
        begin
            payload_pattern = 8'h37 + source_frame_number * 8'd31 +
                              byte_number * 8'd19;
        end
    endfunction

    function [15:0] calculate_ip_checksum;
        input integer declared_payload_length;
        reg [15:0] udp_length;
        reg [15:0] ip_total_length;
        reg [31:0] checksum_sum;
        reg [16:0] checksum_fold_1;
        reg [16:0] checksum_fold_2;
        begin
            udp_length = 16'd8 + declared_payload_length + 16'd1;
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

    function [7:0] network_header_byte;
        input integer header_byte_index;
        input integer declared_payload_length;
        reg [15:0] udp_length;
        reg [15:0] ip_total_length;
        reg [15:0] ip_checksum;
        begin
            udp_length = 16'd8 + declared_payload_length + 16'd1;
            ip_total_length = 16'd20 + udp_length;
            ip_checksum = calculate_ip_checksum(declared_payload_length);
            case (header_byte_index)
                0: network_header_byte=8'h03;  1: network_header_byte=8'h00;
                2: network_header_byte=8'h00;  3: network_header_byte=8'h00;
                4: network_header_byte=8'h00;  5: network_header_byte=8'h01;
                6: network_header_byte=8'h00;  7: network_header_byte=8'h11;
                8: network_header_byte=8'h22;  9: network_header_byte=8'h33;
                10: network_header_byte=8'h44; 11: network_header_byte=8'h55;
                12: network_header_byte=8'h08; 13: network_header_byte=8'h00;
                14: network_header_byte=8'h45; 15: network_header_byte=8'h00;
                16: network_header_byte=ip_total_length[15:8];
                17: network_header_byte=ip_total_length[7:0];
                18: network_header_byte=8'h00; 19: network_header_byte=8'h00;
                20: network_header_byte=8'h40; 21: network_header_byte=8'h00;
                22: network_header_byte=8'h40; 23: network_header_byte=8'h11;
                24: network_header_byte=ip_checksum[15:8];
                25: network_header_byte=ip_checksum[7:0];
                26: network_header_byte=8'hC0; 27: network_header_byte=8'hA8;
                28: network_header_byte=8'h00; 29: network_header_byte=8'h01;
                30: network_header_byte=8'hE0; 31: network_header_byte=8'h00;
                32: network_header_byte=8'h00; 33: network_header_byte=8'h01;
                34: network_header_byte=8'h03; 35: network_header_byte=8'hE8;
                36: network_header_byte=8'h03; 37: network_header_byte=8'hE9;
                38: network_header_byte=udp_length[15:8];
                39: network_header_byte=udp_length[7:0];
                40: network_header_byte=8'h00; 41: network_header_byte=8'h00;
                default: network_header_byte=8'h00;
            endcase
        end
    endfunction

    task fail_and_finish;
        input [8*160-1:0] failure_message;
        begin
            $display("ERROR SWITCH-TO-APP: %0s", failure_message);
            error_count = error_count + 1;
            $finish;
        end
    endtask

    task register_expected_frame;
        input integer source_frame_number;
        input integer payload_length;
        begin
            if (expected_frame_count >= MAX_EXPECTED_FRAMES)
                fail_and_finish("expected frame table overflow");
            expected_source_frame[expected_frame_count] =
                source_frame_number;
            expected_payload_length[expected_frame_count] =
                payload_length[10:0];
            expected_frame_count = expected_frame_count + 1;
        end
    endtask

    // 一帧内部持续保持rx_valid，只有DUT撤销rx_ready时才停顿。
    task send_network_frame;
        input integer source_frame_number;
        input integer declared_payload_length;
        input integer actual_payload_length;
        input integer sequence_number;
        input expect_app_delivery;
        integer network_byte_index;
        integer total_network_length;
        begin
            if (expect_app_delivery)
                register_expected_frame(source_frame_number,
                                        declared_payload_length);

            total_network_length = 42 + actual_payload_length + 1;
            @(negedge sys_clk);
            rx_valid = 1'b1;
            for (network_byte_index = 0;
                 network_byte_index < total_network_length;
                 network_byte_index = network_byte_index + 1) begin
                if (network_byte_index < 42)
                    rx_data = network_header_byte(
                        network_byte_index, declared_payload_length);
                else if (network_byte_index <
                         42 + actual_payload_length)
                    rx_data = payload_pattern(
                        source_frame_number, network_byte_index - 42);
                else
                    rx_data = sequence_number[7:0];
                rx_last =
                    (network_byte_index == total_network_length - 1);

                // Only advance after a rising-edge handshake. Waiting for ready
                // on falling edges can miss a transfer when ready changes in NBA.
                wait_cycles = 0;
                begin : wait_for_rx_transfer
                    while (1) begin
                        @(posedge sys_clk);
                        if (rx_ready === 1'b1)
                            disable wait_for_rx_transfer;
                        wait_cycles = wait_cycles + 1;
                        if (wait_cycles > WAIT_LIMIT)
                            fail_and_finish("RX input handshake timeout");
                    end
                end
                if (network_byte_index != total_network_length - 1)
                    @(negedge sys_clk);
            end
            @(negedge sys_clk);
            rx_valid = 1'b0;
            rx_last = 1'b0;
        end
    endtask

    task confirm_no_app_frame;
        input integer observation_cycles;
        integer observation_index;
        begin
            for (observation_index = 0;
                 observation_index < observation_cycles;
                 observation_index = observation_index + 1) begin
                @(posedge sys_clk);
                if (app_rx_valid === 1'b1)
                    fail_and_finish("invalid network frame reached APP");
            end
        end
    endtask

    task wait_for_all_frames;
        begin
            wait_cycles = 0;
            while (received_frame_count < expected_frame_count) begin
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > WAIT_LIMIT)
                    fail_and_finish("APP output completion timeout");
                @(posedge sys_clk);
            end
        end
    endtask

    always @(posedge sys_clk) begin
        if (!sys_rst_n) begin
            received_frame_count = 0;
            app_byte_index = 0;
            previous_cycle_stalled = 1'b0;
            stalled_app_data = 8'd0;
            stalled_app_last = 1'b0;
        end else begin
            if (previous_cycle_stalled &&
                ((app_rx_valid !== 1'b1) ||
                 (app_rx_data !== stalled_app_data) ||
                 (app_rx_last !== stalled_app_last))) begin
                $display("ERROR SWITCH-TO-APP: output changed while app_rx_ready=0");
                error_count = error_count + 1;
            end

            previous_cycle_stalled = app_rx_valid && !app_rx_ready;
            if (app_rx_valid && !app_rx_ready) begin
                stalled_app_data = app_rx_data;
                stalled_app_last = app_rx_last;
            end

            if (app_rx_valid && app_rx_ready) begin
                if (received_frame_count >= expected_frame_count)
                    fail_and_finish("unexpected APP output frame");
                expected_app_data = payload_pattern(
                    expected_source_frame[received_frame_count],
                    app_byte_index);
                if ((app_rx_data !== expected_app_data) ||
                    (app_rx_last !==
                     (app_byte_index ==
                      expected_payload_length[received_frame_count] - 1))) begin
                    $display("ERROR SWITCH-TO-APP: frame=%0d byte=%0d expected=%02h/%b actual=%02h/%b",
                             received_frame_count, app_byte_index,
                             expected_app_data,
                             app_byte_index ==
                                 expected_payload_length[received_frame_count] - 1,
                             app_rx_data, app_rx_last);
                    error_count = error_count + 1;
                end

                if (app_rx_last) begin
                    received_frame_count = received_frame_count + 1;
                    app_byte_index = 0;
                end else
                    app_byte_index = app_byte_index + 1;
            end
        end
    end

    initial begin
        sys_rst_n = 1'b0;
        rx_data = 8'd0;
        rx_valid = 1'b0;
        rx_last = 1'b0;
        app_rx_ready = 1'b0;
        app_backpressure_cycle = 4'd0;
        expected_frame_count = 0;
        next_valid_sequence = 1;
        error_count = 0;

        repeat (12) @(posedge sys_clk);
        @(negedge sys_clk);
        sys_rst_n = 1'b1;

        // 字节不足：头部声明20字节载荷，实际只有19字节，必须整帧回滚。
        send_network_frame(100, 20, 19, 8'h77, 1'b0);
        confirm_no_app_frame(20);

        // 字节超载：实际载荷比头部声明多1字节，必须整帧回滚。
        send_network_frame(101, 20, 21, 8'h78, 1'b0);
        confirm_no_app_frame(20);

        // 超过最大核心帧长度：1472字节载荷不得交给APP。
        send_network_frame(102, 1471, 1472, 8'h79, 1'b0);
        confirm_no_app_frame(20);

        // 合法边界帧，验证错误帧回滚后接收链路仍可继续使用。
        send_network_frame(0, 17, 17, next_valid_sequence, 1'b1);
        next_valid_sequence = next_valid_sequence + 1;
        send_network_frame(1, 18, 18, next_valid_sequence, 1'b1);
        next_valid_sequence = next_valid_sequence + 1;
        send_network_frame(2, 1471, 1471, next_valid_sequence, 1'b1);
        next_valid_sequence = next_valid_sequence + 1;

        // 大量连续数据：32帧连续输入，APP端同时周期性反压。
        for (stress_index = 0;
             stress_index < STRESS_FRAME_COUNT;
             stress_index = stress_index + 1) begin
            send_network_frame(3 + stress_index,
                               32 + ((stress_index * 29) % 97),
                               32 + ((stress_index * 29) % 97),
                               next_valid_sequence, 1'b1);
            next_valid_sequence = next_valid_sequence + 1;
        end

        wait_for_all_frames;
        repeat (20) @(posedge sys_clk);
        if (app_rx_valid === 1'b1)
            fail_and_finish("unexpected APP data after all frames");

        if (error_count == 0)
            $display("ALL SWITCH-TO-APP TESTS PASSED: frames=%0d rejected=3 stress_frames=%0d",
                     received_frame_count, STRESS_FRAME_COUNT);
        else
            $display("SWITCH-TO-APP TEST FAILED: errors=%0d", error_count);
        $finish;
    end

    initial begin
        #30000000;
        $display("ERROR SWITCH-TO-APP: simulation timeout");
        $finish;
    end
endmodule
