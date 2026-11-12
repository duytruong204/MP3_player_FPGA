clk_gen (altpll) for the MP3 player, 50 MHz in, VCO 700 MHz (M=14, N=1):
  c0  = 50 MHz * 7/31  = 11.2903 MHz -> WM8978 MCLK (audio_mclk); LRC = c0/256 = 44,101 Hz
  c1  = 50 MHz                         -> SD controller / codec I2C
  c2  = 50 MHz, +5000 ps (90 deg)      -> SD controller shifted clock
  c3  = 12.5 MHz                       -> MP3 MAC clock   (HUFF * 4)
  c4  = 3.125 MHz                      -> MP3 Huffman clock
The file was edited by hand from the golden clk_gen.v. If Quartus complains,
re-open it in the MegaWizard (Tools -> MegaWizard Plug-In Manager) and re-enter
the five outputs above (operation mode: normal, compensate clock: c1).
