	component nios is
		port (
			clk_clk                                       : in    std_logic                     := 'X';             -- clk
			mp3_wr_addr_pio_external_connection_export    : out   std_logic_vector(9 downto 0);                     -- export
			mp3_wr_data_pio_external_connection_export    : out   std_logic_vector(15 downto 0);                    -- export
			mp3_wr_en_pio_external_connection_export      : out   std_logic;                                        -- export
			mp3_wr_idle_pio_external_connection_export    : out   std_logic;                                        -- export
			mp3_wr_request_pio_external_connection_export : in    std_logic                     := 'X';             -- export
			reset_reset_n                                 : in    std_logic                     := 'X';             -- reset_n
			sd_card_conduit_end_b_SD_cmd                  : inout std_logic                     := 'X';             -- b_SD_cmd
			sd_card_conduit_end_b_SD_dat                  : inout std_logic                     := 'X';             -- b_SD_dat
			sd_card_conduit_end_b_SD_dat3                 : inout std_logic                     := 'X';             -- b_SD_dat3
			sd_card_conduit_end_o_SD_clock                : out   std_logic;                                        -- o_SD_clock
			sdram_controller_wire_addr                    : out   std_logic_vector(12 downto 0);                    -- addr
			sdram_controller_wire_ba                      : out   std_logic_vector(1 downto 0);                     -- ba
			sdram_controller_wire_cas_n                   : out   std_logic;                                        -- cas_n
			sdram_controller_wire_cke                     : out   std_logic;                                        -- cke
			sdram_controller_wire_cs_n                    : out   std_logic;                                        -- cs_n
			sdram_controller_wire_dq                      : inout std_logic_vector(15 downto 0) := (others => 'X'); -- dq
			sdram_controller_wire_dqm                     : out   std_logic_vector(1 downto 0);                     -- dqm
			sdram_controller_wire_ras_n                   : out   std_logic;                                        -- ras_n
			sdram_controller_wire_we_n                    : out   std_logic;                                        -- we_n
			sys_sdram_pll_sdram_clk_clk                   : out   std_logic;                                        -- clk
			mp3_resetn_pio_external_connection_export     : out   std_logic;                                        -- export
			pio_0_external_connection_export              : in    std_logic_vector(21 downto 0) := (others => 'X')  -- export
		);
	end component nios;

	u0 : component nios
		port map (
			clk_clk                                       => CONNECTED_TO_clk_clk,                                       --                                    clk.clk
			mp3_wr_addr_pio_external_connection_export    => CONNECTED_TO_mp3_wr_addr_pio_external_connection_export,    --    mp3_wr_addr_pio_external_connection.export
			mp3_wr_data_pio_external_connection_export    => CONNECTED_TO_mp3_wr_data_pio_external_connection_export,    --    mp3_wr_data_pio_external_connection.export
			mp3_wr_en_pio_external_connection_export      => CONNECTED_TO_mp3_wr_en_pio_external_connection_export,      --      mp3_wr_en_pio_external_connection.export
			mp3_wr_idle_pio_external_connection_export    => CONNECTED_TO_mp3_wr_idle_pio_external_connection_export,    --    mp3_wr_idle_pio_external_connection.export
			mp3_wr_request_pio_external_connection_export => CONNECTED_TO_mp3_wr_request_pio_external_connection_export, -- mp3_wr_request_pio_external_connection.export
			reset_reset_n                                 => CONNECTED_TO_reset_reset_n,                                 --                                  reset.reset_n
			sd_card_conduit_end_b_SD_cmd                  => CONNECTED_TO_sd_card_conduit_end_b_SD_cmd,                  --                    sd_card_conduit_end.b_SD_cmd
			sd_card_conduit_end_b_SD_dat                  => CONNECTED_TO_sd_card_conduit_end_b_SD_dat,                  --                                       .b_SD_dat
			sd_card_conduit_end_b_SD_dat3                 => CONNECTED_TO_sd_card_conduit_end_b_SD_dat3,                 --                                       .b_SD_dat3
			sd_card_conduit_end_o_SD_clock                => CONNECTED_TO_sd_card_conduit_end_o_SD_clock,                --                                       .o_SD_clock
			sdram_controller_wire_addr                    => CONNECTED_TO_sdram_controller_wire_addr,                    --                  sdram_controller_wire.addr
			sdram_controller_wire_ba                      => CONNECTED_TO_sdram_controller_wire_ba,                      --                                       .ba
			sdram_controller_wire_cas_n                   => CONNECTED_TO_sdram_controller_wire_cas_n,                   --                                       .cas_n
			sdram_controller_wire_cke                     => CONNECTED_TO_sdram_controller_wire_cke,                     --                                       .cke
			sdram_controller_wire_cs_n                    => CONNECTED_TO_sdram_controller_wire_cs_n,                    --                                       .cs_n
			sdram_controller_wire_dq                      => CONNECTED_TO_sdram_controller_wire_dq,                      --                                       .dq
			sdram_controller_wire_dqm                     => CONNECTED_TO_sdram_controller_wire_dqm,                     --                                       .dqm
			sdram_controller_wire_ras_n                   => CONNECTED_TO_sdram_controller_wire_ras_n,                   --                                       .ras_n
			sdram_controller_wire_we_n                    => CONNECTED_TO_sdram_controller_wire_we_n,                    --                                       .we_n
			sys_sdram_pll_sdram_clk_clk                   => CONNECTED_TO_sys_sdram_pll_sdram_clk_clk,                   --                sys_sdram_pll_sdram_clk.clk
			mp3_resetn_pio_external_connection_export     => CONNECTED_TO_mp3_resetn_pio_external_connection_export,     --     mp3_resetn_pio_external_connection.export
			pio_0_external_connection_export              => CONNECTED_TO_pio_0_external_connection_export               --              pio_0_external_connection.export
		);

