`timescale 1ns / 1ps

// AFDX接收帧FIFO。
// 候选载荷先写入环形RAM；整帧校验通过后提交长度描述，失败则回滚写指针。
// APP只能读取已经提交的完整帧，输出直接采用标准ready/valid接口。
module afdx_rx_frame_manager #(
    parameter integer FRAME_LENGTH_WIDTH       = 11,
    parameter integer PAYLOAD_FIFO_DEPTH       = 4096,
    parameter integer PAYLOAD_POINTER_WIDTH    = 12,
    parameter integer DESCRIPTOR_FIFO_DEPTH    = 8,
    parameter integer DESCRIPTOR_POINTER_WIDTH = 3
)(
    input  wire       sys_clk,
    input  wire       sys_rst_n,

    input  wire       frame_capture_start,
    input  wire       payload_write_valid,
    input  wire [7:0] payload_write_data,
    output wire       payload_write_ready,
    output reg        payload_write_overflow,
    output wire       frame_descriptor_ready,

    input  wire       frame_commit,
    input  wire       frame_abort,
    input  wire [FRAME_LENGTH_WIDTH-1:0] frame_payload_length,
    input wire [15:0] frame_vl_id,
    input wire [7:0] frame_sequence_number,

    output wire [7:0] app_rx_data,
    output wire       app_rx_valid,
    output wire       app_rx_last,
    input  wire       app_rx_ready,
    output reg [15:0] app_rx_vl_id,
    output reg [7:0] app_rx_sequence_number
);

    reg [7:0] payload_memory [0:PAYLOAD_FIFO_DEPTH-1];
    reg [PAYLOAD_POINTER_WIDTH-1:0] payload_write_pointer;
    reg [PAYLOAD_POINTER_WIDTH-1:0] payload_read_pointer;
    reg [PAYLOAD_POINTER_WIDTH:0] stored_payload_byte_count;

    reg [PAYLOAD_POINTER_WIDTH-1:0] frame_capture_start_pointer;
    // 回滚计数按RAM容量定宽，不能沿用合法帧描述的位宽。
    reg [PAYLOAD_POINTER_WIDTH:0] candidate_payload_length;
    reg frame_capture_active;
    reg frame_discard_active;

    reg [FRAME_LENGTH_WIDTH-1:0] descriptor_length_memory
        [0:DESCRIPTOR_FIFO_DEPTH-1];
    reg [15:0] descriptor_vl_memory [0:DESCRIPTOR_FIFO_DEPTH-1];
    reg [7:0] descriptor_sn_memory [0:DESCRIPTOR_FIFO_DEPTH-1];
    reg [DESCRIPTOR_POINTER_WIDTH-1:0] descriptor_write_pointer;
    reg [DESCRIPTOR_POINTER_WIDTH-1:0] descriptor_read_pointer;
    reg [DESCRIPTOR_POINTER_WIDTH:0] descriptor_count;

    reg app_rx_frame_active;
    reg [FRAME_LENGTH_WIDTH-1:0] app_rx_bytes_remaining;
    reg [7:0] app_rx_data_register;
    reg app_rx_valid_register;
    reg app_rx_last_register;

    wire descriptor_full;
    wire descriptor_empty;
    wire descriptor_write_enable;
    wire descriptor_read_enable;
    wire app_rx_transfer;
    wire payload_read_enable;
    wire payload_space_available;
    wire candidate_payload_write;
    wire frame_rollback;
    wire candidate_buffer_exhausted;
    wire [PAYLOAD_POINTER_WIDTH:0] rollback_byte_count;

    assign descriptor_full =
        (descriptor_count == DESCRIPTOR_FIFO_DEPTH);
    assign descriptor_empty = (descriptor_count == 0);
    assign descriptor_read_enable = !app_rx_frame_active &&
                                    !app_rx_valid_register &&
                                    !descriptor_empty;
    assign frame_descriptor_ready = !descriptor_full ||
                                    descriptor_read_enable;
    // 候选帧独占全部RAM后，先回滚，再持续接收丢弃到帧尾。
    // 丢弃态不依赖数据/描述空间，确保帧尾能够到达解码器。
    assign payload_write_ready = frame_discard_active ||
                                 (payload_space_available &&
                                  frame_descriptor_ready);
    assign descriptor_write_enable = frame_commit &&
                                     frame_capture_active &&
                                     !frame_discard_active &&
                                     !payload_write_overflow &&
                                     frame_descriptor_ready;

    assign app_rx_data = app_rx_data_register;
    assign app_rx_valid = app_rx_valid_register;
    assign app_rx_last = app_rx_last_register;
    assign app_rx_transfer = app_rx_valid && app_rx_ready;

    // RAM读请求即把一个字节移入输出寄存器。APP停顿时输出寄存器保持不变。
    assign payload_read_enable = sys_rst_n && app_rx_frame_active &&
                                 (app_rx_bytes_remaining != 0) &&
                                 (!app_rx_valid_register || app_rx_ready);

    assign payload_space_available =
        (stored_payload_byte_count < PAYLOAD_FIFO_DEPTH) ||
        payload_read_enable;
    assign candidate_payload_write = payload_write_valid &&
                                     frame_capture_active &&
                                     !frame_discard_active &&
                                     !payload_write_overflow &&
                                     payload_space_available;
    // 仅处理无法自行释放的候选存储耗尽；已提交帧占用导致的满仍正常反压。
    // 这是缓存事务恢复，不增加APP帧长检查或改变TX输入契约。
    assign candidate_buffer_exhausted = frame_capture_active &&
                                       !frame_discard_active &&
                                       (candidate_payload_length ==
                                        PAYLOAD_FIFO_DEPTH);
    assign frame_rollback = frame_capture_active && !frame_discard_active &&
                            (frame_abort || candidate_buffer_exhausted);
    assign rollback_byte_count = candidate_payload_length;

    always @(posedge sys_clk) begin
        if (candidate_payload_write)
            payload_memory[payload_write_pointer] <= payload_write_data;
    end

    // 候选帧状态：frame_capture_start建立回滚点，commit/abort结束事务。
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0) begin
            frame_capture_start_pointer <= {PAYLOAD_POINTER_WIDTH{1'b0}};
            candidate_payload_length <= {(PAYLOAD_POINTER_WIDTH + 1){1'b0}};
            frame_capture_active <= 1'b0;
            frame_discard_active <= 1'b0;
            payload_write_overflow <= 1'b0;
        end else begin
            if (frame_capture_start) begin
                frame_capture_start_pointer <= payload_write_pointer;
                candidate_payload_length <= {(PAYLOAD_POINTER_WIDTH + 1){1'b0}};
                frame_capture_active <= 1'b1;
                frame_discard_active <= 1'b0;
                payload_write_overflow <= 1'b0;
            end

            if (candidate_payload_write)
                candidate_payload_length <= candidate_payload_length + 1'b1;
            else if (payload_write_valid && frame_capture_active &&
                     !payload_space_available)
                payload_write_overflow <= 1'b1;

            if (candidate_buffer_exhausted) begin
                candidate_payload_length <= {(PAYLOAD_POINTER_WIDTH + 1){1'b0}};
                frame_discard_active <= 1'b1;
                payload_write_overflow <= 1'b1;
            end

            if (frame_abort || descriptor_write_enable) begin
                candidate_payload_length <= {(PAYLOAD_POINTER_WIDTH + 1){1'b0}};
                frame_capture_active <= 1'b0;
                frame_discard_active <= 1'b0;
                payload_write_overflow <= 1'b0;
            end
        end
    end

    // 数据RAM读写指针和占用量。回滚只删除当前候选帧，不影响已提交帧。
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0) begin
            payload_write_pointer <= {PAYLOAD_POINTER_WIDTH{1'b0}};
            payload_read_pointer <= {PAYLOAD_POINTER_WIDTH{1'b0}};
            stored_payload_byte_count <=
                {(PAYLOAD_POINTER_WIDTH + 1){1'b0}};
        end else begin
            if (frame_rollback)
                payload_write_pointer <= frame_capture_start_pointer;
            else if (candidate_payload_write)
                payload_write_pointer <= payload_write_pointer + 1'b1;

            if (payload_read_enable)
                payload_read_pointer <= payload_read_pointer + 1'b1;

            if (frame_rollback)
                stored_payload_byte_count <= stored_payload_byte_count -
                    rollback_byte_count - payload_read_enable;
            else begin
                case ({candidate_payload_write, payload_read_enable})
                    2'b10: stored_payload_byte_count <=
                        stored_payload_byte_count + 1'b1;
                    2'b01: stored_payload_byte_count <=
                        stored_payload_byte_count - 1'b1;
                    default: stored_payload_byte_count <=
                        stored_payload_byte_count;
                endcase
            end
        end
    end

    // 只有校验通过的帧长度才进入描述FIFO。
    always @(posedge sys_clk) begin
        if (descriptor_write_enable) begin
            descriptor_length_memory[descriptor_write_pointer] <= frame_payload_length;
            descriptor_vl_memory[descriptor_write_pointer] <= frame_vl_id;
            descriptor_sn_memory[descriptor_write_pointer] <= frame_sequence_number;
        end
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0) begin
            descriptor_write_pointer <=
                {DESCRIPTOR_POINTER_WIDTH{1'b0}};
            descriptor_read_pointer <=
                {DESCRIPTOR_POINTER_WIDTH{1'b0}};
            descriptor_count <=
                {(DESCRIPTOR_POINTER_WIDTH + 1){1'b0}};
        end else begin
            if (descriptor_write_enable)
                descriptor_write_pointer <= descriptor_write_pointer + 1'b1;
            if (descriptor_read_enable)
                descriptor_read_pointer <= descriptor_read_pointer + 1'b1;

            case ({descriptor_write_enable, descriptor_read_enable})
                2'b10: descriptor_count <= descriptor_count + 1'b1;
                2'b01: descriptor_count <= descriptor_count - 1'b1;
                default: descriptor_count <= descriptor_count;
            endcase
        end
    end

    // 取得一个完整帧描述后，按长度从数据RAM逐字节送入输出寄存器。
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0) begin
            app_rx_frame_active <= 1'b0;
            app_rx_vl_id <= 0;
            app_rx_sequence_number <= 0;
            app_rx_bytes_remaining <= {FRAME_LENGTH_WIDTH{1'b0}};
        end else begin
            if (descriptor_read_enable) begin
                app_rx_vl_id <= descriptor_vl_memory[descriptor_read_pointer];
                app_rx_sequence_number <= descriptor_sn_memory[descriptor_read_pointer];
                app_rx_frame_active <= 1'b1;
                app_rx_bytes_remaining <=
                    descriptor_length_memory[descriptor_read_pointer];
            end else if (payload_read_enable) begin
                if (app_rx_bytes_remaining == 1) begin
                    app_rx_bytes_remaining <=
                        {FRAME_LENGTH_WIDTH{1'b0}};
                    app_rx_frame_active <= 1'b0;
                end else
                    app_rx_bytes_remaining <= app_rx_bytes_remaining - 1'b1;
            end
        end
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0) begin
            app_rx_data_register <= 8'd0;
            app_rx_valid_register <= 1'b0;
            app_rx_last_register <= 1'b0;
        end else begin
            if (payload_read_enable) begin
                app_rx_data_register <= payload_memory[payload_read_pointer];
                app_rx_valid_register <= 1'b1;
                app_rx_last_register <= (app_rx_bytes_remaining == 1);
            end else if (app_rx_transfer) begin
                app_rx_valid_register <= 1'b0;
                app_rx_last_register <= 1'b0;
            end
        end
    end

endmodule
