`timescale  1ns/1ns
////////////////////////////////////////////////////////////////////////
// Author        : EmbedFire
// Create Date   : 2019/12/05
// Module Name   : wm8978_ctrl
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

module  wm8978_ctrl
(
    input   wire            sys_clk     ,   //system clock, 50MHz
    input   wire            sys_rst_n   ,   //system reset, active low
    input   wire            audio_bclk  ,   //bit clock output by the WM8978
    input   wire            audio_lrc   ,   //left/right alignment clock output by the WM8978
    input   wire            audio_adcdat,   //ADC data output by the WM8978
    input   wire    [15:0]  dac_data    ,   //input audio data
    
    output  wire            scl         ,   //serial clock signal scl output to the wm8978
    output  wire            audio_dacdat,   //DAC data output to the WM8978
    output  wire            rcv_done    ,   //one data reception done
    output  wire            send_done   ,   //one data transmission done
    output  wire    [15:0]  adc_data    ,   //output audio data
    output  wire            cfg_done    ,   //register configuration done signal
            
    inout   wire            sda             //serial data signal sda output to the wm8978
    
);

//********************************************************************//
//*************************** Instantiation **************************//
//********************************************************************//

//------------- audio_rcv_inst -------------
audio_rcv   audio_rcv_inst
(
    .audio_bclk     (audio_bclk  ),  //bit clock output by the WM8978
    .sys_rst_n      (sys_rst_n   ),  //system reset, active low
    .audio_lrc      (audio_lrc   ),  //left/right alignment clock output by the WM8978
    .audio_adcdat   (audio_adcdat),  //ADC data output by the WM8978

    .adc_data       (adc_data    ),  //data received at one time
    .rcv_done       (rcv_done    )   //one data reception done

);

//------------- audio_send_inst -------------
audio_send  audio_send_inst
(
    .audio_bclk      (audio_bclk  ),   //bit clock output by the WM8978
    .sys_rst_n       (sys_rst_n   ),   //system reset, active low
    .audio_lrc       (audio_lrc   ),   //left/right alignment clock output by the WM8978
    .dac_data        (dac_data    ),   //data sent to the WM8978

    .audio_dacdat    (audio_dacdat),   //DAC data sent to the WM8978
    .send_done       (send_done   )    //one data transmission done

);

//------------- wm8978_cfg_inst -------------
wm8978_cfg  wm8978_cfg_inst
(
    .sys_clk     (sys_clk   ),  //system clock, 50MHz
    .sys_rst_n   (sys_rst_n ),  //system reset, active low
    
    .i2c_scl     (scl       ),  //serial clock signal scl output to the wm8978
    .i2c_sda     (sda       ),  //serial data signal sda output to the wm8978
    .cfg_done    (cfg_done  )   //register configuration done signal
    
);

endmodule