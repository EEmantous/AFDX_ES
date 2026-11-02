`timescale 1ns/1ps
// 各VL保存完整帧，按轮询顺序和BAG间隔发送。
module afdx_multivl_scheduler #(
 // MAX_BYTES: 完整核心帧缓存容量，覆盖1471字节UDP正文和1578字节核心帧。
 parameter integer VL_COUNT=2,DEPTH=1,MAX_BYTES=1578,INPUT_TIMEOUT=125000,
 parameter [32*VL_COUNT-1:0] VL_BAG_CYCLES={VL_COUNT{32'd1}}
)(
 input wire clk,reset,input wire [8*VL_COUNT-1:0] in_data,
 input wire [VL_COUNT-1:0] in_valid,in_last,output wire [VL_COUNT-1:0] in_ready,
 output wire [7:0] out_data,output wire out_valid,out_last,input wire out_ready,
 input wire mac_start_a,mac_start_b,
 output wire [7:0] selected_vl,output wire [11:0] saved_length,
 output wire [32*VL_COUNT-1:0] queue_levels,output wire [VL_COUNT-1:0] drop_event
);
 localparam IDLE=0,SEND=1,WAIT_START=2,LOAD=3;
 /* state：当前步骤。 */ reg [1:0] state;
 /* grant：当前锁定输出的VL队列号；round_robin：下一帧选择时的VL轮询起点。 */ reg [$clog2(VL_COUNT+1)-1:0] grant,round_robin;
 reg [$clog2(MAX_BYTES+1)-1:0] index; // index: 当前帧输出位置。
 integer choice,wrap_choice,scan,v; // choice/wrap_choice: 轮询起点之后和回绕后的候选；scan: 固定VL位置；v: BAG计时通道。
 /* pop：各VL帧队列消费末字节时的组合出队掩码。 */ reg [VL_COUNT-1:0] pop;
 /* seen_a：选中帧对应MAC A/B已经实际开始发送的记忆位；seen_b：选中帧对应MAC A/B已经实际开始发送的记忆位。 */ reg seen_a,seen_b;
 /* cooldown：每VL独立BAG剩余周期计数。 */ reg [31:0] cooldown[0:VL_COUNT-1];
 wire [VL_COUNT-1:0] available;
 wire [8*VL_COUNT-1:0] head_data;
 wire [12*VL_COUNT-1:0] head_length;
 /* length：当前字节或表项位置。 */ reg [11:0] length;
 assign selected_vl=grant;
 assign saved_length=length;
 assign out_valid=!reset && state==SEND;
 assign out_last=out_valid && index==length-1;
 assign out_data=head_data[8*grant+:8];
 always @*begin
  choice=-1;wrap_choice=-1;
  for(scan=VL_COUNT-1;scan>=0;scan=scan-1)begin
   if(available[scan] && cooldown[scan]==0)begin
    wrap_choice=scan;
    if(scan>=round_robin)choice=scan;
   end
  end
  if(choice==-1)choice=wrap_choice;
  pop=0;
  if(out_valid && out_ready && out_last)pop[grant]=1;
 end
 always @(posedge clk)begin
  if(reset)begin
   state<=IDLE;grant<=0;round_robin<=0;index<=0;length<=0;seen_a<=0;seen_b<=0;
   for(v=0;v<VL_COUNT;v=v+1)cooldown[v]<=0;
  end else begin
   for(v=0;v<VL_COUNT;v=v+1)if(cooldown[v]!=0)cooldown[v]<=cooldown[v]-1'b1;
   case(state)
    IDLE:if(choice!=-1 && out_ready)begin
     grant<=choice;length<=head_length[12*choice+:12];index<=0;state<=LOAD;
    end
    LOAD:state<=SEND;
    SEND:if(out_valid && out_ready)begin
     if(out_last)begin state<=WAIT_START;seen_a<=0;seen_b<=0;end
     else index<=index+1;
    end
    WAIT_START:begin
     if(mac_start_a)seen_a<=1;
     if(mac_start_b)seen_b<=1;
     if(mac_start_a || mac_start_b)
      cooldown[grant]<=VL_BAG_CYCLES[32*grant+:32];
     if((seen_a || mac_start_a) && (seen_b || mac_start_b))begin
      state<=IDLE;round_robin<=grant==VL_COUNT-1 ? 0 : grant+1;
     end
    end
    default:state<=IDLE;
   endcase
  end
 end
 genvar g;
 generate for(g=0;g<VL_COUNT;g=g+1)begin: queues
  // STORAGE_BYTES: 帧槽按二的整数次幂对齐，地址由帧号和字节位置直接拼接。
  localparam STORAGE_BYTES=1<<$clog2(MAX_BYTES);
  // ADDRESS_WIDTH: 帧RAM所需地址位数。
  localparam ADDRESS_WIDTH=$clog2(DEPTH*STORAGE_BYTES);
  /* lengths：各VL FIFO中每个完整帧槽的核心帧长度。 */ reg [11:0] lengths[0:DEPTH-1];
  // head/tail/used: 帧队列的读写位置与完整帧数量；position: 正在写入的字节位置。
  reg [$clog2(DEPTH+1)-1:0] head,tail,used;
  reg [$clog2(MAX_BYTES+1)-1:0] position; // position: 当前帧写入位置。
  wire accept=in_valid[g] && in_ready[g];
  wire push=accept && in_last[g];
  assign in_ready[g]=!reset && (used<DEPTH);
  assign available[g]=used!=0;
  // read_position: 提前读取下一拍需要的帧字节，输出暂停时保持当前位置。
  wire [$clog2(MAX_BYTES+1)-1:0] read_position=state!=SEND ? 0 :
   index+((grant==g && out_ready && !out_last) ? 1'b1 : 1'b0);
  // read_byte: 块RAM同步读出的当前帧字节。
  wire [7:0] read_byte;
  // write_address/read_address: 限定为RAM实际宽度的帧字节地址。
  wire [ADDRESS_WIDTH-1:0] write_address=tail*STORAGE_BYTES+position;
  wire [ADDRESS_WIDTH-1:0] read_address=head*STORAGE_BYTES+read_position;
  assign head_data[8*g+:8]=read_byte;
  assign head_length[12*g+:12]=lengths[head];
  assign queue_levels[32*g+:32]=used;
  assign drop_event[g]=0;
  afdx_byte_ram #(.WORDS(DEPTH*STORAGE_BYTES),.ADDRESS_WIDTH(ADDRESS_WIDTH)) memory(
   .clk(clk),.write_enable(accept),.write_address(write_address),.write_data(in_data[8*g+:8]),
   .read_enable(1'b1),.read_address(read_address),.read_data(read_byte));
  always @(posedge clk)begin
   if(reset)begin head<=0;tail<=0;used<=0;position<=0;end
   else begin
    if(accept)begin
     if(in_last[g])begin lengths[tail]<=position+1;tail<=tail==DEPTH-1 ? 0 : tail+1;position<=0;end
     else position<=position+1;
    end
    if(pop[g])head<=head==DEPTH-1 ? 0 : head+1;
    used<=used+push-pop[g];
   end
  end
 end endgenerate
endmodule
