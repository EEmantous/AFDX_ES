`timescale 1ns / 1ps

module sequence_counter(
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    input  wire       frame_transmit_done,
    output reg  [7:0] sequence_number
    );

    always @(posedge sys_clk or negedge sys_rst_n) begin
        // AFDX有效序列号范围为1~255，复位后的第一帧从1开始。
        if(sys_rst_n == 1'b0) sequence_number <= 8'd1;
        else if ((sequence_number == 8'd255) && frame_transmit_done)
            sequence_number <= 8'd1;
        else if (frame_transmit_done)
            sequence_number <= sequence_number + 1'b1;
    end
endmodule
