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

    //push buttons (active low)
    input   wire    key_next     ,  //KEY1: play next song
    input   wire    key_prev     ,  //KEY2: play previous song
    input   wire    key_pause    ,  //KEY3: pause/continue song

    //WM8978 interface
    input   wire    audio_bclk   ,  //bit clock output by the WM8978
    input   wire    audio_lrc    ,  //left/right alignment clock output by the WM8978

    output  wire    audio_mclk   ,  //WM8978 master clock output, 11.2903MHz
    output  wire    audio_dacdat ,  //DAC data output to the WM8978
    //i2c interface
    output  wire    scl          ,  //serial clock signal scl output to the wm8978
    inout   wire    sda          ,  //serial data signal sda output to the wm8978

    //sd card interface
    input   wire    sd_miso      ,  //master in slave out signal
    output  wire    sd_clk       ,  //SD card clock signal
    output  wire    sd_cs_n      ,  //chip select signal
    output  wire    sd_mosi         //master out slave in signal

);

//****************************************************************//
//**************** Parameter and Internal Signal *****************//
//****************************************************************//

//parameter define
//Song table (max 8 songs).  Song i uses bits [32*i +: 32] of SONG_ADDRS and
//bits [18*i +: 18] of SONG_SECTORS.
//SONG_ADDRS   : sector (LBA) of the first cluster of each MP3 file on the SDSC card.
//               Get the values with tools/find_mp3_sector.py (or WinHex) AFTER
//               copying the files to a freshly formatted FAT16 card.
//               417 is the value measured on the author's board card (works).
//               REPLACE it with the numbers read from YOUR card.
//SONG_SECTORS : ceil(file bytes / 512), must be even.  8086 = clean.mp3
//               (4139884 bytes = 8085.7 sectors).
//NUM_SONGS    : number of valid table entries.
//The default is the single song clean.mp3; the key switches songs only if the
//table holds more than one entry.  tools/find_mp3_sector.py prints a
//ready-to-paste table for all *.MP3 files on the card.
parameter           NUM_SONGS       =   4                       ;   //number of songs in the table
parameter   [255:0] SONG_ADDRS      =   {128'd0, 32'd37315,32'd17923,32'd835,32'd37315}       ;   //first sector of each MP3 file
parameter   [143:0] SONG_SECTORS    =   {72'd0, 18'd7704,18'd8086,18'd9418,18'd7704}      ;   //number of sectors occupied by each MP3 file

//push button options (use them to isolate a problem on the board)
parameter   KEY_ACTIVE_LOW  =   1           ;   //1: key pressed = 0 (golden board), 0: key pressed = 1
parameter   SONG_KEYS_EN    =   1           ;   //0: KEY1/KEY2 are ignored (always plays song 0, then the next one at the end of the file)
parameter   PAUSE_KEY_EN    =   1           ;   //0: KEY3 is ignored

//push button timing (50MHz clock cycles)
parameter   KEY_DEBOUNCE    =   32'd1_000_000   ;   //20 ms debounce

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
wire    [15:0]  sd_rd_data      ;   //data read from the sd card
wire            rd_data_en      ;   //sd card read data valid
wire            cfg_done        ;   //register configuration done signal

//keys
wire            next_raw        ;   //KEY1 press, 50 MHz domain
wire            prev_raw        ;   //KEY2 press, 50 MHz domain
wire            next_pulse_50m  ;   //KEY1 press after the enable option
wire            prev_pulse_50m  ;   //KEY2 press after the enable option
wire            key_next_n      ;   //keys converted to active low
wire            key_prev_n      ;
wire            key_pause_n     ;
wire            pause_raw       ;   //KEY3 press, 50MHz domain
wire            pause_pulse_50m ;   //KEY3 press after the enable option
reg             paused          ;   //1: playback is paused (50MHz domain)
reg     [1:0]   pause_bclk = 2'b00; //paused, sync to BCLK domain
wire            next_pulse      ;   //KEY1 press, sd_clk domain
wire            prev_pulse      ;   //KEY2 press, sd_clk domain
wire    [2:0]   song_idx        ;   //song being played

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

assign  mp3_rstn_raw = rst_n & mp3_rst_n;

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

//------------- sd_ctrl_inst (golden, unchanged) -------------
sd_ctrl sd_ctrl_inst
(
    .sys_clk         (clk_50m      ),  //input working clock, 50MHz
    .sys_clk_shift   (clk_50m_shift),  //input working clock, 50MHz, phase shifted by 90 degrees
    .sys_rst_n       (rst_n        ),  //input reset signal, active low
//SD card interface
    .sd_miso         (sd_miso      ),  //master in slave out signal
    .sd_clk          (sd_clk       ),  //SD card clock signal
    .sd_cs_n         (sd_cs_n      ),  //chip select signal
    .sd_mosi         (sd_mosi      ),  //master out slave in signal
//SD card write interface (nothing is written to the SD card, so tie the inputs to 0 and leave the outputs open)
    .wr_en           (0),              //data write enable signal
    .wr_addr         (0),              //write data sector address
    .wr_data         (0),              //write data
    .wr_busy         (),               //write operation busy signal
    .wr_req          (),               //write data request signal
//SD card read interface
    .rd_en           (rd_en        ),  //data read enable signal
    .rd_addr         (rd_addr      ),  //read data sector address
    .rd_busy         (rd_busy      ),  //read operation busy signal
    .rd_data_en      (rd_data_en   ),  //read data valid flag signal
    .rd_data         (sd_rd_data   ),  //read data

    .init_end        (init_end     )   //SD card initialization done signal

);

//------------- push buttons -------------
assign  key_next_n      = (KEY_ACTIVE_LOW != 0) ? key_next     : ~key_next    ;
assign  key_prev_n      = (KEY_ACTIVE_LOW != 0) ? key_prev     : ~key_prev    ;
assign  key_pause_n     = (KEY_ACTIVE_LOW != 0) ? key_pause    : ~key_pause   ;
assign  next_pulse_50m  = next_raw     & (SONG_KEYS_EN != 0);
assign  prev_pulse_50m  = prev_raw     & (SONG_KEYS_EN != 0);
assign  pause_pulse_50m = pause_raw    & (PAUSE_KEY_EN != 0);

key_ctrl #(.DEBOUNCE(KEY_DEBOUNCE))
key_next_inst
(
    .clk        (clk_50m        ),
    .rst_n      (rst_n          ),
    .key_n      (key_next_n     ),
    .key_pulse  (next_raw       )
);

key_ctrl #(.DEBOUNCE(KEY_DEBOUNCE))
key_prev_inst
(
    .clk        (clk_50m        ),
    .rst_n      (rst_n          ),
    .key_n      (key_prev_n     ),
    .key_pulse  (prev_raw       )
);

key_ctrl #(.DEBOUNCE(KEY_DEBOUNCE))
key_pause_inst
(
    .clk        (clk_50m        ),
    .rst_n      (rst_n          ),
    .key_n      (key_pause_n    ),
    .key_pulse  (pause_raw      )
);

//KEY3 toggles pause; a song change (KEY1 / KEY2) releases it so the new song starts playing                                                                                                                                                                                           
  always@(posedge clk_50m or negedge rst_n)                                                                                                                                                                                                                                              
      if(rst_n == 1'b0)                                                                                                                                                                                                                                                                  
          paused  <=  1'b0;                                                                                                                                                                                                                                                              
      else    if(pause_pulse_50m == 1'b1)                                                                                                                                                                                                                                                
          paused  <=  ~paused;                                                                                                                                                                                                                                                           
      else    if((next_pulse_50m == 1'b1) || (prev_pulse_50m == 1'b1))                                                                                                                                                                                                                   
          paused  <=  1'b0;                                                                                                                                                                                                                                                              
                                                                                                                                                                                                                                                                                         
  //paused crosses to the BCLK domain (level signal, 2-flop synchroniser)                                                                                                                                                                                                                
  always@(posedge audio_bclk)                                                                                                                                                                                                                                                            
      pause_bclk  <=  {pause_bclk[0], paused};

//song key pulses cross from the 50MHz domain to the SD SPI clock domain
pulse_sync  next_sync_inst
(
    .src_clk    (clk_50m        ),
    .src_rst_n  (rst_n          ),
    .src_pulse  (next_pulse_50m ),
    .dst_clk    (sd_clk         ),
    .dst_rst_n  (rst_n          ),
    .dst_pulse  (next_pulse     )
);

pulse_sync  prev_sync_inst
(
    .src_clk    (clk_50m        ),
    .src_rst_n  (rst_n          ),
    .src_pulse  (prev_pulse_50m ),
    .dst_clk    (sd_clk         ),
    .dst_rst_n  (rst_n          ),
    .dst_pulse  (prev_pulse     )
);

//------------- mp3_feeder_inst (replaces the Nios II program) -------------
mp3_feeder
#(
    .NUM_SONGS      (NUM_SONGS      ),
    .SONG_ADDRS     (SONG_ADDRS     ),
    .SONG_SECTORS   (SONG_SECTORS   )
)
mp3_feeder_inst
(
    .sd_clk         (sd_clk         ),
    .sys_rst_n      (rst_n          ),
    .sd_init_end    (init_end       ),
    .cfg_done       (cfg_done       ),

    .next_pulse     (next_pulse     ),
    .prev_pulse     (prev_pulse     ),
    .song_idx       (song_idx       ),

    .rd_busy        (rd_busy        ),
    .rd_data_en     (rd_data_en     ),
    .rd_data        (sd_rd_data     ),
    .rd_en          (rd_en          ),
    .rd_addr        (rd_addr        ),

    .write_request  (mp3_wr_request ),
    .write_idle     (mp3_wr_idle    ),
    .ram_waddr      (mp3_wr_addr    ),
    .ram_wdata      (mp3_wr_data    ),
    .ram_we         (mp3_wr_en      ),

    .mp3_rst_n      (mp3_rst_n      )
);

//------------- mp3_top_inst (MAC_MP3 decoder) -------------
mp3_top mp3_top_inst
(
    .HUFF_CLOCK_I               (clk_huff           ),
    .MAC_CLOCK_I                (clk_mac            ),
    .RESETN_I                   (mp3_rstn_mac[1]    ),

    //MP3 bit stream input
    .NIOS_WRITE_DATA_CLK_I      (sd_clk             ),
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
    .USER_LED1_O                ()
);

//------------- pcm_out_ctrl_inst (replaces dac_data part of sd_play_ctrl) -------------
pcm_out_ctrl pcm_out_ctrl_inst
(
    .audio_bclk (audio_bclk         ),
    .sys_rst_n  (pcm_rstn_bclk[1]   ),
    .run        (init_end & cfg_done),
    .send_done  (send_done          ),
    .audio_lrc  (audio_lrc          ),
    .pause      (pause_bclk[1]      ),
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
