`timescale  1ns/1ns
////////////////////////////////////////////////////////////////////////
// Module Name   : pcm_out_ctrl
// Description   : Replaces the FIFO/byte-swap part of the golden
//                 sd_play_ctrl.v.  It hands the decoded PCM samples of
//                 mp3_top (CH0 = left, CH1 = right, two 1024x16 RAMs read
//                 with a common 10-bit address) to the unmodified
//                 wm8978_ctrl/audio_send as 16-bit words, one word per
//                 LRC slot, left first.
//
//   Timing is identical to the golden: dac_data is reloaded on the
//   send_done pulse of audio_send (16 BCLK after an LRC edge), which is
//   long before the next LRC edge latches it into audio_send.
//
//   send_done in the RIGHT slot (audio_lrc = 1): next slot is LEFT  -> CH0[addr]
//   send_done in the LEFT  slot (audio_lrc = 0): next slot is RIGHT -> CH1[addr],
//                                                then addr = addr + 1
//
//   mp3_top uses this address as the playback pointer and decodes the
//   next granule when the pointer reaches the end of the previous one, so
//   the pointer MUST start at 512 after a reset (same as the DE2 design).
//   The pointer only runs when the system is ready (SD + codec configured).
//   The output is muted for MUTE_FRAMES frames after a (re)start so that stale
//   RAM content (the end of the previous pass after the end-of-file restart) is never
//   played: after a restart the decoder needs ~2100 frames before the first fresh
//   samples reach the read pointer.  MUTE_FRAMES = 512 + 1024*n makes the pointer
//   end up at address 0 when the output is un-muted.
////////////////////////////////////////////////////////////////////////

//   GAIN_SHIFT: the MAC_MP3 decoder output is 6 dB below a reference decoder
//   (measured against the ffmpeg decode of clean.mp3: gain 0.496).  GAIN_SHIFT = 1
//   doubles the samples (saturating) so that the loudness equals the golden WAV
//   playback.  Set 0 for the raw decoder output.
////////////////////////////////////////////////////////////////////////

module  pcm_out_ctrl
#(
    parameter   GAIN_SHIFT  =   1   ,
    parameter   MUTE_FRAMES =   3584    //81 ms; 512 + 1024*3
)
(
    input   wire            audio_bclk  ,   //WM8978 bit clock (BCLK)
    input   wire            sys_rst_n   ,   //async reset, low active (system reset & decoder restart)
    input   wire            run         ,   //SD initialised and WM8978 configured
    input   wire            send_done   ,   //from audio_send, once per LRC slot
    input   wire            audio_lrc   ,   //WM8978 LRC
    input   wire            pause       ,   //1: freeze the playback pointer and output silence (BCLK domain)
    input   wire    [15:0]  ch0_data    ,   //mp3_top left  PCM RAM q (valid one BCLK after address)
    input   wire    [15:0]  ch1_data    ,   //mp3_top right PCM RAM q

    output  reg     [9:0]   rd_addr     ,   //mp3_top NIOS_READ_DATA_ADDRESS_I
    output  reg     [15:0]  dac_data        //to wm8978_ctrl
);

reg             started ;   //mute period is over
reg     [12:0]  mute_cnt;   //frames since (re)start

//saturating gain stage (ch << GAIN_SHIFT)
function [15:0] gain;
    input   [15:0]  x;
    begin
        if(GAIN_SHIFT == 0)
            gain = x;
        else
            begin
                //arithmetic shift left by 1 with saturation
                if(x[15] != x[14])
                    gain = x[15] ? 16'h8000 : 16'h7FFF;
                else
                    gain = {x[14:0], 1'b0};
            end
    end
endfunction

always@(posedge audio_bclk  or  negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        begin
            rd_addr     <=  10'd512;
            dac_data    <=  16'd0;
            started     <=  1'b0;
            mute_cnt    <=  13'd0;
        end
    else    if((send_done == 1'b1) && (run == 1'b1) && (pause == 1'b1))
    //else    if(pause == 1'b1)                                                                                                                                                                                                                
        dac_data    <=  16'd0;                  //paused: silence, pointer and mute counter hold
    else    if((send_done == 1'b1) && (run == 1'b1))
        begin
            if(audio_lrc == 1'b1)
                //right slot is being sent -> prepare the left sample
                dac_data    <=  (started == 1'b1) ? gain(ch0_data) : 16'd0;
            else
                begin
                    //left slot is being sent -> prepare the right sample, advance
                    dac_data    <=  (started == 1'b1) ? gain(ch1_data) : 16'd0;
                    rd_addr     <=  rd_addr + 10'd1;
                    if(started == 1'b0)
                        begin
                            mute_cnt    <=  mute_cnt + 13'd1;
                            if(mute_cnt == MUTE_FRAMES - 1)
                                started <=  1'b1;
                        end
                end
        end

endmodule
