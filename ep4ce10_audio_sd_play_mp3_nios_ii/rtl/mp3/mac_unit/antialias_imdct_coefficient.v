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



`timescale 1 ns / 100 ps

`include "defines.v"

module antialias_imdct_coefficient (
	clock,
	CH0_mem_en,
	CH0_address,
	CH0_data_out,
	CH1_mem_en,
	CH1_address,
	CH1_data_out
);

input clock;
input CH0_mem_en, CH1_mem_en;
input [`ADDRESS_WIDTH-1:0] CH0_address, CH1_address;
output [`DATA_WIDTH-1:0] CH0_data_out, CH1_data_out;

// Instantiate the RAM

	lpm_antialias_imdct_coefficient_RAM	antialias_imdct_coefficient_RAM (
	.data_a ( 16'h0000 ),
	.wren_a ( 1'b0 ),
	.address_a ( CH0_address ),
	.data_b ( 16'h0000 ),
	.address_b ( CH1_address ),
	.wren_b ( 1'b0 ),
	.clock_a ( clock ),
	.enable_a ( CH0_mem_en ),
	.clock_b ( clock ),
	.enable_b ( CH1_mem_en ),
	.q_a ( CH0_data_out ),
	.q_b ( CH1_data_out )
	);

endmodule
