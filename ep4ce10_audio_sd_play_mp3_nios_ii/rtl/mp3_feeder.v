`timescale  1ns/1ns
////////////////////////////////////////////////////////////////////////
// Module Name   : mp3_feeder
// Description   : Hardware replacement of the Nios II program of the
//                 MAC_MP3 DE2 demo (hello_world.c).
//
//   mp3_top raises NIOS_WRITE_DATA_REQUEST_O (write_request) whenever one
//   512-word half of its 1024x16 input ring (HUFF_DP) has been consumed.
//   The writer must
//       1. drop IDLE (write_idle = 0) to acknowledge the request,
//       2. write 512 words = 1024 bytes = 2 SD sectors (big-endian words,
//          {first byte, second byte}, NO byte swap),
//       3. raise IDLE again.
//
//   Sector reads reuse the golden sd_ctrl interface exactly like
//   sd_play_ctrl.v does (rd_en pulse, rd_busy falling edge = sector done,
//   rd_data_en/rd_data = 256 words per sector).
//
//   End of file: the last real half is followed by one half of zeros, then
//   the decoder (and the audio read pointer) is restarted via mp3_rst_n and
//   the NEXT song of the table is played (wrapping to song 0; with
//   NUM_SONGS = 1 the same song is repeated).
//
//   Song table: SONG_ADDRS / SONG_SECTORS hold NUM_SONGS (max 8) entries,
//   entry i in bits [32*i +: 32] / [18*i +: 18].  KEY next / previous
//   (next_pulse / prev_pulse, sd_clk domain) change song_req immediately
//   (several presses accumulate); song_play, which selects the sector
//   address, is only updated while the decoder is being restarted, so a
//   sector read in progress is never disturbed.
//
//   Everything runs on sd_clk (same clock the golden uses for the FIFO).
////////////////////////////////////////////////////////////////////////

module  mp3_feeder
#(
    parameter           NUM_SONGS    =   1,                      //number of songs in the table (1..8)
    parameter   [255:0] SONG_ADDRS   =   {224'd0, 32'd417},      //first sector of each MP3 file (see tools/find_mp3_sector.py)
    parameter   [143:0] SONG_SECTORS =   {126'd0, 18'd8086}      //sectors to read = ceil(file bytes / 512), must be even
)
(
    input   wire            sd_clk          ,   //SD card clock (same as golden sd_play_ctrl)
    input   wire            sys_rst_n       ,   //global reset, low active
    input   wire            sd_init_end     ,   //SD card initialisation done
    input   wire            cfg_done        ,   //WM8978 register configuration done

    //playlist keys (one-clock pulses in the sd_clk domain)
    input   wire            next_pulse      ,   //play next song
    input   wire            prev_pulse      ,   //play previous song
    output  wire    [2:0]   song_idx        ,   //song being played

    //sd_ctrl read port
    input   wire            rd_busy         ,
    input   wire            rd_data_en      ,
    input   wire    [15:0]  rd_data         ,
    output  reg             rd_en           ,
    output  wire    [31:0]  rd_addr         ,

    //mp3_top input port ("NIOS_WRITE_*")
    input   wire            write_request   ,   //from mp3_top (MAC clock domain)
    output  reg             write_idle      ,   //to mp3_top
    output  reg     [9:0]   ram_waddr       ,   //HUFF_DP port A address
    output  reg     [15:0]  ram_wdata       ,   //HUFF_DP port A data
    output  reg             ram_we          ,   //HUFF_DP port A write enable

    output  reg             mp3_rst_n           //low = restart decoder + audio pointer
);

//********************************************************************//
//***************** Parameter and Internal Signal ********************//
//********************************************************************//

localparam  S_IDLE      =   3'd0,
            S_RD_CMD    =   3'd1,
            S_RD_BUSY   =   3'd2,
            S_ZERO      =   3'd3,
            S_DONE      =   3'd4,
            S_RESTART   =   3'd5;

reg     [2:0]   state       ;
reg     [17:0]  sector_cnt  ;   //sectors already read
reg     [2:0]   song_req    ;   //requested song (changes immediately on a key press)
reg     [2:0]   song_play   ;   //song being read from the SD card (changes only during restart)
reg             sec_in_req  ;   //0: first sector of the half, 1: second
reg     [9:0]   waddr_cnt   ;   //next ring address to write
reg     [9:0]   zero_cnt    ;   //zero fill counter
reg     [7:0]   rst_cnt     ;   //restart pulse length
reg     [3:0]   done_cnt    ;   //settle time before IDLE is raised
reg             eof_zero    ;   //the zero half after the file end has been written

reg             req_s0      ;   //write_request synchroniser
reg             req_s1      ;
reg             rd_busy_d0  ;
reg             rd_busy_d1  ;

wire            rd_busy_fall;
wire            ready       ;
wire            at_eof      ;
wire    [31:0]  cur_addr    ;
wire    [17:0]  cur_sectors ;
wire    [2:0]   song_next   ;   //song after song_play
wire    [2:0]   song_req_nx ;   //song_req after a next key
wire    [2:0]   song_req_pv ;   //song_req after a previous key
wire            song_change ;

assign  rd_busy_fall = ~rd_busy_d0 & rd_busy_d1;
assign  ready        = sd_init_end & cfg_done;
assign  cur_addr     = SONG_ADDRS[32*song_play +: 32];
assign  cur_sectors  = SONG_SECTORS[18*song_play +: 18];
assign  at_eof       = (sector_cnt >= cur_sectors);
assign  rd_addr      = cur_addr + {14'd0, sector_cnt};
assign  song_idx     = song_play;
assign  song_next    = (song_play == NUM_SONGS - 1) ? 3'd0 : song_play + 3'd1;
assign  song_req_nx  = (song_req  == NUM_SONGS - 1) ? 3'd0 : song_req  + 3'd1;
assign  song_req_pv  = (song_req  == 3'd0) ? NUM_SONGS - 1 : song_req - 3'd1;
assign  song_change  = (song_req != song_play);

//key presses: update the requested song
always@(posedge sd_clk  or  negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        song_req    <=  3'd0;
    else    if((next_pulse == 1'b1) && (prev_pulse == 1'b0))
        song_req    <=  song_req_nx;
    else    if((prev_pulse == 1'b1) && (next_pulse == 1'b0))
        song_req    <=  song_req_pv;
    else    if((state == S_IDLE) && (ready == 1'b1) && (song_change == 1'b0) && (req_s1 == 1'b1)
                && (at_eof == 1'b1) && (eof_zero == 1'b1))
        song_req    <=  song_next;      //end of file: advance to the next song

//********************************************************************//
//******************************* Main Code **************************//
//********************************************************************//

always@(posedge sd_clk  or  negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        begin
            req_s0      <=  1'b0;
            req_s1      <=  1'b0;
            rd_busy_d0  <=  1'b0;
            rd_busy_d1  <=  1'b0;
        end
    else
        begin
            req_s0      <=  write_request;
            req_s1      <=  req_s0;
            rd_busy_d0  <=  rd_busy;
            rd_busy_d1  <=  rd_busy_d0;
        end

//SD word -> HUFF_DP write port (registered, so address/data/we are aligned)
always@(posedge sd_clk  or  negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        begin
            ram_we      <=  1'b0;
            ram_waddr   <=  10'd0;
            ram_wdata   <=  16'd0;
            waddr_cnt   <=  10'd0;
        end
    else    if(state == S_RESTART)
        begin
            ram_we      <=  1'b0;
            waddr_cnt   <=  10'd0;
        end
    else    if(rd_data_en == 1'b1)
        begin
            ram_we      <=  1'b1;
            ram_waddr   <=  waddr_cnt;
            ram_wdata   <=  rd_data;
            waddr_cnt   <=  waddr_cnt + 10'd1;
        end
    else    if(state == S_ZERO)
        begin
            ram_we      <=  1'b1;
            ram_waddr   <=  waddr_cnt;
            ram_wdata   <=  16'd0;
            waddr_cnt   <=  waddr_cnt + 10'd1;
        end
    else
        ram_we      <=  1'b0;

always@(posedge sd_clk  or  negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        begin
            state       <=  S_IDLE;
            rd_en       <=  1'b0;
            write_idle  <=  1'b1;
            sector_cnt  <=  18'd0;
            sec_in_req  <=  1'b0;
            zero_cnt    <=  10'd0;
            rst_cnt     <=  8'd0;
            done_cnt    <=  4'd0;
            eof_zero    <=  1'b0;
            mp3_rst_n   <=  1'b1;
            song_play   <=  3'd0;
        end
    else
        case(state)
        S_IDLE:
            begin
                rd_en       <=  1'b0;
                mp3_rst_n   <=  1'b1;
                write_idle  <=  1'b1;
                sec_in_req  <=  1'b0;
                if((ready == 1'b1) && (song_change == 1'b1))
                    begin
                        rst_cnt     <=  8'd0;           //song changed by a key: restart with the new song
                        state       <=  S_RESTART;
                    end
                else    if((ready == 1'b1) && (req_s1 == 1'b1))
                    begin
                        write_idle  <=  1'b0;           //acknowledge the request
                        if(at_eof == 1'b0)
                            state   <=  S_RD_CMD;       //refill the half from the SD card
                        else    if(eof_zero == 1'b0)
                            begin
                                zero_cnt    <=  10'd0;  //first request past the end: zero half
                                state       <=  S_ZERO;
                            end
                        else
                            begin
                                rst_cnt     <=  8'd0;   //second request past the end: restart
                                state       <=  S_RESTART;
                            end
                    end
            end
        S_RD_CMD:
            begin
                rd_en   <=  1'b1;
                state   <=  S_RD_BUSY;
            end
        S_RD_BUSY:
            begin
                rd_en   <=  1'b0;
                if(rd_busy_fall == 1'b1)
                    begin
                        sector_cnt  <=  sector_cnt + 18'd1;
                        sec_in_req  <=  1'b1;
                        if(sec_in_req == 1'b1)
                            begin
                                done_cnt    <=  4'd0;
                                state       <=  S_DONE;
                            end
                        else
                            state   <=  S_RD_CMD;
                    end
            end
        S_ZERO:
            begin
                zero_cnt    <=  zero_cnt + 10'd1;
                if(zero_cnt == 10'd511)
                    begin
                        eof_zero    <=  1'b1;
                        done_cnt    <=  4'd0;
                        state       <=  S_DONE;
                    end
            end
        S_DONE:
            begin
                done_cnt    <=  done_cnt + 4'd1;
                if(done_cnt == 4'd8)    //last RAM write has long been completed
                    begin
                        write_idle  <=  1'b1;
                        state       <=  S_IDLE;
                    end
            end
        S_RESTART:
            begin
                mp3_rst_n   <=  1'b0;
                rst_cnt     <=  rst_cnt + 8'd1;
                sector_cnt  <=  18'd0;
                eof_zero    <=  1'b0;
                write_idle  <=  1'b1;
                song_play   <=  song_req;               //select the new song
                if(rst_cnt == 8'd255)
                    begin
                        mp3_rst_n   <=  1'b1;
                        state       <=  S_IDLE;
                    end
            end
        default:    state   <=  S_IDLE;
        endcase

endmodule
