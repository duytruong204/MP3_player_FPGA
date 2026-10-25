`timescale  1ns/1ns
////////////////////////////////////////////////////////////////////////
// Author        : EmbedFire
//Create Date    : 2019/09/03
// Module Name   : sd_write
// Project Name  : sd_tft_pic
// Target Devices: Altera EP4CE10F17C8N
// Tool Versions : Quartus 13.0
// Description   : SD card data write operation
//
// Revision      : V1.0
// Additional Comments:
// 
// Platform: EmbedFire Zhengtu Pro FPGA development board
// Company : http://www.embedfire.com
// Forum   : http://www.firebbs.cn
// Taobao  : https://fire-stm32.taobao.com
////////////////////////////////////////////////////////////////////////

module  sd_write
(
    input   wire            sys_clk         ,   //input working clock, 50MHz
    input   wire            sys_clk_shift   ,   //input working clock, 50MHz, phase shifted by 90 degrees
    input   wire            sys_rst_n       ,   //input reset signal, active low
    input   wire            miso            ,   //master in slave out signal
    input   wire            wr_en           ,   //data write enable signal
    input   wire    [31:0]  wr_addr         ,   //write data sector address
    input   wire    [15:0]  wr_data         ,   //write data

    output  reg             cs_n            ,   //output chip select signal
    output  reg             mosi            ,   //master out slave in signal
    output  wire            wr_busy         ,   //write operation busy signal
    output  wire            wr_req              //write data request signal
);

//********************************************************************//
//****************** Parameter and Internal Signal *******************//
//********************************************************************//
//parameter define
parameter   IDLE        =   3'b000  ,   //idle state
            SEND_CMD24  =   3'b001  ,   //write command CMD24 send state
            CMD24_ACK   =   3'b011  ,   //CMD24 response state
            WR_DATA     =   3'b010  ,   //write data state
            WR_BUSY     =   3'b110  ,   //SD card write busy state
            WR_END      =   3'b111  ;   //write end state
parameter   DATA_NUM    =   12'd256 ;   //number of data bytes to write
parameter   CARD_SDHC   =   1'b0    ;   //0: SDSC byte address, 1: SDHC/SDXC sector address
parameter   BYTE_HEAD   =   16'hfffe;   //write data byte header

//wire  define
wire    [47:0]  cmd_wr      ;   //data write command

//reg   define
reg     [2:0]   state       ;   //state machine state
reg     [7:0]   cnt_cmd_bit ;   //command bit counter
reg             ack_en      ;   //response enable signal
reg     [7:0]   ack_data    ;   //response data
reg     [7:0]   cnt_ack_bit ;   //response data byte counter
reg     [11:0]  cnt_data_num;   //counter of the data written
reg     [3:0]   cnt_data_bit;   //write data bit counter
reg     [7:0]   busy_data   ;   //busy state data
reg     [2:0]   cnt_end     ;   //end state clock counter
reg             miso_dly    ;   //master in slave out signal delayed by one clock

//********************************************************************//
//***************************** Main Code ****************************//
//********************************************************************//
//wr_busy: write operation busy signal
assign  wr_busy = (state != IDLE) ? 1'b1 : 1'b0;

//wr_req: write data request signal
assign  wr_req = ((cnt_data_num <= DATA_NUM - 1'b1) && (cnt_data_bit == 4'd15))
                ? 1'b1 : 1'b0;

//cmd_wr: data write command
//SDSC: byte address (sector * 512); SDHC/SDXC: sector number
assign  cmd_wr = {8'h58, (CARD_SDHC ? wr_addr : {wr_addr[22:0], 9'd0}), 8'hff};

//miso_dly: master in slave out signal delayed by one clock
always@(posedge sys_clk_shift or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        miso_dly    <=  1'b0;
    else
        miso_dly    <=  miso;

//ack_en: response enable signal
always@(posedge sys_clk_shift or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        ack_en  <=  1'b0;
    else    if(cnt_ack_bit == 8'd15)
        ack_en  <=  1'b0;
    else    if((state == CMD24_ACK) && (miso == 1'b0)
                && (miso_dly == 1'b1) && (cnt_ack_bit == 8'd0))
        ack_en  <=  1'b1;
    else
        ack_en  <=  ack_en;

//ack_data: response data
//cnt_ack_bit: response data bit counter
always@(posedge sys_clk_shift or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        begin
            ack_data    <=  8'b0;
            cnt_ack_bit <=  8'd0;
        end
    else    if(ack_en == 1'b1)
        begin
            cnt_ack_bit     <=  cnt_ack_bit + 8'd1;
            if(cnt_ack_bit < 8'd8)
                ack_data    <=  {ack_data[6:0],miso_dly};
            else
                ack_data    <=  ack_data;
        end
    else
        cnt_ack_bit <=  8'd0;

//busy_data: busy state data
always@(posedge sys_clk_shift or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        busy_data   <=  8'd0;
    else    if(state == WR_BUSY)
        busy_data   <=  {busy_data[6:0],miso};
    else
        busy_data   <=  8'd0;

//state: state machine state transition
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        state   <=  IDLE;
    else
        case(state)
            IDLE:
                if(wr_en == 1'b1)
                    state   <=  SEND_CMD24;
                else
                    state   <=  state;
            SEND_CMD24:
                if(cnt_cmd_bit == 8'd47)
                    state   <=  CMD24_ACK;
                else
                    state   <=  state;
            CMD24_ACK:
                if(cnt_ack_bit == 8'd15)
                    if(ack_data == 8'h00)
                        state   <=  WR_DATA;
                    else
                        state   <=  SEND_CMD24;
                else
                    state   <=  state;
            WR_DATA:
                if((cnt_data_num == (DATA_NUM + 1'b1))
                    && (cnt_data_bit == 4'd15))
                    state   <=  WR_BUSY;
                else
                    state   <=  state;
            WR_BUSY:
                if(busy_data == 8'hff)
                    state   <=  WR_END;
                else
                    state   <=  state;
            WR_END:
                if(cnt_end == 3'd7)
                    state   <=  IDLE;
                else
                    state   <=  state;
            default:state   <=  IDLE;
        endcase

//cs_n: output chip select signal
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cs_n    <=  1'b1;
    else    if(cnt_end == 3'd7)
        cs_n    <=  1'b1;
    else    if(wr_en == 1'b1)
        cs_n    <=  1'b0;
    else
        cs_n    <=  cs_n;

//cnt_cmd_bit: command bit counter
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cnt_cmd_bit     <=  8'd0;
    else    if(state == SEND_CMD24)
        cnt_cmd_bit     <=  cnt_cmd_bit + 8'd1;
    else
        cnt_cmd_bit     <=  8'd0;

//mosi: master out slave in signal
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        mosi    <=  1'b1;
    else    if(state == SEND_CMD24)
        mosi    <=  cmd_wr[8'd47 - cnt_cmd_bit];
    else    if(state == WR_DATA)
        if(cnt_data_num == 12'd0)
            mosi    <=  BYTE_HEAD[15 - cnt_data_bit];
        else    if((cnt_data_num >= 12'd1) && (cnt_data_num <= DATA_NUM))
            mosi    <=  wr_data[15 - cnt_data_bit];
        else
            mosi    <=  1'b1;
    else
        mosi    <=  1'b1;

//cnt_data_bit: write data bit counter
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cnt_data_bit    <=  4'd0;
    else    if(state == WR_DATA)
        cnt_data_bit    <=  cnt_data_bit + 4'd1;
    else
        cnt_data_bit    <=  4'd0;

//cnt_data_num: counter of the data written
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cnt_data_num    <=  12'd0;
    else    if(state == WR_DATA)
        if(cnt_data_bit == 4'd15)
            cnt_data_num    <=  cnt_data_num + 12'd1;
        else
            cnt_data_num    <=  cnt_data_num;
    else
        cnt_data_num    <=  12'd0;

//cnt_end: end state clock counter
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cnt_end <=  3'd0;
    else    if(state == WR_END)
        cnt_end <=  cnt_end + 3'd1;
    else
        cnt_end <=  3'd0;

endmodule

