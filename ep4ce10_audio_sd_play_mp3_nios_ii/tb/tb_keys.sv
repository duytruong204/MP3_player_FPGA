`timescale 1ns/1ps
// Testbench for the push buttons of audio_sd_play_mp3 (song change).
//
//   KEY1 (key_next)     next song          KEY2 (key_prev)      previous song
//
// Three short songs (tb/make_songs.py, tb/out/song0..2.mp3) are stored on a
// behavioural SDSC card at sectors 100 / 300 / 500 (16 / 6 / 4 sectors).
// Checks:
//   * KEY1 / KEY2 with contact bounce: next / previous song starts at the
//     start sector of that song (consecutive sector reads), wrap-around in
//     both directions, a restart from the middle of a song.
//   * End of file: the player advances to the next song (and wraps).
//   * Two quick KEY1 presses move two songs.
//   * Song 0 played at boot and again after the wrap-around gives the same
//     PCM (clean restart).
// Run from quartus_prj/ (see run_vcs.sh).

module tb_keys;

localparam [31:0] A0 = 100, A1 = 300, A2 = 500;      // start sectors of the songs
localparam        N0 = 16,  N1 = 6,   N2 = 4;        // sectors of the songs
localparam        SLOT = 16384;                      // bytes reserved per song in smem

reg sys_clk = 0, sys_rst_n = 0;
always #10 sys_clk = ~sys_clk;                       // 50 MHz

wire audio_mclk, audio_dacdat, scl, sd_clk, sd_cs_n, sd_mosi;
wire audio_bclk = audio_mclk;                        // WM8978 BCLKDIV = 1
reg  audio_lrc = 0;
reg  sd_miso = 1;
tri1 sda;
reg  [1:0] key_r = 2'b11;                            // [0]=KEY1 next [1]=KEY2 prev

audio_sd_play_mp3
#(
    .NUM_SONGS      (3),
    .SONG_ADDRS     ({160'd0, A2, A1, A0}),
    .SONG_SECTORS   ({90'd0, 18'(N2), 18'(N1), 18'(N0)}),
    .KEY_DEBOUNCE   (32'd1000)                       // 20 us
) dut (
    .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
    .key_next(key_r[0]), .key_prev(key_r[1]),
    .audio_bclk(audio_bclk), .audio_lrc(audio_lrc),
    .audio_mclk(audio_mclk), .audio_dacdat(audio_dacdat),
    .scl(scl), .sda(sda),
    .sd_miso(sd_miso), .sd_clk(sd_clk), .sd_cs_n(sd_cs_n), .sd_mosi(sd_mosi));

integer errors = 0;
task err(input [8*100-1:0] msg);
    begin errors = errors + 1; $display("%0t TB-ERR %0s", $time, msg); end
endtask

// ------------------------------------------------------------ WM8978 I2C slave
reg [3:0] ibit = 0;
reg [7:0] ish = 0;
integer   ibyte = 0;
reg       in_xfer = 0;
reg       ack_drv = 0;
reg [7:0] ib0, ib1, ib2;
integer   i2c_regs = 0;
integer   ilog_reg [0:4095];
reg [8:0] ilog_dat [0:4095];
reg [8:0] last_dat [0:127];
assign sda = ack_drv ? 1'b0 : 1'bz;

always @(negedge sda) if(scl === 1'b1 && !ack_drv) begin in_xfer <= 1; ibit <= 0; ibyte <= 0; end   // START
always @(posedge sda) if(scl === 1'b1 && !ack_drv) begin                                           // STOP
    if(in_xfer && ibyte == 3) begin
        ilog_reg[i2c_regs] = ib1[7:1];
        ilog_dat[i2c_regs] = {ib1[0], ib2};
        last_dat[ib1[7:1]] = {ib1[0], ib2};
        i2c_regs = i2c_regs + 1;
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
    audio_lrc <= (bcnt % 256) >= 128;                // low = left
end

integer k = 0;
reg [15:0] sh = 0;
reg [15:0] left_word = 0;
integer frames = 0;
reg have_left = 0;
reg lrc_seen_edge = 0;
integer run_fidx = 0;                                // frames since the last audio pointer reset
integer capslot = -1;                                // PCM capture slot (-1 = off)
reg signed [15:0] pcmL [0:2*16000-1];
reg signed [15:0] pcmR [0:2*16000-1];
always @(posedge dut.pcm_rstn_bclk[1]) run_fidx = 0;
always @(posedge audio_bclk) begin
    if(audio_lrc !== lrc_prev) begin k = 1; lrc_prev = audio_lrc; lrc_seen_edge = 1; end
    else k = k + 1;
    if(lrc_seen_edge) begin
        if(k >= 2 && k <= 17) sh = {sh[14:0], audio_dacdat};
        if(k == 17) begin
            if(audio_lrc == 1'b0) begin left_word = sh; have_left = 1; end
            else if(have_left) begin
                if(capslot >= 0 && run_fidx < 16000) begin
                    pcmL[capslot*16000 + run_fidx] = left_word;
                    pcmR[capslot*16000 + run_fidx] = sh;
                end
                run_fidx = run_fidx + 1;
                frames = frames + 1; have_left = 0;
            end
        end
    end
end

// ------------------------------------------------------------------ SD card
reg [7:0] smem [0:3*SLOT-1];
reg [8*256-1:0] fname;
integer   sfd, sn;
integer bitcnt = 0;
reg [47:0] cmd_sr;
localparam TXN = 8*700;
reg [TXN-1:0] tx;
integer tx_len = 0, tx_ptr = 0;
integer acmd41_polls = 0;
integer n_cmd17 = 0;

// run bookkeeping: a "run" starts at every decoder restart (mp3_rst_n falling)
integer run_id = 0;
integer run_first [0:63];
integer run_next = 0;
integer seq_err = 0, range_err = 0;
integer j;
initial for(j = 0; j < 64; j = j + 1) run_first[j] = -1;
always @(negedge dut.mp3_rst_n) begin
    run_id = run_id + 1;
    $display("%0t restart #%0d (song_req=%0d, song_play=%0d)", $time, run_id,
             dut.mp3_feeder_inst.song_req, dut.mp3_feeder_inst.song_play);
end

task push_byte(input [7:0] b);
    integer kk;
    begin
        for(kk=7;kk>=0;kk=kk-1) begin tx[TXN-1-tx_len] = b[kk]; tx_len = tx_len+1; end
    end
endtask

task respond(input [5:0] idx, input [31:0] arg);
    integer i, off;
    reg [31:0] sector;
    reg [7:0] d;
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
                if(run_first[run_id] < 0) run_first[run_id] = sector;
                else if(sector != run_next) begin seq_err = seq_err + 1; $display("%0t TB-ERR sector %0d, expected %0d", $time, sector, run_next); end
                run_next = sector + 1;
                if(!((sector >= A0 && sector < A0 + N0) || (sector >= A1 && sector < A1 + N1) || (sector >= A2 && sector < A2 + N2))) begin
                    range_err = range_err + 1; $display("%0t TB-ERR read outside the songs: sector %0d", $time, sector);
                end
                push_byte(8'h00); push_byte(8'hFF); push_byte(8'hFF); push_byte(8'hFF); push_byte(8'hFE);
                for(i=0;i<512;i=i+1) begin
                    d = 8'h00;
                    if(sector >= A0 && sector < A0 + N0) d = smem[0*SLOT + (sector - A0)*512 + i];
                    if(sector >= A1 && sector < A1 + N1) d = smem[1*SLOT + (sector - A1)*512 + i];
                    if(sector >= A2 && sector < A2 + N2) d = smem[2*SLOT + (sector - A2)*512 + i];
                    push_byte(d);
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

// ------------------------------------------------------------ key helpers
// KEY press with contact bounce on press and release (bounces are much
// shorter than the 20 us debounce time).
task key_down(input integer idx);
    integer b;
    begin
        for(b = 0; b < 3; b = b + 1) begin key_r[idx] = 0; #1000; key_r[idx] = 1; #1000; end
        key_r[idx] = 0;
    end
endtask
task key_up(input integer idx);
    integer b;
    begin
        for(b = 0; b < 3; b = b + 1) begin key_r[idx] = 1; #1000; key_r[idx] = 0; #1000; end
        key_r[idx] = 1;
        #100000;
    end
endtask
task key_hold(input integer idx, input integer hold_ns);
    begin key_down(idx); #(hold_ns); key_up(idx); end
endtask
task key_tap(input integer idx);
    begin key_hold(idx, 200000); end
endtask

// wait until restart number r has happened (timeout in ms)
task wait_run(input integer r, input integer ms);
    begin
        fork
            begin wait(run_id >= r); end
            begin #(ms * 1000000); end
        join_any
        disable fork;
        if(run_id < r) err("timeout waiting for a restart");
    end
endtask
// wait until the first sector of run r was read, then check it
task wait_first(input integer r, input integer ms, input [31:0] expect_sec);
    begin
        fork
            begin wait(run_first[r] >= 0); end
            begin #(ms * 1000000); end
        join_any
        disable fork;
        if(run_first[r] < 0) err("timeout waiting for the first sector read of a run");
        else if(run_first[r] != expect_sec) begin
            errors = errors + 1;
            $display("%0t TB-ERR run %0d starts at sector %0d, expected %0d", $time, r, run_first[r], expect_sec);
        end else $display("%0t OK   run %0d starts at sector %0d", $time, r, run_first[r]);
    end
endtask

// compare the PCM captured in slot 0 (boot) with slot 1 (after the wrap-around)
task compare_slots;
    integer f0, f1, n, bad, nz;
    begin
        f0 = 0; while(f0 < 12000 && pcmL[f0] === 16'sd0 && pcmR[f0] === 16'sd0) f0 = f0 + 1;
        f1 = 16000; while(f1 < 28000 && pcmL[f1] === 16'sd0 && pcmR[f1] === 16'sd0) f1 = f1 + 1;
        f1 = f1 - 16000;
        bad = 0; nz = 0;
        for(n = 0; n < 6000; n = n + 1) begin
            if(pcmL[f0+n] !== pcmL[16000+f1+n] || pcmR[f0+n] !== pcmR[16000+f1+n]) bad = bad + 1;
            if(pcmL[f0+n] !== 16'sd0) nz = nz + 1;
        end
        $display("PCM compare: first audio frame boot=%0d / after wrap=%0d, 6000 frames, %0d differ, %0d non-zero", f0, f1, bad, nz);
        if(bad != 0) err("PCM of song 0 differs between the boot run and the run after wrap-around");
        if(nz < 3000) err("PCM compare window is mostly silent");
    end
endtask

// ------------------------------------------------------------------ main
initial begin : main
    integer n, w0;
    // load the songs
    for(n = 0; n < 3; n = n + 1) begin
        $sformat(fname, "../tb/out/song%0d.mp3", n);
        sfd = $fopen(fname, "rb");
        if(sfd == 0) begin $display("TB-FAIL cannot open %0s (run tb/make_songs.py)", fname); $finish; end
        sn = $fread(smem, sfd, n*SLOT);
        $fclose(sfd);
    end
    for(n = 0; n < 2*16000; n = n + 1) begin pcmL[n] = 16'sd0; pcmR[n] = 16'sd0; end
    capslot = 0;
    #200 sys_rst_n = 1;

    wait(dut.init_end);
    wait(dut.cfg_done);
    $display("%0t WM8978 configured (%0d I2C register writes)", $time, i2c_regs);
    #4000000;
    if(i2c_regs != 15) begin errors = errors + 1; $display("TB-ERR expected 15 I2C writes, got %0d", i2c_regs); end

    // ---- song 0 at boot: wait for the capture window
    wait(run_fidx >= 15000);
    capslot = -1;
    if(run_id != 0) err("unexpected decoder restart during the first song");
    if(run_first[0] != A0) err("boot song does not start at the first sector of song 0");

    // ---- KEY1: next (mid-song), KEY1, KEY1 (wrap)
    key_tap(0);   wait_run(1, 50);  wait_first(1, 100, A1);
    key_tap(0);   wait_run(2, 50);  wait_first(2, 100, A2);
    capslot = 1;                          // run_fidx restarts at 0 with the decoder restart
    key_tap(0);   wait_run(3, 50);  wait_first(3, 100, A0);
    wait(run_fidx >= 15000);
    capslot = -1;
    compare_slots;

    // ---- KEY2: previous (wrap 0 -> 2), then 2 -> 1
    key_tap(1);   wait_run(4, 50);  wait_first(4, 100, A2);
    key_tap(1);   wait_run(5, 50);  wait_first(5, 100, A1);

    // ---- end of file advances: song 1 -> 2 -> 0 (wrap)
    wait_run(6, 800);  wait_first(6, 100, A2);
    wait_run(7, 800);  wait_first(7, 100, A0);

    // ---- two quick KEY1 presses: song 0 -> 2
    key_tap(0);
    key_tap(0);
    #30000000;
    if(dut.mp3_feeder_inst.song_play != 3'd2) err("two quick KEY1 presses did not end at song 2");
    if(run_id < 8) err("no restart after the quick KEY1 presses");
    if(run_first[run_id] != A2) err("last run does not start at song 2");
    else $display("%0t OK   after two KEY1 presses (%0d restarts) song 2 plays", $time, run_id - 7);

    if(seq_err != 0) err("sector reads were not consecutive within a run");
    if(range_err != 0) err("sector read outside the song table");
    $display("restarts: %0d, SD CMD17: %0d, I2C writes: %0d", run_id, n_cmd17, i2c_regs);
    if(errors == 0) $display("TB-PASS tb_keys"); else $display("TB-FAIL tb_keys (%0d errors)", errors);
    $finish;
end

initial begin
    #6000000000;
    $display("TB-FAIL timeout");
    $finish;
end

endmodule
