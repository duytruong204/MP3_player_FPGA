
module nios (
	clk_clk,
	mp3_wr_addr_pio_external_connection_export,
	mp3_wr_data_pio_external_connection_export,
	mp3_wr_en_pio_external_connection_export,
	mp3_wr_idle_pio_external_connection_export,
	mp3_wr_request_pio_external_connection_export,
	reset_reset_n,
	sd_card_conduit_end_b_SD_cmd,
	sd_card_conduit_end_b_SD_dat,
	sd_card_conduit_end_b_SD_dat3,
	sd_card_conduit_end_o_SD_clock,
	sdram_controller_wire_addr,
	sdram_controller_wire_ba,
	sdram_controller_wire_cas_n,
	sdram_controller_wire_cke,
	sdram_controller_wire_cs_n,
	sdram_controller_wire_dq,
	sdram_controller_wire_dqm,
	sdram_controller_wire_ras_n,
	sdram_controller_wire_we_n,
	sys_sdram_pll_sdram_clk_clk,
	mp3_resetn_pio_external_connection_export,
	pio_0_external_connection_export);	

	input		clk_clk;
	output	[9:0]	mp3_wr_addr_pio_external_connection_export;
	output	[15:0]	mp3_wr_data_pio_external_connection_export;
	output		mp3_wr_en_pio_external_connection_export;
	output		mp3_wr_idle_pio_external_connection_export;
	input		mp3_wr_request_pio_external_connection_export;
	input		reset_reset_n;
	inout		sd_card_conduit_end_b_SD_cmd;
	inout		sd_card_conduit_end_b_SD_dat;
	inout		sd_card_conduit_end_b_SD_dat3;
	output		sd_card_conduit_end_o_SD_clock;
	output	[12:0]	sdram_controller_wire_addr;
	output	[1:0]	sdram_controller_wire_ba;
	output		sdram_controller_wire_cas_n;
	output		sdram_controller_wire_cke;
	output		sdram_controller_wire_cs_n;
	inout	[15:0]	sdram_controller_wire_dq;
	output	[1:0]	sdram_controller_wire_dqm;
	output		sdram_controller_wire_ras_n;
	output		sdram_controller_wire_we_n;
	output		sys_sdram_pll_sdram_clk_clk;
	output		mp3_resetn_pio_external_connection_export;
	input	[21:0]	pio_0_external_connection_export;
endmodule
