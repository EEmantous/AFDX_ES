`timescale 1ns/1ps
// APP、文件、615A、SNMP和A/B链路连接；外部IO固定62位。
module AFDX_top #(
 parameter integer CLOCK_HZ=12500000,
 // 独立配置业务TX/RX数量；默认10 TX、100 RX，不计SNMP专用VL。
 parameter LOADER=1,
 parameter SNMP_ENABLE=1,
 parameter [15:0] SNMP_RX_VL=16'h0102,SNMP_RESPONSE_VL=16'h0103,SNMP_NOTIFY_VL=16'h0104,
 parameter integer SNMP_COMMUNITY_LENGTH=6,parameter [255:0] SNMP_COMMUNITY="public",
 parameter [31:0] SNMP_TARGET_IP=0,SNMP_CONTROL=32'h3fe,
 parameter integer SNMP_WINDOW_CYCLES=CLOCK_HZ,SNMP_COOLDOWN_CYCLES=CLOCK_HZ,SNMP_RETRY_THRESHOLD=1,
 parameter RTC_MASTER=LOADER,parameter [31:0] RTC_PEER_IP=0,
 parameter [31:0] RTC_INITIAL_SECONDS=0,parameter integer RTC_POLL_CYCLES=CLOCK_HZ,
 parameter integer VL_COUNT=10,TX_VL_COUNT=VL_COUNT,RX_VL_COUNT=100,
 // TASK_DEPTH/FRAME_DEPTH: 现有用例需要的每VL待办任务数和完整发送帧数。
 parameter integer TASK_DEPTH=2,FRAME_DEPTH=1,MAP_ENTRIES=TX_VL_COUNT,
 // Synchronous A/B simulation profile: track recent copies for 100 us.
 // History capacity covers recent frames, not the number of RX subscriptions.
 parameter integer RX_DEDUP_HISTORY=64,
 parameter integer RX_DEDUP_WINDOW_CYCLES=(CLOCK_HZ+9999)/10000,
 parameter integer MAX_FILE_BYTES=8192,EVENT_DEPTH=MAP_ENTRIES+4,
 parameter integer SNMP_BAG_CYCLES=CLOCK_HZ/100,
 // 以下超时和BAG均以clk周期计；改变CLOCK_HZ时需同步检查覆盖参数。
 parameter integer RETRY_CYCLES=CLOCK_HZ,DALLY_CYCLES=2*CLOCK_HZ,
 parameter integer OP_TIMEOUT=10*CLOCK_HZ,STATUS_INTERVAL=CLOCK_HZ,
 parameter integer TASK_GUARD_CYCLES=CLOCK_HZ/1000,
 parameter integer RTC_TIMEOUT_CYCLES=CLOCK_HZ,
 parameter [31:0] RTC_HOLDOVER_CYCLES=32'd30*CLOCK_HZ,
 // 打包数组低位对应索引0；文件ID经FILE_VLS映射到独立任务/BAG队列。
 parameter [16*TX_VL_COUNT-1:0] TX_VL_IDS=default_tx_ids(LOADER),
 parameter [16*RX_VL_COUNT-1:0] RX_VL_IDS=default_rx_ids(LOADER),
 // Each RX subscription selects one of the TX/615A service channels.
 parameter [8*RX_VL_COUNT-1:0] RX_SERVICE_MAP=default_rx_services(0),
 // Simulation performance default: one cycle adds no intentional VL throttling.
 parameter [32*TX_VL_COUNT-1:0] VL_BAG_CYCLES={TX_VL_COUNT{32'd1}},
 parameter [32*MAP_ENTRIES-1:0] FILE_IDS=default_file_ids(0),
 parameter [8*MAP_ENTRIES-1:0] FILE_VLS=default_file_services(0),
 parameter [31:0] LOCAL_IP=32'hc0a80003,
 parameter [47:0] SRC_MAC={16'h0200,LOCAL_IP},
 parameter [255:0] TARGET_NAME=256'h4c5f5345
)(
 // Competition template + complete A/B physical byte streams, 62 IO bits.
 input wire clk,reset,
 // APP consumes rx_data on rx_valid && tx_ready; emits tx_data on tx_valid && rx_ready.
 output wire [7:0] tx_data,input wire [7:0] rx_data,
 output wire tx_valid,input wire rx_valid,
 output wire tx_ready,input wire rx_ready,
 output wire [7:0] gmii_tx_a_txd,output wire gmii_tx_a_en,gmii_tx_a_er,
 output wire [7:0] gmii_tx_b_txd,output wire gmii_tx_b_en,gmii_tx_b_er,
 input wire [7:0] gmii_rx_a_rxd,input wire gmii_rx_a_dv,gmii_rx_a_er,
 input wire [7:0] gmii_rx_b_rxd,input wire gmii_rx_b_dv,gmii_rx_b_er
);

 // Generated default tables avoid zero/FFFF and the reserved management VLs.
 function [15:0] business_id(input /* index：当前字节或表项位置。 */ integer index,input /* base：默认业务VL编号函数的起始值。 */ integer base);
 /* value：本次计算值。 */ integer value;begin value=base+index;if(value>=16'h0102)value=value+3;business_id=value;end endfunction
 function [16*TX_VL_COUNT-1:0] default_tx_ids(input /* role：默认VL表函数的角色参数。 */ integer role);
 /* k：当前字节或表项位置。 */ integer k;begin for(k=0;k<TX_VL_COUNT;k=k+1)default_tx_ids[16*k+:16]=business_id(k,role ? 1 : TX_VL_COUNT+1);end endfunction
 function [16*RX_VL_COUNT-1:0] default_rx_ids(input /* role：默认VL表函数的角色参数。 */ integer role);
 /* k：当前字节或表项位置。 */ integer k;begin for(k=0;k<RX_VL_COUNT;k=k+1)default_rx_ids[16*k+:16]=business_id(k,role ? TX_VL_COUNT+1 : 1);end endfunction
 function [8*RX_VL_COUNT-1:0] default_rx_services(input /* unused：默认文件/服务映射函数的占位参数。 */ integer unused);
 /* k：当前字节或表项位置。 */ integer k;begin for(k=0;k<RX_VL_COUNT;k=k+1)default_rx_services[8*k+:8]=k%(TX_VL_COUNT>0 ? TX_VL_COUNT : 1);end endfunction
 function [32*MAP_ENTRIES-1:0] default_file_ids(input /* unused：默认文件/服务映射函数的占位参数。 */ integer unused);
 /* k：当前字节或表项位置。 */ integer k;begin for(k=0;k<MAP_ENTRIES;k=k+1)default_file_ids[32*k+:32]=k+1;end endfunction
 function [8*MAP_ENTRIES-1:0] default_file_services(input /* unused：默认文件/服务映射函数的占位参数。 */ integer unused);
 /* k：当前字节或表项位置。 */ integer k;begin for(k=0;k<MAP_ENTRIES;k=k+1)default_file_services[8*k+:8]=k%(TX_VL_COUNT>0 ? TX_VL_COUNT : 1);end endfunction

 wire gmii_tx_a_clk,gmii_tx_b_clk;
 wire gmii_rx_a_clk=clk,gmii_rx_b_clk=clk;
 localparam [31:0] SNMP_BAG_VALUE=SNMP_BAG_CYCLES;
 localparam integer NETWORK_VL_COUNT=TX_VL_COUNT+(SNMP_ENABLE ? 2 : 0);
 localparam integer NETWORK_RX_COUNT=RX_VL_COUNT+(SNMP_ENABLE ? 1 : 0);
 wire [15:0] snmp_tx_data;wire [1:0] snmp_tx_valid,snmp_tx_last,snmp_tx_ready;
 wire [63:0] snmp_tx_ip;wire [31:0] snmp_tx_src,snmp_tx_dst;
 wire snmp_rx_ready;
 wire [1023:0] snmp_network_statistics;wire [191:0] snmp_alarm_counts;
 wire [1151:0] snmp_live_statistics;
 wire [31:0] load_overflow,load_success,load_failures,load_retries;
 wire load_event_valid,load_event_ready,load_event_failed;
 wire [31:0] load_event_file,load_event_value,load_event_reason;
 assign snmp_live_statistics={load_retries,load_failures,load_success,load_overflow,snmp_network_statistics};
 // Direct APP manifest and payload stream.
 wire [7:0] stat_select=8'd0;wire [31:0] network_stat,time_stat,task_stat,service_stat;
 wire [TX_VL_COUNT-1:0] active,done,failed,abort,file_abort,commit_bad,cmd_valid,cmd_ready,service_done,service_failed;
 wire [16*TX_VL_COUNT-1:0] service_result;
 wire [32*TX_VL_COUNT-1:0] current_file_ids,current_peers;wire [3*TX_VL_COUNT-1:0] current_operations;
 wire [TX_VL_COUNT-1:0] header_ok,header_bad,data_commit,data_bad,header_pending,data_pending;
 wire [256*TX_VL_COUNT-1:0] header_names,data_names,part_numbers;
 wire [32*TX_VL_COUNT-1:0] header_sizes,data_sizes;wire [8*TX_VL_COUNT-1:0] task_slots;
 wire [31:0] locked_count;wire reserve_file,file_start_error,any_locked,file0_locked,file_fault;
 wire [2:0] reserve_operation;
 wire [96*TX_VL_COUNT-1:0] file_read_addr,file_write_addr;wire [24*TX_VL_COUNT-1:0] file_read_data,file_write_data;
 // file_read_valid/file_read_ready: 各TFTP会话向共享文件RAM请求字节及返回字节的握手。
 wire [3*TX_VL_COUNT-1:0] file_read_valid,file_read_ready;
 wire [3*TX_VL_COUNT-1:0] file_header,file_write_valid,file_write_ready;
 wire [24*TX_VL_COUNT-1:0] channel_file_slots;
 wire find_start,find_done,result_pending;wire [31:0] find_peer_ip,found_ip;wire [255:0] found_name;
 wire [3:0] task_events;wire network_drop;
 wire [8*TX_VL_COUNT-1:0] service_tx_data,network_tx_data;
 wire [TX_VL_COUNT-1:0] service_tx_valid,service_tx_last,service_tx_ready,network_tx_valid,network_tx_last,network_tx_ready;
 wire [32*TX_VL_COUNT-1:0] service_tx_ip,network_tx_ip;
 wire [16*TX_VL_COUNT-1:0] service_tx_src,service_tx_dst,network_tx_src,network_tx_dst;
 localparam RX_CHANNEL_WIDTH=NETWORK_RX_COUNT<=256 ? 8 : $clog2(NETWORK_RX_COUNT);
 wire [RX_CHANNEL_WIDTH-1:0] rx_channel;wire [7:0] udp_rx_data;wire udp_rx_valid,udp_rx_last;wire [31:0] rx_src_ip;wire [15:0] rx_src_port,rx_dst_port;
 wire [TX_VL_COUNT-1:0] service_rx_valid,service_rx_ready;wire [RX_VL_COUNT-1:0] network_rx_ready;
 wire business_rx=rx_channel<RX_VL_COUNT;
 wire [7:0] rx_service=business_rx ? RX_SERVICE_MAP[8*rx_channel+:8] : 0;



 // Direct file stream. There is no CSR or bus decoder in this path.
 wire [7:0] app_file_slot,catalog_index,catalog_data,catalog_read_data,app_wdata,app_rdata;
 wire catalog_write,entry_locked,entry_readable,app_host_begin,app_host_write,app_host_valid,app_host_ready,app_host_error;
 wire [2:0] entry_flags,app_operation;wire [31:0] entry_file_id,entry_header_size,entry_data_size,entry_read_size,app_offset;
 wire app_host_header,submit_valid,submit_ready,submit_error,task_result_valid,task_result_pop,app_error;
 wire [66:0] submit_data;wire [63:0] task_result_data;wire [MAP_ENTRIES-1:0] cancel_files;
 afdx_app_control #(.MAP_ENTRIES(MAP_ENTRIES),.MAX_FILE_BYTES(MAX_FILE_BYTES),.INPUT_TIMEOUT(CLOCK_HZ),.LOADER(LOADER),.FILE_IDS(FILE_IDS)) app(
  .clk(clk),.reset(reset),.rx_data(rx_data),.rx_valid(rx_valid),.tx_ready(tx_ready),
  .tx_data(tx_data),.tx_valid(tx_valid),.rx_ready(rx_ready),
  .file_slot(app_file_slot),.catalog_index(catalog_index),.catalog_data(catalog_data),.catalog_write(catalog_write),
  .catalog_read_data(catalog_read_data),.entry_flags(entry_flags),.entry_file_id(entry_file_id),
  .entry_header_size(entry_header_size),.entry_data_size(entry_data_size),.entry_read_size(entry_read_size),
  .entry_error(file_start_error),.entry_locked(entry_locked),.entry_readable(entry_readable),.host_operation(app_operation),
  .host_offset(app_offset),.host_header(app_host_header),.host_begin(app_host_begin),.host_write(app_host_write),
  .host_valid(app_host_valid),.host_wdata(app_wdata),.host_rdata(app_rdata),.host_ready(app_host_ready),.host_error(app_host_error),
  .submit_data(submit_data),.submit_valid(submit_valid),.submit_ready(submit_ready),.submit_error(submit_error),
  .result_data(task_result_data),.result_valid(task_result_valid),.result_pop(task_result_pop),
  .cancel_files(cancel_files),.find_start(find_start),.find_peer_ip(find_peer_ip),.find_done(find_done),.found_ip(found_ip),.found_name(found_name),.error_event(app_error));
 afdx_file_service #(.LOADER(LOADER),.VL_COUNT(TX_VL_COUNT),.CHANNEL_COUNT(3*TX_VL_COUNT),.MAP_ENTRIES(MAP_ENTRIES),
  .MAX_FILE_BYTES(MAX_FILE_BYTES),.FILE_IDS(FILE_IDS),.FILE_VLS(FILE_VLS),.TARGET_NAME(TARGET_NAME)) files(
  .clk(clk),.reset(reset),.host_slot(app_file_slot),.catalog_index(catalog_index),.catalog_data(catalog_data),.catalog_write(catalog_write),
  .catalog_read_data(catalog_read_data),.entry_flags(entry_flags),.entry_file_id(entry_file_id),
  .entry_header_size(entry_header_size),.entry_data_size(entry_data_size),.entry_read_size(entry_read_size),.entry_locked(entry_locked),.entry_readable(entry_readable),
  .host_operation(app_operation),.host_offset(app_offset),.host_header(app_host_header),.host_begin(app_host_begin),
  .host_write(app_host_write),.host_valid(app_host_valid),.host_wdata(app_wdata),.host_rdata(app_rdata),
  .host_ready(app_host_ready),.host_error(app_host_error),.cancel_files(cancel_files),
  .locked_count(locked_count),.any_locked(any_locked),.file0_locked(file0_locked),
  .reserve_file(reserve_file),.reserve_operation(reserve_operation),.start_error(file_start_error),
  .file_ids(current_file_ids),.done(done),.failed(failed),.header_pending(header_pending),.data_pending(data_pending),
  .header_name(header_names),.data_name(data_names),.part_number(part_numbers),.header_size(header_sizes),.data_size(data_sizes),.task_slots(task_slots),
  .header_ok(header_ok),.header_bad(header_bad),.data_commit(data_commit),.data_bad(data_bad),
  .abort_tasks(file_abort),.task_commit_bad(commit_bad),.fault_event(file_fault),
  .channel_file_slots(channel_file_slots),.read_addr(file_read_addr),.write_addr(file_write_addr),
  .is_header(file_header),.write_valid(file_write_valid),.write_ready(file_write_ready),.write_data(file_write_data),.read_data(file_read_data),
  .read_valid(file_read_valid),.read_ready(file_read_ready));
 arinc615a_tasks #(.LOADER(LOADER),.VL_COUNT(TX_VL_COUNT),.TASK_DEPTH(TASK_DEPTH),.EVENT_DEPTH(EVENT_DEPTH),.MAP_ENTRIES(MAP_ENTRIES),
  .OP_TIMEOUT(OP_TIMEOUT),.TASK_GUARD_CYCLES(TASK_GUARD_CYCLES),.FILE_IDS(FILE_IDS),.FILE_VLS(FILE_VLS)) tasks(
  .clk(clk),.reset(reset),.submit_data(submit_data),.submit_valid(submit_valid),.submit_ready(submit_ready),.submit_error(submit_error),
  .file_start_error(file_start_error),.cancel({TX_VL_COUNT{1'b0}}),
  .locked_count(locked_count),.reserve_file(reserve_file),.reserve_operation(reserve_operation),.file_abort(file_abort),.commit_bad(commit_bad),
  .abort(abort),.active(active),.done(done),.failed(failed),.cmd_valid(cmd_valid),.file_ids(current_file_ids),.peer_ips(current_peers),.operations(current_operations),
  .cmd_ready(cmd_ready),.service_done(service_done),.service_failed(service_failed),.service_result(service_result),
  .find_done(find_done),.result_data(task_result_data),.result_valid(task_result_valid),.result_pop(task_result_pop),
  .result_pending(result_pending),.events(task_events),.stat_select(stat_select),.stat_value(task_stat));
 arinc615a_service #(.SNMP_ENABLE(SNMP_ENABLE),.LOADER(LOADER),.VL_COUNT(TX_VL_COUNT),.MAX_FILE_BYTES(MAX_FILE_BYTES),.RETRY_CYCLES(RETRY_CYCLES),
  .DALLY_CYCLES(DALLY_CYCLES),.OP_TIMEOUT(OP_TIMEOUT),.STATUS_INTERVAL(STATUS_INTERVAL),.TARGET_NAME(TARGET_NAME)) service(
  .clk(clk),.reset(reset),.abort(abort),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.done(service_done),.failed(service_failed),
  .operation(current_operations),.peer_ip(current_peers),.header_name(header_names),.data_name(data_names),.part_number(part_numbers),
  .header_size(header_sizes),.data_size(data_sizes),.header_ok(header_ok),.header_bad(header_bad),.data_commit(data_commit),.data_bad(data_bad),
  .header_pending(header_pending),.data_pending(data_pending),.result(service_result),
  .find_start(find_start),.find_peer_ip(find_peer_ip),.find_done(find_done),.found_ip(found_ip),.found_name(found_name),
  .file_read_addr(file_read_addr),.file_write_addr(file_write_addr),.file_read_data(file_read_data),.file_write_data(file_write_data),
  .file_read_valid(file_read_valid),.file_read_ready(file_read_ready),
  .file_header(file_header),.file_write_valid(file_write_valid),.file_write_ready(file_write_ready),
  .tx_data(service_tx_data),.tx_valid(service_tx_valid),.tx_last(service_tx_last),.tx_ready(service_tx_ready),
  .tx_dst_ip(service_tx_ip),.tx_src_port(service_tx_src),.tx_dst_port(service_tx_dst),
  .rx_data(udp_rx_data),.rx_valid(service_rx_valid),.rx_last(udp_rx_last),.rx_ready(service_rx_ready),
  .rx_src_ip(rx_src_ip),.rx_src_port(rx_src_port),.rx_dst_port(rx_dst_port),.stat_select(stat_select),.stat_value(service_stat),.active(active),.file_ids(current_file_ids),
  .load_valid(load_event_valid),.load_failed(load_event_failed),.load_ready(load_event_ready),
  .load_file(load_event_file),.load_value(load_event_value),.load_reason(load_event_reason),
  .load_overflow(load_overflow),.load_success(load_success),.load_failures(load_failures),.load_retries(load_retries));
 // rtc_timestamp: 本地电子时钟，供仿真观察当前秒和纳秒。
 wire [63:0] rtc_timestamp;
 wire [31:0] uptime=rtc_timestamp[63:32]*100+rtc_timestamp[31:0]/10000000; // uptime: 本地时钟换算的百分之一秒。
 afdx_rtc #(.CLOCK_HZ(CLOCK_HZ),.INITIAL_SECONDS(RTC_INITIAL_SECONDS)) clock(
  .clk(clk),.reset(reset),.timestamp(rtc_timestamp));
 genvar g,e; // g: 业务通道；e: 每通道的三个文件使用者。
 generate for(g=0;g<TX_VL_COUNT;g=g+1)begin: ports
  for(e=0;e<3;e=e+1)begin: file_channels
   assign channel_file_slots[8*(3*g+e)+:8]=task_slots[8*g+:8];
  end
  assign service_rx_valid[g]=udp_rx_valid && business_rx && rx_service==g;
  assign network_tx_data[8*g+:8]=service_tx_data[8*g+:8];
  assign network_tx_valid[g]=service_tx_valid[g];assign network_tx_last[g]=service_tx_last[g];
  assign service_tx_ready[g]=network_tx_ready[g];
  assign network_tx_ip[32*g+:32]=service_tx_ip[32*g+:32];
  assign network_tx_src[16*g+:16]=service_tx_src[16*g+:16];
  assign network_tx_dst[16*g+:16]=service_tx_dst[16*g+:16];
 end endgenerate
 genvar r;
 generate for(r=0;r<RX_VL_COUNT;r=r+1)begin: receive_routes
  localparam integer SERVICE=RX_SERVICE_MAP[8*r+:8];
  if(SERVICE<TX_VL_COUNT)begin
   assign network_rx_ready[r]=service_rx_ready[SERVICE];
  end else assign network_rx_ready[r]=1'b1;
 end endgenerate
 wire [NETWORK_VL_COUNT-1:0] all_network_tx_ready;
 wire [NETWORK_RX_COUNT-1:0] all_network_rx_ready;
 assign network_tx_ready=all_network_tx_ready[TX_VL_COUNT-1:0];
 assign all_network_rx_ready=SNMP_ENABLE ? {(rx_dst_port==161 ? snmp_rx_ready : 1'b1),network_rx_ready} : network_rx_ready;
 genvar s;
 generate if(SNMP_ENABLE)begin: snmp_management
  assign snmp_tx_ready=all_network_tx_ready[TX_VL_COUNT+:2];
  afdx_snmp_udp_service #(.CLOCK_HZ(CLOCK_HZ),.MANAGEMENT_BAG_CYCLES(SNMP_BAG_CYCLES),.RESPONSE_VL(SNMP_RESPONSE_VL),.NOTIFY_VL(SNMP_NOTIFY_VL),
   .BUSINESS_VL(TX_VL_IDS[15:0]),.COMMUNITY_LENGTH(SNMP_COMMUNITY_LENGTH),.COMMUNITY(SNMP_COMMUNITY),
   .DEFAULT_TARGET_IP(SNMP_TARGET_IP),.DEFAULT_CONTROL(SNMP_CONTROL),.DEFAULT_WINDOW(SNMP_WINDOW_CYCLES),
   .DEFAULT_COOLDOWN(SNMP_COOLDOWN_CYCLES),.DEFAULT_RETRY_THRESHOLD(SNMP_RETRY_THRESHOLD)) endpoint(
   .clk(clk),.reset(reset),.uptime(uptime),.rx_data(udp_rx_data),.rx_valid(udp_rx_valid && rx_channel==RX_VL_COUNT && rx_dst_port==161),
   .rx_last(udp_rx_last),.rx_ready(snmp_rx_ready),.rx_ip(rx_src_ip),.rx_port(rx_src_port),
   .tx_data(snmp_tx_data),.tx_valid(snmp_tx_valid),.tx_last(snmp_tx_last),.tx_ready(snmp_tx_ready),
   .tx_ip(snmp_tx_ip),.tx_src(snmp_tx_src),.tx_dst(snmp_tx_dst),
   .live_statistics(snmp_live_statistics),.network_counts(snmp_alarm_counts),
   .load_valid(load_event_valid),.load_failed(load_event_failed),.load_ready(load_event_ready),
   .load_file(load_event_file),.load_value(load_event_value),.load_reason(load_event_reason));
 end else begin: no_snmp_management
  assign snmp_tx_data=0;assign snmp_tx_valid=0;assign snmp_tx_last=0;
  assign snmp_tx_ip=0;assign snmp_tx_src=0;assign snmp_tx_dst=0;
  assign snmp_rx_ready=1;
  assign load_event_ready=1;
 end endgenerate
 wire [8*NETWORK_VL_COUNT-1:0] all_tx_data=SNMP_ENABLE ? {snmp_tx_data,network_tx_data} : network_tx_data;
 wire [NETWORK_VL_COUNT-1:0] all_tx_valid=SNMP_ENABLE ? {snmp_tx_valid,network_tx_valid} : network_tx_valid;
 wire [NETWORK_VL_COUNT-1:0] all_tx_last=SNMP_ENABLE ? {snmp_tx_last,network_tx_last} : network_tx_last;
 wire [32*NETWORK_VL_COUNT-1:0] all_tx_ip=SNMP_ENABLE ? {snmp_tx_ip,network_tx_ip} : network_tx_ip;
 wire [16*NETWORK_VL_COUNT-1:0] all_tx_src=SNMP_ENABLE ? {snmp_tx_src,network_tx_src} : network_tx_src;
 wire [16*NETWORK_VL_COUNT-1:0] all_tx_dst=SNMP_ENABLE ? {snmp_tx_dst,network_tx_dst} : network_tx_dst;
 afdx_network #(.VL_COUNT(NETWORK_VL_COUNT),.RX_VL_COUNT(NETWORK_RX_COUNT),.RX_CHANNEL_WIDTH(RX_CHANNEL_WIDTH),.DEDUP_HISTORY_DEPTH(RX_DEDUP_HISTORY),.DEDUP_WINDOW_CYCLES(RX_DEDUP_WINDOW_CYCLES),.FRAME_DEPTH(FRAME_DEPTH),.TX_VL_IDS(SNMP_ENABLE ? {SNMP_NOTIFY_VL,SNMP_RESPONSE_VL,TX_VL_IDS} : TX_VL_IDS),
  .RX_VL_IDS(SNMP_ENABLE ? {SNMP_RX_VL,RX_VL_IDS} : RX_VL_IDS),
  .VL_BAG_CYCLES(SNMP_ENABLE ? {SNMP_BAG_VALUE,SNMP_BAG_VALUE,VL_BAG_CYCLES} : VL_BAG_CYCLES),.LOCAL_IP(LOCAL_IP),.SRC_MAC(SRC_MAC)) network(
  .clk(clk),.reset(reset),.tx_data(all_tx_data),
  .tx_valid(all_tx_valid),
  .tx_last(all_tx_last),.tx_ready(all_network_tx_ready),
  .tx_dst_ip(all_tx_ip),
  .tx_src_port(all_tx_src),
  .tx_dst_port(all_tx_dst),
  .rx_data(udp_rx_data),.rx_valid(udp_rx_valid),.rx_last(udp_rx_last),.rx_ready(all_network_rx_ready),.rx_channel(rx_channel),
  .rx_src_ip(rx_src_ip),.rx_src_port(rx_src_port),.rx_dst_port(rx_dst_port),
  .stat_select(stat_select),.stat_value(network_stat),.drop_event(network_drop),
  .snmp_statistics(snmp_network_statistics),.snmp_alarm_counts(snmp_alarm_counts),
  .gmii_tx_a_clk(gmii_tx_a_clk),
  .gmii_tx_a_txd(gmii_tx_a_txd),
  .gmii_tx_a_en(gmii_tx_a_en),
  .gmii_tx_a_er(gmii_tx_a_er),
  .gmii_tx_b_clk(gmii_tx_b_clk),
  .gmii_tx_b_txd(gmii_tx_b_txd),
  .gmii_tx_b_en(gmii_tx_b_en),
  .gmii_tx_b_er(gmii_tx_b_er),
  .gmii_rx_a_clk(gmii_rx_a_clk),
  .gmii_rx_a_rxd(gmii_rx_a_rxd),
  .gmii_rx_a_dv(gmii_rx_a_dv),
  .gmii_rx_a_er(gmii_rx_a_er),
  .gmii_rx_b_clk(gmii_rx_b_clk),
  .gmii_rx_b_rxd(gmii_rx_b_rxd),
  .gmii_rx_b_dv(gmii_rx_b_dv),
  .gmii_rx_b_er(gmii_rx_b_er));

 endmodule
