`timescale 1ns/1ps
// ---------------------------------------------------------------------------
// Codec-input equivalence check:  golden (sd_play_ctrl + FIFO) versus the new
// pcm_out_ctrl, both driving an UNMODIFIED wm8978_ctrl/audio_send from the same
// behavioural WM8978 master (BCLK = MCLK, LRC = BCLK / 256, I2S timing).
//
// A behavioural codec receiver decodes both DACDAT streams exactly like the
// WM8978 does (MSB at the 2nd rising BCLK edge after an LRC transition, 16 bits,
// LRC low = left) and checks
//   * golden path : consecutive samples S[j], one per LRC slot
//   * new path    : left = ch0[a], right = ch1[a], a incrementing, one per frame
//   * both paths  : the DACDAT bit position relative to the LRC edge is identical
//                   and dac_data never changes close to an LRC edge.
// The new path is run with GAIN_SHIFT = 0 so the samples must come through bit-exact.
// ---------------------------------------------------------------------------
module tb_codec_input;

localparam real BCLK_HALF = 44.2855;      // 11.2903 MHz
localparam integer NSLOTS = 5200;         // number of LRC slots to observe (>= 1024 frames for the new path)

reg  sys_clk = 0, bclk = 0, lrc = 0, rst_n = 0;
always #10 sys_clk = ~sys_clk;
always #(BCLK_HALF) bclk = ~bclk;

// behavioural WM8978 master: LRC changes on the falling BCLK edge, 128 BCLK per slot
integer bcnt = 0;
always @(negedge bclk) begin
    bcnt <= bcnt + 1;
    if(bcnt % 128 == 127) lrc <= ~lrc;
end
initial begin #1000; rst_n = 1; end

// ----------------------------------------------------------------- stimulus
function [15:0] S(input integer j);
    reg [31:0] x;
    begin x = (j + 1) * 32'h9E3779B1; x = x ^ (x >> 15); x = x * 32'h2C1B3C6D; S = x[31:16] ^ x[15:0]; end
endfunction

// ------------------------------------------------------------ golden path
wire [15:0] fifo_q;  wire [10:0] fifo_cnt;
wire        send_done_g;  wire [15:0] dac_g;  wire dacdat_g;  wire cfg_done_g;  wire scl_g;  tri1 sda_g;
wire        rd_en_g;  wire [31:0] rd_addr_g;

fifo_data golden_fifo (.data(16'd0), .rdclk(bclk), .rdreq(send_done_g), .wrclk(sys_clk), .wrreq(1'b0), .q(fifo_q), .wrusedw(fifo_cnt));
sd_play_ctrl #(.INIT_ADDR(0), .AUDIO_SECTOR(100)) golden_ctrl
(
    .sd_clk(sys_clk), .audio_bclk(bclk), .sys_rst_n(rst_n), .sd_init_end(1'b0), .rd_busy(1'b0),
    .send_done(send_done_g), .fifo_data(fifo_q), .fifo_data_cnt(fifo_cnt), .cfg_done(cfg_done_g),
    .rd_en(rd_en_g), .rd_addr(rd_addr_g), .dac_data(dac_g)
);
wm8978_ctrl codec_g
(
    .sys_clk(sys_clk), .sys_rst_n(rst_n), .audio_bclk(bclk), .audio_lrc(lrc), .audio_adcdat(1'b0),
    .dac_data(dac_g), .scl(scl_g), .audio_dacdat(dacdat_g), .rcv_done(), .send_done(send_done_g),
    .adc_data(), .cfg_done(cfg_done_g), .sda(sda_g)
);

// --------------------------------------------------------------- new path
reg  [15:0] ch0_mem [0:1023];
reg  [15:0] ch1_mem [0:1023];
reg  [15:0] ch0_q, ch1_q;
wire [9:0]  rd_addr_n;
wire        send_done_n;  wire [15:0] dac_n;  wire dacdat_n;  wire cfg_done_n;  wire scl_n;  tri1 sda_n;

always @(posedge bclk) begin ch0_q <= ch0_mem[rd_addr_n]; ch1_q <= ch1_mem[rd_addr_n]; end   // registered read, 1 BCLK latency

pcm_out_ctrl #(.GAIN_SHIFT(0), .MUTE_FRAMES(1536)) new_ctrl
(
    .audio_bclk(bclk), .sys_rst_n(rst_n), .run(1'b1), .send_done(send_done_n), .audio_lrc(lrc),
    .ch0_data(ch0_q), .ch1_data(ch1_q), .rd_addr(rd_addr_n), .dac_data(dac_n)
);
wm8978_ctrl codec_n
(
    .sys_clk(sys_clk), .sys_rst_n(rst_n), .audio_bclk(bclk), .audio_lrc(lrc), .audio_adcdat(1'b0),
    .dac_data(dac_n), .scl(scl_n), .audio_dacdat(dacdat_n), .rcv_done(), .send_done(send_done_n),
    .adc_data(), .cfg_done(cfg_done_n), .sda(sda_n)
);

// ------------------------------------------------------- codec receivers
// one receiver per DACDAT; records word / side / slot number / bit alignment
reg  [15:0] words_g [0:NSLOTS-1];  reg side_g [0:NSLOTS-1];  integer n_g = 0;
reg  [15:0] words_n [0:NSLOTS-1];  reg side_n [0:NSLOTS-1];  integer n_n = 0;
integer     lrc_edges = 0;

reg lrc_prev = 0;
integer rcnt = 0;          // rising edges since the LRC transition (1 = first)
reg [15:0] sh_g, sh_n;
reg        cur_side;
integer    dchg_g = 0, dchg_n = 0;       // BCLK count of last dac_data change
integer    bclk_count = 0;
integer    min_dist_g = 1000, min_dist_n = 1000;   // min distance between a dac_data change and the next LRC edge
integer    bad_pos = 0;

always @(posedge bclk) begin
    bclk_count <= bclk_count + 1;
    if(lrc !== lrc_prev) begin
        lrc_prev <= lrc; rcnt <= 1; lrc_edges <= lrc_edges + 1; cur_side <= lrc;   // side: lrc=0 -> left
        // distance of the last dac_data change before this edge
        if(dchg_g != 0 && (bclk_count - dchg_g) < min_dist_g) min_dist_g = bclk_count - dchg_g;
        if(dchg_n != 0 && (bclk_count - dchg_n) < min_dist_n) min_dist_n = bclk_count - dchg_n;
    end else rcnt <= rcnt + 1;
    // sample serial data: MSB at the 2nd rising edge, LSB at the 17th
    if(rcnt >= 1 && rcnt <= 16) begin   // rcnt is the number of edges already seen after the transition
        sh_g <= {sh_g[14:0], dacdat_g};
        sh_n <= {sh_n[14:0], dacdat_n};
    end
    if(rcnt == 17) begin
        if(n_g < NSLOTS) begin words_g[n_g] <= sh_g; side_g[n_g] <= cur_side; n_g <= n_g + 1; end
        if(n_n < NSLOTS) begin words_n[n_n] <= sh_n; side_n[n_n] <= cur_side; n_n <= n_n + 1; end
    end
end
always @(dac_g) dchg_g = bclk_count + 1;
always @(dac_n) dchg_n = bclk_count + 1;

// ------------------------------------------------------------------- check
integer i, j, k, errors, a;
reg [15:0] exp, sw;
initial begin : main
    errors = 0;
    for(i = 0; i < 8192; i = i + 1) begin sw = S(i); golden_fifo.mem[i] = {sw[7:0], sw[15:8]}; end   // sample S, little-endian bytes, as read from a WAV on the SD card
    for(i = 0; i < 1024; i = i + 1) begin ch0_mem[i] = S(2*i); ch1_mem[i] = S(2*i+1); end
    wait(n_g >= NSLOTS && n_n >= NSLOTS);
    $display("S0..3 = %h %h %h %h ; new slots 3072..3075 = %h %h %h %h", S(0), S(1), S(2), S(3), words_n[3072], words_n[3073], words_n[3074], words_n[3075]);
    #1000;

    // --- golden: find where sample 0 lands, then expect consecutive samples, one per slot
    k = -1;
    for(i = 0; i < 8 && k < 0; i = i + 1) if(words_g[i] == S(0) && S(0) != 0) k = i;
    if(k < 0) begin $display("TB-FAIL golden path never delivered sample 0"); errors = errors + 1; end
    else begin
        $display("golden: sample 0 is sent in slot %0d on the %0s channel", k, side_g[k] ? "RIGHT" : "LEFT");
        for(i = k; i < NSLOTS; i = i + 1) if(words_g[i] !== S(i - k)) begin errors = errors + 1; if(errors < 10) $display("TB-FAIL golden slot %0d got %h exp %h", i, words_g[i], S(i - k)); end
    end

    // --- new path: muted (0) until the pointer wrapped, then left = ch0[a], right = ch1[a]
    k = -1;
    for(i = 0; i < NSLOTS && k < 0; i = i + 1) if(words_n[i] != 0) k = i;
    if(k < 0) begin $display("TB-FAIL new path never delivered data"); errors = errors + 1; end
    else begin
        $display("new   : first non-zero sample in slot %0d on the %0s channel", k, side_n[k] ? "RIGHT" : "LEFT");
        if(k < 3072 || k > 3076) begin errors = errors + 1; $display("TB-FAIL unexpected mute length %0d slots", k); end
        if(side_n[k] != 0) begin errors = errors + 1; $display("TB-FAIL new path first sample is not LEFT"); end
        if(words_n[k] !== S(0)) begin errors = errors + 1; $display("TB-FAIL new path first sample %h exp %h", words_n[k], S(0)); end
        for(i = k; i < NSLOTS; i = i + 1) if(words_n[i] !== S((i - k) % 2048)) begin errors = errors + 1; if(errors < 10) $display("TB-FAIL new slot %0d got %h exp %h side %0d", i, words_n[i], S((i - k) % 2048), side_n[i]); end   // RAM holds 1024 frames and wraps
        for(i = 0; i < k; i = i + 1) if(words_n[i] !== 16'd0) begin errors = errors + 1; $display("TB-FAIL new path not muted in slot %0d", i); end
        $display("new   : %0d slots compared, mute period = %0d slots (3072 expected = MUTE_FRAMES 1536 frames)", NSLOTS - k, k);
    end
    // --- L/R alternate in both
    for(i = 1; i < NSLOTS; i = i + 1) if(side_g[i] == side_g[i-1] || side_n[i] == side_n[i-1]) begin errors = errors + 1; $display("TB-FAIL slot sides do not alternate at %0d", i); i = NSLOTS; end
    // --- timing of dac_data updates relative to the LRC edge
    $display("dac_data last changes %0d BCLK (golden) / %0d BCLK (new) before the next LRC edge (min over run)", min_dist_g, min_dist_n);
    if(min_dist_g < 4 || min_dist_n < 4) begin errors = errors + 1; $display("TB-FAIL dac_data changes too close to the LRC edge"); end
    if(min_dist_n != min_dist_g) begin $display("NOTE: update distance differs between golden and new path (%0d vs %0d)", min_dist_g, min_dist_n); end

    if(errors == 0) $display("TB-PASS codec input equivalent: same audio_send serialisation, bit-exact samples, dac_data reloaded inside the slot, well before the next LRC edge");
    else            $display("TB-FAIL %0d errors", errors);
    $finish;
end

initial begin #(NSLOTS * 128 * 2 * BCLK_HALF * 1.5 + 1000000); $display("TB-FAIL timeout"); $finish; end

endmodule
