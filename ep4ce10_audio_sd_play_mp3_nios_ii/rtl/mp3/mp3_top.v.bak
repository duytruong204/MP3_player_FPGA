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


`timescale 1 ns/ 100 ps

`include "defines.v"

// Integrated with MP3 Code by Henry Ko on May 19, 2006
module mp3_top (
	HUFF_CLOCK_I,
	MAC_CLOCK_I,
	RESETN_I,
	
	// For NIOS MP3 data Input
	NIOS_WRITE_DATA_CLK_I,
	NIOS_WRITE_DATA_ADDRESS_I,
	NIOS_WRITE_DATA_I,
	NIOS_WRITE_DATA_EN_I,
	NIOS_WRITE_DATA_REQUEST_O,
	NIOS_WRITE_DATA_IDLE_I,
		
	// For NIOS PCM sample output
	NIOS_READ_DATA_CLK_I,
	NIOS_READ_DATA_ADDRESS_I,
	NIOS_CH0_READ_DATA_O,
	NIOS_CH1_READ_DATA_O,
	
	NIOS_SAMPLE_FREQUENCY_O
// For debugging
,
	USER_LED0_O,
	USER_LED1_O
);

	input HUFF_CLOCK_I;
	input MAC_CLOCK_I;
	input RESETN_I;
	
	input NIOS_WRITE_DATA_CLK_I;
	input [`ADDRESS_WIDTH-1:0]	NIOS_WRITE_DATA_ADDRESS_I;
	input [`DATA_WIDTH-1:0]		NIOS_WRITE_DATA_I;
	input 						NIOS_WRITE_DATA_EN_I;
	input 						NIOS_WRITE_DATA_IDLE_I;
	output						NIOS_WRITE_DATA_REQUEST_O;
	reg							NIOS_WRITE_DATA_REQUEST_O;
	input NIOS_READ_DATA_CLK_I;
	input [`ADDRESS_WIDTH-1:0]	NIOS_READ_DATA_ADDRESS_I;
	output [`DATA_WIDTH-1:0]	NIOS_CH0_READ_DATA_O;
	output [`DATA_WIDTH-1:0]	NIOS_CH1_READ_DATA_O;
	
	output [1:0]				NIOS_SAMPLE_FREQUENCY_O;
	reg [1:0]					NIOS_SAMPLE_FREQUENCY_O;
	
	reg							MP3_end_of_song;
	wire [1:0] 					MP3_Info_Mode;
	reg [1:0] 					MP3_Info_Mode_buffer;
	reg [1:0] 					MP3_Info_Mode_MAC_clock;
	wire [1:0] 					MP3_Info_Frequency;
	reg [1:0] 					MP3_Info_Frequency_buffer;

	// for Huff/Dequantizer
	reg 						HUFF_resetn;
	wire						HUFF_done;
	wire 						MAC_RAM_Idle;

	wire [`DATA_WIDTH-1:0] 		HUFF_DP_DATA;
	wire [`ADDRESS_WIDTH-1:0] 	HUFF_DP_ADDRESS;

	//for REQ RAMs
	wire 						Req_RAM_we;
	wire [`DATA_WIDTH-1:0] 		Req_RAM_write_data;
	wire [`DATA_WIDTH-1:0] 		Req_RAM_read_data;
	wire [`ADDRESS_WIDTH-1:0] 	Req_RAM_address;

	wire 						BR_RAM_we;
	wire [`DATA_WIDTH-1:0] 		BR_RAM_write_data;
	wire [`DATA_WIDTH-1:0] 		BR_RAM_read_data;
	wire [`ADDRESS_WIDTH-3:0] 	BR_RAM_address;
	
	wire [`ADDRESS_WIDTH-1:0] 	MAC_RAM_write_address;
	wire [`DATA_WIDTH-1:0] 		MAC_RAM_write_data;
	wire 						CH0_MAC_RAM_we;
	wire 						CH1_MAC_RAM_we;

	// for MAC
	wire [3:0]					CH0_WBBM;
	reg [1:0] 					MAC_state;
	wire [1:0] 					MP3_Info_CH0_MAC_block_type;
	wire 		 				MP3_Info_CH0_MAC_mixed_block;
	wire 		 				MP3_Info_CH0_MAC_switching;
	reg [1:0] 					MP3_Info_CH0_MAC_block_type_buffer;
	reg 		 				MP3_Info_CH0_MAC_mixed_block_buffer;
	reg 		 				MP3_Info_CH0_MAC_switching_buffer;
	reg [1:0] 					MP3_Info_CH0_MAC_block_type_MAC_clock;
	reg 		 				MP3_Info_CH0_MAC_mixed_block_MAC_clock;
	reg 		 				MP3_Info_CH0_MAC_switching_MAC_clock;

	assign MP3_Info_CH0_MAC_switching = CH0_WBBM[3];
	assign MP3_Info_CH0_MAC_block_type = CH0_WBBM[2:1];
	assign MP3_Info_CH0_MAC_mixed_block = CH0_WBBM[0];

	wire [3:0]					CH1_WBBM;
	wire [1:0] 					MP3_Info_CH1_MAC_block_type;
	wire 		 				MP3_Info_CH1_MAC_mixed_block;
	wire 		 				MP3_Info_CH1_MAC_switching;
	reg [1:0] 					MP3_Info_CH1_MAC_block_type_buffer;
	reg 		 				MP3_Info_CH1_MAC_mixed_block_buffer;
	reg 		 				MP3_Info_CH1_MAC_switching_buffer;
	reg [1:0] 					MP3_Info_CH1_MAC_block_type_MAC_clock;
	reg 		 				MP3_Info_CH1_MAC_mixed_block_MAC_clock;
	reg 		 				MP3_Info_CH1_MAC_switching_MAC_clock;

	assign MP3_Info_CH1_MAC_switching = CH1_WBBM[3];
	assign MP3_Info_CH1_MAC_block_type = CH1_WBBM[2:1];
	assign MP3_Info_CH1_MAC_mixed_block = CH1_WBBM[0];
	wire 								MAC_resetn;

	reg 						CH0_MAC_start;
	wire [`ADDRESS_WIDTH-1:0] 	CH0_MAC_RAM_read_address;
	wire [`DATA_WIDTH-1:0] 		CH0_MAC_RAM_read_data;
	wire 						CH0_MAC_RAM_read_en_MAC_clock;
	reg 						CH0_MAC_RAM_read_en_HUFF_clock;
	reg [`ADDRESS_WIDTH-1:0] 	CH0_PCM_RAM_write_address_buffer;

	wire [`DATA_WIDTH-1:0] 		CH0_PCM_RAM_write_data;
	wire [`ADDRESS_WIDTH-1:0] 	CH0_PCM_RAM_write_address;
	wire 						CH0_PCM_RAM_we;

	reg 						CH1_MAC_start;
	wire [`ADDRESS_WIDTH-1:0] 	CH1_MAC_RAM_read_address;
	wire [`DATA_WIDTH-1:0] 		CH1_MAC_RAM_read_data;
	wire 						CH1_MAC_RAM_read_en_MAC_clock;
	reg 						CH1_MAC_RAM_read_en_HUFF_clock;

	wire [`DATA_WIDTH-1:0] 		CH1_PCM_RAM_write_data;
	wire [`ADDRESS_WIDTH-1:0] 	CH1_PCM_RAM_write_address;
	wire 						CH1_PCM_RAM_we;

	wire 						MAC_done;

	// For AUDIO codec
	reg [`ADDRESS_WIDTH-1:0] 	NIOS_READ_DATA_ADDRESS_MAC_clock;
	reg [`ADDRESS_WIDTH-1:0] 	NIOS_READ_DATA_ADDRESS_s1;
	reg [`ADDRESS_WIDTH-1:0] 	NIOS_READ_DATA_ADDRESS_s2;
	
	// For debugging
	output USER_LED0_O;
	output USER_LED1_O;
	
	// DP RAM between Huffman and NIOS
lpm_HUFF_DP 	lpm_HUFF_DP_inst (
		// output from NIOS
	.data_a ( NIOS_WRITE_DATA_I ),
	.wren_a ( NIOS_WRITE_DATA_EN_I ),
	//.wren_a (  ),
	.address_a ( NIOS_WRITE_DATA_ADDRESS_I ),
	.clock_a ( NIOS_WRITE_DATA_CLK_I ),
	//.enable_a ( NIOS_WRITE_DATA_EN_I ),
	.enable_a ( 1'b1),
	.q_a ( ),
		// input to HUFF	 
	.data_b ( 16'h0000 ),
	.address_b ( HUFF_DP_ADDRESS ),
	.wren_b ( 1'b0 ),
	.clock_b ( HUFF_CLOCK_I ),
	.enable_b ( 1'b1 ),
	.q_b ( HUFF_DP_DATA )
	);
	
/*
  RAMB16_S18_S18 HUFF_DP (
		// output from NIOS
    .DOA(),
    .DOPA(),
    .ADDRA(NIOS_WRITE_DATA_ADDRESS_I),
    .CLKA(NIOS_WRITE_DATA_CLK_I),
    .DIA(NIOS_WRITE_DATA_I),
    .DIPA(2'b00),
    .ENA(NIOS_WRITE_DATA_EN_I),
    .SSRA(1'b0),
    .WEA(NIOS_WRITE_DATA_EN_I),

		// input to HUFF	 
	 .DOB(HUFF_DP_DATA),
    .DOPB(),
    .ADDRB(HUFF_DP_ADDRESS),
    .CLKB(HUFF_CLOCK_I),
    .DIB(16'h0000),
    .DIPB(2'b00),
    .ENB(1'b1),
    .SSRB(1'b0),
	 .WEB(1'b0)
  );
*/
	// New huffman and requantizer with one RAM
	huffctl HUFFMANDECODER (
    .CLK_I(HUFF_CLOCK_I),
    .RESETN_I(HUFF_resetn),
    
    .HUFF_DONE_O(HUFF_done),
    .MAC_READY_I(MAC_RAM_Idle),
    .DUAL_SELECT_I(1'b0),
    .WBBM_O(CH1_WBBM),
    .WBBML_O(CH0_WBBM),
    
    .GR_O(),
    .CH_O(),
    .NCH_O(),
    .SAMPLE_FREQUENCY_O(MP3_Info_Frequency),
    .MODE_O(MP3_Info_Mode),
    .MODE_EXTENSION_O(),
    
    .RAM_ADDRESS_O(Req_RAM_address),
    .RAM_WE_O(Req_RAM_we),
    .RAM_DATAIN_O(Req_RAM_write_data),
    .RAM_DATAOUT_I(Req_RAM_read_data),
    
    .DPR_ADDRESS_O(HUFF_DP_ADDRESS),
    .DPR_DATAOUT_I(HUFF_DP_DATA),
    
    .BR_ADDRESS_O(BR_RAM_address),
    .BR_DATAIN_O(BR_RAM_write_data),
    .BR_WE_O(BR_RAM_we),
    .BR_DATAOUT_I(BR_RAM_read_data),
    
    .MAC_DATAIN_O(MAC_RAM_write_data),
    .MAC_ADDRESS_O(MAC_RAM_write_address),
    .MAC_LEFT_WE_O(CH0_MAC_RAM_we),
    .MAC_RIGHT_WE_O(CH1_MAC_RAM_we)
  );

// Requantizer RAM
lpm_req_ram	lpm_req_ram_inst (
	.data_a ( Req_RAM_write_data ),
	.wren_a ( Req_RAM_we ),
	.address_a ( Req_RAM_address ),
	.data_b ( BR_RAM_write_data ),
	.address_b ( {2'b11,BR_RAM_address} ),
	.wren_b ( BR_RAM_we ),
	.clock ( HUFF_CLOCK_I ),
	.q_a ( Req_RAM_read_data ),
	.q_b ( BR_RAM_read_data )
	);
/*
  RAMB16_S18_S18 Req_RAM (
    .DOA(Req_RAM_read_data),
    .DOB(BR_RAM_read_data),
    .DOPA(),
    .DOPB(),
    .ADDRA(Req_RAM_address),
    .ADDRB({2'b11,BR_RAM_address}),
    .CLKA(HUFF_CLOCK_I),
    .CLKB(HUFF_CLOCK_I),
    .DIA(Req_RAM_write_data),
    .DIB(BR_RAM_write_data),
    .DIPA(2'b00),
    .DIPB(2'b00),
    .ENA(1'b1),
    .ENB(1'b1),
    .SSRA(1'b0),
    .SSRB(1'b0),
    .WEA(Req_RAM_we),
    .WEB(BR_RAM_we)
  );
*/
	// DP RAM between Huffman and MAC
lpm_CH0_MAC_RAM 	lpm_CH0_MAC_RAM_inst (
		// output from Huffman
	.data_a ( MAC_RAM_write_data ),
	.wren_a ( CH0_MAC_RAM_we ),
	.address_a ( MAC_RAM_write_address ),
	.clock_a ( HUFF_CLOCK_I ),
	//.enable_a ( CH0_MAC_RAM_we ),
	.enable_a ( 1'b1),
	.q_a ( ),
		// input to MAC
	.data_b ( 16'h0000 ),
	.address_b ( CH0_MAC_RAM_read_address ),
	.wren_b ( 1'b0 ),
	.clock_b ( MAC_CLOCK_I ),
	.enable_b ( CH0_MAC_RAM_read_en_MAC_clock ),
//	.enable_b (1'b1),
	.q_b ( CH0_MAC_RAM_read_data )
	);
	
lpm_CH1_MAC_RAM 	lpm_CH1_MAC_RAM_inst (
		// output from Huffman
	.data_a ( MAC_RAM_write_data ),
	.wren_a ( CH1_MAC_RAM_we ),
	.address_a ( MAC_RAM_write_address ),
	.clock_a ( HUFF_CLOCK_I ),
	//.enable_a ( CH1_MAC_RAM_we ),
	.enable_a ( 1'b1),
	.q_a ( ),
		// input to MAC
	.data_b ( 16'h0000 ),
	.address_b ( CH0_MAC_RAM_read_address ),
	.wren_b ( 1'b0 ),
	.clock_b ( MAC_CLOCK_I ),
	.enable_b ( CH1_MAC_RAM_read_en_MAC_clock ),
//	.enable_b (1'b1),
	.q_b ( CH1_MAC_RAM_read_data )
	);

	// MAC
	mac_unit MAC_module (
		.MAC_CLOCK_I(MAC_CLOCK_I), 
		.MAC_RESETN_I(MAC_resetn),

		.CH0_MAC_START_I(CH0_MAC_start),
		.CH0_MAC_BLOCK_I(MP3_Info_CH0_MAC_block_type_MAC_clock),
		.CH0_MAC_MIXED_I(MP3_Info_CH0_MAC_mixed_block_MAC_clock),
		.CH0_MAC_SWITCHING_I(MP3_Info_CH0_MAC_switching_MAC_clock),
		.CH0_MAC_RAM_DATA_I(CH0_MAC_RAM_read_data),
//		.CH0_MAC_RAM_DATA_I(16'h0000),
		.CH0_MAC_RAM_ADDRESS_O(CH0_MAC_RAM_read_address),
		.CH0_MAC_RAM_EN_O(CH0_MAC_RAM_read_en_MAC_clock),
		.CH0_PCM_RAM_DATA_O(CH0_PCM_RAM_write_data),
		.CH0_PCM_RAM_WE_O(CH0_PCM_RAM_we),
		.CH0_PCM_RAM_ADDRESS_O(CH0_PCM_RAM_write_address),

		.CH1_MAC_START_I(CH1_MAC_start),
		.CH1_MAC_BLOCK_I(MP3_Info_CH1_MAC_block_type_MAC_clock),
		.CH1_MAC_MIXED_I(MP3_Info_CH1_MAC_mixed_block_MAC_clock),
		.CH1_MAC_SWITCHING_I(MP3_Info_CH1_MAC_switching_MAC_clock),
		.CH1_MAC_RAM_DATA_I(CH1_MAC_RAM_read_data),
		.CH1_MAC_RAM_ADDRESS_O(CH1_MAC_RAM_read_address),
		.CH1_MAC_RAM_EN_O(CH1_MAC_RAM_read_en_MAC_clock),
		.CH1_PCM_RAM_DATA_O(CH1_PCM_RAM_write_data),
		.CH1_PCM_RAM_WE_O(CH1_PCM_RAM_we),
		.CH1_PCM_RAM_ADDRESS_O(CH1_PCM_RAM_write_address),

		.MAC_DONE_O(MAC_done)
	);

 	// DP RAM between MAC and Audio
lpm_CH0_PCM_RAM 	lpm_CH0_PCM_RAM_inst (
		// output from MAC
	.data_a ( CH0_PCM_RAM_write_data ),
	.wren_a ( CH0_PCM_RAM_we ),
	.address_a ( CH0_PCM_RAM_write_address ),
	.clock_a ( MAC_CLOCK_I ),
	//.enable_a ( CH0_PCM_RAM_we ),
	.enable_a ( 1'b1),
	.q_a ( ),
		// output to NIOS
	.data_b ( 16'h0000 ),
	.address_b ( NIOS_READ_DATA_ADDRESS_I ),
	.wren_b ( 1'b0 ),
	.clock_b ( NIOS_READ_DATA_CLK_I ),
	.enable_b ( 1'b1 ),
	.q_b ( NIOS_CH0_READ_DATA_O )
	);

/*
	RAMB16_S18_S18 CH0_PCM_RAM (
		// output from MAC
    .DOA(),
    .DOPA(),
    .ADDRA(CH0_PCM_RAM_write_address),
    .CLKA(MAC_CLOCK_I),
    .DIA(CH0_PCM_RAM_write_data),
    .DIPA(2'b00),
    .ENA(CH0_PCM_RAM_we),
    .SSRA(1'b0),
    .WEA(CH0_PCM_RAM_we),

		// output to NIOS	 
	 .DOB(NIOS_CH0_READ_DATA_O),
    .DOPB(),
    .ADDRB(NIOS_READ_DATA_ADDRESS_I),
    .CLKB(NIOS_READ_DATA_CLK_I),
    .DIB(16'h0000),
    .DIPB(2'b00),
    .ENB(1'b1),
    .SSRB(1'b0),
	 .WEB(1'b0)
  );
*/
lpm_CH1_PCM_RAM 	lpm_CH1_PCM_RAM_inst (
		// output from MAC
	.data_a ( CH1_PCM_RAM_write_data ),
	.wren_a ( CH1_PCM_RAM_we ),
	.address_a ( CH1_PCM_RAM_write_address ),
	.clock_a ( MAC_CLOCK_I ),
	//.enable_a ( CH1_PCM_RAM_we ),
	.enable_a ( 1'b1),
	.q_a ( ),
		// output to NIOS
	.data_b ( 16'h0000 ),
	.address_b ( NIOS_READ_DATA_ADDRESS_I ),
	.wren_b ( 1'b0 ),
	.clock_b ( NIOS_READ_DATA_CLK_I ),
	.enable_b ( 1'b1 ),
	.q_b ( NIOS_CH1_READ_DATA_O )
	);
/*
	RAMB16_S18_S18 CH1_PCM_RAM (
		// output from MAC
    .DOA(),
    .DOPA(),
    .ADDRA(CH1_PCM_RAM_write_address),
    .CLKA(MAC_CLOCK_I),
    .DIA(CH1_PCM_RAM_write_data),
    .DIPA(2'b00),
    .ENA(CH1_PCM_RAM_we),
    .SSRA(1'b0),
    .WEA(CH1_PCM_RAM_we),

		// output to NIOS
	 .DOB(NIOS_CH1_READ_DATA_O),
    .DOPB(),
    .ADDRB(NIOS_READ_DATA_ADDRESS_I),
    .CLKB(NIOS_READ_DATA_CLK_I),
    .DIB(16'h0000),
    .DIPB(2'b00),
    .ENB(1'b1),
    .SSRB(1'b0),
	 .WEB(1'b0)
  );
*/

	// For debugging (LED counters clocked by derived signals removed for Cyclone IV E port)
	assign USER_LED0_O = 1'b0;
	assign USER_LED1_O = 1'b0;

	assign MAC_resetn = RESETN_I;
	
	always @ (posedge MAC_CLOCK_I) begin
		// buffer read address across bit clock domain
		// The address bus comes from the audio (BCLK) domain: register it twice and
		// only accept it when two consecutive samples agree, so a bit-skewed
		// transition can never produce a false address match.
		NIOS_READ_DATA_ADDRESS_s1 <= NIOS_READ_DATA_ADDRESS_I;
		NIOS_READ_DATA_ADDRESS_s2 <= NIOS_READ_DATA_ADDRESS_s1;
		if (NIOS_READ_DATA_ADDRESS_s1 == NIOS_READ_DATA_ADDRESS_s2)
			NIOS_READ_DATA_ADDRESS_MAC_clock <= NIOS_READ_DATA_ADDRESS_s2;
		MP3_Info_Mode_MAC_clock <= MP3_Info_Mode_buffer;

//		if (CH0_MAC_RAM_read_en_MAC_clock == 1'b0) begin
			MP3_Info_CH0_MAC_block_type_MAC_clock <= MP3_Info_CH0_MAC_block_type_buffer;
			MP3_Info_CH0_MAC_mixed_block_MAC_clock <= MP3_Info_CH0_MAC_mixed_block_buffer;
			MP3_Info_CH0_MAC_switching_MAC_clock <= MP3_Info_CH0_MAC_switching_buffer;
//		end
		
//		if (CH1_MAC_RAM_read_en_MAC_clock == 1'b0) begin
			MP3_Info_CH1_MAC_block_type_MAC_clock <= MP3_Info_CH1_MAC_block_type_buffer;
			MP3_Info_CH1_MAC_mixed_block_MAC_clock <= MP3_Info_CH1_MAC_mixed_block_buffer;
			MP3_Info_CH1_MAC_switching_MAC_clock <= MP3_Info_CH1_MAC_switching_buffer;
//		end
	end

	always @ (posedge MAC_CLOCK_I or negedge MAC_resetn) begin
		if (MAC_resetn == 1'b0) begin
			MAC_state <= 2'd0;
			CH0_MAC_start <= 1'b0;
			CH1_MAC_start <= 1'b0;
			CH0_PCM_RAM_write_address_buffer <= 10'd500;
		end else begin
			case (MAC_state) 
			2'd0: begin
				if ((MAC_done == 1'b1) && (NIOS_READ_DATA_ADDRESS_MAC_clock == CH0_PCM_RAM_write_address_buffer)) begin
					CH0_PCM_RAM_write_address_buffer <= 10'd0;

					MAC_state <= 2'd1;
				end		
			end
			2'd1: begin
				// start MAC unit according to read address from Audio
				if ((CH0_MAC_start == 1'b0) && (MAC_done == 1'b1)
				 && (NIOS_READ_DATA_ADDRESS_MAC_clock == CH0_PCM_RAM_write_address_buffer)) begin
					// start the MAC
					CH0_MAC_start <= 1'b1;
					if ((MP3_Info_Mode_MAC_clock == 2'b00) || (MP3_Info_Mode_MAC_clock == 2'b01)) CH1_MAC_start <= 1'b1;
					else CH1_MAC_start <= 1'b0;

					MAC_state <= 2'd2;
				end
			end
			2'd2: begin
				// de-assert the start signal
				if ((CH0_MAC_start == 1'b1) && (MAC_done == 1'b0)) begin
					CH0_MAC_start <= 1'b0;
					CH1_MAC_start <= 1'b0;

					CH0_PCM_RAM_write_address_buffer <= CH0_PCM_RAM_write_address;

					MAC_state <= 2'd1;
				end
			end
			endcase
		end
	end

	reg [2:0] NIOS_state;
	reg HUFF_address_msb_buffer;
	reg NIOS_WRITE_DATA_IDLE_buffer;
	reg NIOS_WRITE_DATA_IDLE_meta;

	always @ (posedge MAC_CLOCK_I) begin
		HUFF_address_msb_buffer <= HUFF_DP_ADDRESS[9];
		NIOS_WRITE_DATA_IDLE_meta <= NIOS_WRITE_DATA_IDLE_I;
		NIOS_WRITE_DATA_IDLE_buffer <= NIOS_WRITE_DATA_IDLE_meta;		
	end

	always @ (posedge MAC_CLOCK_I or negedge MAC_resetn) begin
		if (MAC_resetn == 1'b0) begin
			NIOS_state <= 3'd0;
			NIOS_WRITE_DATA_REQUEST_O <= 1'b0;
			HUFF_resetn <= 1'b0;
		end else begin
			case (NIOS_state) 
			3'd0: begin
				// start write request at the same time as MAC
				if ((NIOS_WRITE_DATA_REQUEST_O == 1'b0) && (NIOS_WRITE_DATA_IDLE_buffer == 1'b1)
				 && (NIOS_READ_DATA_ADDRESS_MAC_clock == CH0_PCM_RAM_write_address_buffer)) begin
					// start the write request
					NIOS_WRITE_DATA_REQUEST_O <= 1'b1;

					NIOS_state <= 3'd1;
				end
			end
			3'd1: begin
				// de-assert the start signal
				if ((NIOS_WRITE_DATA_REQUEST_O == 1'b1) && (NIOS_WRITE_DATA_IDLE_buffer == 1'b0)) begin
					NIOS_WRITE_DATA_REQUEST_O <= 1'b0;

					NIOS_state <= 3'd2;
				end
			end
			3'd2: begin
				// start write request to fill the second half of the DP RAM
				if ((NIOS_WRITE_DATA_REQUEST_O == 1'b0) && (NIOS_WRITE_DATA_IDLE_buffer == 1'b1)) begin
					// start the write request
					NIOS_WRITE_DATA_REQUEST_O <= 1'b1;

					NIOS_state <= 3'd3;

					HUFF_resetn <= 1'b1;
				end
			end
			3'd3: begin
				// de-assert the start signal
				if ((NIOS_WRITE_DATA_REQUEST_O == 1'b1) && (NIOS_WRITE_DATA_IDLE_buffer == 1'b0)) begin
					NIOS_WRITE_DATA_REQUEST_O <= 1'b0;

					NIOS_state <= 3'd4;
				end
			end
			default: begin
				if ((HUFF_address_msb_buffer != HUFF_DP_ADDRESS[9]) && (NIOS_WRITE_DATA_IDLE_buffer == 1'b1)) begin
					NIOS_WRITE_DATA_REQUEST_O <= 1'b1;

					NIOS_state <= 3'd3;
				end
			end
			endcase
		end
	end

	reg [1:0] MP3_state;

	always @ (posedge HUFF_CLOCK_I) begin
		CH0_MAC_RAM_read_en_HUFF_clock <= CH0_MAC_RAM_read_en_MAC_clock;
		CH1_MAC_RAM_read_en_HUFF_clock <= CH1_MAC_RAM_read_en_MAC_clock;
	end
	
	assign MAC_RAM_Idle = ~(CH0_MAC_RAM_read_en_HUFF_clock || CH1_MAC_RAM_read_en_HUFF_clock);

	// state machine for handshaking with huffman
	always @ (posedge HUFF_done or negedge MAC_resetn) begin
		if (MAC_resetn == 1'b0) begin
			MP3_Info_Frequency_buffer <= 2'd0;
			MP3_Info_Mode_buffer <= 2'd0;

			MP3_Info_CH0_MAC_block_type_buffer <= 2'b00;
			MP3_Info_CH0_MAC_mixed_block_buffer <= 1'b0;
			MP3_Info_CH0_MAC_switching_buffer <= 1'b0;

			MP3_Info_CH1_MAC_block_type_buffer <= 2'b00;
			MP3_Info_CH1_MAC_mixed_block_buffer <= 1'b0;
			MP3_Info_CH1_MAC_switching_buffer <= 1'b0;
		end else begin
//			if (HUFF_done == 1'b1) begin
				MP3_Info_Frequency_buffer <= MP3_Info_Frequency;
				MP3_Info_Mode_buffer <= MP3_Info_Mode;

				MP3_Info_CH0_MAC_block_type_buffer <= MP3_Info_CH0_MAC_block_type;
				MP3_Info_CH0_MAC_mixed_block_buffer <= MP3_Info_CH0_MAC_mixed_block;
				MP3_Info_CH0_MAC_switching_buffer <= MP3_Info_CH0_MAC_switching;

				MP3_Info_CH1_MAC_block_type_buffer <= MP3_Info_CH1_MAC_block_type;
				MP3_Info_CH1_MAC_mixed_block_buffer <= MP3_Info_CH1_MAC_mixed_block;
				MP3_Info_CH1_MAC_switching_buffer <= MP3_Info_CH1_MAC_switching;
//			end
		end
	end

	// The codec sample rate is fixed by the board PLL (44.1 kHz for clean.mp3);
	// the decoded frequency code is not used any more.
	always @ (posedge MAC_CLOCK_I or negedge MAC_resetn) begin
		if (MAC_resetn == 1'b0) NIOS_SAMPLE_FREQUENCY_O <= `FREQUENCY_48K;
		else NIOS_SAMPLE_FREQUENCY_O <= MP3_Info_Frequency_buffer;
	end

endmodule
