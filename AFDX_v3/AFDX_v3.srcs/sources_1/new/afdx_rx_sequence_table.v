`timescale 1ns / 1ps

// AFDX接收序列号状态表。
//
// 每个表项保存一个VLID标签和该VL最近一次接受的序列号。表采用直接映射，
// 默认由VLID低12位索引4096个表项；若不同VLID映射到同一表项，后到的VL
// 会替换原表项。工程后续加入可配置VL表时，可把vl_id先映射成无冲突索引。
//
// 为避免在复位分支中展开大规模RAM清零逻辑，复位释放后由硬件逐项清除
// valid位。sequence_check_ready拉高以后才允许接收网络帧。
module afdx_rx_sequence_table #(
    parameter integer VL_INDEX_WIDTH = 12
)(
    input  wire                       sys_clk,
    input  wire                       sys_rst_n,

    input  wire                       sequence_check_start,
    input  wire [15:0]                sequence_check_vl_id,
    input  wire [7:0]                 sequence_check_number,

    output reg                        sequence_check_ready,
    output wire                       sequence_check_busy,
    output reg                        sequence_check_done,
    output reg                        sequence_check_passed,
    output reg                        sequence_error,
    output reg                        duplicate_frame
);

    localparam integer VL_TABLE_DEPTH = (1 << VL_INDEX_WIDTH);
    localparam [1:0] CHECK_IDLE = 2'd0;
    localparam [1:0] CHECK_READ = 2'd1;
    localparam [1:0] CHECK_COMPARE = 2'd2;

    reg [15:0] vl_tag_memory [0:VL_TABLE_DEPTH-1];
    reg [7:0]  sequence_number_memory [0:VL_TABLE_DEPTH-1];
    reg        entry_valid_memory [0:VL_TABLE_DEPTH-1];

    reg [VL_INDEX_WIDTH-1:0] initialization_address;
    reg [VL_INDEX_WIDTH-1:0] sequence_check_address;
    reg [15:0] checked_vl_id;
    reg [7:0]  checked_sequence_number;
    reg        stored_entry_valid;
    reg [15:0] stored_vl_id;
    reg [7:0]  stored_sequence_number;
    reg [1:0]  sequence_check_state;

    wire [7:0] expected_sequence_number;
    wire       stored_entry_matches;
    wire       memory_write_enable;

    assign sequence_check_busy = !sequence_check_ready ||
                                 (sequence_check_state != CHECK_IDLE);
    assign expected_sequence_number = (stored_sequence_number == 8'd255) ?
                                      8'd1 : stored_sequence_number + 1'b1;
    assign stored_entry_matches = stored_entry_valid &&
                                  (stored_vl_id == checked_vl_id);
    assign memory_write_enable =
        (sequence_check_state == CHECK_COMPARE) &&
        (checked_sequence_number != 8'd0) &&
        !(stored_entry_matches &&
          (checked_sequence_number == stored_sequence_number));

    // RAM读写过程不带异步复位，使综合器能够稳定推断块RAM。
    // 清表阶段只写valid位；标签和序列号在valid=0时没有意义。
    always @(posedge sys_clk) begin
        if (sequence_check_ready == 1'b0) begin
            entry_valid_memory[initialization_address] <= 1'b0;
        end
        else begin
            if (sequence_check_state == CHECK_READ) begin
                stored_entry_valid <=
                    entry_valid_memory[sequence_check_address];
                stored_vl_id <= vl_tag_memory[sequence_check_address];
                stored_sequence_number <=
                    sequence_number_memory[sequence_check_address];
            end

            if (memory_write_enable == 1'b1) begin
                entry_valid_memory[sequence_check_address] <= 1'b1;
                vl_tag_memory[sequence_check_address] <= checked_vl_id;
                sequence_number_memory[sequence_check_address] <=
                    checked_sequence_number;
            end
        end
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0) begin
            initialization_address <= {VL_INDEX_WIDTH{1'b0}};
            sequence_check_address <= {VL_INDEX_WIDTH{1'b0}};
            checked_vl_id          <= 16'd0;
            checked_sequence_number <= 8'd0;
            sequence_check_state   <= CHECK_IDLE;
            sequence_check_ready   <= 1'b0;
            sequence_check_done    <= 1'b0;
            sequence_check_passed  <= 1'b0;
            sequence_error         <= 1'b0;
            duplicate_frame        <= 1'b0;
        end
        else begin
            sequence_check_done   <= 1'b0;
            sequence_check_passed <= 1'b0;
            sequence_error        <= 1'b0;
            duplicate_frame       <= 1'b0;

            if (sequence_check_ready == 1'b0) begin
                if (initialization_address == VL_TABLE_DEPTH - 1) begin
                    initialization_address <= {VL_INDEX_WIDTH{1'b0}};
                    sequence_check_ready <= 1'b1;
                end
                else begin
                    initialization_address <= initialization_address + 1'b1;
                end
            end
            else begin
                case (sequence_check_state)
                    CHECK_IDLE: begin
                        if (sequence_check_start == 1'b1) begin
                            sequence_check_address <=
                                sequence_check_vl_id[VL_INDEX_WIDTH-1:0];
                            checked_vl_id <= sequence_check_vl_id;
                            checked_sequence_number <= sequence_check_number;
                            sequence_check_state <= CHECK_READ;
                        end
                    end

                    CHECK_READ: begin
                        sequence_check_state <= CHECK_COMPARE;
                    end

                    CHECK_COMPARE: begin
                        sequence_check_done <= 1'b1;

                        // 序列号0不属于AFDX有效范围，拒绝该帧。
                        if (checked_sequence_number == 8'd0) begin
                            sequence_check_passed <= 1'b0;
                            sequence_error <= 1'b1;
                        end
                        // 未初始化表项或直接映射发生标签替换：接受并建立基线。
                        else if ((stored_entry_valid == 1'b0) ||
                                 (stored_vl_id != checked_vl_id)) begin
                            sequence_check_passed <= 1'b1;
                        end
                        // 双网冗余或链路重发造成的重复帧不再交给应用。
                        else if (checked_sequence_number ==
                                 stored_sequence_number) begin
                            sequence_check_passed <= 1'b0;
                            duplicate_frame <= 1'b1;
                        end
                        // 连续序列正常接受。
                        else if (checked_sequence_number ==
                                 expected_sequence_number) begin
                            sequence_check_passed <= 1'b1;
                        end
                        // 跳号表示发生丢帧或乱序；当前帧仍交付，并用它重建基线。
                        else begin
                            sequence_check_passed <= 1'b1;
                            sequence_error <= 1'b1;
                        end

                        sequence_check_state <= CHECK_IDLE;
                    end

                    default: sequence_check_state <= CHECK_IDLE;
                endcase
            end
        end
    end

endmodule
