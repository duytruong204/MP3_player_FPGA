#!/bin/bash
# Compile and run a testbench with Synopsys VCS.
#   ./run_vcs.sh tb_audio_sd_play_mp3 [+FRAMES=22050 ...]
#   ./run_vcs.sh tb_codec_input
#   ./run_vcs.sh tb_keys           (push buttons: song change)
# The simulation runs from quartus_prj/ because the decoder RAM init files
# are referenced relative to the Quartus project directory.
set -e
TB=${1:-tb_audio_sd_play_mp3}; shift || true
HERE=$(cd "$(dirname "$0")" && pwd)
export VCS_HOME=${VCS_HOME:-/global/apps/vcs_2023.12-SP2-10}
SIMLIB=${ALTERA_SIMLIB:-/global/apps/quartus_6.0/linux/eda/sim_lib}   # altera_mf.v (altsyncram), 220model.v (lpm_mult)
R=$HERE/../rtl
GOLD=$HERE/../../ep4ce10_audio_sd_play_wav/rtl
mkdir -p $HERE/out $HERE/build
# The Quartus 6.0 altera_mf model does not know the Cyclone IV E settings; simulate a copy of the
# decoder sources with the family string of the original (Cyclone II).  RAM contents/behaviour are identical.
SIMMP3=$HERE/build/mp3_sim
rm -rf $SIMMP3; mkdir -p $SIMMP3; cp -r $R/mp3/*.v $R/mp3/newhuff $R/mp3/mac_unit $SIMMP3/
find $SIMMP3 -name '*.v' | xargs sed -i 's/"Cyclone IV E"/"Cyclone II"/g'
if [ "$TB" = tb_keys ]; then python3 $HERE/make_songs.py; fi
cd $HERE/../quartus_prj
MP3=$(cd $SIMMP3 && ls *.v newhuff/*.v mac_unit/*.v | grep -v -E 'defines.v|huffctl_comb.v' | sed "s#^#$SIMMP3/#")
case $TB in
  tb_audio_sd_play_mp3|tb_keys)
    SRC="$R/sd/*.v $R/wm8978/*.v $R/pcm_out_ctrl.v $R/mp3_feeder.v $R/key_ctrl.v $R/pulse_sync.v $R/audio_sd_play_mp3.v $MP3 $HERE/models/clk_gen_model.v" ;;
  tb_codec_input)
    SRC="$R/wm8978/*.v $R/pcm_out_ctrl.v $HERE/models/fifo_data_model.v $GOLD/sd_play_ctrl.v" ;;
esac
$VCS_HOME/bin/vcs -full64 -sverilog -timescale=1ns/1ps -notice $VCS_EXTRA -top $TB -Mdir=$HERE/build/csrc_$TB -o $HERE/build/simv_$TB \
   +incdir+$SIMMP3 +incdir+$SIMMP3/newhuff +incdir+$SIMMP3/mac_unit \
   $SRC $SIMLIB/220model.v $SIMLIB/altera_mf.v $HERE/$TB.sv -l $HERE/build/compile_$TB.log
$HERE/build/simv_$TB "$@" -l $HERE/out/run_$TB.log
