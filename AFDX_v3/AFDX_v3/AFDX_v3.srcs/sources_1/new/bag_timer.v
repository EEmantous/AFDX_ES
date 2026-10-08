`timescale 1ns / 1ps

module bag_timer #(
    parameter integer BAG_CYCLES = 400_000,
    parameter integer BAG_COUNTER_WIDTH = 32
)(
    input  wire sys_clk,
    input  wire sys_rst_n,
    input  wire frame_available, //描述FIFO中至少有一帧完整数据
    input  wire frame_transmit_start, //一帧实际开始发送
    input  wire frame_transmit_busy,  //发送器正在输出当前帧
    output reg  bag_grant     //BAG允许开始发送
);

    reg [BAG_COUNTER_WIDTH-1:0] bag_cycle_count;

    wire bag_grant_request;
    assign bag_grant_request = frame_available &&
                               !frame_transmit_busy &&
                               !bag_grant &&
                               (bag_cycle_count ==
                                {BAG_COUNTER_WIDTH{1'b0}});

    // BAG等待计数器：一帧实际开始发送后才开始倒计时。
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0)
            bag_cycle_count <= {BAG_COUNTER_WIDTH{1'b0}};
        else if (frame_transmit_start == 1'b1) begin
            if (BAG_CYCLES <= 1)
                bag_cycle_count <= {BAG_COUNTER_WIDTH{1'b0}};
            else
                bag_cycle_count <= BAG_CYCLES - 1;
        end
        else if (bag_cycle_count != {BAG_COUNTER_WIDTH{1'b0}})
            bag_cycle_count <= bag_cycle_count - 1'b1;
        else
            bag_cycle_count <= {BAG_COUNTER_WIDTH{1'b0}};
    end

    // 存在请求且BAG等待结束时，产生一个时钟周期的许可。
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0)
            bag_grant <= 1'b0;
        else if (bag_grant_request == 1'b1)
            bag_grant <= 1'b1;
        else
            bag_grant <= 1'b0;
    end

endmodule
