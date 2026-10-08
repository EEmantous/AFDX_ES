`timescale 1ns / 1ps

// TX帧管理器：信任APP输入，载荷直接写入正式FIFO。
// app_tx_last是唯一帧尾；本模块只统计帧长，不检查超长或上游协议错误。
module afdx_tx_frame_manager #(
    parameter integer BAG_CYCLES = 400_000,
    parameter integer FRAME_LENGTH_WIDTH = 11,
    parameter integer DESCRIPTOR_FIFO_DEPTH = 4,
    parameter integer DESCRIPTOR_POINTER_WIDTH = 2
)(
    input  wire                          sys_clk,
    input  wire                          sys_rst_n,

    input  wire [7:0]                    app_tx_data,
    input  wire                          app_tx_valid,
    input  wire                          app_tx_last,
    output wire                          app_tx_ready,

    output wire                          scheduled_frame_grant,
    output wire [FRAME_LENGTH_WIDTH-1:0] scheduled_frame_length,
    input  wire                          frame_transmit_start,
    input  wire                          frame_transmit_busy,

    input  wire                          payload_read_enable,
    output wire [7:0]                    payload_read_data,
    output wire                          payload_read_last,
    output wire                          payload_fifo_empty
);
    reg [FRAME_LENGTH_WIDTH-1:0] app_tx_byte_count;

    wire app_tx_transfer;
    wire payload_fifo_full;
    wire descriptor_write_ready;
    wire descriptor_write_enable;
    wire [FRAME_LENGTH_WIDTH-1:0] descriptor_write_frame_length;

    // APP负责保证帧长和last正确。发送端只在数据FIFO或描述FIFO无法接收时反压。
    assign app_tx_ready = sys_rst_n && !payload_fifo_full &&
                          descriptor_write_ready;
    assign app_tx_transfer = app_tx_valid && app_tx_ready;

    // 当前握手字节带last时，数据和对应帧长在同一时钟沿分别写入两个FIFO。
    assign descriptor_write_enable = app_tx_transfer && app_tx_last;
    assign descriptor_write_frame_length = app_tx_byte_count + 1'b1;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0)
            app_tx_byte_count <= {FRAME_LENGTH_WIDTH{1'b0}};
        else if (app_tx_transfer) begin
            if (app_tx_last)
                app_tx_byte_count <= {FRAME_LENGTH_WIDTH{1'b0}};
            else
                app_tx_byte_count <= app_tx_byte_count + 1'b1;
        end
    end

    fifo_ip_tx u_payload_fifo (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .payload_write_valid(app_tx_transfer),
        .payload_write_data(app_tx_data),
        .payload_write_last(app_tx_last),
        .payload_fifo_full(payload_fifo_full),
        .payload_read_enable(payload_read_enable),
        .payload_read_data(payload_read_data),
        .payload_read_last(payload_read_last),
        .payload_fifo_empty(payload_fifo_empty),
        .payload_fifo_data_count()
    );

    afdx_tx_frame_scheduler #(
        .BAG_CYCLES(BAG_CYCLES),
        .FRAME_LENGTH_WIDTH(FRAME_LENGTH_WIDTH),
        .DESCRIPTOR_FIFO_DEPTH(DESCRIPTOR_FIFO_DEPTH),
        .DESCRIPTOR_POINTER_WIDTH(DESCRIPTOR_POINTER_WIDTH)
    ) u_frame_scheduler (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .descriptor_write_enable(descriptor_write_enable),
        .descriptor_write_frame_length(descriptor_write_frame_length),
        .descriptor_write_ready(descriptor_write_ready),
        .scheduled_frame_length(scheduled_frame_length),
        .scheduled_frame_grant(scheduled_frame_grant),
        .frame_transmit_start(frame_transmit_start),
        .frame_transmit_busy(frame_transmit_busy)
    );

endmodule
