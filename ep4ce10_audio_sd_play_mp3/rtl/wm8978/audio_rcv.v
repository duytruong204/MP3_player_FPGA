`timescale  1ns/1ns
////////////////////////////////////////////////////////////////////////
// Author        : EmbedFire
// Create Date   : 2019/12/05
// Module Name   : audio_rcv
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

module  audio_rcv
(
    input   wire        audio_bclk      ,   //bit clock output by the WM8978
    input   wire        sys_rst_n       ,   //system reset, active low
    input   wire        audio_lrc       ,   //left/right alignment clock output by the WM8978
    input   wire        audio_adcdat    ,   //ADC data output by the WM8978

    output  reg [15:0]  adc_data        ,   //data received at one time
    output  reg         rcv_done            //one data reception done

);

//********************************************************************//
//************************** Internal Signal *************************//
//********************************************************************//

//reg   define
reg             audio_lrc_d1;   //alignment clock delayed by one clock
reg     [4:0]   adcdat_cnt  ;   //counter of the ADC data bits output by the WM8978
reg     [15:0]  data_reg    ;   //adc_data data register

//wire  define
wire            lrc_edge    ;   //alignment clock edge flag signal

//********************************************************************//
//***************************** Main Code ****************************//
//********************************************************************//

assign  lrc_edge    =   audio_lrc   ^   audio_lrc_d1; //the edge flag is generated with an XOR operator

//delay the audio_lrc signal by one clock to get the edge flag easily
always@(posedge audio_bclk  or  negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        audio_lrc_d1    <=  1'b0    ;
    else
        audio_lrc_d1    <=  audio_lrc   ;
        
//adcdat_cnt: the counter is cleared when the edge flag is high
always@(posedge audio_bclk  or  negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        adcdat_cnt    <=  5'b0    ;
    else    if(lrc_edge == 1'b1)
        adcdat_cnt    <=  5'b0    ;
    else    if(adcdat_cnt < 5'd19)
        adcdat_cnt  <=  adcdat_cnt + 1'b1;

//store the ADC data output by the WM8978 in data_reg, 24 bits at a time
always@(posedge audio_bclk  or  negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        data_reg    <=  16'b0   ;
    else    if(adcdat_cnt <= 5'd15)
        data_reg[15-adcdat_cnt] <=  audio_adcdat    ;
    else
        data_reg    <=  data_reg    ;
        
//after the last bit has been transferred, the register value is passed to adc_data
always@(posedge audio_bclk  or  negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        adc_data    <=  16'b0   ;
    else    if(adcdat_cnt == 5'd16)
        adc_data    <=  data_reg    ;
    else
        adc_data    <=  adc_data    ;
        
//after the last bit has been transferred, a one-clock done flag is output
always@(posedge audio_bclk  or  negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        rcv_done    <=  1'b0    ;
    else    if(adcdat_cnt == 5'd16)
        rcv_done    <=  1'b1    ;
    else
        rcv_done    <=  1'b0    ;

endmodule
