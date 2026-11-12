`timescale  1ns/1ns
////////////////////////////////////////////////////////////////////////
// Module Name   : pulse_sync
// Description   : Transfers a one-clock pulse from the src_clk domain to
//                 the dst_clk domain (toggle + 3-flop synchroniser +
//                 edge detect).  Pulses must be further apart than about
//                 4 dst_clk periods (true for push-button pulses).
////////////////////////////////////////////////////////////////////////

module  pulse_sync
(
    input   wire    src_clk     ,   //source clock
    input   wire    src_rst_n   ,   //source reset, active low
    input   wire    src_pulse   ,   //one-clock pulse in the source domain
    input   wire    dst_clk     ,   //destination clock
    input   wire    dst_rst_n   ,   //destination reset, active low

    output  wire    dst_pulse       //one-clock pulse in the destination domain
);

reg             toggle  ;   //source domain: flips on every pulse
reg     [2:0]   sync    ;   //destination domain synchroniser + edge detect register

always@(posedge src_clk or negedge src_rst_n)
    if(src_rst_n == 1'b0)
        toggle  <=  1'b0;
    else    if(src_pulse == 1'b1)
        toggle  <=  ~toggle;

always@(posedge dst_clk or negedge dst_rst_n)
    if(dst_rst_n == 1'b0)
        sync    <=  3'b000;
    else
        sync    <=  {sync[1:0], toggle};

assign  dst_pulse = sync[2] ^ sync[1];

endmodule
