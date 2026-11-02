`timescale 1ns/1ps
// 按GET请求顺序查表，输出各OID的值。
module snmp_agent #(
    parameter integer MAX_BYTES=256, // MAX_BYTES: 当前GET和Trap用例的报文均不超过256字节。
    parameter V2_ENABLE=0,
    parameter integer CLOCK_HZ=12500000,
    parameter integer COMMUNITY_LENGTH=6,
    parameter [255:0] COMMUNITY="public"
) (
    input wire clk, reset_n,
    input wire [31:0] uptime, // uptime: 本地时钟给出的百分之一秒计数。
    input wire [7:0] in_data,
    input wire in_valid, in_last,
    output wire in_ready,
    output wire [7:0] out_data,
    output wire out_valid, out_last,
    output wire [10:0] out_length,
    input wire out_ready,
    output  reg snapshot_request,
    input wire snapshot_valid,
    output wire [7:0] snapshot_addr,
    input wire [31:0] snapshot_data,
    input wire [1055:0] management_snapshot,
    output  reg rejected_event
);
 localparam MIB_COUNT=V2_ENABLE ? 71 : 38,NONE=127;
 localparam IDLE=0,WAIT_TLV=1,INTEGER_VALUE=2,OID_VALUE=3,LOOK_COMPARE=4,
  SNAPSHOT=5,SELECT_BINDING=6,VALUE_SETUP=7,EMIT_BINDING=8,FINALIZE=9,SEND=10,RELEASE=11;
 // state: 请求解析、查表或回复发送阶段。
 reg [3:0] state;
 // phase: 当前BER字段的位置：消息、版本、community、PDU、ID、错误、索引、列表、绑定、OID、值。
 reg [3:0] phase;
 // request_valid/request_length: 请求RAM中完整报文的有效位和长度。
 wire request_valid;
 wire [10:0] request_length;
 // request_release: 回复完成后释放请求RAM。
 wire request_release=state==RELEASE;
 // direct_addr: 读取请求ID、OID或复制OID时的RAM地址。
 reg [10:0] direct_addr;
 // memory_data: 请求RAM当前字节。
 wire [7:0] memory_data;
 // tlv_start/tlv_start_addr: 启动下一个BER字段及其地址。
 reg tlv_start;
 reg [10:0] tlv_start_addr;
 // tlv_read_addr/tlv_value/tlv_length/tlv_end: BER读取位置、正文起点、长度和结束地址。
 wire [10:0] tlv_read_addr,tlv_value,tlv_length,tlv_end;
 // tlv_tag/tlv_done: 本字段类型和读取完成脉冲。
 wire [7:0] tlv_tag;
 wire tlv_done;
 snmp_request_buffer #(.MAX_BYTES(MAX_BYTES)) request(
  .clk(clk),.reset_n(reset_n),.in_data(in_data),.in_valid(in_valid),.in_last(in_last),.in_ready(in_ready),
  .request_valid(request_valid),.request_length(request_length),
  .read_addr(state==WAIT_TLV ? tlv_read_addr : direct_addr),.read_data(memory_data),
  .request_release(request_release),.oversize_event());
 snmp_ber_reader ber(.clk(clk),.reset_n(reset_n),.start(tlv_start),.start_addr(tlv_start_addr),
  .limit_addr(request_length),.read_addr(tlv_read_addr),.read_data(memory_data),.done(tlv_done),.valid(),
  .tag(tlv_tag),.value_addr(tlv_value),.value_length(tlv_length),.end_addr(tlv_end));
 // request_id: 回复原样带回的请求编号。
 reg [31:0] request_id;
 // remaining: 请求ID或OID还需读取的字节数量。
 reg [10:0] remaining;
 // next_field/list_end/binding_end/oid_end: 当前ID、绑定列表、绑定和OID后续字段地址。
 reg [10:0] next_field,list_end,binding_end,oid_end;
 // subid: 当前OID段的base128累加值。
 reg [31:0] subid;
 // first_subid: 当前段是否包含OID最前面的1.3。
 reg first_subid;
 // arcs: 当前OID的九段数字。
 reg [31:0] arcs[0:8];
 // arc_count/compare_arc: OID段数量及查表正在比较的段。
 reg [3:0] arc_count,compare_arc;
 // candidate/exact_rank: 正在查找的MIB项和匹配的MIB项。
 reg [6:0] candidate,exact_rank;
 // MAX_BINDINGS: 合法绑定至少含2字节SEQUENCE头、3字节OID TLV和2字节值TLV，按7字节保守分配。
 localparam MAX_BINDINGS=MAX_BYTES/7;
 // BINDING_WIDTH: 请求绑定数量及描述项位置所需位数。
 localparam BINDING_WIDTH=$clog2(MAX_BINDINGS+1);
 // raw_addr/raw_length: 当前请求实际可容纳的各OID地址和字节长度。
 reg [10:0] raw_addr[0:MAX_BINDINGS-1],raw_length[0:MAX_BINDINGS-1];
 // exact_table: 各请求OID对应的MIB项。
 reg [6:0] exact_table[0:MAX_BINDINGS-1];
 // binding_count/binding_index: 请求OID数量及当前回复的OID位置。
 reg [BINDING_WIDTH-1:0] binding_count;
 reg [BINDING_WIDTH-1:0] binding_index;
 // selected_rank: 当前正在回复的MIB项。
 reg [6:0] selected_rank;
 // value_tag/value_length/value_number: 当前回复值的BER类型、字节数和值。
 reg [7:0] value_tag;
 reg [4:0] value_length;
 reg [31:0] value_number;
 // body_length/emit_index/send_index: 回复正文长度、当前绑定编码位置和整包发送位置。
 reg [10:0] body_length,emit_index,send_index;
 // saved_uptime: 本次GET读取的时刻。
 reg [31:0] saved_uptime;
 // next_subid: 当前OID字节并入后的数字。
 wire [31:0] next_subid=(subid<<7)|{25'd0,memory_data[6:0]};
 // name_length/binding_length: 当前OID字节长度和整项回复长度。
 wire [10:0] name_length=raw_length[binding_index];
 wire [10:0] binding_length=10+name_length+value_length;
 // id_size/header_length/total_length: 请求ID编码宽度、固定回复头长度和整包长度。
 wire [2:0] id_size=signed_size(request_id);
 wire [10:0] header_length=25+COMMUNITY_LENGTH+id_size;
 wire [10:0] total_length=header_length+body_length;
 // outer_length/pdu_length/vb_content_length: BER三层结构的正文长度。
 wire [15:0] outer_length=total_length-4,pdu_length=12+id_size+body_length,vb_content_length=binding_length-4;
 // selected_number: 时间、网络统计或管理统计中选中的值。
 wire [31:0] selected_number=selected_rank==2 ? saved_uptime :
  (V2_ENABLE && selected_rank>=38 ? management_snapshot[32*(selected_rank-38)+:32] : snapshot_data);
 assign snapshot_addr=selected_rank>=4 && selected_rank<38 ? stat_slot(selected_rank)*4 : 0;
 assign out_length=total_length;
 assign out_valid=reset_n && state==SEND;
 assign out_last=out_valid && send_index==total_length-1'b1;
 // BODY_ADDRESS_WIDTH: 回复正文RAM的实际地址位数。
 localparam BODY_ADDRESS_WIDTH=$clog2(MAX_BYTES);
 // body_write_address/body_read_address: 当前编码字节和下一拍发送字节的位置。
 wire [BODY_ADDRESS_WIDTH-1:0] body_write_address=body_length+emit_index;
 wire [BODY_ADDRESS_WIDTH-1:0] body_read_address=send_index<header_length ? 0 :
  send_index-header_length+((out_valid && out_ready && !out_last) ? 1'b1 : 1'b0);
 // body_byte: 回复正文RAM同步读出的发送字节。
 wire [7:0] body_byte;
 assign out_data=send_index<header_length ? header_byte(send_index) : body_byte;
    function [7:0] community_byte;
        input /* index：当前字节或表项位置。 */ integer index;
        begin community_byte=COMMUNITY >> (8*(COMMUNITY_LENGTH-1-index)); end
    endfunction
    function integer stat_slot;
        input /* rank：固定MIB函数参数。 */ integer rank;
        /* n：当前字节位置。 */ integer n;
        begin n=rank-4; stat_slot=n<3 ? n : n+2; end
    endfunction
    function [31:0] mib_arc;
        input /* rank：固定MIB函数参数；index：当前字节或表项位置。 */ integer rank, index;
        begin
            mib_arc=0;
            case(index)
                0:mib_arc=1; 1:mib_arc=3; 2:mib_arc=6; 3:mib_arc=1;
                4:mib_arc=rank<4 ? 2 : 3;
                5:mib_arc=rank<4 ? 1 : 9999;
                6:mib_arc=rank>=38 ? 2 : 1;
                7:mib_arc=rank<4 ? (rank==3 ? 5 : rank+1) : (rank>=38 ? rank-37 : stat_slot(rank)+1);
                8:mib_arc=0;
                9:mib_arc=0;
            endcase
            // Private root is 1.3.6.1.3.9999.1.<slot+1>.0: nine arcs.
        end
    endfunction
    function integer oid_arcs;
        input /* rank：固定MIB函数参数。 */ integer rank;
        begin oid_arcs=9; end
    endfunction
    function [2:0] signed_size;
        input [31:0] v;
        begin
            if(v[31:7]==0 || &v[31:7]) signed_size=1;
            else if(v[31:15]==0 || &v[31:15]) signed_size=2;
            else if(v[31:23]==0 || &v[31:23]) signed_size=3;
            else signed_size=4;
        end
    endfunction
    function [2:0] unsigned_size;
        input [31:0] v;
        begin
            if(v<128) unsigned_size=1; else if(v<32768) unsigned_size=2;
            else if(v<8388608) unsigned_size=3;
            else if(!v[31]) unsigned_size=4; else unsigned_size=5;
        end
    endfunction
    function [7:0] header_byte;
        input /* index：当前字节或表项位置。 */ integer index;
        /* p：当前字节或表项位置；id：当前字节或表项位置；e：当前文件通道；l：当前字节或表项位置。 */ integer p,id,e,l;
        begin
            p=9+COMMUNITY_LENGTH; id=p+4; e=id+2+id_size; l=e+6;
            header_byte=0;
            if(index==0) header_byte='h30;
            else if(index==1) header_byte='h82;
            else if(index==2) header_byte=outer_length[15:8];
            else if(index==3) header_byte=outer_length[7:0];
            else if(index==4) header_byte=2;
            else if(index==5 || index==6) header_byte=1;
            else if(index==7) header_byte=4;
            else if(index==8) header_byte=COMMUNITY_LENGTH;
            else if(index<p) header_byte=community_byte(index-9);
            else if(index==p) header_byte='ha2;
            else if(index==p+1) header_byte='h82;
            else if(index==p+2) header_byte=pdu_length[15:8];
            else if(index==p+3) header_byte=pdu_length[7:0];
            else if(index==id) header_byte=2;
            else if(index==id+1) header_byte=id_size;
            else if(index<e) header_byte=request_id >> (8*(e-1-index));
            else if(index==e || index==e+3) header_byte=2;
            else if(index==e+1 || index==e+4) header_byte=1;
            else if(index==e+2) header_byte=0;
            else if(index==e+5) header_byte=(0==17 || 0==11) ? 1 : 0;
            else if(index==l) header_byte='h30;
            else if(index==l+1) header_byte='h82;
            else if(index==l+2) header_byte={5'd0,body_length[10:8]};
            else if(index==l+3) header_byte=body_length[7:0];
        end
    endfunction
    function [7:0] mib_value_byte;
        input /* index：当前字节或表项位置。 */ integer index;
        /* description：生成sysDescr固定字符串的函数临时字节串。 */ reg [183:0] description;
        /* name：生成sysName固定字符串的函数临时字节串。 */ reg [55:0] name;
        begin
            description="AFDX V3 FPGA end system"; name="AFDX-V3";
            if(selected_rank==0) mib_value_byte=description >> (8*(22-index));
            else if(selected_rank==1) begin
                case(index)
                    0:mib_value_byte='h2b;1:mib_value_byte=6;2:mib_value_byte=1;
                    3:mib_value_byte=3;4:mib_value_byte='hce;default:mib_value_byte='h0f;
                endcase
            end else if(selected_rank==3) mib_value_byte=name >> (8*(6-index));
            else mib_value_byte=value_number >> (8*(value_length-1-index));
        end
    endfunction

 // emit_byte: 当前回复绑定所需的一个字节。
 reg [7:0] emit_byte;
 always @*begin
  emit_byte=0;
  if(emit_index==0)emit_byte='h30;
  else if(emit_index==1)emit_byte='h82;
  else if(emit_index==2)emit_byte=vb_content_length[15:8];
  else if(emit_index==3)emit_byte=vb_content_length[7:0];
  else if(emit_index==4)emit_byte=6;
  else if(emit_index==5)emit_byte='h82;
  else if(emit_index==6)emit_byte={5'd0,name_length[10:8]};
  else if(emit_index==7)emit_byte=name_length[7:0];
  else if(emit_index<8+name_length)emit_byte=memory_data;
  else if(emit_index==8+name_length)emit_byte=value_tag;
  else if(emit_index==9+name_length)emit_byte=value_length;
  else emit_byte=mib_value_byte(emit_index-10-name_length);
 end
 afdx_byte_ram #(.WORDS(MAX_BYTES),.ADDRESS_WIDTH(BODY_ADDRESS_WIDTH)) body(
  .clk(clk),.write_enable(reset_n && state==EMIT_BINDING),.write_address(body_write_address),.write_data(emit_byte),
  .read_enable(1'b1),.read_address(body_read_address),.read_data(body_byte));
 task read_tlv(input [10:0] address,input [3:0] field); // address: 字段起点；field: 字段在请求中的位置。
  begin tlv_start_addr<=address;phase<=field;tlv_start<=1;state<=WAIT_TLV;end
 endtask
 always @(posedge clk)begin
  if(state==WAIT_TLV && tlv_done && phase==9)begin
   raw_addr[binding_count]<=tlv_value;raw_length[binding_count]<=tlv_length;
  end
  if(state==WAIT_TLV && tlv_done && phase==10)exact_table[binding_count]<=exact_rank;
  if(state==OID_VALUE && !memory_data[7])begin
   if(first_subid)begin arcs[0]<=1;arcs[1]<=next_subid-40;end
   else arcs[arc_count]<=next_subid;
  end
 end
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin
   state<=IDLE;phase<=0;tlv_start<=0;tlv_start_addr<=0;direct_addr<=0;
   request_id<=0;remaining<=0;next_field<=0;list_end<=0;binding_end<=0;oid_end<=0;
   subid<=0;first_subid<=1;arc_count<=0;compare_arc<=0;candidate<=0;exact_rank<=NONE;
   binding_count<=0;binding_index<=0;selected_rank<=0;
   value_tag<=0;value_length<=0;value_number<=0;body_length<=0;emit_index<=0;send_index<=0;
   saved_uptime<=0;snapshot_request<=0;rejected_event<=0;
  end else begin
   tlv_start<=0;snapshot_request<=0;rejected_event<=0;
   case(state)
    IDLE:if(request_valid)begin binding_count<=0;body_length<=0;read_tlv(0,0);end
    WAIT_TLV:if(tlv_done)case(phase)
     0:read_tlv(tlv_value,1);
     1:read_tlv(tlv_end,2);
     2:read_tlv(tlv_end,3);
     3:if(tlv_tag=='ha0)read_tlv(tlv_value,4);else begin rejected_event<=1;state<=RELEASE;end
     4:begin request_id<=0;remaining<=tlv_length;direct_addr<=tlv_value;next_field<=tlv_end;state<=INTEGER_VALUE;end
     5:read_tlv(tlv_end,6);
     6:read_tlv(tlv_end,7);
     7:begin list_end<=tlv_end;read_tlv(tlv_value,8);end
     8:begin binding_end<=tlv_end;read_tlv(tlv_value,9);end
     9:begin
      direct_addr<=tlv_value;remaining<=tlv_length;oid_end<=tlv_end;
      subid<=0;first_subid<=1;arc_count<=0;state<=OID_VALUE;
     end
     10:begin
      binding_count<=binding_count+1'b1;
      if(binding_end==list_end)begin snapshot_request<=1;state<=SNAPSHOT;end
      else read_tlv(binding_end,8);
     end
    endcase
    INTEGER_VALUE:begin
     request_id<=(request_id<<8)|memory_data;
     direct_addr<=direct_addr+1'b1;remaining<=remaining-1'b1;
     if(remaining==1)read_tlv(next_field,5);
    end
    OID_VALUE:begin
     direct_addr<=direct_addr+1'b1;remaining<=remaining-1'b1;
     if(memory_data[7])subid<=next_subid;
     else begin
      subid<=0;first_subid<=0;arc_count<=first_subid ? 2 : arc_count+1'b1;
      if(remaining==1)begin candidate<=0;compare_arc<=0;exact_rank<=NONE;state<=LOOK_COMPARE;end
     end
    end
    LOOK_COMPARE:begin
     if(arcs[compare_arc]!=mib_arc(candidate,compare_arc) || compare_arc==8)begin
      if(compare_arc==8 && arcs[compare_arc]==0 && arc_count==9)exact_rank<=candidate;
      if(candidate==MIB_COUNT-1)read_tlv(oid_end,10);
      else begin candidate<=candidate+1'b1;compare_arc<=0;end
     end else compare_arc<=compare_arc+1'b1;
    end
    SNAPSHOT:if(snapshot_valid)begin saved_uptime<=uptime;binding_index<=0;state<=SELECT_BINDING;end
    SELECT_BINDING:begin selected_rank<=exact_table[binding_index];state<=VALUE_SETUP;end
    VALUE_SETUP:begin
     direct_addr<=raw_addr[binding_index];emit_index<=0;
     if(selected_rank==NONE)begin value_tag<='h80;value_length<=0;end
     else if(selected_rank==0)begin value_tag<=4;value_length<=23;end
     else if(selected_rank==1)begin value_tag<=6;value_length<=6;end
     else if(selected_rank==3)begin value_tag<=4;value_length<=7;end
     else begin value_number<=selected_number;value_tag<=selected_rank==2 ? 'h43 : 'h42;value_length<=unsigned_size(selected_number);end
     state<=EMIT_BINDING;
    end
    EMIT_BINDING:begin
     if(emit_index>=7 && emit_index<7+name_length)direct_addr<=raw_addr[binding_index]+emit_index-7;
     if(emit_index==binding_length-1)begin
      body_length<=body_length+binding_length;
      if(binding_index+1'b1<binding_count)begin binding_index<=binding_index+1'b1;state<=SELECT_BINDING;end
      else state<=FINALIZE;
     end else emit_index<=emit_index+1'b1;
    end
    FINALIZE:begin send_index<=0;state<=SEND;end
    SEND:if(out_ready)begin if(out_last)state<=RELEASE;else send_index<=send_index+1'b1;end
    RELEASE:state<=IDLE;
   endcase
  end
 end
endmodule
