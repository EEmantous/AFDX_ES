`timescale 1ns/1ps
module tb_afdx_rx_protection_stats;
    reg clk=0,reset=1; always #5 clk=~clk;
    reg [7:0] app_tx_data=0; reg app_tx_valid=0,app_tx_last=0; wire app_tx_ready;
    wire [7:0] app_rx_data; wire app_rx_valid,app_rx_last;
    reg app_rx_ready=1; wire [15:0] app_rx_vl_id; wire [7:0] app_rx_sequence_number;
    wire [7:0] tx_a_data,tx_b_data; wire tx_a_valid,tx_a_last,tx_b_valid,tx_b_last;
    reg tx_a_ready=1,tx_b_ready=1;
    reg [7:0] rx_a_data=0,rx_b_data=0; reg rx_a_valid=0,rx_a_last=0,rx_b_valid=0,rx_b_last=0;
    wire rx_a_ready,rx_b_ready;
    reg [7:0] stats_addr=0; reg stats_clear=0; wire [31:0] stats_rdata; wire stats_error;
    AFDX_top #(.BAG_CYCLES(1),.RX_IDLE_TIMEOUT_CYCLES(16),.TX_IDLE_TIMEOUT_CYCLES(16),.HISTORY_DEPTH(4)) dut (
        .clk(clk),.reset(reset),
        .app_tx_data(app_tx_data),.app_tx_valid(app_tx_valid),.app_tx_last(app_tx_last),.app_tx_ready(app_tx_ready),
        .app_rx_data(app_rx_data),.app_rx_valid(app_rx_valid),.app_rx_last(app_rx_last),.app_rx_ready(app_rx_ready),
        .app_rx_vl_id(app_rx_vl_id),.app_rx_sequence_number(app_rx_sequence_number),
        .tx_a_data(tx_a_data),.tx_a_valid(tx_a_valid),.tx_a_last(tx_a_last),.tx_a_ready(tx_a_ready),
        .tx_b_data(tx_b_data),.tx_b_valid(tx_b_valid),.tx_b_last(tx_b_last),.tx_b_ready(tx_b_ready),
        .rx_a_data(rx_a_data),.rx_a_valid(rx_a_valid),.rx_a_last(rx_a_last),.rx_a_ready(rx_a_ready),
        .rx_b_data(rx_b_data),.rx_b_valid(rx_b_valid),.rx_b_last(rx_b_last),.rx_b_ready(rx_b_ready),
        .stats_addr(stats_addr),.stats_clear(stats_clear),
        .stats_rdata(stats_rdata),.stats_error(stats_error));
    reg [7:0] expected_data[0:32767],expected_sn[0:32767];
    reg [15:0] expected_vl[0:32767]; reg expected_last[0:32767];
    integer app_read=0,app_written=0,delivered=0,phase=0,i;
    reg stalled=0;reg [32:0] held;
    // Independent protocol reference, including valid IP checksum when declared
    // length differs from actual length, so the length check is exercised alone.
    function [7:0] golden;
        input integer index,len,sn,seed,delta,bad_checksum;
        input [15:0] vl;
        integer padded,ip_len,udp_len,sum,checksum;
        begin
            padded=len<17?17:len;udp_len=padded+9+delta;ip_len=udp_len+20;
            sum='h4500+ip_len+'h4000+'h4011+'hC0A8+1+'hC0A8+3;
            sum=(sum&65535)+(sum>>16);sum=(sum&65535)+(sum>>16);checksum=(~sum)&65535;
            golden=0;
            if(index>=42&&index<42+len)golden=seed+index-42;
            if(index==42+padded)golden=sn;
            case(index)
                0:golden=3;4:golden=vl[15:8];5:golden=vl[7:0];6:golden=2;11:golden=1;12:golden=8;
                14:golden='h45;16:golden=ip_len>>8;17:golden=ip_len;
                20,22:golden='h40;23:golden='h11;24:golden=(checksum>>8)^bad_checksum;25:golden=checksum;
                26,30:golden='hC0;27,31:golden='hA8;29:golden=1;33:golden=3;
                34:golden=10001>>8;35:golden=10001;36:golden=20003>>8;37:golden=20003;
                38:golden=udp_len>>8;39:golden=udp_len;default:;
            endcase
        end
    endfunction
    always @(posedge clk) if(!reset)begin
        if(stalled&&(!app_rx_valid||held!=={app_rx_vl_id,app_rx_sequence_number,app_rx_last,app_rx_data}))$fatal(1,"APP identity hold phase=%0d",phase);
        stalled=app_rx_valid&&!app_rx_ready;held={app_rx_vl_id,app_rx_sequence_number,app_rx_last,app_rx_data};
        if(app_rx_valid&&app_rx_ready)begin
            if(app_read>=app_written||app_rx_data!==expected_data[app_read]||app_rx_last!==expected_last[app_read]||
                app_rx_vl_id!==expected_vl[app_read]||app_rx_sequence_number!==expected_sn[app_read])
                $fatal(1,"Unexpected/malformed APP frame phase=%0d byte=%0d",phase,app_read);
            app_read=app_read+1;if(app_rx_last)delivered=delivered+1;
        end
    end
    task automatic expect_frame(input integer len,input integer sn,input integer seed,input [15:0] vl);
        integer n,padded;begin
            padded=len<17?17:len;
            for(n=0;n<padded;n=n+1)begin
                expected_data[app_written]=n<len?seed+n:0;expected_sn[app_written]=sn;
                expected_vl[app_written]=vl;expected_last[app_written]=(n==padded-1);app_written=app_written+1;
            end
        end
    endtask
    task automatic inject(input integer plane,input integer len,input integer sn,input integer seed,
        input [15:0] vl,input integer count,input integer with_last,input integer delta,input integer bad_checksum);
        integer n;reg [7:0] value;begin
            for(n=0;n<count;n=n+1)begin
                value=golden(n,len,sn,seed,delta,bad_checksum,vl);
                @(negedge clk);
                if(plane==0)begin rx_a_data=value;rx_a_valid=1;rx_a_last=with_last&&(n==count-1);end
                else begin rx_b_data=value;rx_b_valid=1;rx_b_last=with_last&&(n==count-1);end
                @(posedge clk);if(plane==0)while(!rx_a_ready)@(posedge clk);else while(!rx_b_ready)@(posedge clk);
            end
            @(negedge clk);if(plane==0)begin rx_a_valid=0;rx_a_last=0;end else begin rx_b_valid=0;rx_b_last=0;end
        end
    endtask
    task automatic check_counter(input integer index,input integer expected);
        begin @(negedge clk);stats_addr=index*4;#1;
            if(stats_error||stats_rdata!==expected)$fatal(1,"Counter phase=%0d index=%0d actual=%0d expected=%0d",phase,index,stats_rdata,expected);
        end
    endtask
    task automatic drain;begin wait(app_read==app_written);repeat(40)@(negedge clk);end endtask
    task automatic send_app(input integer count,input integer with_last);
        integer n;begin
            for(n=0;n<count;n=n+1)begin
                @(negedge clk);app_tx_data=n;app_tx_valid=1;app_tx_last=with_last&&(n==count-1);
                @(posedge clk);while(!app_tx_ready)@(posedge clk);
            end
            @(negedge clk);app_tx_valid=0;app_tx_last=0;
        end
    endtask
    // Separate counter DUT permits an explicit near-wrap setup without changing
    // production saturation thresholds or waiting 2**32 events.
    reg [35:0] isolated_events=0;reg isolated_clear=0;
    reg [7:0] isolated_addr=4;wire [31:0] isolated_data;wire isolated_error;
    afdx_es_stats isolated_stats(.sys_clk(clk),.sys_rst_n(!reset),.events(isolated_events),
        .app_tx_valid(1'b0),.app_tx_ready(1'b1),.app_tx_last(1'b0),.clear(isolated_clear),
        .read_addr(isolated_addr),.read_data(isolated_data),.read_error(isolated_error));
    initial begin
        repeat(5)@(negedge clk);reset=0;repeat(4200)@(negedge clk);
        phase=1;
        fork
            inject(0,1471,1,16,16'h0101,6000,0,0,0);
            inject(1,1471,1,32,16'h0102,7000,1,0,0);
        join
        repeat(40)@(negedge clk);
        check_counter(10,1);check_counter(11,1);check_counter(12,0);
        check_counter(22,1);check_counter(23,1);check_counter(24,0);
        phase=2;
        fork
            inject(0,17,1,16,16'h0101,44,0,0,0);
            inject(1,1471,1,32,16'h0102,900,0,0,0);
        join
        repeat(40)@(negedge clk);
        check_counter(10,2);check_counter(12,1);check_counter(22,2);check_counter(24,1);
        phase=3;
        fork
            inject(0,17,1,16,16'h0101,59,1,0,0);
            inject(1,17,1,32,16'h0102,60,1,1,0);
        join
        repeat(200)@(negedge clk);
        check_counter(10,3);check_counter(13,1);check_counter(22,3);check_counter(26,1);
        phase=4;
        expect_frame(1471,1,48,16'h0101);expect_frame(1471,1,96,16'h0102);
        fork
            inject(0,1471,1,48,16'h0101,1514,1,0,0);
            inject(1,1471,1,96,16'h0102,1514,1,0,0);
        join
        drain;check_counter(9,1);check_counter(21,1);
        phase=5;app_rx_ready=0;
        for(i=2;i<=7;i=i+1)expect_frame(1471,i,64+i,16'h0101);
        fork
            begin for(i=2;i<=7;i=i+1)inject(0,1471,i,64+i,16'h0101,1514,1,0,0);end
            begin wait(rx_a_valid&&!rx_a_ready);repeat(80)@(negedge clk);app_rx_ready=1;end
        join
        drain;check_counter(12,1);check_counter(9,7);
        phase=6;
        inject(0,1471,7,71,16'h0101,1514,1,0,0);repeat(2000)@(negedge clk);
        check_counter(16,1);check_counter(18,1);check_counter(10,4);
        inject(1,1471,7,71,16'h0101,1514,1,0,0);repeat(4000)@(negedge clk);
        check_counter(33,1);check_counter(21,2);
        expect_frame(17,9,80,16'h0101);inject(0,17,9,80,16'h0101,60,1,0,0);drain;
        check_counter(17,1);
        phase=7;
        inject(1,17,0,85,16'h0102,60,1,0,0);repeat(200)@(negedge clk);
        check_counter(28,1);check_counter(29,1);check_counter(22,4);
        inject(0,17,10,90,16'h0101,60,1,0,1);repeat(200)@(negedge clk);
        check_counter(14,1);check_counter(10,5);
        expect_frame(17,10,90,16'h0101);inject(0,17,10,90,16'h0101,60,1,0,0);drain;
        if(delivered!=10)$fatal(1,"RX delivery total");
        phase=8;
        stats_clear=1;@(negedge clk);stats_clear=0;
        for(i=0;i<36;i=i+1)check_counter(i,0);
        send_app(17,1);repeat(300)@(negedge clk);check_counter(0,1);check_counter(1,1);check_counter(2,1);
        tx_b_ready=0;send_app(17,1);wait(tx_b_valid);repeat(100)@(negedge clk);
        check_counter(1,2);check_counter(2,1);check_counter(3,0);check_counter(4,0);
        tx_b_ready=1;repeat(100)@(negedge clk);check_counter(2,2);
        send_app(1472,1);repeat(6000)@(negedge clk);
        check_counter(0,3);check_counter(1,2);check_counter(2,2);check_counter(5,1);check_counter(6,1);
        send_app(8,0);repeat(80)@(negedge clk);check_counter(7,1);
        repeat(40)@(negedge clk);check_counter(7,1);
        stats_addr=1;#1;if(!stats_error||stats_rdata!=0)$fatal(1,"unaligned stats read");
        stats_addr=252;#1;if(!stats_error||stats_rdata!=0)$fatal(1,"out-of-range stats read");
        @(negedge clk);isolated_stats.counters[1]=32'hfffffffe;isolated_events[1]=1;
        repeat(3)@(negedge clk);isolated_events=0;
        #1;if(isolated_data!==32'hffffffff)$fatal(1,"counter saturation");
        isolated_events[1]=1;isolated_clear=1;@(negedge clk);
        #1;if(isolated_data!=0)$fatal(1,"clear priority");
        isolated_events=0;isolated_clear=0;
        $display("RX PROTECTION STATS PASSED: simultaneous oversize/missing-last, recovery, backpressure, RX/TX reasons, saturation and clear");$finish;
    end
    initial begin #10000000;$fatal(1,"TIMEOUT RX protection stats phase=%0d",phase);end
endmodule
