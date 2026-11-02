`timescale 1ns/1ps
// 按APP目录接收文件和任务，按记录格式送回完成结果与文件。
module afdx_app_control #(
 parameter integer MAP_ENTRIES=3,MAX_FILE_BYTES=8192,INPUT_TIMEOUT=12500000,
 parameter LOADER=1,
 parameter [32*MAP_ENTRIES-1:0] FILE_IDS={32'd3,32'd2,32'd1}
)(
 input wire clk,reset,input wire [7:0] rx_data,input wire rx_valid,output wire tx_ready,
 output /* tx_data：当前APP输出字节。 */ reg [7:0] tx_data,output /* tx_valid：APP输出字节有效。 */ reg tx_valid,input wire rx_ready,
 output wire [7:0] file_slot,catalog_index,catalog_data,output wire catalog_write,
 input wire [7:0] catalog_read_data,input wire [2:0] entry_flags,
 input wire [31:0] entry_file_id,entry_header_size,entry_data_size,entry_read_size,
 input wire entry_error,entry_locked,entry_readable,
 output wire [2:0] host_operation,
 output wire [31:0] host_offset,output wire host_header,host_begin,host_write,host_valid,
 output wire [7:0] host_wdata,input wire [7:0] host_rdata,input wire host_ready,host_error,
 output wire [66:0] submit_data,output wire submit_valid,input wire submit_ready,submit_error,
 input wire [63:0] result_data,input wire result_valid,output wire result_pop,
 output wire [MAP_ENTRIES-1:0] cancel_files,
 output /* find_start：接收FIND命令后发给615A服务的单周期启动脉冲。 */ reg find_start,output wire [31:0] find_peer_ip,input wire find_done,
 input wire [31:0] found_ip,input wire [255:0] found_name,
 output /* error_event：对应错误/拒绝/溢出/丢弃事件指示。 */ reg error_event
);
 localparam IDLE=0,HEADER=1,CATALOG=2,CHECK=3,SELECT_SOURCE=4,OPEN_SOURCE=5,
  PAYLOAD=6,VERIFY=7,DISPATCH=8,WAIT_RESULT=9,AFTER_RESULT=10,
  STORE_NEXT=11,AFTER_STORE=12,OUT_HEADER=13,OUT_FIXED=14,OUT_FILE=15,WAIT_FIND=16;
 /* state：当前步骤；return_state：子过程/发送/输出记录结束后返回的状态编码。 */ reg [4:0] state,return_state;
 /* operation：。 */ reg [2:0] operation;
 /* entry_count：本次目录声明的文件条目数；cursor：当前字节位置；field_index：目录头或113字节目录项内的字节位置；pending_tasks：已提交而尚未收到完成记录的任务数。 */ reg [7:0] entry_count,cursor,field_index,pending_tasks;
 /* peer_ip：APP目录头提供的对端IP；offset：当前头文件/数据文件的后端字节偏移。 */ reg [31:0] peer_ip,offset;
 /* source_header：源对象选择：1为LUH头；deliver_result_file：成功完成后需要向APP自动输出正式数据文件。 */ reg source_header,deliver_result_file;
 /* record_kind：；record_handle：APP输出记录文件句柄。 */ reg [7:0] record_kind,record_handle;
 /* record_length：APP输出记录正文长度；output_index：固定正文中的当前输出字节偏移。 */ reg [31:0] record_length,output_index;
 /* output_header_index：6字节APP记录头中的当前位置。 */ reg [2:0] output_header_index;
 /* fixed_payload：非文件输出记录正文缓存。 */ reg [287:0] fixed_payload;
 assign tx_ready=!reset && (state==IDLE || state==HEADER ||
  (state==CATALOG && !entry_locked) || (state==PAYLOAD && host_ready));
 wire take=rx_valid && tx_ready;
 wire output_take=tx_valid && rx_ready;
 assign file_slot=cursor;
 assign catalog_index=field_index;
 assign catalog_data=rx_data;
 assign catalog_write=take && state==CATALOG;
 assign host_operation=operation;
 assign host_offset=offset;
 assign host_header=(state==PAYLOAD || state==OPEN_SOURCE || state==SELECT_SOURCE) && source_header;
 assign host_begin=!reset && state==OPEN_SOURCE;
 assign host_write=state==PAYLOAD;
 assign host_valid=!reset && ((state==PAYLOAD && rx_valid) || (state==OUT_FILE && rx_ready));
 assign host_wdata=rx_data;
 assign submit_data={entry_file_id,operation,peer_ip};
 assign submit_valid=state==DISPATCH && cursor<entry_count && entry_flags[2] && operation!=0;
 assign result_pop=state==WAIT_RESULT && result_valid;
 assign cancel_files=0;
 assign find_peer_ip=peer_ip;
 wire [31:0] object_size=source_header ? entry_header_size : entry_data_size;
 function [7:0] lookup_slot(input [31:0] id);
 /* k：当前字节或表项位置。 */ integer k;
 begin lookup_slot=8'hff;for(k=0;k<MAP_ENTRIES;k=k+1)if(FILE_IDS[32*k+:32]==id)lookup_slot=k;end
 endfunction
 task emit;
 input [7:0] kind,handle;input [31:0] length;input [287:0] payload;input [4:0] next_state;
 begin
  record_kind<=kind;record_handle<=handle;record_length<=length;fixed_payload<=payload;
  output_header_index<=0;output_index<=0;return_state<=next_state;state<=OUT_HEADER;offset<=0;
 end endtask
 task fail(input [7:0] code);
 begin error_event<=1;emit(8'he0,cursor+1,1,{280'd0,code},pending_tasks==0 ? IDLE : WAIT_RESULT);end
 endtask
 task next_object;
 begin offset<=0;
  if(source_header)source_header<=0;else begin source_header<=1;cursor<=cursor+1'b1;end
  state<=SELECT_SOURCE;
 end endtask
 always @*begin
  tx_valid=0;tx_data=0;
  if(!reset)case(state)
   OUT_HEADER:begin
    tx_valid=1;
    case(output_header_index)
     0:tx_data=record_kind;1:tx_data=record_handle;
     default:tx_data=record_length[8*(output_header_index-2)+:8];
    endcase
   end
   OUT_FIXED:begin tx_valid=1;tx_data=fixed_payload[8*output_index+:8];end
   OUT_FILE:begin
    tx_valid=host_ready;
    tx_data=host_rdata;
   end
   default:begin end
  endcase
 end
 always @(posedge clk)begin
  if(reset)begin
   state<=IDLE;return_state<=IDLE;operation<=0;entry_count<=0;cursor<=0;field_index<=0;
   pending_tasks<=0;peer_ip<=0;offset<=0;source_header<=1;deliver_result_file<=0;
   record_kind<=0;record_handle<=0;record_length<=0;output_index<=0;
   output_header_index<=0;fixed_payload<=0;find_start<=0;error_event<=0;
  end else begin
   find_start<=0;error_event<=0;
   case(state)
    IDLE:if(take)begin
     cursor<=0;entry_count<=0;field_index<=1;pending_tasks<=0;operation<=0;peer_ip<=0;
     state<=HEADER;
    end
    HEADER:if(take)begin
     field_index<=field_index+1'b1;
     case(field_index)
      1:operation<=rx_data[2:0];
      2:entry_count<=rx_data;
      3,4,5,6:peer_ip[8*(field_index-3)+:8]<=rx_data;
      default:begin end
     endcase
     if(field_index==6)begin
      field_index<=0;cursor<=0;
      if(operation==5)begin find_start<=1;state<=WAIT_FIND;end else state<=CATALOG;
     end
    end
    CATALOG:if(take)begin
     if(field_index==112)begin
      field_index<=0;
      if(cursor==entry_count-1)begin cursor<=0;state<=CHECK;end else cursor<=cursor+1'b1;
     end else field_index<=field_index+1'b1;
    end
    CHECK:begin
     if(cursor==entry_count-1)begin cursor<=0;source_header<=1;state<=SELECT_SOURCE;end
     else cursor<=cursor+1'b1;
    end
    SELECT_SOURCE:begin
     if(cursor==entry_count)begin cursor<=0;state<=VERIFY;end
     else if(source_header ? entry_flags[0] : entry_flags[1])begin offset<=0;state<=OPEN_SOURCE;end
     else next_object;
    end
    OPEN_SOURCE:if(object_size==0)next_object;else state<=PAYLOAD;
    PAYLOAD:if(take)begin
     if(offset+1==object_size)next_object;
     else offset<=offset+1'b1;
    end
    VERIFY:begin
     if(cursor==entry_count-1)begin cursor<=0;state<=DISPATCH;end
     else cursor<=cursor+1'b1;
    end
    DISPATCH:begin
     if(cursor==entry_count)begin
      cursor<=0;emit(8'h30,0,1,288'd0,operation==0 ? STORE_NEXT : WAIT_RESULT);
     end else if(!entry_flags[2] || operation==0)cursor<=cursor+1'b1;
     else if(submit_error)fail(8'd8);
     else if(submit_valid && submit_ready)begin cursor<=cursor+1'b1;pending_tasks<=pending_tasks+1'b1;end
    end
    STORE_NEXT:begin
     if(cursor==entry_count)state<=IDLE;
     else if(entry_flags[1])begin
      emit(8'h10,cursor+1,entry_read_size,288'd0,AFTER_STORE);
     end else cursor<=cursor+1'b1;
    end
    AFTER_STORE:begin cursor<=cursor+1'b1;state<=STORE_NEXT;end
    WAIT_RESULT:begin
     if(result_valid)begin
      cursor<=lookup_slot(result_data[31:0]);
      if(pending_tasks!=0)pending_tasks<=pending_tasks-1'b1;
      deliver_result_file<=!result_data[56] && result_data[47:32]==3 &&
       (LOADER ? (operation==3 || operation==4) : operation==2);
      emit(8'h20,lookup_slot(result_data[31:0])+1,8,{224'd0,result_data},AFTER_RESULT);
     end else if(pending_tasks==0)state<=IDLE;
    end
    AFTER_RESULT:begin
     if(deliver_result_file)begin
      deliver_result_file<=0;
      emit(8'h10,cursor+1,entry_read_size,288'd0,WAIT_RESULT);
     end else state<=WAIT_RESULT;
    end
    WAIT_FIND:if(find_done)emit(8'h40,0,36,{found_name,found_ip},IDLE);
    OUT_HEADER:if(output_take)begin
     if(output_header_index==5)begin
      if(record_length==0)state<=return_state;
      else state<=record_kind==8'h10 ? OUT_FILE : OUT_FIXED;
     end else output_header_index<=output_header_index+1'b1;
    end
    OUT_FIXED:if(output_take)begin
     if(output_index+1==record_length)state<=return_state;else output_index<=output_index+1'b1;
    end
    OUT_FILE:if(output_take)begin
     if(offset+1==record_length)state<=return_state;else offset<=offset+1'b1;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
