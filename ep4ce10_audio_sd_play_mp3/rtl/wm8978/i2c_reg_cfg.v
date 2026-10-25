`timescale  1ns/1ns
////////////////////////////////////////////////////////////////////////
// Author        : EmbedFire
// Create Date   : 2019/12/05
// Module Name   : i2c_reg_cfg
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

module  i2c_reg_cfg
(
    input   wire            i2c_clk     ,   //system clock, supplied by the i2c module
    input   wire            sys_rst_n   ,   //system reset, active low
    input   wire            cfg_end     ,   //single register configuration done

    output  reg             cfg_start   ,   //single register configuration trigger signal
    output  wire    [15:0]  cfg_data    ,   //register address 7 bit + data 9 bit
    output  reg             cfg_done        //register configuration done
    
);

//********************************************************************//
//****************** Parameter and Internal Signal *******************//
//********************************************************************//

//parameter define
parameter   REG_NUM         =   6'd15    ;   //total number of registers to configure
parameter   CNT_WAIT_MAX    =   10'd1000 ;   //start configuring the registers after a 1 ms wait following power-up
parameter   LOUT1VOL        =   6'd30    ;   //headphone left channel volume setting (0~63)
parameter   ROUT1VOL        =   6'd30    ;   //headphone right channel volume setting (0~63)
parameter   SPK_LOUT2VOL    =   6'd50    ;   //speaker left channel volume setting (0~63)
parameter   SPK_ROUT2VOL    =   6'd50    ;   //speaker right channel volume setting (0~63)

//wire  define
wire    [15:0]  cfg_data_reg[REG_NUM-1:0];   //register configuration data buffer

//reg   define
reg     [9:0]  cnt_wait     ;   //register configuration power-up wait counter
reg     [5:0]  reg_num      ;   //number of configured registers


//********************************************************************//
//******************************* Main Code **************************//
//********************************************************************//

//cnt_wait: register configuration wait counter
always@(posedge i2c_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cnt_wait    <=  10'd0;
    else    if(cnt_wait < CNT_WAIT_MAX)
        cnt_wait    <=  cnt_wait + 1'b1;

//reg_num: number of configured registers
always@(posedge i2c_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        reg_num <=  6'd0;
    else    if(cfg_end == 1'b1)
        reg_num <=  reg_num + 1'b1;

//cfg_start: single register configuration trigger signal
always@(posedge i2c_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cfg_start   <=  1'b0;
    else    if(cnt_wait == (CNT_WAIT_MAX - 1'b1))
        cfg_start   <=  1'b1;
    else    if((cfg_end == 1'b1) && (reg_num < (REG_NUM - 1'b1)))
        cfg_start   <=  1'b1;
    else
        cfg_start   <=  1'b0;

//cfg_done: register configuration done
always@(posedge i2c_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cfg_done    <=  1'b0;
    else    if((reg_num == REG_NUM - 1'b1) && (cfg_end == 1'b1))
        cfg_done    <=  1'b1;

//cfg_data: 7 bit address + 9 bit data
assign  cfg_data = (cfg_done == 1'b1) ? 16'b0 : cfg_data_reg[reg_num];

//----------------------------------------------------
//cfg_data_reg: register configuration data buffer
//see the documentation for the function of each register
assign  cfg_data_reg[00]  =       {7'd0 , 9'd0                  }; 
assign  cfg_data_reg[01]  =       {7'd1 , 9'b1_0010_1111        };
assign  cfg_data_reg[02]  =       {7'd2 , 9'b1_1000_0000        };
assign  cfg_data_reg[03]  =       {7'd4 , 9'b0_0001_0000        };
assign  cfg_data_reg[04]  =       {7'd6 , 9'b0_0000_0001        };
assign  cfg_data_reg[05]  =       {7'd10, 9'b0_0000_1000        };
assign  cfg_data_reg[06]  =       {7'd43, 9'b0_0001_0000        }; 
assign  cfg_data_reg[07]  =       {7'd49, 9'b0_0000_0110        };
assign  cfg_data_reg[08]  =       {7'd50, 9'b0_0000_0001        };
assign  cfg_data_reg[09]  =       {7'd51, 9'b0_0000_0001        };
assign  cfg_data_reg[10]  =       {7'd52, 3'b110 , LOUT1VOL     };
assign  cfg_data_reg[11]  =       {7'd53, 3'b110 , ROUT1VOL     };
assign  cfg_data_reg[12]  =       {7'd54, 3'b110 , SPK_LOUT2VOL };
assign  cfg_data_reg[13]  =       {7'd55, 3'b110 , SPK_ROUT2VOL }; 
//enable the audio output only after the headphone and speaker volumes have been updated, to avoid a "pop" sound
assign  cfg_data_reg[14]  =       {7'd3 , 9'b0_0110_1111        };
//-------------------------------------------------------

endmodule 