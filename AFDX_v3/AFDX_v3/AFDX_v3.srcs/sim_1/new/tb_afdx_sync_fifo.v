`timescale 1ns/1ps
module tb_afdx_sync_fifo;
    reg clk=0,srst=1; always #5 clk=~clk;
    reg [8:0] din=0; reg wr_en=0,rd_en=0;
    wire [8:0] dout; wire full,empty; wire [3:0] data_count;
    integer i; reg [8:0] previous;
    afdx_sync_fifo #(.ADDRESS_WIDTH(3),.DEPTH(8)) dut(
        .clk(clk),.srst(srst),.din(din),.wr_en(wr_en),.rd_en(rd_en),
        .dout(dout),.full(full),.empty(empty),.data_count(data_count));
    task tick; begin @(posedge clk);#1;@(negedge clk);end endtask
    initial begin
        tick;srst=0;rd_en=1;tick;
        if(!empty||data_count!=0||dout!=0)$fatal(1,"empty read protection");
        rd_en=0;wr_en=1;
        for(i=0;i<8;i=i+1)begin din=9'h100+i;tick;end
        if(!full||data_count!=8)$fatal(1,"full capacity");
        din=9'h1ff;tick;if(data_count!=8)$fatal(1,"full write protection");
        wr_en=0;rd_en=1;
        for(i=0;i<8;i=i+1)begin
            previous=dout;#1;if(dout!==previous)$fatal(1,"unsolicited FIFO read");
            @(posedge clk);#1;if(dout!==9'h100+i)$fatal(1,"Standard read order/last");@(negedge clk);
        end
        tick;if(!empty||data_count!=0||dout!==9'h107)$fatal(1,"empty holds output");
        rd_en=0;wr_en=1;din=9'h55;tick;
        rd_en=1;din=9'h66;tick;if(data_count!=1||dout!==9'h55)$fatal(1,"simultaneous transfer");
        wr_en=0;tick;if(!empty||dout!==9'h66)$fatal(1,"pointer wrap order");
        srst=1;tick;if(!empty||full||dout!=0)$fatal(1,"synchronous reset");
        $display("PORTABLE FIFO PASSED");$finish;
    end
    initial begin #10000;$fatal(1,"TIMEOUT portable FIFO");end
endmodule
