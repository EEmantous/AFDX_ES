`timescale 1ns / 1ps

// 将TX内核的“请求/下一拍应答”接口转换为标准ready/valid数据流。
// 两项弹性缓存同时覆盖一个在途请求和交换机侧的突发反压。
module afdx_tx_switch_stream (
    input  wire       sys_clk,
    input  wire       sys_rst_n,

    output wire       builder_read_request,
    input  wire       builder_read_ready,
    input  wire [7:0] builder_data,
    input  wire       builder_valid,
    input  wire       builder_last,

    output wire [7:0] tx_data,
    output wire       tx_valid,
    output wire       tx_last,
    input  wire       tx_ready
);

    reg [7:0] buffer_data_0;
    reg [7:0] buffer_data_1;
    reg       buffer_last_0;
    reg       buffer_last_1;
    reg       buffer_write_pointer;
    reg       buffer_read_pointer;
    reg [1:0] buffered_byte_count;
    reg [1:0] pending_request_count;

    wire tx_transfer;
    wire builder_response_valid;
    wire [2:0] reserved_slot_count;

    assign tx_valid = (buffered_byte_count != 0);
    assign tx_data = buffer_read_pointer ? buffer_data_1 : buffer_data_0;
    assign tx_last = buffer_read_pointer ? buffer_last_1 : buffer_last_0;
    assign tx_transfer = tx_valid && tx_ready;

    // 每个builder_read_request恰好在随后产生一个builder_valid应答。
    // pending_request_count为
    // 应答预留缓存位置；同拍弹出时可立即补发一个请求。
    assign builder_response_valid = builder_valid;
    assign reserved_slot_count = {1'b0, buffered_byte_count} +
                                 {1'b0, pending_request_count};
    assign builder_read_request = sys_rst_n && builder_read_ready &&
        ((reserved_slot_count < 3'd2) || tx_transfer);

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0) begin
            buffer_data_0 <= 8'd0;
            buffer_data_1 <= 8'd0;
            buffer_last_0 <= 1'b0;
            buffer_last_1 <= 1'b0;
            buffer_write_pointer <= 1'b0;
            buffer_read_pointer <= 1'b0;
            buffered_byte_count <= 2'd0;
            pending_request_count <= 2'd0;
        end else begin
            if (builder_response_valid) begin
                if (buffer_write_pointer == 1'b0) begin
                    buffer_data_0 <= builder_data;
                    buffer_last_0 <= builder_last;
                end else begin
                    buffer_data_1 <= builder_data;
                    buffer_last_1 <= builder_last;
                end
                buffer_write_pointer <= buffer_write_pointer + 1'b1;
            end

            if (tx_transfer)
                buffer_read_pointer <= buffer_read_pointer + 1'b1;

            case ({builder_response_valid, tx_transfer})
                2'b10: buffered_byte_count <= buffered_byte_count + 1'b1;
                2'b01: buffered_byte_count <= buffered_byte_count - 1'b1;
                default: buffered_byte_count <= buffered_byte_count;
            endcase

            case ({builder_read_request, builder_response_valid})
                2'b10: pending_request_count <= pending_request_count + 1'b1;
                2'b01: pending_request_count <= pending_request_count - 1'b1;
                default: pending_request_count <= pending_request_count;
            endcase
        end
    end

endmodule
