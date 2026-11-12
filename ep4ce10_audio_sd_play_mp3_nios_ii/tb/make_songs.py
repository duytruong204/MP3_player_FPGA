#!/usr/bin/env python3
"""Cut three short test songs out of ../sd_image/clean.mp3 for tb_keys.sv.

Each song starts at a real MPEG frame boundary and is cut to a whole number
of 512-byte sectors.  Songs 1 and 2 start in the middle of the file, so
their first frame(s) use bit-reservoir bytes that are missing - the decoded
audio of those frames is wrong, which does not matter here: the test only
needs three different, deterministic songs.

  song 0 : start of the file          16 sectors (about 0.5 s)
  song 1 : frames from ~ frame 2000    6 sectors
  song 2 : frames from ~ frame 4000    4 sectors

Output: tb/out/song0.mp3, song1.mp3, song2.mp3
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "sd_image", "clean.mp3")
OUT = os.path.join(HERE, "out")

BITRATES = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0]
SAMPLE_RATES = [44100, 48000, 32000, 0]

SONGS = [(0, 16), (2000, 6), (4000, 4)]      # (first frame index, sectors)


def frames(data, limit):
    """Yield (offset, length, main_data_begin) of consecutive MPEG1 layer III frames."""
    pos = 0
    while pos + 4 <= len(data) and pos < limit:
        h = data[pos:pos + 4]
        if h[0] != 0xFF or (h[1] & 0xE0) != 0xE0:
            raise SystemExit("lost frame sync at byte %d" % pos)
        if ((h[1] >> 3) & 3) != 3 or ((h[1] >> 1) & 3) != 1:
            raise SystemExit("not MPEG1 layer III at byte %d" % pos)
        crc = 2 if (h[1] & 1) == 0 else 0
        br = BITRATES[h[2] >> 4] * 1000
        sr = SAMPLE_RATES[(h[2] >> 2) & 3]
        pad = (h[2] >> 1) & 1
        length = 144 * br // sr + pad
        mdb = (data[pos + 4 + crc] << 1) | (data[pos + 5 + crc] >> 7)
        yield pos, length, mdb
        pos += length


def main():
    data = open(SRC, "rb").read()
    fr = list(frames(data, 3000000))
    os.makedirs(OUT, exist_ok=True)
    for i, (first, sectors) in enumerate(SONGS):
        k = first
        start = fr[k][0]
        chunk = data[start:start + sectors * 512]
        if len(chunk) != sectors * 512:
            raise SystemExit("source too short")
        with open(os.path.join(OUT, "song%d.mp3" % i), "wb") as f:
            f.write(chunk)
        print("song%d: frame %d (byte %d), %d sectors" % (i, k, start, sectors))
    return 0


if __name__ == "__main__":
    sys.exit(main())
