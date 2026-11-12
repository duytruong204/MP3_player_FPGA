`timescale  1ns/1ns
////////////////////////////////////////////////////////////////////////
// Author        : EmbedFire
// Create Date   : 2019/12/05
// Module Name   : wm8978_cfg
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

module  wm8978_cfg
(
    input   wire    sys_clk     ,   //system clock, 50MHz
    input   wire    sys_rst_n   ,   //system reset, active low

    output  wire    i2c_scl     ,   //serial clock signal scl output to the WM8978
    inout   wire    i2c_sda     ,   //serial data signal sda output to the WM8978
    output  wire    cfg_done        //register configuration done signal
);

//****************************************************************//
//**************** Parameter and Internal Signal *****************//
//****************************************************************//

//wire  define
wire            cfg_start   ;   //input i2c start trigger signal
wire    [15:0]  cfg_data    ;   //register address 7 bit + data 9 bit
wire            i2c_clk     ;   //i2c driver clock
wire            i2c_end     ;   //one i2c read/write operation done

//****************************************************************//
//************************* Instantiation ************************//
//****************************************************************//

//------------------------ i2c_ctrl_inst -----------------------
i2c_ctrl
#(
    . DEVICE_ADDR     (7'b0011_010   )  ,   //i2c device address
    . SYS_CLK_FREQ    (26'd50_000_000)  ,   //input system clock frequency
    . SCL_FREQ        (18'd250_000   )      //i2c device scl clock frequency
)
i2c_ctrl_inst
(
    .sys_clk        (sys_clk       ),   //input system clock, 50MHz
    .sys_rst_n      (sys_rst_n     ),   //input reset signal, active low
    .wr_en          (1'b1          ),   //input write enable signal
    .rd_en          (1'b0          ),   //input read enable signal
    .i2c_start      (cfg_start     ),   //input i2c start trigger signal
    .addr_num       (1'b0          ),   //input number of i2c byte address bytes
    .byte_addr      (cfg_data[15:8]),   //input i2c byte address + highest data bit
    .wr_data        (cfg_data[7:0] ),   //input i2c device data low eight bits

    .rd_data        (              ),   //data read from the i2c device
    .i2c_end        (i2c_end       ),   //one i2c read/write operation done
    .i2c_clk        (i2c_clk       ),   //i2c driver clock
    .i2c_scl        (i2c_scl       ),   //serial clock signal scl output to the i2c device
    .i2c_sda        (i2c_sda       )    //serial data signal sda output to the i2c device
);

//---------------------- i2c_reg_cfg_inst ---------------------
 i2c_reg_cfg     i2c_reg_cfg_inst
 (
    .i2c_clk     (i2c_clk   ),   //system clock, supplied by the i2c module
    .sys_rst_n   (sys_rst_n ),   //system reset, active low
    .cfg_end     (i2c_end   ),   //single register configuration done

    .cfg_start   (cfg_start ),   //single register configuration trigger signal
    .cfg_data    (cfg_data  ),   //register address and data
    .cfg_done    (cfg_done  )    //register configuration done signal
); 

endmodule