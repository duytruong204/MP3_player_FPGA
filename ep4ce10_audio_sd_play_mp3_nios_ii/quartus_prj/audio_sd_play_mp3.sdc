# Timing constraints for audio_sd_play_mp3 (EP4CE10F17C8)
#
# Check the TimeQuest "Report Unconstrained Paths" / clock summary after the
# first compile; node names below use wildcards so they survive renaming.

create_clock -name sys_clk    -period 20.000 [get_ports sys_clk]
# WM8978 is I2S master: BCLK = MCLK = 11.2903 MHz (period ~88.6 ns)
create_clock -name audio_bclk -period 88.571 [get_ports audio_bclk]

# PLL outputs: c0 = MCLK 11.29 MHz, c1/c2 = 50 MHz, c3 = MAC 12.5 MHz, c4 = HUFF 3.125 MHz
derive_pll_clocks
derive_clock_uncertainty

# SD SPI clock: divided from the 50 MHz clock inside sd_ctrl (12.5 MHz in run
# mode, 390 kHz during init).  sd_clk / spi_clk_shift is also used as the write
# clock of the MP3 input RAM and for mp3_feeder.
create_clock -name sd_spi_clk       -period 80.000 [get_registers {*sd_ctrl_inst|spi_clk}]
create_clock -name sd_spi_clk_shift -period 80.000 [get_registers {*sd_ctrl_inst|spi_clk_shift}]

# The domains (audio BCLK, SD SPI, MP3 MAC, MP3 Huffman, 50 MHz system) exchange
# only handshake/level signals that are synchronised in RTL (mp3_feeder,
# mp3_top, reset synchronisers) or go through true dual-clock RAMs.
set_clock_groups -asynchronous \
    -group [get_clocks audio_bclk] \
    -group [get_clocks {sd_spi_clk sd_spi_clk_shift}] \
    -group [get_clocks {*pll1|clk[3]}] \
    -group [get_clocks {*pll1|clk[4]}] \
    -group [get_clocks {sys_clk *pll1|clk[0] *pll1|clk[1] *pll1|clk[2]}]

# Push buttons (KEY1, KEY2) are asynchronous human inputs, synchronised and
# debounced in key_ctrl.
set_false_path -from [get_ports {key_next key_prev key_pause}]
