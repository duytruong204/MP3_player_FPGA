`timescale  1ns/1ns
////////////////////////////////////////////////////////////////////////
// Author        : EmbedFire
//Create Date    : 2019/09/03
// Module Name   : sd_ctrl
// Project Name  : sd_tft_pic
// Target Devices: Altera EP4CE10F17C8N
// Tool Versions : Quartus 13.0
// Description   : SD card control top module
//
// Revision      : V1.0
// Additional Comments:
// 
// Platform: EmbedFire Zhengtu Pro FPGA development board
// Company : http://www.embedfire.com
// Forum   : http://www.firebbs.cn
// Taobao  : https://fire-stm32.taobao.com
////////////////////////////////////////////////////////////////////////

module  sd_ctrl
(
    input   wire            sys_clk         ,   //input working clock, 50MHz
    input   wire            sys_clk_shift   ,   //input working clock, 50MHz, phase shifted by 90 degrees
    input   wire            sys_rst_n       ,   //input reset signal, active low
    //SD card interface
    input   wire            sd_miso         ,   //master in slave out signal
    output  wire            sd_clk          ,   //SD card clock signal
    output  reg             sd_cs_n         ,   //chip select signal
    output  reg             sd_mosi         ,   //master out slave in signal
    //SD card write interface
    input   wire            wr_en           ,   //data write enable signal
    input   wire    [31:0]  wr_addr         ,   //write data sector address
    input   wire    [15:0]  wr_data         ,   //write data
    output  wire            wr_busy         ,   //write operation busy signal
    output  wire            wr_req          ,   //write data request signal
    //SD card read interface
    input   wire            rd_en           ,   //data read enable signal
    input   wire    [31:0]  rd_addr         ,   //read data sector address
    output  wire            rd_busy         ,   //read operation busy signal
    output  wire            rd_data_en      ,   //read data valid flag signal
    output  wire    [15:0]  rd_data         ,   //read data

    output  wire            init_end            //SD card initialization done signal
);

//********************************************************************//
//****************** Parameter and Internal Signal *******************//
//********************************************************************//
//wire define
wire            init_cs_n   ;   //chip select signal in the initialization phase
wire            init_mosi   ;   //master out slave in signal in the initialization phase
wire            wr_cs_n     ;   //chip select signal in the write phase
wire            wr_mosi     ;   //master out slave in signal in the write phase
wire            rd_cs_n     ;   //chip select signal in the read phase
wire            rd_mosi     ;   //master out slave in signal in the read phase
wire    [6:0]   div_lim     ;   //half-period length of spi_clk in sys_clk cycles - 1

//parameter define
parameter   DIV_INIT    =   7'd63   ;   //init: toggle every 64 clk -> 390.6 kHz
parameter   DIV_RUN     =   7'd1    ;   //run : toggle every 2 clk  -> 12.5 MHz

//reg   define
reg     [6:0]   div_cnt     ;   //SPI clock divider counter
reg             spi_clk     ;   //divided SPI clock
reg             spi_clk_shift;  //spi_clk delayed by ~5 ns (sys_clk_shift)
reg             init_end_s0 ;   //init_end synchroniser
reg             init_end_s1 ;

//********************************************************************//
//***************************** Main Code ****************************//
//********************************************************************//
//SPI clock generation.
//A card only accepts <= 400 kHz while it is being initialised and <= 25 MHz
//in default-speed data mode, so the original 50 MHz is too fast (SDSC cards
//are especially picky).
//  before init_end : 50 MHz / 128 = 390.6 kHz
//  after  init_end : 50 MHz / 4   = 12.5   MHz
//spi_clk is the clock of the sd_init / sd_read / sd_write FSMs.  sd_clk (pin
//and FIFO write clock) is spi_clk delayed by one sys_clk_shift edge (~5 ns),
//the same 90 degree phase relationship the original design used between
//sys_clk and sys_clk_shift: MOSI changes 5 ns before the card sees the
//rising edge and MISO is sampled on the shifted clock.
always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        begin
            init_end_s0 <=  1'b0;
            init_end_s1 <=  1'b0;
        end
    else
        begin
            init_end_s0 <=  init_end;
            init_end_s1 <=  init_end_s0;
        end

assign  div_lim = init_end_s1 ? DIV_RUN : DIV_INIT;

always@(posedge sys_clk or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        begin
            div_cnt <=  7'd0;
            spi_clk <=  1'b0;
        end
    else    if(div_cnt >= div_lim)
        begin
            div_cnt <=  7'd0;
            spi_clk <=  ~spi_clk;
        end
    else
        div_cnt <=  div_cnt + 7'd1;

always@(posedge sys_clk_shift or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        spi_clk_shift   <=  1'b0;
    else
        spi_clk_shift   <=  spi_clk;

//sd_clk: SD card clock signal
assign  sd_clk = spi_clk_shift;

//SD card interface signal selection
always@(*)
    if(init_end == 1'b0)
        begin
            sd_cs_n <=  init_cs_n;
            sd_mosi <=  init_mosi;
        end
    else    if(wr_busy == 1'b1)
        begin
            sd_cs_n <=  wr_cs_n;
            sd_mosi <=  wr_mosi;
        end
    else    if(rd_busy == 1'b1)
        begin
            sd_cs_n <= rd_cs_n;
            sd_mosi <= rd_mosi;
        end
    else
        begin
            sd_cs_n <=  1'b1;
            sd_mosi <=  1'b1;
        end

//********************************************************************//
//************************** Instantiation ***************************//
//********************************************************************//
//------------- sd_init_inst -------------
sd_init sd_init_inst
(
    .sys_clk        (spi_clk        ),  //SPI FSM clock (390.6 kHz init / 12.5 MHz run)
    .sys_clk_shift  (spi_clk_shift  ),  //spi_clk delayed ~5 ns
    .sys_rst_n      (sys_rst_n      ),  //input reset signal, active low
    .miso           (sd_miso        ),  //master in slave out signal

    .cs_n           (init_cs_n      ),  //output chip select signal
    .mosi           (init_mosi      ),  //master out slave in signal
    .init_end       (init_end       )   //initialization done signal
);

//------------- sd_write_inst -------------
sd_write    sd_write_inst
(
    .sys_clk        (spi_clk            ),  //SPI FSM clock
    .sys_clk_shift  (spi_clk_shift      ),  //spi_clk delayed ~5 ns
    .sys_rst_n      (sys_rst_n          ),  //input reset signal, active low
    .miso           (sd_miso            ),  //master in slave out signal
    .wr_en          (wr_en && init_end  ),  //data write enable signal
    .wr_addr        (wr_addr            ),  //write data sector address
    .wr_data        (wr_data            ),  //write data

    .cs_n           (wr_cs_n            ),  //output chip select signal
    .mosi           (wr_mosi            ),  //master out slave in signal
    .wr_busy        (wr_busy            ),  //write operation busy signal
    .wr_req         (wr_req             )   //write data request signal
);

//------------- sd_read_inst -------------
sd_read sd_read_inst
(
    .sys_clk        (spi_clk            ),  //SPI FSM clock
    .sys_clk_shift  (spi_clk_shift      ),  //spi_clk delayed ~5 ns
    .sys_rst_n      (sys_rst_n          ),  //input reset signal, active low
    .miso           (sd_miso            ),  //master in slave out signal
    .rd_en          (rd_en & init_end   ),  //data read enable signal
    .rd_addr        (rd_addr            ),  //read data sector address

    .rd_busy        (rd_busy            ),  //read operation busy signal
    .rd_data_en     (rd_data_en         ),  //read data valid flag signal
    .rd_data        (rd_data            ),  //read data
    .cs_n           (rd_cs_n            ),  //chip select signal
    .mosi           (rd_mosi            )   //master out slave in signal
);

endmodule