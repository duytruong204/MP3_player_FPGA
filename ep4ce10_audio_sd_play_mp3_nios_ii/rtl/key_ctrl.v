`timescale  1ns/1ns
////////////////////////////////////////////////////////////////////////
// Module Name   : key_ctrl
// Description   : Debounced push button with a one-clock press pulse.
//
//   - key_n is active low (button pulls the pin to ground), asynchronous,
//     so it is passed through a 2-flop synchroniser first.
//   - The synchronised level must be stable for DEBOUNCE clocks before the
//     debounced state changes (20 ms at 50 MHz by default).
//   - key_pulse is high for exactly one clock when the debounced state
//     changes to "pressed".
////////////////////////////////////////////////////////////////////////

module  key_ctrl
#(
    parameter   DEBOUNCE        =   32'd1_000_000       //20 ms at 50 MHz
)
(
    input   wire    clk         ,   //50 MHz system clock
    input   wire    rst_n       ,   //reset, active low
    input   wire    key_n       ,   //button input, low = pressed

    output  reg     key_pulse       //one-clock pulse per press
);

reg             key_s0      ;   //synchroniser
reg             key_s1      ;
reg             pressed     ;   //debounced state, 1 = pressed
reg     [31:0]  deb_cnt     ;   //debounce counter

always@(posedge clk or negedge rst_n)
    if(rst_n == 1'b0)
        begin
            key_s0      <=  1'b1;
            key_s1      <=  1'b1;
        end
    else
        begin
            key_s0      <=  key_n;
            key_s1      <=  key_s0;
        end

always@(posedge clk or negedge rst_n)
    if(rst_n == 1'b0)
        begin
            pressed     <=  1'b0;
            deb_cnt     <=  32'd0;
            key_pulse   <=  1'b0;
        end
    else
        begin
            key_pulse   <=  1'b0;
            //key_s1 is active low (0 = pressed): "equal" means the input differs from the debounced state
            if(key_s1 == pressed)
                begin
                    if(deb_cnt == DEBOUNCE - 1)
                        begin
                            deb_cnt     <=  32'd0;
                            pressed     <=  ~pressed;
                            if(pressed == 1'b0)
                                key_pulse   <=  1'b1;   //new press
                        end
                    else
                        deb_cnt     <=  deb_cnt + 32'd1;
                end
            else
                deb_cnt     <=  32'd0;
        end

endmodule
