`timescale 1ns / 1ps

module fifo_ip_tx (
    input  wire       sys_clk,
    input  wire       sys_rst_n,

    // 载荷写入接口
    input  wire       payload_write_valid,
    input  wire [7:0] payload_write_data,
    input  wire       payload_write_last,
    output wire       payload_fifo_full,

    // 载荷读取接口
    input  wire       payload_read_enable,
    output wire [7:0] payload_read_data,
    output wire       payload_read_last,
    output wire       payload_fifo_empty,

    output wire [10:0] payload_fifo_data_count
);

    wire       fifo_reset;
    wire [8:0] fifo_din;
    wire [8:0] fifo_dout;
    wire       ip_write_enable;
    wire       ip_read_enable;
    wire [11:0] portable_data_count;

    // 顶层使用低电平复位，FIFO IP使用高电平同步复位。
    assign fifo_reset = ~sys_rst_n;

    // fifo_din[8]保存应用数据结束标志。
    assign fifo_din = {payload_write_last, payload_write_data};

    // 在封装层保留满、空保护。
    assign ip_write_enable = payload_write_valid && !payload_fifo_full;
    assign ip_read_enable = payload_read_enable && !payload_fifo_empty;

    assign payload_read_data = fifo_dout[7:0];
    assign payload_read_last = fifo_dout[8];
    // Legacy 11-bit occupancy saturates at 2047; full reports the 2048th word.
    assign payload_fifo_data_count = portable_data_count[11] ?
                                     11'h7ff : portable_data_count[10:0];

    afdx_sync_fifo u_fifo_tx (
        .clk          (sys_clk),
        .srst         (fifo_reset),
        .din          (fifo_din),
        .wr_en        (ip_write_enable),
        .rd_en        (ip_read_enable),
        .dout         (fifo_dout),
        .full         (payload_fifo_full),
        .empty        (payload_fifo_empty),
        .data_count   (portable_data_count)
    );

endmodule
