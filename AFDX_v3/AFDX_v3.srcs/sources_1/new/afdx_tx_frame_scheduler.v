`timescale 1ns / 1ps

// 完整帧调度器。
// 内部保存已提交帧的长度，并在BAG允许时弹出一个描述符启动发送。
module afdx_tx_frame_scheduler #(
    parameter integer BAG_CYCLES = 400_000,
    parameter integer FRAME_LENGTH_WIDTH = 11,
    parameter integer DESCRIPTOR_FIFO_DEPTH = 4,
    parameter integer DESCRIPTOR_POINTER_WIDTH = 2
)(
    input  wire                          sys_clk,
    input  wire                          sys_rst_n,

    input  wire                          descriptor_write_enable,
    input  wire [FRAME_LENGTH_WIDTH-1:0]
                                             descriptor_write_frame_length,
    output wire                          descriptor_write_ready,

    output wire [FRAME_LENGTH_WIDTH-1:0] scheduled_frame_length,
    output wire                          scheduled_frame_grant,
    input  wire                          frame_transmit_start,
    input  wire                          frame_transmit_busy
);
    wire descriptor_fifo_full;
    wire descriptor_fifo_empty;
    wire descriptor_fifo_read_enable;

    assign descriptor_write_ready = !descriptor_fifo_full;
    assign descriptor_fifo_read_enable = scheduled_frame_grant &&
                                         !descriptor_fifo_empty;

    frame_descriptor_fifo #(
        .FRAME_LENGTH_WIDTH(FRAME_LENGTH_WIDTH),
        .FIFO_DEPTH(DESCRIPTOR_FIFO_DEPTH),
        .POINTER_WIDTH(DESCRIPTOR_POINTER_WIDTH)
    ) u_frame_descriptor_fifo (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .descriptor_write_enable(descriptor_write_enable),
        .descriptor_write_frame_length(descriptor_write_frame_length),
        .descriptor_read_enable(descriptor_fifo_read_enable),
        .descriptor_read_frame_length(scheduled_frame_length),
        .descriptor_full(descriptor_fifo_full),
        .descriptor_empty(descriptor_fifo_empty),
        .descriptor_count()
    );

    bag_timer #(
        .BAG_CYCLES(BAG_CYCLES)
    ) u_bag_timer (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .frame_available(!descriptor_fifo_empty),
        .frame_transmit_start(frame_transmit_start),
        .frame_transmit_busy(frame_transmit_busy),
        .bag_grant(scheduled_frame_grant)
    );

endmodule
