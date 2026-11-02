`timescale 1ns/1ps
// 各VL独立运行615A，并在本层统计真实重试和完成事件。
module arinc615a_service #(
 parameter LOADER=1,SNMP_ENABLE=1,parameter integer VL_COUNT=2,MAX_FILE_BYTES=8192,
 parameter integer NAME_BYTES=16, // NAME_BYTES: 当前仿真配置的名称缓存，包含末尾零字节。
 parameter integer RETRY_CYCLES=12500000,DALLY_CYCLES=25000000,OP_TIMEOUT=125000000,STATUS_INTERVAL=12500000,
 parameter [255:0] TARGET_NAME=256'h4c5f5345
)(
 input wire clk,reset,input wire [VL_COUNT-1:0] abort,cmd_valid,
 output wire [VL_COUNT-1:0] cmd_ready,done,failed,
 input wire [3*VL_COUNT-1:0] operation,input wire [32*VL_COUNT-1:0] peer_ip,
 // 只提供每个当前任务的文件信息，不广播整份目录。
 input wire [256*VL_COUNT-1:0] header_name,data_name,part_number,
 input wire [32*VL_COUNT-1:0] header_size,data_size,
 input wire [VL_COUNT-1:0] header_ok,header_bad,data_commit,data_bad,
 output wire [VL_COUNT-1:0] header_pending,data_pending,output wire [16*VL_COUNT-1:0] result,
 input wire find_start,input wire [31:0] find_peer_ip,
 output wire find_done,output wire [31:0] found_ip,output wire [255:0] found_name,
 output wire [96*VL_COUNT-1:0] file_read_addr,file_write_addr,
 input wire [24*VL_COUNT-1:0] file_read_data,output wire [24*VL_COUNT-1:0] file_write_data,
 output wire [3*VL_COUNT-1:0] file_read_valid, // file_read_valid: 各会话的文件读取请求。
 input wire [3*VL_COUNT-1:0] file_read_ready, // file_read_ready: 各会话请求的文件字节已经返回。
 output wire [3*VL_COUNT-1:0] file_header,file_write_valid,input wire [3*VL_COUNT-1:0] file_write_ready,
 output wire [8*VL_COUNT-1:0] tx_data,output wire [VL_COUNT-1:0] tx_valid,tx_last,
 input wire [VL_COUNT-1:0] tx_ready,
 output wire [32*VL_COUNT-1:0] tx_dst_ip,output wire [16*VL_COUNT-1:0] tx_src_port,tx_dst_port,
 input wire [7:0] rx_data,input wire [VL_COUNT-1:0] rx_valid,input wire rx_last,
 output wire [VL_COUNT-1:0] rx_ready,input wire [31:0] rx_src_ip,input wire [15:0] rx_src_port,rx_dst_port,
 input wire [VL_COUNT-1:0] active,
 input wire [32*VL_COUNT-1:0] file_ids,
 output wire load_valid,load_failed,input wire load_ready,
 output wire [31:0] load_file,load_value,load_reason,load_overflow,load_success,load_failures,load_retries,
 input wire [7:0] stat_select,output /* stat_value：旧诊断位置，固定为0。 */ wire [31:0] stat_value
);
 wire [3*VL_COUNT-1:0] retries;
 wire [VL_COUNT-1:0] find_dones;wire [32*VL_COUNT-1:0] found_ips;
 // found_names: 每个VL发现的目标名，向APP输出时自动补零至32字节。
 wire [8*NAME_BYTES*VL_COUNT-1:0] found_names;
 assign find_done=find_dones[0];assign found_ip=found_ips[31:0];assign found_name=found_names[8*NAME_BYTES-1:0];
 genvar g;
 generate for(g=0;g<VL_COUNT;g=g+1)begin: vl
  arinc615a_node #(.LOADER(LOADER),.TARGET_TASK_FILTER(1),.NAME_BYTES(NAME_BYTES),.MAX_FILE_BYTES(MAX_FILE_BYTES),
   .RETRY_CYCLES(RETRY_CYCLES),.DALLY_CYCLES(DALLY_CYCLES),.OP_TIMEOUT(OP_TIMEOUT),
   .STATUS_INTERVAL(STATUS_INTERVAL),.TARGET_NAME(TARGET_NAME)) node(
   .clk(clk),.reset(reset),.abort(abort[g]),.cmd_valid(cmd_valid[g]),.cmd_ready(cmd_ready[g]),
   .cmd_operation(operation[3*g+:3]),.cmd_peer_ip(g==0 && find_start ? find_peer_ip : peer_ip[32*g+:32]),
   .header_name(header_name[256*g+:8*NAME_BYTES]),.data_name(data_name[256*g+:8*NAME_BYTES]),.part_number(part_number[256*g+:8*NAME_BYTES]),
   .header_size(header_size[32*g+:32]),.data_size(data_size[32*g+:32]),
   .header_ok(header_ok[g]),.header_bad(header_bad[g]),.data_commit(data_commit[g]),.data_bad(data_bad[g]),
   .header_pending(header_pending[g]),.data_pending(data_pending[g]),.done(done[g]),.failed(failed[g]),.busy(),.result(result[16*g+:16]),
   .find_start(g==0 && find_start),.find_done(find_dones[g]),.found_ip(found_ips[32*g+:32]),.found_name(found_names[8*NAME_BYTES*g+:8*NAME_BYTES]),
   .rx_data(rx_data),.rx_valid(rx_valid[g]),.rx_last(rx_last),.rx_ready(rx_ready[g]),
   .rx_src_ip(rx_src_ip),.rx_src_port(rx_src_port),.rx_dst_port(rx_dst_port),
   .tx_data(tx_data[8*g+:8]),.tx_valid(tx_valid[g]),.tx_last(tx_last[g]),.tx_ready(tx_ready[g]),
   .tx_dst_ip(tx_dst_ip[32*g+:32]),.tx_src_port(tx_src_port[16*g+:16]),.tx_dst_port(tx_dst_port[16*g+:16]),
   .app_read_addr(file_read_addr[96*g+:96]),.app_read_data(file_read_data[24*g+:24]),
   .app_read_valid(file_read_valid[3*g+:3]),.app_read_ready(file_read_ready[3*g+:3]),
   .app_header(file_header[3*g+:3]),.app_write_valid(file_write_valid[3*g+:3]),.app_write_ready(file_write_ready[3*g+:3]),
   .app_write_addr(file_write_addr[96*g+:96]),.app_write_data(file_write_data[24*g+:24]),
   .transferred(),.retry_events(retries[3*g+:3]));
 end endgenerate
 assign stat_value=0;
 generate if(SNMP_ENABLE)begin: telemetry
  afdx_snmp_load_events #(.VL_COUNT(VL_COUNT)) loading(
   .clk(clk),.reset(reset),.active(active),.done(done),.failed(failed),.file_ids(file_ids),.results(result),
   .retry_events(retries),.valid(load_valid),.ready(load_ready),.is_failure(load_failed),
   .file_id(load_file),.value(load_value),.reason(load_reason),.overflow_count(load_overflow),
   .success_count(load_success),.failure_count(load_failures),.retry_total(load_retries));
 end else begin: no_telemetry
  assign load_valid=0;assign load_failed=0;assign load_file=0;assign load_value=0;assign load_reason=0;
  assign load_overflow=0;assign load_success=0;assign load_failures=0;assign load_retries=0;
 end endgenerate
endmodule
