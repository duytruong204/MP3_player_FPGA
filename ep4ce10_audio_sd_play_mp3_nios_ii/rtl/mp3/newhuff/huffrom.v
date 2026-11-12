// 
//  MAC_MP3: A Low Energy Implementation of an Audio Decoder
//
//  Copyright (C) 2007 McMaster University
// 
//==============================================================================
// 
// This file is part of MAC_MP3
// 
// MAC_MP3 is distributed in the hope that it will be useful for further research,
// but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
// or FITNESS FOR A PARTICULAR PURPOSE. MAC_MP3 is free; you can redistribute it
// and/or modify it provided that proper reference is provided to the authors. See
// the documents included in the "doc" folder for further details.
//
//==============================================================================


`timescale 1ns / 100ps

module huffrom(clk,addressA,dataoutA,addressB,dataoutB);
  input clk;
  input [10:0] addressA;
  output [15:0] dataoutA;
  input [10:0] addressB;
  output [15:0] dataoutB;

  reg addrmuxA;
  reg addrmuxB;
  //wire addrmuxA;
  //wire addrmuxB;
  wire [15:0] memdataA [1:0];
  wire [15:0] memdataB [1:0];
  
  //assign addrmuxA = addressA[10];
  //assign addrmuxB = addressB[10];
  assign dataoutA = memdataA[addrmuxA];
  assign dataoutB = memdataB[addrmuxB];
  
  always @ (posedge clk)
  begin
    addrmuxA <= addressA[10];
    addrmuxB <= addressB[10];
  end
  
  lpm_huff_romblock0	huff_romblock0 (
	.data_a ( 16'h0000 ),
	.wren_a ( 1'b0 ),
	.address_a ( addressA[9:0] ),
	.data_b ( 16'h0000 ),
	.address_b ( addressB[9:0] ),
	.wren_b ( 1'b0 ),
	.clock ( clk ),
	.q_a ( memdataA[0] ),
	.q_b ( memdataB[0] )
	);

  lpm_huff_romblock1	huff_romblock1 (
	.data_a ( 16'h0000 ),
	.wren_a ( 1'b0 ),
	.address_a ( addressA[9:0] ),
	.data_b ( 16'h0000 ),
	.address_b ( addressB[9:0] ),
	.wren_b ( 1'b0 ),
	.clock ( clk ),
	.q_a ( memdataA[1] ),
	.q_b ( memdataB[1] )
	);
 
endmodule
