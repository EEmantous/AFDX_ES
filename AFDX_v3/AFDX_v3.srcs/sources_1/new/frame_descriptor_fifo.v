`timescale 1ns / 1ps

// 小深度帧描述FIFO。每个条目对应数据FIFO中的一帧完整数据。
// descriptor_read_frame_length为队首描述的直通输出；读使能与发送器锁存长度
// 在同一时钟沿完成。
module frame_descriptor_fifo #(
    parameter integer FRAME_LENGTH_WIDTH = 11,
    parameter integer FIFO_DEPTH = 4,
    parameter integer POINTER_WIDTH = 2
)(
    input  wire                          sys_clk,
    input  wire                          sys_rst_n,
    input  wire                          descriptor_write_enable,
    input  wire [FRAME_LENGTH_WIDTH-1:0] descriptor_write_frame_length,
    input  wire                          descriptor_read_enable,
    output wire [FRAME_LENGTH_WIDTH-1:0] descriptor_read_frame_length,
    output wire                          descriptor_full,
    output wire                          descriptor_empty,
    output reg  [POINTER_WIDTH:0]         descriptor_count
);

    reg [FRAME_LENGTH_WIDTH-1:0] descriptor_length_memory
        [0:FIFO_DEPTH-1];
    reg [POINTER_WIDTH-1:0] descriptor_write_pointer;
    reg [POINTER_WIDTH-1:0] descriptor_read_pointer;

    wire descriptor_write_transfer;
    wire descriptor_read_transfer;

    assign descriptor_full = (descriptor_count == FIFO_DEPTH);
    assign descriptor_empty = (descriptor_count == 0);
    assign descriptor_read_transfer = descriptor_read_enable &&
                                      !descriptor_empty;
    // 满状态下若同周期弹出一个条目，允许新描述无气泡写入。
    assign descriptor_write_transfer = descriptor_write_enable &&
        (!descriptor_full || descriptor_read_transfer);
    assign descriptor_read_frame_length =
        descriptor_length_memory[descriptor_read_pointer];

    // 存储阵列无需复位；只有有效条目才会被读取。
    // 独立的同步写过程便于综合器稳定推断为寄存器阵列。
    always @(posedge sys_clk) begin
        if (descriptor_write_transfer == 1'b1)
            descriptor_length_memory[descriptor_write_pointer] <=
                descriptor_write_frame_length;
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0) begin
            descriptor_write_pointer <= {POINTER_WIDTH{1'b0}};
            descriptor_read_pointer <= {POINTER_WIDTH{1'b0}};
            descriptor_count <= {(POINTER_WIDTH + 1){1'b0}};
        end
        else begin
            if (descriptor_write_transfer == 1'b1)
                descriptor_write_pointer <= descriptor_write_pointer + 1'b1;

            if (descriptor_read_transfer == 1'b1)
                descriptor_read_pointer <= descriptor_read_pointer + 1'b1;

            case ({descriptor_write_transfer, descriptor_read_transfer})
                2'b10: descriptor_count <= descriptor_count + 1'b1;
                2'b01: descriptor_count <= descriptor_count - 1'b1;
                default: descriptor_count <= descriptor_count;
            endcase
        end
    end

endmodule
