# ep4ce10_audio_sd_play_mp3 - play MP3 files from an SD card (EP4CE10F17C8 + WM8978)

Golden reference: `../ep4ce10_audio_sd_play_wav` (SD card -> FIFO -> WM8978).
Here the FIFO/byte-swap part is replaced by the MAC_MP3 decoder:

    SD card -> sd_ctrl -> mp3_feeder -> mp3_top (MAC_MP3, HUFF_DP ring RAM) -> PCM RAMs
            -> pcm_out_ctrl -> wm8978_ctrl (unchanged golden) -> WM8978 -> speaker

`rtl/sd/*` and `rtl/wm8978/*` are unmodified copies of the golden files (only the
comments were translated to English).

## Keys

| key | pin | function |
|---|---|---|
| KEY1 | M2  (`key_next`)     | play the next song |
| KEY2 | M1  (`key_prev`)     | play the previous song |

The keys are **active low** (pressed = 0, like the reset key M15).  If your board is
active high, set the parameter `KEY_ACTIVE_LOW = 0` in `rtl/audio_sd_play_mp3.v`
(`SONG_KEYS_EN = 0` ignores the keys, useful to isolate a problem on the board).  Each key is synchronised and
debounced for 20 ms (`rtl/key_ctrl.v`); a press gives exactly one action.

* **Songs.**  The playlist is a fixed table in `rtl/audio_sd_play_mp3.v`
  (`NUM_SONGS`, `SONG_ADDRS`, `SONG_SECTORS`, up to 8 songs, see below).  KEY1/KEY2 move
  through the table with wrap-around (last -> first, first -> last).  The new song
  starts from its beginning after a restart of the decoder (about 0.1 s of silence).
  Several quick presses accumulate (two presses = two songs further).  When a song ends
  the player continues with the **next** song (the last song wraps to song 0; with a
  single song it repeats that song).
* **Volume.**  Not controlled by keys; the WM8978 keeps the golden volume (headphone 30,
  speaker 50).

## Clocks (clk_gen, PLL VCO 700 MHz)
| output | freq | use |
|---|---|---|
| c0 | 11.2903 MHz | WM8978 MCLK = BCLK -> LRC = 44.1028 kHz (+0.006 % vs 44.1 kHz) |
| c1 / c2 | 50 MHz / +5 ns | system clock / SD SPI clock (as golden) |
| c3 | 12.5 MHz | decoder MAC clock |
| c4 | 3.125 MHz | decoder Huffman clock (MAC/4, edges aligned) |

`quartus_prj/ip_core/clk_gen` was edited by hand (see `README_pll.txt`); if Quartus
complains, re-generate it with the MegaWizard using the table above.

## Put the MP3 files on the card
1. Format the card FAT16 (SDSC 2 GB) and copy the MP3 files into the **root directory**,
   one after the other (each file must be stored in contiguous clusters, so do not
   delete / rewrite files on that card).  Strip ID3v2 tags, the decoder expects an MPEG
   frame sync at the first byte.
2. `python3 tools/find_mp3_sector.py <card image or /dev/sdX>` lists **all** `*.MP3` files
   of the root directory (directory order = copy order = KEY1 order, max. 8) and prints a
   ready-to-paste table, e.g.

        parameter           NUM_SONGS    = 3;
        parameter   [255:0] SONG_ADDRS   = {160'd0, 32'd448, 32'd384, 32'd320};
        parameter   [143:0] SONG_SECTORS = {90'd0, 18'd4, 18'd6, 18'd16};

   Song 0 is the right-most entry.  With a file name
   (`... CLEAN.MP3 clean.mp3`) only that file is used and compared with the original.
3. Paste the three lines over the parameters of `rtl/audio_sd_play_mp3.v` and recompile.
   Default: one song, `clean.mp3` at sector 417 (the value that works on the author's
   card), 8086 sectors.  A wrong start sector (pointing at non-MP3 data) gives steady
   broadband noise instead of music.  The sector counts are rounded up to an even number.

## Compile / test on the board
1. Open `quartus_prj/audio_sd_play_mp3.qpf`, compile.  Expected: ~3.8 k LEs of the decoder,
   ~35 of 46 M9K blocks.  Check TimeQuest for the decoder derived clocks.  The key inputs
   are `set_false_path` in the `.sdc`.
2. Program, press reset: the song plays after ~0.1 s (mute period).  Try KEY1 / KEY2.
3. `pcm_out_ctrl` GAIN_SHIFT=1 doubles the decoder output (saturating) to match the loudness of
   the golden WAV playback (the decoder is ~6 dB lower).  Set 0 for the raw decoder output.
4. Things to confirm on the board: key polarity and song order.

## Simulation (Synopsys VCS)
    tb/run_vcs.sh tb_audio_sd_play_mp3        # whole system incl. behavioural SD card + WM8978, 1 s of audio
    python3 tools/compare_pcm.py              # PCM vs the golden WAV (gain, SNR, L/R, alignment)
    tb/run_vcs.sh tb_codec_input              # codec input of the new path vs the golden path
    tb/run_vcs.sh tb_keys                     # keys: song change, wrap, end of file (~3 min)
Options of the first TB: `+FRAMES=n +MP3=file +OUT=file`,
`VCS_EXTRA="-pvalue+tb_audio_sd_play_mp3.MP3_SECTOR_P=16"` (short file -> tests the
end-of-file restart), `VCS_EXTRA=+define+DUMP_HUFF` (dump the decoder's Huffman/requantizer
stream).

`tb_keys` uses three short songs cut from `clean.mp3` (`tb/make_songs.py`, called by
`run_vcs.sh`) stored at sectors 100/300/500, bouncing keys and a short debounce time.
It checks: next / previous song start sector and consecutive sector reads, wrap-around in
both directions, restart from the middle of a song, end-of-file advance (and wrap), two quick
presses = two songs, and identical PCM for song 0 at boot and after the wrap-around.
