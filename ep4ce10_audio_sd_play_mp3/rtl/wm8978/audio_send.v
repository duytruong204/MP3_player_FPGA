`timescale  1ns/1ns
////////////////////////////////////////////////////////////////////////
// Author        : EmbedFire
// Create Date   : 2019/12/05
// Module Name   : audio_send
// Project Name  : audio_sd_play
// Target Devices: Altera EP4CE10F17C8N
// Tool Versions : Quartus 13.0
// Description   : 
// 
// Revision      : V1.0
// Additional Comments:
// 
// Platform: EmbedFire Zhengtu Pro FPGA development board
// Company : http://www.embedfire.com
// Forum   : http://www.firebbs.cn
// Taobao  : https://fire-stm32.taobao.com
////////////////////////////////////////////////////////////////////////

module  audio_send
(
    input   wire            audio_bclk      ,   //bit clock output by the WM8978
    input   wire            sys_rst_n       ,   //system reset, active low
    input   wire            audio_lrc       ,   //left/right alignment clock output by the WM8978
    input   wire    [15:0]  dac_data        ,   //data sent to the WM8978

    output  reg             audio_dacdat    ,   //DACDAT data sent to the WM8978
    output  reg             send_done           //one data transmission done
);

//********************************************************************//
//************************** Internal Signal *************************//
//********************************************************************//

//reg   define
reg             audio_lrc_d1;   //alignment clock delayed by one clock
reg     [4:0]   dacdat_cnt  ;   //counter of the DACDAT data bits sent
reg     [15:0]  data_reg    ;   //dac_data data register

//wire  define
wire            lrc_edge    ;   //alignment clock edge flag signal

//********************************************************************//
//***************************** Main Code ****************************//
//********************************************************************//

assign  lrc_edge = audio_lrc ^ audio_lrc_d1; //the edge flag is generated with an XOR operator

//delay the audio_lrc signal by one clock to get the edge flag easily
always@(posedge audio_bclk  or  negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        audio_lrc_d1    <=  1'b0    ;
    else
        audio_lrc_d1    <=  audio_lrc   ;
        
//dacdat_cnt: the counter is cleared when the edge flag is high
always@(posedge audio_bclk  or  negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        dacdat_cnt    <=  1'b0    ;
    else    if(lrc_edge == 1'b1)
        dacdat_cnt    <=  1'b0    ;
    else    if(dacdat_cnt < 5'd19)
        dacdat_cnt  <=  dacdat_cnt + 1'b1;

//store the dac_data to be sent in data_reg
always@(posedge audio_bclk  or  negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        data_reg    <=  16'b0   ;
    else    if(lrc_edge == 1'b1)
        data_reg <=  dac_data   ;
    else
        data_reg    <=  data_reg    ;
        
//on the falling edge the data_reg bits are passed to audio_dacdat one by one
always@(negedge audio_bclk  or  negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        audio_dacdat    <=  1'b0   ;
    else    if(dacdat_cnt <= 5'd15)
        audio_dacdat    <=  data_reg[15 - dacdat_cnt]    ;

//after the last bit has been transferred, a one-clock send-done flag is output
always@(posedge audio_bclk  or  negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        send_done    <=  1'b0    ;
    else    if(dacdat_cnt == 5'd16)
        send_done    <=  1'b1    ;
    else
        send_done    <=  1'b0    ;

endmodule
