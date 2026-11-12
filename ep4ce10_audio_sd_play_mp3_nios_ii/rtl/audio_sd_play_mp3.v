`timescale  1ns/1ns
////////////////////////////////////////////////////////////////////////
// Module Name   : audio_sd_play_mp3
// Target Devices: Altera EP4CE10F17C8
// Description   : Play an MP3 file stored on an SDSC card through the
//                 WM8978 codec.  Derived from the golden audio_sd_play
//                 (WAV) project:
//                   - sd_ctrl, wm8978_ctrl (audio_send, wm8978_cfg, i2c_*)
//                     are the golden modules, unchanged
//                   - the FIFO + sd_play_ctrl are replaced by
//                     mp3_feeder -> mp3_top (MAC_MP3 decoder) -> pcm_out_ctrl
//                   - the PLL MCLK is 11.2903 MHz instead of 12 MHz, so the
//                     WM8978 LRC is 44.1 kHz (clean.mp3 native rate)
//
//   Push buttons (active low): KEY1 next song, KEY2 previous song, KEY3 pause/continue.
//
//   Data flow:  SD card -> sd_ctrl -> mp3_feeder -> HUFF_DP RAM (mp3_top)
//               mp3_top -> CH0/CH1 PCM RAM -> pcm_out_ctrl -> dac_data
//               -> wm8978_ctrl.audio_send -> WM8978 (I2S, DAC)
////////////////////////////////////////////////////////////////////////

module  audio_sd_play_mp3
(
    //system clock and reset
    input   wire    sys_clk      ,  //system clock, 50MHz
    input   wire    sys_rst_n    ,  //system reset, active low


    //WM8978 interface
    input   wire    audio_bclk   ,  //bit clock output by the WM8978
    input   wire    audio_lrc    ,  //left/right alignment clock output by the WM8978

    output  wire    audio_mclk   ,  //WM8978 master clock output, 11.2903MHz
    output  wire    audio_dacdat ,  //DAC data output to the WM8978
    //i2c interface
    output  wire    scl          ,  //serial clock signal scl output to the wm8978
    inout   wire    sda          ,  //serial data signal sda output to the wm8978

    //sd card interface
    inout   wire    sd_miso      ,  //master in slave out signal
    output  wire    sd_clk       ,  //SD card clock signal
    inout  wire    sd_cs_n      ,  //chip select signal
    inout  wire    sd_mosi      ,   //master out slave in signal
	 //sd RAM
	 output wire [12:0] sdram_controller_wire_addr,                    //                  sdram_controller_wire.addr
	 output wire [1:0]  sdram_controller_wire_ba,                      //                                       .ba
	 output wire        sdram_controller_wire_cas_n,                   //                                       .cas_n
	 output wire        sdram_controller_wire_cke,                     //                                       .cke
	 output wire        sdram_controller_wire_cs_n,                    //                                       .cs_n
	 inout  wire [15:0] sdram_controller_wire_dq,                      //                                       .dq
	 output wire [1:0]  sdram_controller_wire_dqm,                     //                                       .dqm
	 output wire        sdram_controller_wire_ras_n,                   //                                       .ras_n
	 output wire        sdram_controller_wire_we_n,                    //                                       .we_n
	 output wire        sys_sdram_pll_sdram_clk_clk                    //                sys_sdram_pll_sdram_clk.clk

);

//****************************************************************//
//**************** Parameter and Internal Signal *****************//
//****************************************************************//

//wire  define
wire            rst_n           ;   //held in reset while the clock outputs are not stable
wire            init_end        ;   //sd card initialization done signal
wire            rd_busy         ;   //sd card read operation busy signal
wire            send_done       ;   //one data transmission done signal
wire            rd_en           ;   //sd card data read enable signal
wire    [31:0]  rd_addr         ;   //sd card read sector address
wire    [15:0]  dac_data        ;   //audio playback data for the WM8978
wire            clk_50m         ;   //50MHz clock output
wire            clk_50m_shift   ;   //50MHz output, shifted by 90 degrees
wire            clk_mac         ;   //MP3 MAC clock  (12.5 MHz)
wire            clk_huff        ;   //MP3 Huffman clock (3.125 MHz)
wire            locked          ;   //high means the PLL clock output has become stable
wire            cfg_done        ;   //register configuration done signal

//feeder <-> mp3_top
wire            mp3_rst_n       ;   //feeder: decoder restart (low active)
wire            mp3_wr_request  ;   //mp3_top asks for the next half of data
wire            mp3_wr_idle     ;   //feeder: not writing
wire    [9:0]   mp3_wr_addr     ;
wire    [15:0]  mp3_wr_data     ;
wire            mp3_wr_en       ;

//mp3_top <-> pcm_out_ctrl
wire    [9:0]   pcm_rd_addr     ;
wire    [15:0]  pcm_ch0_data    ;   //left
wire    [15:0]  pcm_ch1_data    ;   //right

wire            mp3_rstn_raw    ;
reg     [1:0]   mp3_rstn_mac    ;   //reset synchroniser, MAC clock domain
reg     [1:0]   pcm_rstn_bclk   ;   //reset synchroniser, BCLK domain

//rst_n: reset signal
assign  rst_n = sys_rst_n & locked;

//assign  mp3_rstn_raw = rst_n & mp3_rst_n;
assign  mp3_rstn_raw = rst_n;

//decoder reset: asynchronous assert, synchronous release (MAC clock)
always@(posedge clk_mac or negedge mp3_rstn_raw)
    if(mp3_rstn_raw == 1'b0)
        mp3_rstn_mac    <=  2'b00;
    else
        mp3_rstn_mac    <=  {mp3_rstn_mac[0], 1'b1};

//audio pointer reset: asynchronous assert, synchronous release (BCLK)
always@(posedge audio_bclk or negedge mp3_rstn_raw)
    if(mp3_rstn_raw == 1'b0)
        pcm_rstn_bclk   <=  2'b00;
    else
        pcm_rstn_bclk   <=  {pcm_rstn_bclk[0], 1'b1};

//****************************************************************//
//************************* Instantiation ************************//
//****************************************************************//

//------------- clk_gen_inst -------------
clk_gen     clk_gen_inst
(
    .areset (~sys_rst_n     ),  //asynchronous reset, active high
    .inclk0 (sys_clk        ),  //input clock
    .c0     (audio_mclk     ),  //11.2903MHz clock output (WM8978 MCLK, LRC = 44.1kHz)
    .c1     (clk_50m        ),  //50MHz clock output
    .c2     (clk_50m_shift  ),  //50MHz clock output, shifted by 90 degrees
    .c3     (clk_mac        ),  //12.5MHz clock output (MP3 MAC)
    .c4     (clk_huff       ),  //3.125MHz clock output (MP3 Huffman)
    .locked (locked         )   //clock lock signal, active high

);

nios u0 (
        .clk_clk                                       (sys_clk),                                       //                                    clk.clk
		  .mp3_resetn_pio_external_connection_export		 (mp3_rst_n),
        .mp3_wr_addr_pio_external_connection_export    (mp3_wr_addr),    //    mp3_wr_addr_pio_external_connection.export
        .mp3_wr_data_pio_external_connection_export    (mp3_wr_data),    //    mp3_wr_data_pio_external_connection.export
        .mp3_wr_en_pio_external_connection_export      (mp3_wr_en),      //      mp3_wr_en_pio_external_connection.export
        .mp3_wr_idle_pio_external_connection_export    (mp3_wr_idle),    //    mp3_wr_idle_pio_external_connection.export
        .mp3_wr_request_pio_external_connection_export (mp3_wr_request), // mp3_wr_request_pio_external_connection.export
        .reset_reset_n                                 (sys_rst_n),                                 //                                  reset.reset_n
        .sd_card_conduit_end_b_SD_cmd                  (sd_mosi),                  //                    sd_card_conduit_end.b_SD_cmd
        .sd_card_conduit_end_b_SD_dat                  (sd_miso),                  //                                       .b_SD_dat
        .sd_card_conduit_end_b_SD_dat3                 (sd_cs_n),                 //                                       .b_SD_dat3
        .sd_card_conduit_end_o_SD_clock                (sd_clk),                //                                       .o_SD_clock
        .sdram_controller_wire_addr                    (sdram_controller_wire_addr),                    //                  sdram_controller_wire.addr
        .sdram_controller_wire_ba                      (sdram_controller_wire_ba),                      //                                       .ba
        .sdram_controller_wire_cas_n                   (sdram_controller_wire_cas_n),                   //                                       .cas_n
        .sdram_controller_wire_cke                     (sdram_controller_wire_cke),                     //                                       .cke
        .sdram_controller_wire_cs_n                    (sdram_controller_wire_cs_n),                    //                                       .cs_n
        .sdram_controller_wire_dq                      (sdram_controller_wire_dq),                      //                                       .dq
        .sdram_controller_wire_dqm                     (sdram_controller_wire_dqm),                     //                                       .dqm
        .sdram_controller_wire_ras_n                   (sdram_controller_wire_ras_n),                   //                                       .ras_n
        .sdram_controller_wire_we_n                    (sdram_controller_wire_we_n),                    //                                       .we_n
        .sys_sdram_pll_sdram_clk_clk                   (sys_sdram_pll_sdram_clk_clk),                    //                sys_sdram_pll_sdram_clk.clk
		  //.pio_0_external_connection_export({NIOS_state_wire, NIOS_WRITE_DATA_IDLE_buffer_wire, NIOS_READ_DATA_ADDRESS_MAC_clock_wire, CH0_PCM_RAM_write_address_buffer_wire}) //22bits
	 );
	 
wire NIOS_state_wire;
wire NIOS_WRITE_DATA_IDLE_buffer_wire;
wire [9:0] NIOS_READ_DATA_ADDRESS_MAC_clock_wire;
wire [9:0] CH0_PCM_RAM_write_address_buffer_wire;


//------------- mp3_top_inst (MAC_MP3 decoder) -------------
mp3_top mp3_top_inst
(
    .HUFF_CLOCK_I               (clk_huff           ),
    .MAC_CLOCK_I                (clk_mac            ),
	 .RESETN_I                    (mp3_rstn_mac[1]    ),
    //MP3 bit stream input
	 .NIOS_WRITE_DATA_CLK_I      (sys_clk             ),
    .NIOS_WRITE_DATA_ADDRESS_I  (mp3_wr_addr        ),
    .NIOS_WRITE_DATA_I          (mp3_wr_data        ),
    .NIOS_WRITE_DATA_EN_I       (mp3_wr_en          ),
    .NIOS_WRITE_DATA_REQUEST_O  (mp3_wr_request     ),
    .NIOS_WRITE_DATA_IDLE_I     (mp3_wr_idle        ),

    //PCM output
    .NIOS_READ_DATA_CLK_I       (audio_bclk         ),

    .NIOS_READ_DATA_ADDRESS_I   (pcm_rd_addr        ),
    .NIOS_CH0_READ_DATA_O       (pcm_ch0_data       ),
    .NIOS_CH1_READ_DATA_O       (pcm_ch1_data       ),

    .NIOS_SAMPLE_FREQUENCY_O    (),
    .USER_LED0_O                (),
    .USER_LED1_O                (),
//	 .NIOS_state_wire(NIOS_state_wire),
//	 .NIOS_WRITE_DATA_IDLE_buffer_wire(NIOS_WRITE_DATA_IDLE_buffer_wire),
//	 .NIOS_READ_DATA_ADDRESS_MAC_clock_wire(NIOS_READ_DATA_ADDRESS_MAC_clock_wire),
//	 .CH0_PCM_RAM_write_address_buffer_wire(CH0_PCM_RAM_write_address_buffer_wire)
);

//------------- pcm_out_ctrl_inst (replaces dac_data part of sd_play_ctrl) -------------
pcm_out_ctrl pcm_out_ctrl_inst
(
    .audio_bclk (audio_bclk         ),
    .sys_rst_n  (pcm_rstn_bclk[1]   ),
    .run        (cfg_done),
    .send_done  (send_done          ),
    .audio_lrc  (audio_lrc          ),
    .pause      (2'b00      ),
    .ch0_data   (pcm_ch0_data       ),
    .ch1_data   (pcm_ch1_data       ),

    .rd_addr    (pcm_rd_addr        ),
    .dac_data   (dac_data           )
);

//------------- wm8978_ctrl_inst (golden, unchanged) -------------
wm8978_ctrl wm8978_ctrl_inst
(
    .sys_clk     (clk_50m     ),  //system clock, 50MHz
    .sys_rst_n   (rst_n       ),  //system reset, active low
    .audio_bclk  (audio_bclk  ),  //bit clock output by the WM8978
    .audio_lrc   (audio_lrc   ),  //left/right alignment clock output by the WM8978
    .audio_adcdat(),              //ADC data output by the WM8978
    .dac_data    (dac_data    ),  //input audio data

    .scl         (scl         ),  //serial clock signal scl output to the wm8978
    .audio_dacdat(audio_dacdat),  //DAC data output to the WM8978
    .rcv_done    (),              //one data reception done
    .send_done   (send_done   ),  //one data transmission done
    .adc_data    (),              //output audio data
    .cfg_done    (cfg_done    ),  //register configuration done signal
    .sda         (sda         )   //serial data signal sda output to the wm8978

);

endmodule

