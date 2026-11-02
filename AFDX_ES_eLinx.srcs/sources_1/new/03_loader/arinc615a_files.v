`timescale 1ns/1ps
// 按固定字段生成或读取615A控制文件。
module arinc615a_files #(
 // MAX_BYTES: 现有单条目615A控制文件所需缓存；应用文件由TFTP按协商块长传送。
 parameter integer NAME_BYTES=32,MAX_BYTES=128,
 parameter [15:0] VERSION=16'h4133
)(
 input wire clk,reset,build,input wire [3:0] kind,
 input wire [15:0] status_code,counter,input wire [7:0] percent,
 input wire [8*NAME_BYTES-1:0] selected_name,part_number,serial_number,
 output /* built：一次操作完成指示。 */ reg built,output /* size：最近生成控制文件的总字节数。 */ reg [31:0] size,
 input wire [31:0] read_addr,output wire [7:0] read_data,
 input wire read_valid, // read_valid: TFTP请求读取当前生成文件的字节。
 output reg read_ready, // read_ready: 同步RAM已返回请求字节。
 input wire write_valid,input wire [31:0] write_addr,input wire [7:0] write_data,
 input wire parse,input wire [31:0] received_size,
 output /* parsed：一次操作完成指示；parse_ok：控制文件已经解析完成。 */ reg parsed,parse_ok,output /* parsed_status：最近成功遍历到的STATUS字段值。 */ reg [15:0] parsed_status,
 output /* parsed_name：最近解析的NAME字段字节串；parsed_part：最近解析的PART字段字节串。 */ reg [8*NAME_BYTES-1:0] parsed_name,parsed_part
);
 localparam IDLE=0,HEADER=1,FIELDS=2,PATCH=3;
 localparam END=0,COUNT=1,NAME=2,PART=3,STATUS=4,COUNTER=5,
            EXCEPTION=6,ESTIMATE=7,RATIO=8,DESCRIPTION=9,ITEM_STATUS=10,SERIAL=11;
 /* state：当前步骤。 */ reg [2:0] state;
 /* parsing：当前运行解析路径而非生成路径。 */ reg parsing;
 /* saved_kind：build/parse开始时锁存的控制文件类型1..12；step：当前控制文件字段程序的步骤号。 */ reg [3:0] saved_kind,step;
 /* cursor：当前字节位置。 */ reg [9:0] cursor;
 /* field_index：当前控制文件字段内的字节位置；field_length：当前变长字段的声明字节数。 */ reg [8:0] field_index,field_length;
 /* saved_status：本次编解码锁存的615A状态码；saved_counter：本次编解码锁存的状态计数器。 */ reg [15:0] saved_status,saved_counter;
 /* saved_percent：本次编解码锁存的0..100进度值。 */ reg [7:0] saved_percent;
 /* saved_name：本次编解码锁存的选定名称；saved_part：本次编解码锁存的部件号；saved_serial：本次编解码锁存的序列号。 */ reg [8*NAME_BYTES-1:0] saved_name,saved_part,saved_serial;
 /* field_type：当前字段类型。 */ reg [3:0] field_type;
 /* field_word：当前双字节整数字段的组合值。 */ reg [15:0] field_word;
 /* field_text：当前字符串字段选择出的名称/部件号/序列号组合值。 */ reg [8*NAME_BYTES-1:0] field_text;
 /* emit_byte：当前控制文件待写RAM的组合生成字节。 */ reg [7:0] emit_byte;
 /* length：当前字节或表项位置。 */ integer length;
 // incoming: 控制文件RAM同步读出的当前解析字节。
 wire [7:0] incoming;
 // GENERATED_ADDRESS_WIDTH: 生成文件RAM的实际地址位数。
 localparam GENERATED_ADDRESS_WIDTH=$clog2(MAX_BYTES);
 // generated_read_address/generated_write_address: 当前生成文件的读写字节地址。
 wire [GENERATED_ADDRESS_WIDTH-1:0] generated_read_address=read_addr,generated_write_address=cursor;
 // received_write_address/received_read_address: 接收文件的写入位置和下一拍解析位置。
 wire [GENERATED_ADDRESS_WIDTH-1:0] received_write_address=write_addr;
 wire [GENERATED_ADDRESS_WIDTH-1:0] received_read_address=cursor+
  ((state==HEADER || (state==FIELDS && field_type!=END)) ? 1'b1 : 1'b0);
 // generated_write: 本拍在生成控制文件；generated_byte: 当前生成或回填的字节。
 wire generated_write=!reset && !parsing && (state==HEADER || (state==FIELDS && field_type!=END) || state==PATCH);
 wire [7:0] generated_byte=state==HEADER ? (cursor==4 ? VERSION[15:8] : cursor==5 ? VERSION[7:0] : 8'd0) :
  state==PATCH ? (size>>(8*(3-cursor))) : emit_byte;
 afdx_byte_ram #(.WORDS(MAX_BYTES),.ADDRESS_WIDTH(GENERATED_ADDRESS_WIDTH)) generated(
  .clk(clk),.write_enable(generated_write),.write_address(generated_write_address),.write_data(generated_byte),
  .read_enable(!reset && read_valid && !read_ready),.read_address(generated_read_address),.read_data(read_data));
 afdx_byte_ram #(.WORDS(MAX_BYTES),.ADDRESS_WIDTH(GENERATED_ADDRESS_WIDTH)) received(
  .clk(clk),.write_enable(!reset && write_valid),.write_address(received_write_address),.write_data(write_data),
  .read_enable(1'b1),.read_address(received_read_address),.read_data(incoming));
 always @(posedge clk)begin
  if(reset)read_ready<=0;
  else read_ready<=read_valid && !read_ready;
 end
 function integer text_length;
 input [8*NAME_BYTES-1:0] value;/* k：当前字节或表项位置。 */ integer k;
 begin
  text_length=NAME_BYTES-1;
  for(k=NAME_BYTES-1;k>=0;k=k-1)if(value[8*k+:8]==0)text_length=k;
 end endfunction
 // A short field program is shared by encoding and decoding. Description
 // content is skipped with a bounds check; lists contain exactly one entry.
 always @*begin
  field_type=END;
  case(saved_kind)
   1,2,3,4:case(step)0:field_type=STATUS;1:field_type=DESCRIPTION;endcase
   5:case(step)
    0,3:field_type=COUNT;1:field_type=NAME;2:field_type=SERIAL;4:field_type=PART;
    5:field_type=DESCRIPTION;6:field_type=NAME;
   endcase
   6:case(step)
    0:field_type=COUNTER;1:field_type=STATUS;2:field_type=EXCEPTION;
    3:field_type=ESTIMATE;4:field_type=DESCRIPTION;
   endcase
   7:case(step)0:field_type=COUNT;1:field_type=NAME;2:field_type=PART;endcase
   8,10:case(step)
    0:field_type=STATUS;1:field_type=DESCRIPTION;2:field_type=COUNTER;
    3:field_type=EXCEPTION;4:field_type=ESTIMATE;5:field_type=RATIO;
    6:field_type=COUNT;7:field_type=NAME;
    8:field_type=saved_kind==8 ? PART : ITEM_STATUS;
    9:field_type=saved_kind==8 ? RATIO : DESCRIPTION;
    10:field_type=saved_kind==8 ? ITEM_STATUS : END;
    11:field_type=saved_kind==8 ? DESCRIPTION : END;
   endcase
   9,11:case(step)0:field_type=COUNT;1:field_type=NAME;2:field_type=DESCRIPTION;endcase
   12:case(step)0:field_type=COUNT;1:field_type=NAME;endcase
  endcase
  field_word=0;
  case(field_type)
   COUNT:field_word=1;
   STATUS,ITEM_STATUS:field_word=saved_status;
   COUNTER:field_word=saved_counter;
   ESTIMATE:field_word=saved_status==2 ? 16'hffff : 0;
  endcase
  field_text=field_type==PART ? saved_part : field_type==SERIAL ? saved_serial : saved_name;
  length=text_length(field_text)+1;
  emit_byte=0;
  case(field_type)
   NAME,PART,SERIAL:begin
    if(field_index==0)emit_byte=length;
    else if(field_index<length)emit_byte=field_text[8*(field_index-1)+:8];
   end
   DESCRIPTION:emit_byte=0;
   RATIO:case(field_index)
    0:emit_byte="0"+saved_percent/100;
    1:emit_byte="0"+(saved_percent/10)%10;
    2:emit_byte="0"+saved_percent%10;
   endcase
   default:emit_byte=field_index==0 ? field_word[15:8] : field_word[7:0];
  endcase
 end
 always @(posedge clk)begin
  if(reset)begin
   state<=IDLE;parsing<=0;cursor<=0;step<=0;
   field_index<=0;field_length<=0;saved_kind<=0;
   saved_status<=0;saved_counter<=0;saved_percent<=0;saved_name<=0;saved_part<=0;saved_serial<=0;
   built<=0;size<=0;parsed<=0;parse_ok<=0;parsed_status<=0;parsed_name<=0;parsed_part<=0;
  end else begin
   built<=0;parsed<=0;
   case(state)
    IDLE:if(build || parse)begin
     saved_kind<=kind;saved_status<=status_code;saved_counter<=counter;
     saved_percent<=percent;saved_name<=selected_name;saved_part<=part_number;saved_serial<=serial_number;
     parsing<=parse;
     cursor<=0;step<=0;field_index<=0;field_length<=0;
     if(parse)begin parsed_status<=0;parsed_name<=0;parsed_part<=0;end
     state<=HEADER;
    end
    HEADER:begin
     cursor<=cursor+1;
     if(cursor==5)state<=FIELDS;
    end
    FIELDS:begin
     if(field_type==END)begin
      if(parsing)begin parsed<=1;parse_ok<=1;state<=IDLE;end
      else begin size<=cursor;cursor<=0;state<=PATCH;end
     end else begin
      cursor<=cursor+1;
      if(field_type==NAME || field_type==PART || field_type==SERIAL || field_type==DESCRIPTION)begin
       if(field_index==0)begin
        field_length<=parsing ? incoming : field_type==DESCRIPTION ? 0 : length;
        if((parsing ? incoming==0 : field_type==DESCRIPTION))begin step<=step+1;field_index<=0;end
        else begin
         field_index<=1;
         if(parsing && field_type==NAME)parsed_name<=0;
         if(parsing && field_type==PART)parsed_part<=0;
        end
       end else begin
        if(parsing && field_type!=DESCRIPTION)begin
         if(field_index==field_length)begin end
         else begin
          if(field_index<=NAME_BYTES)begin
           if(field_type==NAME)parsed_name[8*(field_index-1)+:8]<=incoming;
           else if(field_type==PART)parsed_part[8*(field_index-1)+:8]<=incoming;
          end
         end
        end
        if(field_index==field_length)begin field_index<=0;step<=step+1;end
        else field_index<=field_index+1;
       end
      end else if(field_type==RATIO)begin
       if(field_index==2)begin field_index<=0;step<=step+1;end
       else field_index<=field_index+1;
      end else begin
       if(parsing && field_type==STATUS)begin
        if(field_index==0)parsed_status[15:8]<=incoming;else parsed_status[7:0]<=incoming;
       end
       if(field_index==1)begin field_index<=0;step<=step+1;end
       else field_index<=1;
      end
     end
    end
    PATCH:begin
     cursor<=cursor+1;
     if(cursor==3)begin built<=1;state<=IDLE;end
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
