`timescale 1ns/1ps
// Behavioural model of the golden dcfifo "fifo_data" (LPM_SHOWAHEAD = OFF):
// on a read request the word at the read pointer appears on q one rdclk later.
// The testbench pre-loads mem[] hierarchically.
module fifo_data
(
    input  wire [15:0] data,
    input  wire        rdclk,
    input  wire        rdreq,
    input  wire        wrclk,
    input  wire        wrreq,
    output reg  [15:0] q,
    output wire [10:0] wrusedw
);
    reg [15:0] mem [0:8191];
    integer    rdptr;
    initial begin rdptr = 0; q = 16'd0; end
    always @(posedge rdclk) if(rdreq) begin q <= mem[rdptr]; rdptr <= rdptr + 1; end
    assign wrusedw = 11'd1024;     // always "full enough": sd_play_ctrl keeps its read enable low
endmodule
