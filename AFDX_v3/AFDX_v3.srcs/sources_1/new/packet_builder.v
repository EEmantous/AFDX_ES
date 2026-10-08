`timescale 1ns / 1ps
module packet_builder #(
    parameter FRAME_LENGTH_WIDTH = 11,
    parameter [47:0] DEST_MAC = 48'h03_00_00_00_00_01,
    parameter [47:0] SRC_MAC  = 48'h00_11_22_33_44_55,
    parameter [31:0] SRC_IP   = 32'hC0_A8_00_01,
    parameter [31:0] DEST_IP  = 32'hE0_00_00_01,
    parameter [15:0] SRC_PORT = 16'd1000,
    parameter [15:0] DEST_PORT = 16'd1001
)(
    input  wire                        sys_clk,
    input  wire                        sys_rst_n,

    // BAG发送许可
    input  wire                        bag_grant,

    // 当前帧信息
    input  wire [FRAME_LENGTH_WIDTH-1:0] payload_frame_length,
    input  wire [7:0]                  sequence_number,

    // 载荷FIFO读取接口
    input  wire [7:0]                  payload_read_data,
    input  wire                        payload_read_last,
    input  wire                        payload_fifo_empty,
    output wire                        payload_read_enable,

    // 字节读取接口：适配器发出请求，本模块在下一拍返回一个有效字节。
    input  wire                        builder_read_request,
    output wire                        builder_read_ready,
    output wire [7:0]                  builder_data,
    output reg                         builder_valid,
    output reg                         builder_last,

    // 帧状态
    output reg                         frame_transmit_start,
    output reg                         frame_transmit_done,
    output reg                         frame_transmit_busy
);

    // 当前正在发送的帧信息。
    // 必须在bag_grant到来时锁存，防止应用写入下一帧后覆盖这些信息。
    reg [FRAME_LENGTH_WIDTH-1:0] active_payload_length;
    reg [7:0] active_sequence_number;

    // 当前帧是否已经输出过第一个字节。
    reg first_frame_byte_sent;

    // FIFO应用数据已经输出完毕，等待输出序列号。
    reg sequence_byte_pending;

    // AFDX应用载荷不足17字节时，在序列号之前补零。
    reg [4:0] padding_byte_count;
    reg       padding_byte_valid;

    // 头部输出控制。Ethernet、IPv4和UDP头共42字节。
    reg       header_output_active;
    reg [5:0] header_byte_index;
    reg [7:0] header_byte_register;
    reg       header_byte_valid;

    wire [7:0] header_byte_data;
    wire header_read_ready;
    wire header_read_transfer;
    wire final_header_byte_transfer;
    wire payload_read_ready;
    wire sequence_read_ready;
    wire sequence_read_transfer;
    wire padding_read_ready;
    wire padding_read_transfer;
    wire payload_byte_valid;
    wire final_payload_byte_valid;

    //==================================================
    // 输出请求控制
    //==================================================
    // 获得BAG许可后，先依次输出42字节报文头。
    assign header_read_ready = frame_transmit_busy && header_output_active;
    assign header_read_transfer = builder_read_request && header_read_ready;
    assign final_header_byte_transfer = header_read_transfer &&
                                        (header_byte_index == 6'd41);

    // 报文头输出结束后才能输出FIFO数据，并且必须保证FIFO非空。
    // 当最后一个应用数据字节已经有效时暂停读取，防止读入下一帧。
    assign payload_read_ready = frame_transmit_busy &&
                                !header_output_active &&
                                !sequence_byte_pending &&
                                (padding_byte_count == 5'd0) &&
                                !payload_fifo_empty &&
                                !final_payload_byte_valid;

    assign padding_read_ready = frame_transmit_busy &&
                                !header_output_active &&
                                !sequence_byte_pending &&
                                (padding_byte_count != 5'd0);
    assign padding_read_transfer = builder_read_request &&
                                   padding_read_ready;

    // 应用数据发送结束后，可以接受一次序列号输出请求。
    assign sequence_read_ready = frame_transmit_busy &&
                                 sequence_byte_pending;

    assign builder_read_ready = header_read_ready || payload_read_ready ||
                                padding_read_ready || sequence_read_ready;

    // 只有应用数据阶段才读取FIFO。
    assign payload_read_enable = builder_read_request && payload_read_ready;

    // 序列号不来自FIFO，由packet_builder直接产生。
    assign sequence_read_transfer = builder_read_request &&
                                    sequence_read_ready;

    // FIFO为Standard模式，payload_read_enable后的下一个时钟周期，
    // payload_read_data、payload_read_last与builder_valid同时有效。
    assign payload_byte_valid = builder_valid &&
                                !builder_last &&
                                !header_byte_valid &&
                                !padding_byte_valid;
    assign final_payload_byte_valid = payload_byte_valid &&
                                      payload_read_last;

    // 头部来自header_builder，应用数据来自FIFO，最后一个字节为序列号。
    // builder_valid=0时builder_data的值无效，不需要额外清零。
    assign builder_data = builder_last ? active_sequence_number :
                          header_byte_valid ? header_byte_register :
                          padding_byte_valid ? 8'h00 :
                          payload_read_data;

    //==================================================
    // Ethernet、IPv4和UDP头部字节生成
    //==================================================
    afdx_header_builder #(
        .FRAME_LENGTH_WIDTH (FRAME_LENGTH_WIDTH),
        .DEST_MAC           (DEST_MAC),
        .SRC_MAC            (SRC_MAC),
        .SRC_IP             (SRC_IP),
        .DEST_IP            (DEST_IP),
        .SRC_PORT           (SRC_PORT),
        .DEST_PORT          (DEST_PORT)
    ) u_afdx_header_builder (
        .payload_frame_length(active_payload_length),
        .header_byte_index(header_byte_index),
        .header_byte_data(header_byte_data)
    );

    //==================================================
    // 当前帧信息锁存
    //==================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0)
            active_payload_length <= {FRAME_LENGTH_WIDTH{1'b0}};
        else if (bag_grant == 1'b1)
            active_payload_length <= payload_frame_length;
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0)
            active_sequence_number <= 8'd1;
        else if (bag_grant == 1'b1)
            active_sequence_number <= sequence_number;
    end

    //==================================================
    // 报文头输出控制
    //==================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0)
            header_output_active <= 1'b0;
        else if (bag_grant == 1'b1)
            header_output_active <= 1'b1;
        else if (final_header_byte_transfer == 1'b1)
            header_output_active <= 1'b0;
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0)
            header_byte_index <= 6'd0;
        else if (bag_grant == 1'b1)
            header_byte_index <= 6'd0;
        else if (header_read_transfer == 1'b1) begin
            if (header_byte_index == 6'd41)
                header_byte_index <= 6'd0;
            else
                header_byte_index <= header_byte_index + 1'b1;
        end
    end

    // 在接受头部输出请求时保存当前字节，避免索引递增后数据改变。
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0)
            header_byte_register <= 8'd0;
        else if (header_read_transfer == 1'b1)
            header_byte_register <= header_byte_data;
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0)
            header_byte_valid <= 1'b0;
        else if (header_read_transfer == 1'b1)
            header_byte_valid <= 1'b1;
        else
            header_byte_valid <= 1'b0;
    end

    //==================================================
    // 整帧忙标志
    //==================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0)
            frame_transmit_busy <= 1'b0;
        else if (bag_grant == 1'b1)
            frame_transmit_busy <= 1'b1;
        else if (sequence_read_transfer == 1'b1)
            frame_transmit_busy <= 1'b0;
    end

    //==================================================
    // 应用数据结束后转入序列号输出阶段
    //==================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0)
            sequence_byte_pending <= 1'b0;
        else if (bag_grant == 1'b1)
            sequence_byte_pending <= 1'b0;
        else if (sequence_read_transfer == 1'b1)
            sequence_byte_pending <= 1'b0;
        else if ((final_payload_byte_valid == 1'b1) &&
                 (active_payload_length >= 17))
            sequence_byte_pending <= 1'b1;
        else if ((padding_read_transfer == 1'b1) &&
                 (padding_byte_count == 5'd1))
            sequence_byte_pending <= 1'b1;
    end

    // 在最后一个应用数据字节输出后计算所需填充字节数。
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0)
            padding_byte_count <= 5'd0;
        else if (bag_grant == 1'b1)
            padding_byte_count <= 5'd0;
        else if ((final_payload_byte_valid == 1'b1) &&
                 (active_payload_length < 17))
            padding_byte_count <= 5'd17 - active_payload_length[4:0];
        else if (padding_read_transfer == 1'b1)
            padding_byte_count <= padding_byte_count - 1'b1;
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0)
            padding_byte_valid <= 1'b0;
        else if (padding_read_transfer == 1'b1)
            padding_byte_valid <= 1'b1;
        else
            padding_byte_valid <= 1'b0;
    end

    //==================================================
    // 输出有效和最后一个字节标志
    //==================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0)
            builder_valid <= 1'b0;
        else if ((header_read_transfer == 1'b1) ||
                 (payload_read_enable == 1'b1) ||
                 (padding_read_transfer == 1'b1) ||
                 (sequence_read_transfer == 1'b1))
            builder_valid <= 1'b1;
        else
            builder_valid <= 1'b0;
    end

    // FIFO中的fifo_last只是应用数据结束标志。
    // 完整输出帧的最后一个字节是sequence_number。
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0)
            builder_last <= 1'b0;
        else if (sequence_read_transfer == 1'b1)
            builder_last <= 1'b1;
        else
            builder_last <= 1'b0;
    end

    //==================================================
    // 帧开始标志
    //==================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0)
            first_frame_byte_sent <= 1'b0;
        else if (bag_grant == 1'b1)
            first_frame_byte_sent <= 1'b0;
        else if ((header_read_transfer == 1'b1) ||
                 (payload_read_enable == 1'b1) ||
                 (padding_read_transfer == 1'b1) ||
                 (sequence_read_transfer == 1'b1))
            first_frame_byte_sent <= 1'b1;
    end

    // frame_transmit_start与本帧第一个builder_valid字节对齐。
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0)
            frame_transmit_start <= 1'b0;
        else if (((header_read_transfer == 1'b1) ||
                  (payload_read_enable == 1'b1) ||
                  (padding_read_transfer == 1'b1) ||
                  (sequence_read_transfer == 1'b1)) &&
                 (first_frame_byte_sent == 1'b0))
            frame_transmit_start <= 1'b1;
        else
            frame_transmit_start <= 1'b0;
    end

    // frame_transmit_done与序列号输出字节对齐，只保持一个时钟周期。
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0)
            frame_transmit_done <= 1'b0;
        else if (sequence_read_transfer == 1'b1)
            frame_transmit_done <= 1'b1;
        else
            frame_transmit_done <= 1'b0;
    end

endmodule
