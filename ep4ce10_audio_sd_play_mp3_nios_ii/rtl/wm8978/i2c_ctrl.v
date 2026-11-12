`timescale  1ns/1ns
////////////////////////////////////////////////////////////////////////
// Author        : EmbedFire
// Create Date   : 2019/04/01
// Module Name   : i2c_ctrl
// Project Name  : audio_sd_play
// Target Devices: Altera EP4CE10F17C8N
// Tool Versions : Quartus 13.0
// Description   : i2c driver module
// 
// Revision      : V1.0
// Additional Comments:
// 
// Platform: EmbedFire Zhengtu Pro FPGA development board
// Company : http://www.embedfire.com
// Forum   : http://www.firebbs.cn
// Taobao  : https://fire-stm32.taobao.com
////////////////////////////////////////////////////////////////////////

module  i2c_ctrl
#(
    parameter   DEVICE_ADDR     =   7'b1010_000     ,   //i2c device address
    parameter   SYS_CLK_FREQ    =   26'd50_000_000  ,   //input system clock frequency
    parameter   SCL_FREQ        =   18'd250_000         //i2c device scl clock frequency
)
(
    input   wire            sys_clk     ,   //input system clock, 50MHz
    input   wire            sys_rst_n   ,   //input reset signal, active low
    input   wire            wr_en       ,   //input write enable signal
    input   wire            rd_en       ,   //input read enable signal
    input   wire            i2c_start   ,   //input i2c start trigger signal
    input   wire            addr_num    ,   //input number of i2c byte address bytes
    input   wire    [15:0]  byte_addr   ,   //input i2c byte address
    input   wire    [7:0]   wr_data     ,   //input i2c device data

    output  reg             i2c_clk     ,   //i2c driver clock
    output  reg             i2c_end     ,   //one i2c read/write operation done
    output  reg     [7:0]   rd_data     ,   //data read from the i2c device
    output  reg             i2c_scl     ,   //serial clock signal scl output to the i2c device
    inout   wire            i2c_sda         //serial data signal sda output to the i2c device
);

//********************************************************************//
//****************** Parameter and Internal Signal *******************//
//********************************************************************//
// parameter define
parameter   CNT_CLK_MAX     =   (SYS_CLK_FREQ/SCL_FREQ) >> 2'd3   ;   //maximum count of the cnt_clk counter

parameter   CNT_START_MAX   =   8'd100; //maximum count of the cnt_start counter

parameter   IDLE            =   4'd00,  //idle state
            START_1         =   4'd01,  //start state 1
            SEND_D_ADDR     =   4'd02,  //device address write state + control write
            ACK_1           =   4'd03,  //acknowledge state 1
            SEND_B_ADDR_H   =   4'd04,  //byte address high eight bits write state
            ACK_2           =   4'd05,  //acknowledge state 2
            SEND_B_ADDR_L   =   4'd06,  //byte address low eight bits write state
            ACK_3           =   4'd07,  //acknowledge state 3
            WR_DATA         =   4'd08,  //write data state
            ACK_4           =   4'd09,  //acknowledge state 4
            START_2         =   4'd10,  //start state 2
            SEND_RD_ADDR    =   4'd11,  //device address write state + control read
            ACK_5           =   4'd12,  //acknowledge state 5
            RD_DATA         =   4'd13,  //read data state
            N_ACK           =   4'd14,  //not-acknowledge state
            STOP            =   4'd15;  //stop state

// wire  define
wire            sda_in          ;   //sda input data register
wire            sda_en          ;   //sda data write enable signal

// reg   define
reg     [7:0]   cnt_clk         ;   //system clock counter, controls the generation of the clk_i2c clock signal
reg     [3:0]   state           ;   //state machine state
reg             cnt_i2c_clk_en  ;   //cnt_i2c_clk counter enable signal
reg     [1:0]   cnt_i2c_clk     ;   //clk_i2c clock counter, controls the generation of the cnt_bit signal
reg     [2:0]   cnt_bit         ;   //sda bit counter
reg             ack             ;   //acknowledge signal
reg             i2c_sda_reg     ;   //sda data buffer
reg     [7:0]   rd_data_reg     ;   //data read from the i2c device

//********************************************************************//
//***************************** Main Code ****************************//
//********************************************************************//
// cnt_clk: system clock counter, controls the generation of the clk_i2c clock signal
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cnt_clk <=  8'd0;
    else    if(cnt_clk == CNT_CLK_MAX - 1'b1)
        cnt_clk <=  8'd0;
    else
        cnt_clk <=  cnt_clk + 1'b1;

// i2c_clk: i2c driver clock
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        i2c_clk <=  1'b1;
    else    if(cnt_clk == CNT_CLK_MAX - 1'b1)
        i2c_clk <=  ~i2c_clk;

// cnt_i2c_clk_en: cnt_i2c_clk counter enable signal
always@(posedge i2c_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cnt_i2c_clk_en  <=  1'b0;
    else    if((state == STOP) && (cnt_bit == 3'd3) &&(cnt_i2c_clk == 3))
        cnt_i2c_clk_en  <=  1'b0;
    else    if(i2c_start == 1'b1)
        cnt_i2c_clk_en  <=  1'b1;

// cnt_i2c_clk: i2c_clk clock counter, controls the generation of the cnt_bit signal
always@(posedge i2c_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cnt_i2c_clk <=  2'd0;
    else    if(cnt_i2c_clk_en == 1'b1)
        cnt_i2c_clk <=  cnt_i2c_clk + 1'b1;

// cnt_bit: sda bit counter
always@(posedge i2c_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cnt_bit <=  3'd0;
    else    if((state == IDLE) || (state == START_1) || (state == START_2)
                || (state == ACK_1) || (state == ACK_2) || (state == ACK_3)
                || (state == ACK_4) || (state == ACK_5) || (state == N_ACK))
        cnt_bit <=  3'd0;
    else    if((cnt_bit == 3'd7) && (cnt_i2c_clk == 2'd3))
        cnt_bit <=  3'd0;
    else    if((cnt_i2c_clk == 2'd3) && (state != IDLE))
        cnt_bit <=  cnt_bit + 1'b1;

// state: state machine state transition
always@(posedge i2c_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        state   <=  IDLE;
    else    case(state)
        IDLE:
            if(i2c_start == 1'b1)
                state   <=  START_1;
            else
                state   <=  state;
        START_1:
            if(cnt_i2c_clk == 3)
                state   <=  SEND_D_ADDR;
            else
                state   <=  state;
        SEND_D_ADDR:
            if((cnt_bit == 3'd7) &&(cnt_i2c_clk == 3))
                state   <=  ACK_1;
            else
                state   <=  state;
        ACK_1:
            if((cnt_i2c_clk == 3) && (ack == 1'b0))
                begin
                    if(addr_num == 1'b1)
                        state   <=  SEND_B_ADDR_H;
                    else
                        state   <=  SEND_B_ADDR_L;
                end
             else
                state   <=  state;
        SEND_B_ADDR_H:
            if((cnt_bit == 3'd7) &&(cnt_i2c_clk == 3))
                state   <=  ACK_2;
            else
                state   <=  state;
        ACK_2:
            if((cnt_i2c_clk == 3) && (ack == 1'b0))
                state   <=  SEND_B_ADDR_L;
            else
                state   <=  state;
        SEND_B_ADDR_L:
            if((cnt_bit == 3'd7) && (cnt_i2c_clk == 3))
                state   <=  ACK_3;
            else
                state   <=  state;
        ACK_3:
            if((cnt_i2c_clk == 3) && (ack == 1'b0))
                begin
                    if(wr_en == 1'b1)
                        state   <=  WR_DATA;
                    else    if(rd_en == 1'b1)
                        state   <=  START_2;
                    else
                        state   <=  state;
                end
             else
                state   <=  state;
        WR_DATA:
            if((cnt_bit == 3'd7) &&(cnt_i2c_clk == 3))
                state   <=  ACK_4;
            else
                state   <=  state;
        ACK_4:
            if((cnt_i2c_clk == 3) && (ack == 1'b0))
                state   <=  STOP;
            else
                state   <=  state;
        START_2:
            if(cnt_i2c_clk == 3)
                state   <=  SEND_RD_ADDR;
            else
                state   <=  state;
        SEND_RD_ADDR:
            if((cnt_bit == 3'd7) &&(cnt_i2c_clk == 3))
                state   <=  ACK_5;
            else
                state   <=  state;
        ACK_5:
            if((cnt_i2c_clk == 3) && (ack == 1'b0))
                state   <=  RD_DATA;
            else
                state   <=  state;
        RD_DATA:
            if((cnt_bit == 3'd7) &&(cnt_i2c_clk == 3))
                state   <=  N_ACK;
            else
                state   <=  state;
        N_ACK:
            if(cnt_i2c_clk == 3)
                state   <=  STOP;
            else
                state   <=  state;
        STOP:
            if((cnt_bit == 3'd3) &&(cnt_i2c_clk == 3))
                state   <=  IDLE;
            else
                state   <=  state;
        default:    state   <=  IDLE;
    endcase

// ack: acknowledge signal
always@(*)
    case    (state)
        IDLE,START_1,SEND_D_ADDR,SEND_B_ADDR_H,SEND_B_ADDR_L,
        WR_DATA,START_2,SEND_RD_ADDR,RD_DATA,N_ACK:
            ack <=  1'b1;
        ACK_1,ACK_2,ACK_3,ACK_4,ACK_5:
            if(cnt_i2c_clk == 2'd0)
                ack <=  sda_in;
            else
                ack <=  ack;
        default:    ack <=  1'b1;
    endcase

// i2c_scl: serial clock signal scl output to the i2c device
always@(*)
    case    (state)
        IDLE:
            i2c_scl <=  1'b1;
        START_1:
            if(cnt_i2c_clk == 2'd3)
                i2c_scl <=  1'b0;
            else
                i2c_scl <=  1'b1;
        SEND_D_ADDR,ACK_1,SEND_B_ADDR_H,ACK_2,SEND_B_ADDR_L,
        ACK_3,WR_DATA,ACK_4,START_2,SEND_RD_ADDR,ACK_5,RD_DATA,N_ACK:
            if((cnt_i2c_clk == 2'd1) || (cnt_i2c_clk == 2'd2))
                i2c_scl <=  1'b1;
            else
                i2c_scl <=  1'b0;
        STOP:
            if((cnt_bit == 3'd0) &&(cnt_i2c_clk == 2'd0))
                i2c_scl <=  1'b0;
            else
                i2c_scl <=  1'b1;
        default:    i2c_scl <=  1'b1;
    endcase

// i2c_sda_reg: sda data buffer
always@(*)
    case    (state)
        IDLE:
            begin
                i2c_sda_reg <=  1'b1;
                rd_data_reg <=  8'd0;
            end
        START_1:
            if(cnt_i2c_clk <= 2'd0)
                i2c_sda_reg <=  1'b1;
            else
                i2c_sda_reg <=  1'b0;
        SEND_D_ADDR:
            if(cnt_bit <= 3'd6)
                i2c_sda_reg <=  DEVICE_ADDR[6 - cnt_bit];
            else
                i2c_sda_reg <=  1'b0;
        ACK_1:
            i2c_sda_reg <=  1'b1;
        SEND_B_ADDR_H:
            i2c_sda_reg <=  byte_addr[15 - cnt_bit];
        ACK_2:
            i2c_sda_reg <=  1'b1;
        SEND_B_ADDR_L:
            i2c_sda_reg <=  byte_addr[7 - cnt_bit];
        ACK_3:
            i2c_sda_reg <=  1'b1;
        WR_DATA:
            i2c_sda_reg <=  wr_data[7 - cnt_bit];
        ACK_4:
            i2c_sda_reg <=  1'b1;
        START_2:
            if(cnt_i2c_clk <= 2'd1)
                i2c_sda_reg <=  1'b1;
            else
                i2c_sda_reg <=  1'b0;
        SEND_RD_ADDR:
            if(cnt_bit <= 3'd6)
                i2c_sda_reg <=  DEVICE_ADDR[6 - cnt_bit];
            else
                i2c_sda_reg <=  1'b1;
        ACK_5:
            i2c_sda_reg <=  1'b1;
        RD_DATA:
            if(cnt_i2c_clk  == 2'd2)
                rd_data_reg[7 - cnt_bit]    <=  sda_in;
            else
                rd_data_reg <=  rd_data_reg;
        N_ACK:
            i2c_sda_reg <=  1'b1;
        STOP:
            if((cnt_bit == 3'd0) && (cnt_i2c_clk < 2'd3))
                i2c_sda_reg <=  1'b0;
            else
                i2c_sda_reg <=  1'b1;
        default:
            begin
                i2c_sda_reg <=  1'b1;
                rd_data_reg <=  rd_data_reg;
            end
    endcase

// rd_data: data read from the i2c device
always@(posedge i2c_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        rd_data <=  8'd0;
    else    if((state == RD_DATA) && (cnt_bit == 3'd7) && (cnt_i2c_clk == 2'd3))
        rd_data <=  rd_data_reg;

// i2c_end: one read/write operation end signal
always@(posedge i2c_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        i2c_end <=  1'b0;
    else    if((state == STOP) && (cnt_bit == 3'd3) &&(cnt_i2c_clk == 3))
        i2c_end <=  1'b1;
    else
        i2c_end <=  1'b0;

// sda_in: sda input data register
assign  sda_in = i2c_sda;
// sda_en: sda data write enable signal
assign  sda_en = ((state == RD_DATA) || (state == ACK_1) || (state == ACK_2)
                    || (state == ACK_3) || (state == ACK_4) || (state == ACK_5))
                    ? 1'b0 : 1'b1;
// i2c_sda: serial data signal sda output to the i2c device
assign  i2c_sda = (sda_en == 1'b1) ? i2c_sda_reg : 1'bz;

endmodule
