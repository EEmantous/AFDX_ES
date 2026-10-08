`timescale 1ns/1ps
// One real DUT. External MAC-side traffic is driven by behavioral test tasks;
// no synthesizable switch/peer ES is needed to verify the standalone endpoint.
module tb_afdx_end_system;
    reg clk=0,reset=1;always #40 clk=~clk;
    reg [7:0] app_tx_data=0;reg app_tx_valid=0,app_tx_last=0;
    wire app_tx_ready;
    wire [7:0] app_rx_data;wire app_rx_valid,app_rx_last;
    reg app_rx_ready=1;wire [15:0] app_rx_vl_id;wire [7:0] app_rx_sequence_number;
    wire [7:0] tx_a_data,tx_b_data;wire tx_a_valid,tx_a_last,tx_b_valid,tx_b_last;
    reg tx_a_ready=1,tx_b_ready=1;
    reg [7:0] rx_a_data=0,rx_b_data=0;reg rx_a_valid=0,rx_a_last=0,rx_b_valid=0,rx_b_last=0;
    wire rx_a_ready,rx_b_ready;
    AFDX_top #(.BAG_CYCLES(12500),.DEDUP_WINDOW_CYCLES(20000)) dut(
        .clk(clk),.reset(reset),
        .app_tx_data(app_tx_data),.app_tx_valid(app_tx_valid),.app_tx_last(app_tx_last),.app_tx_ready(app_tx_ready),
        .app_rx_data(app_rx_data),.app_rx_valid(app_rx_valid),.app_rx_last(app_rx_last),.app_rx_ready(app_rx_ready),
        .app_rx_vl_id(app_rx_vl_id),.app_rx_sequence_number(app_rx_sequence_number),
        .tx_a_data(tx_a_data),.tx_a_valid(tx_a_valid),.tx_a_last(tx_a_last),.tx_a_ready(tx_a_ready),
        .tx_b_data(tx_b_data),.tx_b_valid(tx_b_valid),.tx_b_last(tx_b_last),.tx_b_ready(tx_b_ready),
        .rx_a_data(rx_a_data),.rx_a_valid(rx_a_valid),.rx_a_last(rx_a_last),.rx_a_ready(rx_a_ready),
        .rx_b_data(rx_b_data),.rx_b_valid(rx_b_valid),.rx_b_last(rx_b_last),.rx_b_ready(rx_b_ready),
        .stats_addr(8'd0),.stats_clear(1'b0),
        .stats_rdata(),.stats_error());
    reg [7:0] a_frames[0:32767],b_frames[0:32767];
    integer lengths[0:15],seeds[0:15],a_seen[0:15],b_seen[0:15];
    integer a_offset=0,b_offset=0,a_frame=1,b_frame=1,cycle=0;
    integer app_read=0,app_written=0,delivered=0,phase=0;
    reg [7:0] expected_data[0:32767],expected_sn[0:32767];
    reg [15:0] expected_vl[0:32767];reg expected_last[0:32767];
    reg stalled=0;reg [32:0] held;integer i,k;
    reg stall_a=0,stall_b=0,random_app_ready=0;
    function [7:0] golden;
        input integer sn,index;
        integer padded,ip_len,udp_len,sum,checksum;
        begin
            padded=lengths[sn]<17?17:lengths[sn];udp_len=padded+9;ip_len=udp_len+20;
            sum='h4500+ip_len+'h4000+'h4011+'hC0A8+1+'hC0A8+3;
            sum=(sum&65535)+(sum>>16);sum=(sum&65535)+(sum>>16);checksum=(~sum)&65535;
            golden=0;
            if(index>=42&&index<42+lengths[sn])golden=seeds[sn]+index-42;
            if(index==42+padded)golden=sn;
            case(index)
                0:golden=3;4:golden=1;5:golden=1;6:golden=2;11:golden=1;12:golden=8;
                14:golden='h45;16:golden=ip_len>>8;17:golden=ip_len;
                20,22:golden='h40;23:golden='h11;24:golden=checksum>>8;25:golden=checksum;
                26,30:golden='hC0;27,31:golden='hA8;29:golden=1;33:golden=3;
                34:golden=10001>>8;35:golden=10001;36:golden=20003>>8;37:golden=20003;
                38:golden=udp_len>>8;39:golden=udp_len;
                default:;
            endcase
        end
    endfunction
    always @(negedge clk)begin
        tx_a_ready=!stall_a && (cycle%7)!=2;
        tx_b_ready=!stall_b && (cycle%11)>3;
        if(random_app_ready)app_rx_ready=(cycle%13)>5;
    end
    always @(posedge clk)begin
        cycle=cycle+1;
        if(!reset)begin
            if(tx_a_valid&&tx_a_ready)begin
                if(a_offset==0)a_frame=tx_a_data==3?a_frame:0;
                if(a_frame<1||a_frame>9||tx_a_data!==golden(a_frame,a_offset))$fatal(1,"A golden bytes frame=%0d byte=%0d",a_frame,a_offset);
                a_frames[a_frame*2048+a_offset]=tx_a_data;
                if(tx_a_last)begin
                    if(a_offset!=42+(lengths[a_frame]<17?17:lengths[a_frame]))$fatal(1,"A length/last");
                    a_seen[a_frame]=a_seen[a_frame]+1;a_offset=0;
                    a_frame=a_frame+1;
                end else a_offset=a_offset+1;
            end
            if(tx_b_valid&&tx_b_ready)begin
                if(b_frame<1||b_frame>9||tx_b_data!==golden(b_frame,b_offset))$fatal(1,"B golden bytes frame=%0d byte=%0d",b_frame,b_offset);
                b_frames[b_frame*2048+b_offset]=tx_b_data;
                if(tx_b_last)begin
                    if(b_offset!=42+(lengths[b_frame]<17?17:lengths[b_frame]))$fatal(1,"B length/last");
                    b_seen[b_frame]=b_seen[b_frame]+1;b_offset=0;b_frame=b_frame+1;
                end else b_offset=b_offset+1;
            end
            if(stalled&&(!app_rx_valid||{app_rx_vl_id,app_rx_sequence_number,app_rx_last,app_rx_data}!==held))$fatal(1,"APP data/identity hold");
            stalled=app_rx_valid&&!app_rx_ready;
            held={app_rx_vl_id,app_rx_sequence_number,app_rx_last,app_rx_data};
            if(app_rx_valid&&app_rx_ready)begin
                if(app_read>=app_written||app_rx_data!==expected_data[app_read]||app_rx_last!==expected_last[app_read]||
                   app_rx_vl_id!==expected_vl[app_read]||app_rx_sequence_number!==expected_sn[app_read])
                    $fatal(1,"APP data/identity/count phase=%0d byte=%0d",phase,app_read);
                app_read=app_read+1;if(app_rx_last)delivered=delivered+1;
            end
        end
    end
    task automatic expect_frame(input integer sn,input [15:0] vl);
        integer n,padded;begin
            padded=lengths[sn]<17?17:lengths[sn];
            for(n=0;n<padded;n=n+1)begin
                expected_data[app_written]=n<lengths[sn]?seeds[sn]+n:0;
                expected_last[app_written]=(n==padded-1);expected_sn[app_written]=sn;expected_vl[app_written]=vl;app_written=app_written+1;
            end
        end
    endtask
    task automatic send(input integer sn,input integer len,input integer seed);
        integer n;begin
            lengths[sn]=len;seeds[sn]=seed;
            for(n=0;n<len;n=n+1)begin
                @(negedge clk);app_tx_data=seed+n;app_tx_valid=1;app_tx_last=(n==len-1);
                @(posedge clk);while(!app_tx_ready)@(posedge clk);
            end
            @(negedge clk);app_tx_valid=0;app_tx_last=0;
        end
    endtask
    task automatic inject(input integer plane,input integer sn,input [15:0] vl,input integer bad_checksum);
        integer n,total;reg [7:0] value;begin
            total=43+(lengths[sn]<17?17:lengths[sn]);
            for(n=0;n<total;n=n+1)begin
                value=a_seen[sn]?a_frames[sn*2048+n]:b_frames[sn*2048+n];
                if(n==4)value=vl[15:8];if(n==5)value=vl[7:0];
                if(bad_checksum&&n==24)value=value^1;
                @(negedge clk);
                if(plane==0)begin rx_a_data=value;rx_a_valid=1;rx_a_last=(n==total-1);end
                else begin rx_b_data=value;rx_b_valid=1;rx_b_last=(n==total-1);end
                @(posedge clk);if(plane==0)while(!rx_a_ready)@(posedge clk);else while(!rx_b_ready)@(posedge clk);
            end
            @(negedge clk);if(plane==0)begin rx_a_valid=0;rx_a_last=0;end else begin rx_b_valid=0;rx_b_last=0;end
        end
    endtask
    task automatic drain;begin wait(app_read==app_written);repeat(200)@(negedge clk);end endtask
    initial begin
        for(i=0;i<16;i=i+1)begin lengths[i]=0;seeds[i]=0;a_seen[i]=0;b_seen[i]=0;end
        repeat(4)@(negedge clk);reset=0;repeat(4200)@(negedge clk);
        phase=1;send(1,1,'h10);wait(a_seen[1]&&b_seen[1]);expect_frame(1,'h0101);inject(0,1,'h0101,0);drain;
        phase=2;send(2,18,'h20);wait(a_seen[2]&&b_seen[2]);expect_frame(2,'h0101);inject(0,2,'h0101,0);drain;
        inject(1,1,'h0101,0);inject(1,2,'h0101,0);repeat(300)@(negedge clk);if(delivered!=2)$fatal(1,"delayed old duplicate");
        phase=3;random_app_ready=1;send(3,1471,'h30);wait(a_seen[3]&&b_seen[3]);expect_frame(3,'h0101);
        fork inject(0,3,'h0101,0);inject(1,3,'h0101,0);join drain;
        // Receiving only one network still delivers; TX always creates both copies.
        phase=4;send(4,17,'h40);wait(a_seen[4]&&b_seen[4]);expect_frame(4,'h0101);inject(0,4,'h0101,0);drain;
        phase=5;send(5,17,'h50);wait(a_seen[5]&&b_seen[5]);expect_frame(5,'h0101);inject(1,5,'h0101,0);drain;
        // Both MAC outputs stalled: valid/data must wait, not cancel either copy.
        phase=6;stall_a=1;stall_b=1;send(6,17,'h60);
        wait(tx_a_valid&&tx_b_valid);repeat(20)@(negedge clk);
        if(a_seen[6]||b_seen[6])$fatal(1,"MAC stall lost pending copy");
        stall_a=0;stall_b=0;wait(a_seen[6]&&b_seen[6]);
        expect_frame(6,'h0101);inject(0,6,'h0101,0);drain;
        phase=7;
        fork send(7,18,'h70);begin wait(b_offset==10);@(negedge clk);stall_b=1;end join
        wait(a_seen[7]);expect_frame(7,'h0101);inject(0,7,'h0101,0);drain;
        if(b_seen[7])$fatal(1,"B partial stall ignored");
        stall_b=0;wait(b_seen[7]);
        phase=8;send(8,17,'h80);wait(a_seen[8]&&b_seen[8]);expect_frame(8,'h0101);
        inject(0,8,'h0101,0);inject(1,8,'h0101,0);drain;
        expect_frame(8,'h0102);inject(1,8,'h0102,0);drain;
        inject(0,8,'h0101,1);repeat(300)@(negedge clk);if(delivered!=9)$fatal(1,"bad IP checksum accepted");
        phase=9;send(9,17,'h90);wait(a_seen[9]&&b_seen[9]);expect_frame(9,'h0101);inject(0,9,'h0101,0);inject(1,9,'h0101,0);drain;
        for(i=1;i<=9;i=i+1)begin
            if(a_seen[i]!=1)$fatal(1,"A replica totals");
            if(b_seen[i]!=1)$fatal(1,"B replica totals");
            if(a_seen[i]&&b_seen[i])for(k=0;k<43+(lengths[i]<17?17:lengths[i]);k=k+1)
                if(a_frames[i*2048+k]!==b_frames[i*2048+k])$fatal(1,"A/B copy mismatch");
        end
        if(delivered!=10)$fatal(1,"delivery total");
        $display("V3 END SYSTEM PASSED: 9 shared TX frames, 10 identity-checked deliveries, external MAC models only");$finish;
    end
    initial begin #30000000;$fatal(1,"TIMEOUT V3 phase=%0d delivery=%0d app=%0d/%0d tx=%0d/%0d",phase,delivered,app_read,app_written,a_frame,b_frame);end
endmodule
