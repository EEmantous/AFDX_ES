`timescale 1ns/1ps
// 将一条事件编码为七个绑定的SNMPv2 Trap。
module snmp_v2_trap # (parameter integer CLOCK_HZ=12500000)(
    input wire clk,reset_n,event_valid,
    input wire [31:0] uptime, // uptime: 本地时钟给出的百分之一秒计数。
    output wire event_ready,
    input wire [31:0] event_class,event_source,event_value,event_threshold,event_detail,
    input wire [31:0] target_ip,
    input wire [15:0] target_vl,
    input wire [255:0] community,
    input wire [5:0] community_length,
    output wire [7:0] out_data,
    output wire out_valid,out_last,
    input wire out_ready,
    output wire [10:0] out_length,
    output /* route_ip：接受事件时锁存的Trap目标IP与VL。 */ reg [31:0] route_ip,
    output /* route_vl：接受事件时锁存的Trap目标IP与VL。 */ reg [15:0] route_vl
);
    localparam IDLE=0,SEND=1;
    /* state：当前步骤。 */ reg state;
    /* fields：锁存的6个无符号值：uptime、class、source、value、threshold、detail。 */ reg [31:0] fields[0:5];
    /* saved_community：接受事件时锁存的community内容与字节长度。 */ reg [255:0] saved_community;
    /* saved_length：接受事件时锁存的community内容与字节长度。 */ reg [5:0] saved_length;
    /* cursor：当前字节位置。 */ reg [10:0] cursor;
    /* n：当前字节位置；body_length：按锁存字段最短编码长度组合计算的绑定正文/头/完整消息长度；header_length：按锁存字段最短编码长度组合计算的绑定正文/头/完整消息长度；total_length：按锁存字段最短编码长度组合计算的绑定正文/头/完整消息长度。 */ integer n,body_length,header_length,total_length;
    function integer usize;
        input [31:0] v;
        begin if(v<128) usize=1;else if(v<32768) usize=2;
            else if(v<8388608) usize=3;else if(!v[31]) usize=4;else usize=5;end
    endfunction
    function integer name_length;
        input /* f：当前文件位置。 */ integer f;begin name_length=f==0 ? 8 : (f==1 ? 10 : 9);end
    endfunction
    function integer value_length;
        input /* f：当前文件位置。 */ integer f;begin value_length=f==1 ? 8 : usize(fields[f==0 ? 0 : f-1]);end
    endfunction
    function [7:0] name_byte;
        input /* f：当前文件位置；k：当前字节或表项位置。 */ integer f,k;
        begin
            name_byte=0;
            if(f==0) case(k)
                0:name_byte='h2b;1:name_byte=6;2:name_byte=1;3:name_byte=2;
                4:name_byte=1;5:name_byte=1;6:name_byte=3;default:name_byte=0;
            endcase
            else if(f==1) case(k)
                0:name_byte='h2b;1:name_byte=6;2:name_byte=1;3:name_byte=6;
                4:name_byte=3;5:name_byte=1;6:name_byte=1;7:name_byte=4;8:name_byte=1;default:name_byte=0;
            endcase
            else case(k)
                0:name_byte='h2b;1:name_byte=6;2:name_byte=1;3:name_byte=3;
                4:name_byte='hce;5:name_byte='h0f;6:name_byte=3;7:name_byte=f-1;default:name_byte=0;
            endcase
        end
    endfunction
    function [7:0] byte_at;
        input /* p：当前字节或表项位置。 */ integer p;
        /* h：当前字节或表项位置；k：当前字节或表项位置；f：当前文件位置；nl：当前字节或表项位置；vl：当前字节或表项位置；offset：当前字节或表项位置；size：当前字节或表项位置；relative：当前字节或表项位置。 */ integer h,k,f,nl,vl,offset,size,relative;
        /* v：当前VL位置。 */ reg [31:0] v;
        begin
            h=9+saved_length;byte_at=0;
            if(p==0) byte_at='h30;else if(p==1) byte_at='h82;
            else if(p==2) byte_at=(total_length-4)>>8;else if(p==3) byte_at=total_length-4;
            else if(p==4) byte_at=2;else if(p==5 || p==6) byte_at=1;
            else if(p==7) byte_at=4;else if(p==8) byte_at=saved_length;
            else if(p<h) byte_at=saved_community>>(8*(saved_length-1-(p-9)));
            else if(p==h) byte_at='ha7;else if(p==h+1) byte_at='h82;
            else if(p==h+2) byte_at=(body_length+13)>>8;else if(p==h+3) byte_at=body_length+13;
            else if(p==h+4 || p==h+7 || p==h+10) byte_at=2;
            else if(p==h+5 || p==h+6 || p==h+8 || p==h+11) byte_at=1;
            else if(p==h+13) byte_at='h30;else if(p==h+14) byte_at='h82;
            else if(p==h+15) byte_at=body_length>>8;else if(p==h+16) byte_at=body_length;
            else if(p>=header_length) begin
                offset=header_length;
                for(f=0;f<7;f=f+1) begin
                    nl=name_length(f);vl=value_length(f);size=6+nl+vl;relative=p-offset;
                    if(p>=offset && p<offset+size) begin
                        if(relative==0) byte_at='h30;
                        else if(relative==1) byte_at=size-2;
                        else if(relative==2) byte_at=6;
                        else if(relative==3) byte_at=nl;
                        else if(relative<4+nl) byte_at=name_byte(f,relative-4);
                        else if(relative==4+nl) byte_at=f==0 ? 'h43 : (f==1 ? 6 : 'h42);
                        else if(relative==5+nl) byte_at=vl;
                        else begin
                            k=relative-6-nl;
                            if(f==1) case(k)
                                0:byte_at='h2b;1:byte_at=6;2:byte_at=1;3:byte_at=3;
                                4:byte_at='hce;5:byte_at='h0f;6:byte_at=0;default:byte_at=1;
                            endcase
                            else begin
                                v=fields[f==0 ? 0 : f-1];
                                byte_at=(vl==5 && k==0) ? 0 : v>>(8*(vl-1-k));
                            end
                        end
                    end
                    offset=offset+size;
                end
            end
        end
    endfunction
    always @* begin
        body_length=113+usize(fields[0])+usize(fields[1])+usize(fields[2])+usize(fields[3])+usize(fields[4])+usize(fields[5]);
        header_length=26+saved_length;total_length=header_length+body_length;
    end
    assign event_ready=reset_n && state==IDLE;
    assign out_valid=reset_n && state==SEND;
    assign out_last=out_valid && cursor==total_length-1;
    assign out_length=total_length;
    assign out_data=byte_at(cursor);
    /* i：当前通道或表项位置。 */ integer i;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            state<=IDLE;cursor<=0;
            saved_community<=0;saved_length<=1;route_ip<=0;route_vl<=0;
            for(i=0;i<6;i=i+1) fields[i]<=0;
        end else begin
            if(event_valid && event_ready) begin
                fields[0]<=uptime;fields[1]<=event_class;fields[2]<=event_source;
                fields[3]<=event_value;fields[4]<=event_threshold;fields[5]<=event_detail;
                saved_community<=community;saved_length<=community_length;
                route_ip<=target_ip;route_vl<=target_vl;cursor<=0;state<=SEND;
            end
            if(out_valid && out_ready) begin
                if(out_last) state<=IDLE;else cursor<=cursor+1'b1;
            end
        end
    end
endmodule
