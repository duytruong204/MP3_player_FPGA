`timescale  1ns/1ns
////////////////////////////////////////////////////////////////////////
// Author        : EmbedFire
//Create Date    : 2019/09/03
// Module Name   : sd_init
// Project Name  : sd_tft_pic
// Target Devices: Altera EP4CE10F17C8N
// Tool Versions : Quartus 13.0
// Description   : SD card initialization
//
// Revision      : V1.0
// Additional Comments:
// 
// Platform: EmbedFire Zhengtu Pro FPGA development board
// Company : http://www.embedfire.com
// Forum   : http://www.firebbs.cn
// Taobao  : https://fire-stm32.taobao.com
////////////////////////////////////////////////////////////////////////

module  sd_init
(
    input   wire    sys_clk         ,   //input working clock, 50MHz
    input   wire    sys_clk_shift   ,   //input working clock, 50MHz, phase shifted by 90 degrees
    input   wire    sys_rst_n       ,   //input reset signal, active low
    input   wire    miso            ,   //master in slave out signal

    output  reg     cs_n            ,   //output chip select signal
    output  reg     mosi            ,   //master out slave in signal
    output  reg     init_end            //initialization done signal
);

//********************************************************************//
//****************** Parameter and Internal Signal *******************//
//********************************************************************//
//parameter define
parameter   CMD0    =   {8'h40,8'h00,8'h00,8'h00,8'h00,8'h95},  //reset command
            CMD8    =   {8'h48,8'h00,8'h00,8'h01,8'haa,8'h87},  //query voltage command
            CMD55   =   {8'h77,8'h00,8'h00,8'h00,8'h00,8'hff},  //application command prefix
            ACMD41  =   {8'h69,8'h40,8'h00,8'h00,8'h00,8'hff}, //application command (HCS=1, SD v2.0 cards)
            ACMD41_V1 = {8'h69,8'h00,8'h00,8'h00,8'h00,8'hff}; //ACMD41 with HCS=0 (SD v1.x cards)
parameter   CNT_WAIT_MAX    =   8'd100; //maximum count of the power-on synchronization wait clocks
parameter   TO_MAX          =   8'd128; //response timeout in SPI clocks (spec: R1 within 8 bytes = 64 clocks)
parameter   IDLE        =   4'b0000,    //idle state
            SEND_CMD0   =   4'b0001,    //CMD0 send state
            CMD0_ACK    =   4'b0011,    //CMD0 response state
            SEND_CMD8   =   4'b0010,    //CMD8 send state
            CMD8_ACK    =   4'b0110,    //CMD8 response state
            SEND_CMD55  =   4'b0111,    //CMD55 send state
            CMD55_ACK   =   4'b0101,    //CMD55 response state
            SEND_ACMD41 =   4'b0100,    //ACMD41 send state
            ACMD41_ACK  =   4'b1100,    //ACMD41 response state
            INIT_END    =   4'b1101;    //initialization done state

//reg   define
reg     [7:0]   cnt_wait        ;   //power-on synchronization clock counter
reg     [3:0]   state           ;   //state machine state
reg     [7:0]   cnt_cmd_bit     ;   //command bit counter
reg             miso_dly        ;   //master in slave out signal delayed by one clock
reg             ack_en          ;   //response enable signal
reg     [39:0]  ack_data        ;   //response data
reg     [7:0]   cnt_ack_bit     ;   //response data byte counter
reg     [7:0]   cnt_to          ;   //response timeout counter
reg             v1_card         ;   //1: card rejected CMD8 (SD v1.x SDSC), use HCS=0

//********************************************************************//
//***************************** Main Code ****************************//
//********************************************************************//
//cnt_wait: power-on synchronization clock counter
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cnt_wait    <=  8'd0;
    else    if(cnt_wait >= CNT_WAIT_MAX)
        cnt_wait    <=  CNT_WAIT_MAX;
    else
        cnt_wait    <=  cnt_wait + 1'b1;

//state: state machine state transition
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        state   <=  IDLE;
    else
        case(state)
            IDLE:
                if(cnt_wait == CNT_WAIT_MAX)
                    state   <=  SEND_CMD0;
                else
                    state   <=  state;
            SEND_CMD0:
                if(cnt_cmd_bit == 8'd48)
                    state   <=  CMD0_ACK;
                else
                    state   <=  state;
            CMD0_ACK:
                if(cnt_ack_bit == 8'd48)
                    if(ack_data[39:32] == 8'h01)
                        state   <=  SEND_CMD8;
                    else
                        state   <=  SEND_CMD0;
                else    if(cnt_to >= TO_MAX)
                    state   <=  SEND_CMD0;
                else
                    state   <=  state;
            SEND_CMD8:
                if(cnt_cmd_bit == 8'd48)
                    state   <=  CMD8_ACK;
                else
                    state   <=  state;
            CMD8_ACK:
    //R1 bit2 = illegal command: SD v1.x card, skip the voltage check (use HCS=0)
                if(cnt_ack_bit == 8'd48)
                    if(ack_data[34] == 1'b1)
                        state   <=  SEND_CMD55;
                    else    if(ack_data[11:8] == 4'b0001)
                        state   <=  SEND_CMD55;
                    else
                        state   <=  SEND_CMD8;
                else    if(cnt_to >= TO_MAX)
                    state   <=  SEND_CMD8;
                else
                    state   <=  state;
            SEND_CMD55:
                if(cnt_cmd_bit == 8'd48)
                    state   <=  CMD55_ACK;
                else
                    state   <=  state;
            CMD55_ACK:
                if(cnt_ack_bit == 8'd48)
                    if(ack_data[39:32] == 8'h01)
                        state   <=  SEND_ACMD41;
                    else
                        state   <=  SEND_CMD55;
                else    if(cnt_to >= TO_MAX)
                    state   <=  SEND_CMD55;
                else
                    state   <=  state;
            SEND_ACMD41:
                if(cnt_cmd_bit == 8'd48)
                    state   <=  ACMD41_ACK;
                else
                    state   <=  state;
            ACMD41_ACK:
                if(cnt_ack_bit == 8'd48)
                    if(ack_data[39:32] == 8'h00)
                        state   <=  INIT_END;
                    else
                        state   <=  SEND_CMD55;
                else    if(cnt_to >= TO_MAX)
                    state   <=  SEND_CMD55;
                else
                    state   <=  state;
            INIT_END:
                state   <=  state;
            default:
                state   <=  IDLE;
        endcase

//cs_n,mosi,init_end,cnt_cmd_bit
//chip select, master out slave in, initialization end signal, command bit counter
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        begin
            cs_n            <=  1'b1;
            mosi            <=  1'b1;
            init_end        <=  1'b0;
            cnt_cmd_bit     <=  8'd0;
        end
    else
        case(state)
            IDLE:
                begin
                    cs_n            <=  1'b1;
                    mosi            <=  1'b1;
                    init_end        <=  1'b0;
                    cnt_cmd_bit     <=  8'd0;
                end
            SEND_CMD0:
                if(cnt_cmd_bit == 8'd48)
                    cnt_cmd_bit     <=  8'd0;
                else
                    begin
                        cs_n            <=  1'b0;
                        mosi            <=  CMD0[8'd47 - cnt_cmd_bit];
                        init_end        <=  1'b0;
                        cnt_cmd_bit     <=  cnt_cmd_bit + 8'd1;
                    end
            CMD0_ACK:
                if(cnt_ack_bit == 8'd47)
                    cs_n    <=  1'b1;
                else
                    cs_n    <=  1'b0;
            SEND_CMD8:
                if(cnt_cmd_bit == 8'd48)
                    cnt_cmd_bit     <=  8'd0;
                else
                    begin
                        cs_n            <=  1'b0;
                        mosi            <=  CMD8[8'd47 - cnt_cmd_bit];
                        init_end        <=  1'b0;
                        cnt_cmd_bit     <=  cnt_cmd_bit + 8'd1;
                    end
            CMD8_ACK:
                if(cnt_ack_bit == 8'd47)
                    cs_n    <=  1'b1;
                else
                    cs_n    <=  1'b0;
            SEND_CMD55:
                if(cnt_cmd_bit == 8'd48)
                    cnt_cmd_bit     <=  8'd0;
                else
                    begin
                        cs_n            <=  1'b0;
                        mosi            <=  CMD55[8'd47 - cnt_cmd_bit];
                        init_end        <=  1'b0;
                        cnt_cmd_bit     <=  cnt_cmd_bit + 8'd1;
                    end
            CMD55_ACK:
                if(cnt_ack_bit == 8'd47)
                    cs_n    <=  1'b1;
                else
                    cs_n    <=  1'b0;
            SEND_ACMD41:
                if(cnt_cmd_bit == 8'd48)
                    cnt_cmd_bit     <=  8'd0;
                else
                    begin
                        cs_n            <=  1'b0;
                        mosi            <=  v1_card ? ACMD41_V1[8'd47 - cnt_cmd_bit]
                                                    : ACMD41[8'd47 - cnt_cmd_bit];
                        init_end        <=  1'b0;
                        cnt_cmd_bit     <=  cnt_cmd_bit + 8'd1;
                    end
            ACMD41_ACK:
                if(cnt_ack_bit < 8'd47)
                    cs_n    <=  1'b0;
                else
                    cs_n    <=  1'b1;
            INIT_END:
                begin
                    cs_n        <=  1'b1;
                    mosi        <=  1'b1;
                    init_end    <=  1'b1;
                end
            default:
                begin
                    cs_n    <=  1'b1;
                    mosi    <=  1'b1;
                end
        endcase

//cnt_to:response timeout. Counts SPI clocks while an *_ACK state is still
//waiting for the start bit of the response (cnt_ack_bit == 0, ack_en low).
//Without it a missing response would hang the FSM forever.
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cnt_to  <=  8'd0;
    else    if((state == CMD0_ACK) || (state == CMD8_ACK) ||
                (state == CMD55_ACK) || (state == ACMD41_ACK))
        if((cnt_ack_bit == 8'd0) && (ack_en == 1'b0))
            begin
                if(cnt_to < TO_MAX)
                    cnt_to  <=  cnt_to + 8'd1;
            end
        else
            cnt_to  <=  8'd0;
    else
        cnt_to  <=  8'd0;

//v1_card:CMD8 rejected as illegal command -> SD v1.x card, ACMD41 with HCS=0
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        v1_card <=  1'b0;
    else    if((state == CMD8_ACK) && (cnt_ack_bit == 8'd48))
        v1_card <=  ack_data[34];

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
    else    if(cnt_ack_bit == 8'd47)
        ack_en  <=  1'b0;
    else    if((miso == 1'b0) && (miso_dly == 1'b1) && (cnt_ack_bit == 8'd0))
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
            if(cnt_ack_bit < 8'd40)
                ack_data    <=  {ack_data[38:0],miso_dly};
            else
                ack_data    <=  ack_data;
        end
    else
        cnt_ack_bit <=  8'd0;

endmodule
