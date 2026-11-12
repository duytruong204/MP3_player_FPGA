`timescale 1ns/1ps
// Full-system testbench of audio_sd_play_mp3:
//   behavioural SDSC card (SPI mode) holding clean.mp3 at sector INIT_ADDR,
//   behavioural WM8978 (I2C slave that ACKs and logs register writes,
//   I2S master: BCLK = MCLK, LRC = BCLK/256, captures the DAC data bit stream).
//
// Plusargs:   +FRAMES=<n>   stereo frames to capture (default 44100)
//             +OUT=<file>   captured PCM, "left right" per line (signed decimal)
//             +MP3=<file>   MP3 file that is stored on the card
//             +I2C=<file>   log of the I2C register writes
//             +NOEOF        do not run the end-of-file check
// Run from quartus_prj/ (the decoder RAM init files are found relative to it).

module tb_audio_sd_play_mp3;

parameter INIT_ADDR = 8832;
parameter MP3_SECTOR_P = 8086;

reg sys_clk = 0, sys_rst_n = 0;
always #10 sys_clk = ~sys_clk;                  // 50 MHz

wire audio_mclk, audio_dacdat, scl, sd_clk, sd_cs_n, sd_mosi;
wire audio_bclk = audio_mclk;                   // WM8978 BCLKDIV = 1
reg  audio_lrc = 0;
reg  sd_miso = 1;
tri1 sda;

audio_sd_play_mp3 #(.NUM_SONGS(1), .SONG_ADDRS({224'd0, 32'(INIT_ADDR)}), .SONG_SECTORS({126'd0, 18'(MP3_SECTOR_P)})) dut (
    .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
    .key_next(1'b1), .key_prev(1'b1),
    .audio_bclk(audio_bclk), .audio_lrc(audio_lrc),
    .audio_mclk(audio_mclk), .audio_dacdat(audio_dacdat),
    .scl(scl), .sda(sda),
    .sd_miso(sd_miso), .sd_clk(sd_clk), .sd_cs_n(sd_cs_n), .sd_mosi(sd_mosi));

// ------------------------------------------------------------ WM8978 I2C slave
reg [3:0] ibit = 0;
reg [7:0] ish = 0;
integer   ibyte = 0;
reg       in_xfer = 0;
reg       ack_drv = 0;
reg [7:0] ib0, ib1, ib2;
integer   i2c_fd;
integer   i2c_regs = 0;
assign sda = ack_drv ? 1'b0 : 1'bz;

always @(negedge sda) if(scl === 1'b1 && !ack_drv) begin in_xfer <= 1; ibit <= 0; ibyte <= 0; end   // START
always @(posedge sda) if(scl === 1'b1 && !ack_drv) begin                                           // STOP
    if(in_xfer && ibyte == 3) begin
        i2c_regs = i2c_regs + 1;
        if(i2c_fd) $fdisplay(i2c_fd, "dev=%02h reg=%0d data=%03h", ib0, ib1[7:1], {ib1[0], ib2});
    end
    in_xfer <= 0;
end
always @(posedge scl) if(in_xfer) begin
    if(ibit < 8) begin ish = {ish[6:0], sda}; ibit <= ibit + 1; end
    else begin
        case(ibyte) 0: ib0 = ish; 1: ib1 = ish; 2: ib2 = ish; endcase
        ibyte <= ibyte + 1; ibit <= 0;
    end
end
always @(negedge scl) if(in_xfer) begin
    if(ibit == 8) ack_drv <= 1'b1; else ack_drv <= 1'b0;
end

// ---------------------------------------------- WM8978 I2S master (LRC) + capture
integer bcnt = 0;
reg     lrc_prev = 0;
always @(negedge audio_bclk) begin
    bcnt <= bcnt + 1;
    audio_lrc <= (bcnt % 256) >= 128;           // low = left
end

integer k = 0;                                   // rising BCLK edges since the LRC transition
reg [15:0] sh = 0;
reg [15:0] left_word = 0;
integer frames = 0, max_frames, pcm_fd;
reg have_left = 0;
reg lrc_seen_edge = 0;
always @(posedge audio_bclk) begin
    if(audio_lrc !== lrc_prev) begin k = 1; lrc_prev = audio_lrc; lrc_seen_edge = 1; end
    else k = k + 1;
    if(lrc_seen_edge) begin
        if(k >= 2 && k <= 17) sh = {sh[14:0], audio_dacdat};
        if(k == 17) begin
            if(audio_lrc == 1'b0) begin left_word = sh; have_left = 1; end
            else if(have_left) begin
                $fdisplay(pcm_fd, "%0d %0d", $signed(left_word), $signed(sh));
                frames = frames + 1; have_left = 0;
            end
        end
    end
end

// ------------------------------------------------------------------ SD card
localparam MP3_MAX = 5000000;
reg [7:0] mp3 [0:MP3_MAX-1];
integer   mp3_size = 0;
reg [8*256-1:0] mp3_name;
integer   mp3_fd;

integer bitcnt = 0;
reg [47:0] cmd_sr;
localparam TXN = 8*700;
reg [TXN-1:0] tx;
integer tx_len = 0, tx_ptr = 0;
integer acmd41_polls = 0;
integer n_cmd17 = 0;
integer first_sector_seen = -1;

task push_byte(input [7:0] b);
    integer kk;
    begin
        for(kk=7;kk>=0;kk=kk-1) begin tx[TXN-1-tx_len] = b[kk]; tx_len = tx_len+1; end
    end
endtask

task respond(input [5:0] idx, input [31:0] arg);
    integer i, off;
    reg [31:0] sector;
    begin
        tx = {TXN{1'b1}}; tx_len = 0; tx_ptr = 0;
        push_byte(8'hFF); push_byte(8'hFF);
        case(idx)
        0:  push_byte(8'h01);
        8:  begin push_byte(8'h01); push_byte(8'h00); push_byte(8'h00); push_byte(8'h01); push_byte(8'hAA); end
        55: push_byte(8'h01);
        41: begin acmd41_polls = acmd41_polls + 1; push_byte(acmd41_polls >= 3 ? 8'h00 : 8'h01); end
        17: begin
                n_cmd17 = n_cmd17 + 1;
                sector = arg >> 9;                    // SDSC: byte address
                if(first_sector_seen < 0) first_sector_seen = sector;
                push_byte(8'h00); push_byte(8'hFF); push_byte(8'hFF); push_byte(8'hFF); push_byte(8'hFE);
                for(i=0;i<512;i=i+1) begin
                    off = (sector - INIT_ADDR) * 512 + i;
                    if(sector >= INIT_ADDR && off < mp3_size) push_byte(mp3[off]);
                    else push_byte(8'h00);
                end
                push_byte(8'h00); push_byte(8'h00);
            end
        default: push_byte(8'h04);
        endcase
    end
endtask

always @(posedge sd_clk) begin
    if(sd_cs_n) bitcnt = 0;
    else if(bitcnt == 0 && sd_mosi == 1'b1) begin end
    else begin
        cmd_sr = {cmd_sr[46:0], sd_mosi};
        bitcnt = bitcnt + 1;
        if(bitcnt == 48) begin
            bitcnt = 0;
            respond(cmd_sr[45:40], cmd_sr[39:8]);
        end
    end
end
always @(negedge sd_clk) begin
    if(sd_cs_n) begin sd_miso <= 1'b1; tx_len = 0; tx_ptr = 0; end
    else if(tx_ptr < tx_len) begin sd_miso <= tx[TXN-1-tx_ptr]; tx_ptr = tx_ptr + 1; end
    else sd_miso <= 1'b1;
end

// ------------------------------------------------------- decoder monitors
// The decoder is paced by the audio pointer: one granule (576 samples) every
// 576 / 44101 Hz = 13.06 ms.  A longer distance between MAC starts = underrun.
integer eof_seen = 0, eof_at_mac = 0;
realtime t_mac_prev = 0, t_mac_start_first = 0;
integer  n_mac = 0, n_underrun = 0, n_hreq = 0;
realtime gap;
always @(posedge dut.mp3_top_inst.CH0_MAC_start) begin
    if(t_mac_prev != 0) begin
        gap = $realtime - t_mac_prev;
        if(gap > 14000000.0) begin
            if(eof_seen != eof_at_mac) $display("%0t INFO end-of-file restart, granule gap %0.3f ms", $time, gap/1e6);
            else begin
                n_underrun = n_underrun + 1;
                $display("%0t WARN granule gap %0.3f ms (underrun)", $time, gap/1e6);
            end
        end
    end
    else t_mac_start_first = $realtime;
    t_mac_prev = $realtime;
    eof_at_mac = eof_seen;
    n_mac = n_mac + 1;
end
always @(posedge dut.mp3_top_inst.NIOS_WRITE_DATA_REQUEST_O) n_hreq = n_hreq + 1;

// ------------------------------------------------------------------ main
integer errors = 0;
always @(negedge dut.mp3_rst_n) eof_seen = eof_seen + 1;

initial begin : main
    reg [8*256-1:0] f_out, f_mp3, f_i2c;
    integer n;
    if(!$value$plusargs("FRAMES=%d", max_frames)) max_frames = 44100;
    if(!$value$plusargs("OUT=%s", f_out)) f_out = "../tb/out/pcm_hw.txt";
    if(!$value$plusargs("MP3=%s", f_mp3)) f_mp3 = "../sd_image/clean.mp3";
    if(!$value$plusargs("I2C=%s", f_i2c)) f_i2c = "../tb/out/i2c_log.txt";
    pcm_fd = $fopen(f_out, "w");
    i2c_fd = $fopen(f_i2c, "w");
    mp3_fd = $fopen(f_mp3, "rb");
    if(mp3_fd == 0) begin $display("TB-FAIL cannot open %0s", f_mp3); $finish; end
    mp3_size = $fread(mp3, mp3_fd);
    $fclose(mp3_fd);
    $display("MP3 file loaded: %0d bytes, placed at sector %0d, MP3_SECTOR=%0d", mp3_size, INIT_ADDR, MP3_SECTOR_P);
    #200 sys_rst_n = 1;
    wait(dut.init_end);
    $display("%0t SD init done, ACMD41 polls = %0d", $time, acmd41_polls);
    wait(dut.cfg_done);
    $display("%0t WM8978 configured (%0d I2C register writes)", $time, i2c_regs);
    while(frames < max_frames) @(posedge audio_bclk);
    $display("%0t captured %0d frames, SD CMD17 count = %0d, first sector = %0d", $time, frames, n_cmd17, first_sector_seen);
    $display("granule starts: %0d, underruns: %0d, huffman half-requests: %0d", n_mac, n_underrun, n_hreq);
    $fclose(pcm_fd); $fclose(i2c_fd);
    if(i2c_regs != 15) begin errors = errors + 1; $display("TB-ERR expected 15 I2C writes, got %0d", i2c_regs); end
    if(n_underrun != 0) begin errors = errors + 1; $display("TB-ERR decoder underrun"); end
    if(n_mac < 2) begin errors = errors + 1; $display("TB-ERR decoder never started"); end
    if(errors == 0) $display("TB-PASS (compare PCM with tools/compare_pcm.py)"); else $display("TB-FAIL");
    $finish;
end

initial begin
    // watchdog: 3 s of simulated time
    #3000000000;
    $display("TB-FAIL timeout, frames=%0d", frames);
    $finish;
end


`ifdef DUMP_HUFF
// debug: dump Huffman-decoded + requantized sample stream (compared with the stand-alone decoder testbench)
integer hfd;
initial hfd = $fopen("../tb/out/huff_sys.txt", "w");
always @(posedge dut.mp3_top_inst.HUFF_CLOCK_I)
    if(dut.mp3_top_inst.HUFFMANDECODER.stage == 4 && dut.mp3_top_inst.HUFFMANDECODER.state == 3 && dut.mp3_top_inst.HUFFMANDECODER.step == 0)
        $fwrite(hfd, "%0d %0d\n", dut.mp3_top_inst.HUFFMANDECODER.decoded_sign ? -$signed({1'b0,dut.mp3_top_inst.HUFFMANDECODER.decoded_sample}) : $signed({1'b0,dut.mp3_top_inst.HUFFMANDECODER.decoded_sample}),
                                $signed(dut.mp3_top_inst.HUFFMANDECODER.req_result_signed));
`endif

endmodule
