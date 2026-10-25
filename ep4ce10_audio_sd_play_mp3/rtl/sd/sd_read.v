`timescale  1ns/1ns
////////////////////////////////////////////////////////////////////////
// Author        : EmbedFire
//Create Date    : 2019/09/03
// Module Name   : sd_read
// Project Name  : sd_tft_pic
// Target Devices: Altera EP4CE10F17C8N
// Tool Versions : Quartus 13.0
// Description   : SD card data read operation
//
// Revision      : V1.0
// Additional Comments:
// 
// Platform: EmbedFire Zhengtu Pro FPGA development board
// Company : http://www.embedfire.com
// Forum   : http://www.firebbs.cn
// Taobao  : https://fire-stm32.taobao.com
////////////////////////////////////////////////////////////////////////

module  sd_read
(
    input   wire            sys_clk         ,   //input working clock, 50MHz
    input   wire            sys_clk_shift   ,   //input working clock, 50MHz, phase shifted by 90 degrees
    input   wire            sys_rst_n       ,   //input reset signal, active low
    input   wire            miso            ,   //master in slave out signal
    input   wire            rd_en           ,   //data read enable signal
    input   wire    [31:0]  rd_addr         ,   //read data sector address

    output  wire            rd_busy         ,   //read operation busy signal
    output  reg             rd_data_en      ,   //read data valid flag signal
    output  reg     [15:0]  rd_data         ,   //read data
    output  reg             cs_n            ,   //chip select signal
    output  reg             mosi                //master out slave in signal
);

//********************************************************************//
//****************** Parameter and Internal Signal *******************//
//********************************************************************//
//parameter define
parameter   IDLE        =   3'b000  ,   //idle state
            SEND_CMD17  =   3'b001  ,   //read command CMD17 send state
            CMD17_ACK   =   3'b011  ,   //CMD17 response state
            RD_DATA     =   3'b010  ,   //read data state
            RD_END      =   3'b110  ;   //read end state
parameter   DATA_NUM    =   12'd256 ;   //number of data bytes to read
parameter   CARD_SDHC   =   1'b0    ;   //0: SDSC byte address, 1: SDHC/SDXC sector address

//wire  define
wire    [47:0]  cmd_rd      ;   //data read command

//reg   define
reg     [2:0]   state       ;   //state machine state
reg     [7:0]   cnt_cmd_bit ;   //command bit counter
reg             ack_en      ;   //response enable signal
reg     [7:0]   ack_data    ;   //response data
reg     [7:0]   cnt_ack_bit ;   //response data byte counter
reg     [11:0]  cnt_data_num;   //counter of the data read out
reg     [3:0]   cnt_data_bit;   //read data bit counter
reg     [2:0]   cnt_end     ;   //end state clock counter
reg             miso_dly    ;   //master in slave out signal delayed by one clock
reg     [15:0]  rd_data_reg ;   //read data register
reg     [15:0]  byte_head   ;   //read data byte header
reg             byte_head_en;   //read data byte header enable

//********************************************************************//
//***************************** Main Code ****************************//
//********************************************************************//
//rd_busy: read operation busy signal
assign  rd_busy = (state != IDLE) ? 1'b1 : 1'b0;

//cmd_rd: data read command
//SDSC (<=2GB) cards take a BYTE address in CMD17 (sector * 512);
//SDHC/SDXC cards take a sector number.  Set CARD_SDHC=1'b1 for an SDHC card.
assign  cmd_rd = {8'h51, (CARD_SDHC ? rd_addr : {rd_addr[22:0], 9'd0}), 8'hff};

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
    else    if((state == CMD17_ACK) && (miso == 1'b0)
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

//state: state machine state transition
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        state   <=  IDLE;
    else
        case(state)
            IDLE:
                if(rd_en == 1'b1)
                    state   <=  SEND_CMD17;
                else
                    state   <=  state;
            SEND_CMD17:
                if(cnt_cmd_bit == 8'd47)
                    state   <=  CMD17_ACK;
                else
                    state   <=  state;
            CMD17_ACK:
                if(cnt_ack_bit == 8'd15)
                    if(ack_data == 8'h00)
                        state   <=  RD_DATA;
                    else
                        state   <=  SEND_CMD17;
                else
                    state   <=  state;
            RD_DATA:
                if((cnt_data_num == (DATA_NUM + 1'b1))
                    && (cnt_data_bit == 4'd15))
                    state   <=  RD_END;
                else
                    state   <=  state;
            RD_END:
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
    else    if(rd_en == 1'b1)
        cs_n    <=  1'b0;
    else
        cs_n    <=  cs_n;

//cnt_cmd_bit: command bit counter
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cnt_cmd_bit     <=  8'd0;
    else    if(state == SEND_CMD17)
        cnt_cmd_bit     <=  cnt_cmd_bit + 8'd1;
    else
        cnt_cmd_bit     <=  8'd0;

//mosi: master out slave in signal
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        mosi    <=  1'b1;
    else    if(state == SEND_CMD17)
        mosi    <=  cmd_rd[8'd47 - cnt_cmd_bit];
    else
        mosi    <=  1'b1;

//byte_head: read data byte header
always@(posedge sys_clk_shift or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        byte_head   <=  16'b0;
    else    if(byte_head_en == 1'b0)
        byte_head   <=  16'b0;
    else    if(byte_head_en == 1'b1)
        byte_head   <=  {byte_head[14:0],miso};
    else
        byte_head   <=  byte_head;

//byte_head_en: read data byte header enable
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        byte_head_en    <=  1'b0;
    else    if(byte_head == 16'hfffe)
        byte_head_en    <=  1'b0;
    else    if((state == RD_DATA) && (cnt_data_num == 12'd0)
                && (cnt_data_bit == 4'd0))
        byte_head_en    <=  1'b1;
    else
        byte_head_en    <=  byte_head_en;

//cnt_data_bit: read data bit counter
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cnt_data_bit    <=  4'd0;
    else    if((state == RD_DATA) && (cnt_data_num >= 12'd1))
        cnt_data_bit    <=  cnt_data_bit + 4'd1;
    else
        cnt_data_bit    <=  4'd0;

//cnt_data_num: counter of the data read out
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cnt_data_num    <=  12'd0;
    else    if(state == RD_DATA)
        if((cnt_data_bit == 4'd15) || (byte_head == 16'hfffe))
            cnt_data_num    <=  cnt_data_num + 12'd1;
        else
            cnt_data_num    <=  cnt_data_num;
    else
        cnt_data_num    <=  12'd0;

//rd_data_reg: read data register
always@(posedge sys_clk_shift or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        rd_data_reg <=  16'd0;
    else    if((state == RD_DATA) && (cnt_data_num >= 12'd1)
                && (cnt_data_num <= DATA_NUM))
        rd_data_reg <=  {rd_data_reg[14:0],miso};
    else
        rd_data_reg <=  16'd0;

//rd_data_en: read data valid flag signal
//rd_data: read data
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        begin
            rd_data_en  <=  1'b0;
            rd_data     <=  16'd0;
        end
    else    if(state == RD_DATA)
        begin
            if((cnt_data_bit == 4'd15) && (cnt_data_num <= DATA_NUM))
                begin
                    rd_data_en  <=  1'b1;
                    rd_data     <=  rd_data_reg;
                end
            else
                begin
                    rd_data_en  <=  1'b0;
                    rd_data     <=  rd_data;
                end
        end
    else
        begin
            rd_data_en  <=  1'b0;
            rd_data     <=  16'd0;
        end

//cnt_end: end state clock counter
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cnt_end <=  3'd0;
    else    if(state == RD_END)
        cnt_end <=  cnt_end + 3'd1;
    else
        cnt_end <=  3'd0;

endmodule
