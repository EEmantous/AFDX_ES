`timescale 1ns/1ps
// Portable single-clock FIFO. Standard read: rd_en accepted on an edge updates
// dout after that edge. Full/empty protect access; RAM contents need no reset.
// DEPTH must equal 2**ADDRESS_WIDTH. No FWFT or vendor primitives.
module afdx_sync_fifo #(
    parameter integer DATA_WIDTH = 9,
    parameter integer ADDRESS_WIDTH = 11,
    parameter integer DEPTH = 2048
) (
    input wire clk, srst,
    input wire [DATA_WIDTH-1:0] din,
    input wire wr_en, rd_en,
    output reg [DATA_WIDTH-1:0] dout,
    output wire full, empty,
    output reg [ADDRESS_WIDTH:0] data_count
);
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    reg [ADDRESS_WIDTH-1:0] write_pointer, read_pointer;
    wire write_transfer = !srst && wr_en && !full;
    wire read_transfer = !srst && rd_en && !empty;
    assign full = (data_count == DEPTH);
    assign empty = (data_count == 0);

    always @(posedge clk) begin
        if (write_transfer) memory[write_pointer] <= din;
    end
    always @(posedge clk) begin
        if (srst) dout <= 0;
        else if (read_transfer) dout <= memory[read_pointer];
    end
    always @(posedge clk) begin
        if (srst) begin
            write_pointer <= 0; read_pointer <= 0; data_count <= 0;
        end else begin
            if (write_transfer) write_pointer <= write_pointer + 1'b1;
            if (read_transfer) read_pointer <= read_pointer + 1'b1;
            case ({write_transfer,read_transfer})
                2'b10: data_count <= data_count + 1'b1;
                2'b01: data_count <= data_count - 1'b1;
                default: data_count <= data_count;
            endcase
        end
    end
endmodule
