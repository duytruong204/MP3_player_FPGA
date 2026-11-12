`timescale 1ns/1ps
// Behavioural replacement of the altpll clk_gen IP (simulation only).
//   c0 = 11.2903 MHz (WM8978 MCLK)   c1 = 50 MHz   c2 = 50 MHz + 5 ns
//   c3 = 12.5 MHz (MP3 MAC)          c4 = 3.125 MHz (MP3 Huffman)
// c1/c3/c4 are edge-aligned (same relation as in the PLL).
module clk_gen
(
    input   wire    areset,
    input   wire    inclk0,
    output  wire    c0,
    output  wire    c1,
    output  wire    c2,
    output  wire    c3,
    output  wire    c4,
    output  reg     locked
);

reg c0_r = 1'b0, c1_r = 1'b0, c2_r = 1'b0, c3_r = 1'b0, c4_r = 1'b0;
reg pll_on = 1'b0;
reg [1:0] d3 = 2'd0;
reg [1:0] d4 = 2'd0;

initial begin
    locked = 1'b0;
    #1000 pll_on = 1'b1;
    #1000 locked = 1'b1;
end

// 50 MHz
always #10 if(pll_on) c1_r = ~c1_r;
// c2 = c1 delayed by 5 ns (90 degrees)
always @(c1_r) c2_r <= #5 c1_r;
// 12.5 MHz = c1 / 4, 3.125 MHz = c3 / 4 (aligned edges)
always @(posedge c1_r) begin
    if(d3 == 2'd1) begin c3_r <= ~c3_r; d3 <= 2'd0; end
    else d3 <= d3 + 2'd1;
end
always @(posedge c3_r) begin
    if(d4 == 2'd1) begin c4_r <= ~c4_r; d4 <= 2'd0; end   //half period = 2 MAC clocks = 160 ns
    else d4 <= d4 + 2'd1;
end
// 11.2903 MHz: period 88.5714 ns
always #44.2857 if(pll_on) c0_r = ~c0_r;

assign c0 = c0_r;
assign c1 = c1_r;
assign c2 = c2_r;
assign c3 = c3_r;
assign c4 = c4_r;

endmodule
