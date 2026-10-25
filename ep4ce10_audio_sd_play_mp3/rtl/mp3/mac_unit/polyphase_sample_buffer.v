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

`include "defines.v"

module polyphase_sample_buffer(clock, mem_en, wr_en, address, data_in ,data_out);

input clock;
input mem_en;
input wr_en;
input [`ADDRESS_WIDTH-1:0] address;
input [`DATA_WIDTH-1:0] data_in;
output [`DATA_WIDTH-1:0] data_out;

// Instantiate the RAM
lpm_polyphase_sample_buffer_RAM	polyphase_sample_buffer_RAM (
	.data ( data_in ),
	.wren ( wr_en ),
	.address ( address ),
	.clock ( clock ),
	.enable ( mem_en ),
	.q ( data_out )
	);

endmodule
