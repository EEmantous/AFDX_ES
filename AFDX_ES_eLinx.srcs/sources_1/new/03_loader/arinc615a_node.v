`timescale 1ns/1ps
// 连接一个业务通道的615A控制器、三个TFTP会话和文件读写。
module arinc615a_node #(
 parameter LOADER=0,TARGET_TASK_FILTER=0,parameter integer NAME_BYTES=32,MAX_FILE_BYTES=8192,
 parameter integer RETRY_CYCLES=12500000,DALLY_CYCLES=25000000,
 parameter integer OP_TIMEOUT=125000000,STATUS_INTERVAL=12500000,
 parameter [8*NAME_BYTES-1:0] TARGET_NAME=256'h4c5f5345, // low bytes "ES_L"
 parameter [8*NAME_BYTES-1:0] TARGET_TYPE=256'h58444641,
 parameter [8*NAME_BYTES-1:0] TARGET_POSITION=256'h31,
 parameter [8*NAME_BYTES-1:0] LITERAL_NAME=TARGET_NAME,
 parameter [8*NAME_BYTES-1:0] SERIAL_NUMBER=256'h31303030,
 parameter [8*NAME_BYTES-1:0] MANUFACTURER=256'h58444e56 // "VNDX"
)(
 input wire clk,reset,abort,
 input wire cmd_valid,output wire cmd_ready,input wire [2:0] cmd_operation,input wire [31:0] cmd_peer_ip,
 input wire [8*NAME_BYTES-1:0] header_name,data_name,part_number,
 input wire [31:0] header_size,data_size,
 input wire header_ok,header_bad,data_commit,data_bad,
 output wire header_pending,data_pending,
 output wire done,failed,busy,output wire [15:0] result,
 input wire find_start,output /* find_done：一次操作完成指示。 */ reg find_done,output /* found_ip：最近有效FIND IAN发布的目标IP和名称。 */ reg [31:0] found_ip,
 output /* found_name：最近有效FIND IAN发布的目标IP和名称。 */ reg [8*NAME_BYTES-1:0] found_name,
 input wire [7:0] rx_data,input wire rx_valid,rx_last,output wire rx_ready,
 input wire [31:0] rx_src_ip,input wire [15:0] rx_src_port,rx_dst_port,
 output wire [7:0] tx_data,output wire tx_valid,tx_last,input wire tx_ready,
 output wire [31:0] tx_dst_ip,output wire [15:0] tx_src_port,tx_dst_port,
 output wire [95:0] app_read_addr,input wire [23:0] app_read_data,
 output wire [2:0] app_read_valid, // app_read_valid: 三个会话各自请求读取文件字节。
 input wire [2:0] app_read_ready, // app_read_ready: 对应文件字节已经返回。
 output wire [2:0] app_header,app_write_valid,input wire [2:0] app_write_ready,
 output wire [95:0] app_write_addr,output wire [23:0] app_write_data,
 output wire [95:0] transferred,output wire [2:0] retry_events
);
 function integer text_length;
 input [8*NAME_BYTES-1:0] name;/* k：当前字节或表项位置。 */ integer k;
 begin text_length=NAME_BYTES;for(k=NAME_BYTES-1;k>=0;k=k-1)if(name[8*k+:8]==0)text_length=k;end
 endfunction
 function [8*NAME_BYTES-1:0] find_identity;
 input /* field：当前字节或表项位置。 */ integer field;
 begin case(field)
  0:find_identity=TARGET_NAME;1:find_identity=TARGET_TYPE;2:find_identity=TARGET_POSITION;
  3:find_identity=LITERAL_NAME;default:find_identity=MANUFACTURER;
 endcase end endfunction
 function [8*NAME_BYTES-1:0] protocol_name;
 input [3:0] kind;
 /* k：当前字节或表项位置；n：当前字节位置。 */ integer k,n;/* ext：控制文件类别对应的三字符扩展名。 */ reg [23:0] ext;
 begin
  case(kind)
  1:ext="LCI";2:ext="LUI";3:ext="LND";4:ext="LNO";5:ext="LCL";6:ext="LCS";
  7:ext="LUR";8:ext="LUS";9:ext="LNR";10:ext="LNS";11:ext="LNL";12:ext="LNA";default:ext=0;
  endcase
  protocol_name=0;n=text_length(TARGET_NAME);
  for(k=0;k<NAME_BYTES;k=k+1)if(k<n)protocol_name[8*k+:8]=TARGET_NAME[8*k+:8];
  if(n+4<NAME_BYTES)begin
   protocol_name[8*n+:8]=".";protocol_name[8*(n+1)+:8]=ext[23:16];
   protocol_name[8*(n+2)+:8]=ext[15:8];protocol_name[8*(n+3)+:8]=ext[7:0];
  end
 end endfunction
 function [3:0] classify;
 input [8*NAME_BYTES-1:0] name;/* k：当前字节或表项位置。 */ integer k;
 begin
  classify=0;
  for(k=1;k<=12;k=k+1)if(name==protocol_name(k))classify=k;
  // Reserved control files can never be reclassified as application bytes.
  if(classify==0)begin
   if(name==data_name && name!=0)classify=13;
   else if(name==header_name && name!=0)classify=14;
  end
 end endfunction
 /* server_peer：最近UDP69请求的源IP。 */ reg [31:0] server_peer;
 wire [2:0] operation;
 wire [31:0] peer;
 wire cvalid,cwrite,svalid;wire [3:0] ckind,skind;wire [8*NAME_BYTES-1:0] cname;
 wire [15:0] admission,sstatus,scounter;wire [7:0] progress;
 wire abort_xfer;
 wire [2:0] erx_ready,etx_valid,etx_last,etx_ready,eopen,ewrite,edone,efail,ecommand_ready;
 wire [15:0] etid[0:2];
 wire [7:0] etx_data[0:2];wire [31:0] etx_ip[0:2];wire [15:0] etx_src[0:2],etx_dst[0:2];
 wire [8*NAME_BYTES-1:0] ename[0:2];
 wire [31:0] read_addr[0:2],write_addr[0:2],ebytes[0:2],esize[0:2];
 wire [7:0] write_data[0:2],codec_data[0:2];wire [2:0] ewvalid,codec_built,codec_parsed,codec_ok;
 wire [15:0] codec_status[0:2];wire [8*NAME_BYTES-1:0] codec_name[0:2],codec_part[0:2];
 wire [3:0] ekind[0:2];/* active_kind：三个TFTP上下文各自当前对象类型。 */ reg [3:0] active_kind[0:2];
 /* open_armed：每个上下文的file_open已处理；generated_ready：对应控制文件已经生成完毕；pending：对应控制文件解析/发送完成事件等待交给业务控制器；parse_busy：对应上下文在解析接收到的控制文件。 */ reg [2:0] open_armed,generated_ready,pending,parse_busy;
 /* event_k：三个上下文各自排队的事件类别、解析有效性、状态码和文件名。 */ reg [3:0] event_k[0:2];/* event_good：控制文件已经解析完成。 */ reg event_good[0:2];/* event_code：三个上下文各自排队的事件类别、解析有效性、状态码和文件名。 */ reg [15:0] event_code[0:2];
 /* event_n：三个上下文各自排队的事件类别、解析有效性、状态码和文件名。 */ reg [8*NAME_BYTES-1:0] event_n[0:2];
 /* ev：当前字节或表项位置。 */ integer ev;
 always @*begin
  ev=-1;
  if(pending[0])ev=0;else if(pending[1])ev=1;else if(pending[2])ev=2;
 end
 wire event_valid=ev>=0;
 wire srv_open=eopen[1] && !open_armed[1] && !ewrite[1];
 arinc615a_controller #(.LOADER(LOADER),.TARGET_TASK_FILTER(TARGET_TASK_FILTER),.NAME_BYTES(NAME_BYTES),.OP_TIMEOUT(OP_TIMEOUT),.STATUS_INTERVAL(STATUS_INTERVAL)) control(
 .clk(clk),.reset(reset),.abort(abort),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_operation(cmd_operation),.cmd_peer_ip(cmd_peer_ip),
 .header_name(header_name),.data_name(data_name),.header_ok(header_ok),.header_bad(header_bad),.data_commit(data_commit),.data_bad(data_bad),
 .header_pending(header_pending),.data_pending(data_pending),.srv_open(srv_open),.srv_kind(ekind[1]),.srv_peer(server_peer),
 .admission_status(admission),.event_valid(event_valid),.event_ok(ev<0 ? 1'b0 : event_good[ev]),
 .event_failed((edone[1] && efail[1])),.event_kind(ev<0 ? 4'd0 : event_k[ev]),
 .event_status(ev<0 ? 16'd0 : event_code[ev]),.event_name(ev<0 ? {8*NAME_BYTES{1'b0}} : event_n[ev]),
 .c_ready(ecommand_ready[0]),.c_done(edone[0]),.c_failed(efail[0]),.c_valid(cvalid),.c_write(cwrite),.c_kind(ckind),.c_name(cname),
 .s_ready(ecommand_ready[2]),.s_done(edone[2]),.s_failed(efail[2]),.s_valid(svalid),.s_kind(skind),.s_status(sstatus),
 .status_counter(scounter),.percent(progress),.peer_ip(peer),.done(done),.failed(failed),.result(result),.busy(busy),
 .abort_transfers(abort_xfer),.operation(operation));
 // Incoming stream is a complete, validated UDP datagram, with stable metadata.

 always @(posedge clk)if(reset)server_peer<=0;else if(rx_valid && rx_ready && rx_dst_port==69)server_peer<=rx_src_ip;
 genvar g;
 generate for(g=0;g<3;g=g+1)begin:engines
  localparam [15:0] TID=g==0 ? 16'd42000 : g==1 ? 16'd41000 : 16'd43000;
  wire select_rx=rx_dst_port==etid[g] || (g==1 && rx_dst_port==69);
  wire [8*NAME_BYTES-1:0] command_name=g==0 ? (ckind<=12 ? protocol_name(ckind) : cname) : protocol_name(skind);
  wire write_command=g==0 ? cwrite : 1'b1;
  assign ekind[g]=classify(ename[g]);
  wire app_object=active_kind[g]>=13;
  // engine_read_valid: 当前会话组装DATA包时请求下一个源字节。
  wire engine_read_valid;
  // codec_read_ready: 控制文件同步RAM已返回当前字节。
  wire codec_read_ready;
  // Host writes are streamed once; uncommitted data is not an installed image.
  assign app_read_addr[32*g+:32]=read_addr[g];
  assign app_read_valid[g]=engine_read_valid && app_object;
  assign app_header[g]=active_kind[g]==14;
  assign app_write_valid[g]=ewvalid[g] && app_object;
  assign app_write_addr[32*g+:32]=write_addr[g];
  assign app_write_data[8*g+:8]=write_data[g];
  assign transferred[32*g+:32]=ebytes[g];
  wire [31:0] open_size=ekind[g]==14 ? header_size : ekind[g]==13 ? (ewrite[g] ? 32'd0 : data_size) :
                              ewrite[g] ? 32'd0 : esize[g];
  arinc615a_tftp #(.NAME_BYTES(NAME_BYTES),.MAX_FILE_BYTES(MAX_FILE_BYTES),.RETRY_CYCLES(RETRY_CYCLES),.DALLY_CYCLES(DALLY_CYCLES),
                   .MAX_BLOCK_BYTES(g==2 ? 512 : 1467),.LOCAL_TID(TID),.SERVER_ENABLE(g==1)) tftp(
   .clk(clk),.reset(reset),.abort(abort_xfer),.cmd_valid(g==0 ? cvalid : g==2 ? svalid : 1'b0),
   .cmd_ready(ecommand_ready[g]),.cmd_write(write_command),.cmd_peer_ip(peer),.cmd_name(command_name),
   .cmd_large_block(g==0 && ckind==13 && data_size>512),
   .rx_data(rx_data),.rx_valid(rx_valid && select_rx && !parse_busy[g]),.rx_last(rx_last),.rx_ready(erx_ready[g]),
   .rx_src_ip(rx_src_ip),.rx_src_port(rx_src_port),.rx_dst_port(rx_dst_port),
   .tx_data(etx_data[g]),.tx_valid(etx_valid[g]),.tx_last(etx_last[g]),.tx_ready(etx_ready[g]),
   .tx_dst_ip(etx_ip[g]),.tx_src_port(etx_src[g]),.tx_dst_port(etx_dst[g]),
   .file_open_valid(eopen[g]),.file_open_ready((ekind[g]>=13 || ewrite[g]) ? 1'b1 : generated_ready[g]),
   .file_name(ename[g]),.file_write(ewrite[g]),.file_open_error(16'd0),.file_size(open_size),
   .file_read_addr(read_addr[g]),.file_read_data(app_object ? app_read_data[8*g+:8] : codec_data[g]),
   .file_read_valid(engine_read_valid),.file_read_ready(app_object ? app_read_ready[g] : codec_read_ready),
   .file_write_valid(ewvalid[g]),.file_write_ready(app_object ? app_write_ready[g] : 1'b1),
   .file_write_addr(write_addr[g]),.file_write_data(write_data[g]),.file_done(edone[g]),.file_failed(efail[g]),
   .transferred(ebytes[g]),.busy(),.listen_tid(etid[g]),.previous_tid(),.error_code(),.retry_event(retry_events[g]),.duplicates(),.malformed());
  wire [8*NAME_BYTES-1:0] selection=ekind[g]==5 ? LITERAL_NAME : (ekind[g]==7 || ekind[g]==8) ? header_name : data_name;
  arinc615a_files #(.NAME_BYTES(NAME_BYTES)) files(
   .clk(clk),.reset(reset),.build(eopen[g] && !open_armed[g] && !ewrite[g] && ekind[g]<=12),
   .kind(eopen[g] ? ekind[g] : active_kind[g]),.status_code(ekind[g]<=4 ? admission : sstatus),
   .counter(scounter),.percent(progress),.selected_name(selection),.part_number(part_number),.serial_number(SERIAL_NUMBER),
   .built(codec_built[g]),.size(esize[g]),.read_addr(read_addr[g]),.read_data(codec_data[g]),
   .read_valid(engine_read_valid && !app_object),.read_ready(codec_read_ready),
   .write_valid(ewvalid[g] && !app_object),.write_addr(write_addr[g]),.write_data(write_data[g]),
   .parse(edone[g] && !efail[g] && ewrite[g] && active_kind[g]<=12),.received_size(ebytes[g]),
   .parsed(codec_parsed[g]),.parse_ok(codec_ok[g]),.parsed_status(codec_status[g]),.parsed_name(codec_name[g]),.parsed_part(codec_part[g]));
  always @(posedge clk)begin
   if(reset)begin open_armed[g]<=0;generated_ready[g]<=0;active_kind[g]<=0;pending[g]<=0;parse_busy[g]<=0;event_k[g]<=0;event_good[g]<=0;event_code[g]<=0;event_n[g]<=0;end
   else begin
    if(ev==g)pending[g]<=0;
    if(edone[g] && !efail[g] && ewrite[g] && active_kind[g]<=12)parse_busy[g]<=1;
    if(codec_parsed[g] || abort_xfer)parse_busy[g]<=0;
    if(!eopen[g])begin open_armed[g]<=0;generated_ready[g]<=0;end
    else if(!open_armed[g])begin open_armed[g]<=1;active_kind[g]<=ekind[g];end
    if(codec_built[g])generated_ready[g]<=1;
    if(codec_parsed[g])begin
     pending[g]<=1;event_k[g]<=active_kind[g];event_good[g]<=codec_ok[g];event_code[g]<=codec_status[g];event_n[g]<=codec_name[g];
    end else if(edone[g] && !efail[g] && !ewrite[g] && active_kind[g]<=12)begin
     pending[g]<=1;event_k[g]<=active_kind[g];event_good[g]<=1;event_code[g]<=1;event_n[g]<=0;
    end
   end
  end
 end endgenerate
 // FIND回复只包含固定身份参数，直接按发送位置读取常量，不再缓存整包。
 // unused: 允许在常量表达式中生成固定回复的占位参数。
 function [8*(5*NAME_BYTES+8)-1:0] find_reply(input integer unused);
  // field/character/offset/length: 身份字段号、字段内字节、回复位置和字段长度。
  integer field,character,offset,length;
  // identity: 当前身份参数的固定字符串。
  reg [8*NAME_BYTES-1:0] identity;
  begin
   find_reply=0;find_reply[15:8]=2;offset=2;
   for(field=0;field<5;field=field+1)begin
    identity=find_identity(field);length=text_length(identity);
    for(character=0;character<NAME_BYTES;character=character+1)
     if(character<length)begin find_reply[8*offset+:8]=identity[8*character+:8];offset=offset+1;end
    offset=offset+1;
   end
   find_reply[8*offset+:8]=8'h10;
  end
 endfunction
 // FIND_REPLY/FIND_REPLY_LENGTH: 编译时生成的固定IAN回复和实际字节数。
 localparam [8*(5*NAME_BYTES+8)-1:0] FIND_REPLY=find_reply(0);
 localparam FIND_REPLY_LENGTH=8+text_length(TARGET_NAME)+text_length(TARGET_TYPE)+
  text_length(TARGET_POSITION)+text_length(LITERAL_NAME)+text_length(MANUFACTURER);
 /* find_rx：FIND命令的前四字节。 */ reg [7:0] find_rx[0:3];
 /* find_count：FIND接收计数、完整消息长度和发送游标；find_length：FIND接收计数、完整消息长度和发送游标；find_index：FIND接收计数、完整消息长度和发送游标。 */ reg [8:0] find_count,find_length,find_index;/* find_pending：FIND请求已收齐；find_sending：FIND回复正在发送。 */ reg find_pending,find_sending;
 /* find_peer：FIND消息目标IP及UDP端口。 */ reg [31:0] find_peer;/* find_port：FIND消息目标IP及UDP端口。 */ reg [15:0] find_port;
 /* find_fields：FIND IAN接收字段数及当前字段字符数。 */ reg [2:0] find_fields;
 /* find_chars：FIND IAN接收字段数及当前字段字符数。 */ reg [8:0] find_chars;
 /* find_candidate：IAN第一字段解析得到的目标名称。 */ reg [8*NAME_BYTES-1:0] find_candidate;
 wire find_selected=rx_dst_port==1001;
 wire find_rx_ready=!find_sending && !find_pending;
 /* tx_locked：整包输出所有权已锁定/已授权。 */ reg tx_locked;/* tx_owner：当前整包仲裁选中的输入来源。 */ reg [1:0] tx_owner;
 /* candidate：FIND/状态/服务/控制四路输出的组合候选来源。 */ reg [1:0] candidate;
 always @*begin
  if(find_sending)candidate=3;
  else if(etx_valid[2])candidate=2;
  else if(etx_valid[1])candidate=1;
  else candidate=0;
 end
 wire [1:0] owner=tx_locked ? tx_owner : candidate;
 assign tx_valid=owner==3 ? find_sending : etx_valid[owner];
 // find_byte: 当前IRQ请求或固定IAN回复的发送字节。
 wire [7:0] find_byte=LOADER ? (find_index==1 ? 8'd1 : find_index==3 ? 8'h10 : 8'd0) : FIND_REPLY[8*find_index+:8];
 assign tx_data=owner==3 ? find_byte : etx_data[owner];
 assign tx_last=owner==3 ? find_index==find_length-1 : etx_last[owner];
 assign tx_dst_ip=owner==3 ? find_peer : etx_ip[owner];
 assign tx_src_port=owner==3 ? 16'd1001 : etx_src[owner];
 assign tx_dst_port=owner==3 ? find_port : etx_dst[owner];
 assign etx_ready[0]=owner==0 && tx_ready;
 assign etx_ready[1]=owner==1 && tx_ready;
 assign etx_ready[2]=owner==2 && tx_ready;
 assign rx_ready= find_selected ? find_rx_ready :
   (rx_dst_port==etid[0]) ? (erx_ready[0] && !parse_busy[0]) :
   (rx_dst_port==69 || rx_dst_port==etid[1]) ? (erx_ready[1] && !parse_busy[1]) :
   (rx_dst_port==etid[2]) ? (erx_ready[2] && !parse_busy[2]) : 1'b1;
 always @(posedge clk)begin
  if(reset)begin tx_locked<=0;tx_owner<=0;find_count<=0;find_pending<=0;find_sending<=0;find_index<=0;
    find_fields<=0;find_chars<=0;find_candidate<=0;
    find_length<=0;find_peer<=0;find_port<=1001;find_done<=0;found_ip<=0;found_name<=0;end
  else begin
   find_done<=0;
   if(tx_valid)begin
    if(tx_ready && tx_last)tx_locked<=0;
    else begin tx_locked<=1;tx_owner<=owner;end
   end
   if(find_start && LOADER && !find_sending && !find_pending && find_count==0)begin
    find_length<=4;find_index<=0;find_sending<=1;find_peer<=cmd_peer_ip;find_port<=1001;
   end
   if(rx_valid && rx_ready && find_selected)begin
    if(find_count==0)begin
     find_peer<=rx_src_ip;find_port<=rx_src_port;
     find_fields<=0;find_chars<=0;find_candidate<=0;
    end
    if(find_count>=2)begin
     if(rx_data==0)begin
      find_fields<=find_fields+1'b1;find_chars<=0;
     end else begin
      if(find_fields==0 && find_chars<NAME_BYTES-1)find_candidate[8*find_chars+:8]<=rx_data;
      find_chars<=find_chars+1'b1;
     end
    end
    if(find_count<4)find_rx[find_count]<=rx_data;
    if(rx_last)begin find_length<=find_count+1'b1;find_pending<=1;find_count<=0;end
    else find_count<=find_count+1'b1;
   end
   if(find_pending)begin
    find_pending<=0;
    if(!LOADER && {find_rx[0],find_rx[1],find_rx[2],find_rx[3]}==32'h00010010)begin
     find_length<=FIND_REPLY_LENGTH;find_index<=0;find_sending<=1;
    end else if(LOADER && find_rx[0]==0 && find_rx[1]==2)begin
     found_ip<=find_peer;found_name<=find_candidate;find_done<=1;
    end
   end
   if(owner==3 && tx_valid && tx_ready)begin
    if(tx_last)begin find_sending<=0;find_index<=0;end else find_index<=find_index+1'b1;
   end
  end
 end
endmodule

