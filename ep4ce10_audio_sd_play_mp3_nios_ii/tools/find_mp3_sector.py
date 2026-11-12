#!/usr/bin/env python3
"""Locate an MP3 file on a FAT16/FAT32 card (or card image) and print the
song table of audio_sd_play_mp3.v: NUM_SONGS, SONG_ADDRS and SONG_SECTORS.

Does exactly what the WinHex procedure does by hand:
  MBR (optional) -> boot sector -> data region -> root dir entry -> cluster
  -> absolute sector, and checks the file is stored in contiguous clusters.

Usage:
    find_mp3_sector.py <image-or-device> [NAME.MP3] [original.mp3]
      NAME.MP3     8.3 name in the root directory (default: ALL *.MP3 files in the
                   root directory, up to 8, in directory order = the order in
                   which they were copied to the card)
      original.mp3 optional: compare the bytes on the card with this file
Examples:
    find_mp3_sector.py card.img CLEAN.MP3 ../sd_image/clean.mp3
    find_mp3_sector.py /dev/sdX            (needs read permission)

The decoder is fed whole 512-byte sectors, 2 sectors per request, so
the sector count of each song is rounded UP to an even number (the few bytes after the end of
the file are harmless).
"""
import struct
import sys

SECTOR = 512
MAX_SONGS = 8       # table size of audio_sd_play_mp3.v


def rd(f, lba, n=1):
    f.seek(lba * SECTOR)
    return f.read(n * SECTOR)


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    path = sys.argv[1]
    want = sys.argv[2].upper() if len(sys.argv) > 2 else None
    orig = sys.argv[3] if len(sys.argv) > 3 else None

    f = open(path, "rb")
    s0 = rd(f, 0)
    part = 0
    if s0[0x36:0x3B] not in (b"FAT16", b"FAT12") and s0[0x52:0x57] != b"FAT32":
        # MBR: first partition entry
        part = struct.unpack_from("<I", s0, 0x1C6)[0]
        print("MBR: partition 1 starts at LBA %d (offset 0x1C6)" % part)
    else:
        print("sector 0 is a boot sector (no MBR)")
    vbr = rd(f, part)
    bps, spc, rsvd, nfat, root_ent = struct.unpack_from("<HBHBH", vbr, 0x0B)
    fatsz16 = struct.unpack_from("<H", vbr, 0x16)[0]
    fatsz32 = struct.unpack_from("<I", vbr, 0x24)[0]
    root_clus = struct.unpack_from("<I", vbr, 0x2C)[0]
    tot16 = struct.unpack_from("<H", vbr, 0x13)[0]
    tot32 = struct.unpack_from("<I", vbr, 0x20)[0]
    total = tot16 or tot32
    is32 = fatsz16 == 0
    fatsz = fatsz32 if is32 else fatsz16
    if bps != SECTOR:
        raise SystemExit("bytes/sector = %d, expected 512" % bps)
    root_secs = (root_ent * 32 + SECTOR - 1) // SECTOR
    fat_start = part + rsvd
    root_start = fat_start + nfat * fatsz
    data_start = root_start + root_secs
    print("type=%s spc=%d rsvd=%d nFAT=%d FATsz=%d rootEnt=%d"
          % ("FAT32" if is32 else "FAT16", spc, rsvd, nfat, fatsz, root_ent))
    print("PartStart=%d FATstart=%d DataStart=%d" % (part, fat_start, data_start))
    print("card size (this partition) = %.1f MB" % (total * SECTOR / 1e6))

    def clus2lba(c):
        return data_start + (c - 2) * spc

    def fat_next(c):
        if is32:
            off = c * 4
            e = struct.unpack_from("<I", rd(f, fat_start + off // SECTOR),
                                   off % SECTOR)[0] & 0x0FFFFFFF
            return e, 0x0FFFFFF8
        off = c * 2
        e = struct.unpack_from("<H", rd(f, fat_start + off // SECTOR),
                               off % SECTOR)[0]
        return e, 0xFFF8

    if is32:
        dir_sectors = [clus2lba(root_clus) + i for i in range(spc)]
    else:
        dir_sectors = [root_start + i for i in range(root_secs)]

    found = []
    for lba in dir_sectors:
        sec = rd(f, lba)
        for i in range(0, SECTOR, 32):
            e = sec[i:i + 32]
            if e[0] == 0x00:
                break
            if e[0] == 0xE5 or e[11] == 0x0F or e[11] & 0x08:
                continue
            name = e[0:8].decode("latin1").rstrip() + "." + \
                e[8:11].decode("latin1").rstrip()
            hi = struct.unpack_from("<H", e, 0x14)[0] if is32 else 0
            lo = struct.unpack_from("<H", e, 0x1A)[0]
            size = struct.unpack_from("<I", e, 0x1C)[0]
            found.append((name, (hi << 16) | lo, size))
    for n, c, s in found:
        print("  entry %-12s cluster=%d size=%d" % (n, c, s))

    if want is None:
        sel = [x for x in found if x[0].upper().endswith(".MP3")]
    else:
        sel = [x for x in found if x[0].upper() == want]
    if not sel:
        raise SystemExit("file not found in root directory")
    if len(sel) > MAX_SONGS:
        print("WARNING: %d MP3 files found, the table holds %d; using the first %d"
              % (len(sel), MAX_SONGS, MAX_SONGS))
        sel = sel[:MAX_SONGS]

    ok = True
    table = []
    for name, clus, size in sel:
        nclus = -(-size // (spc * SECTOR))
        chain, c = [clus], clus
        for _ in range(nclus - 1):
            c, _eoc = fat_next(c)
            chain.append(c)
        contiguous = all(chain[i + 1] == chain[i] + 1 for i in range(len(chain) - 1))
        init_addr = clus2lba(clus)
        print()
        print("file             = %s (%d bytes)" % (name, size))
        print("start cluster    = %d (%d clusters)" % (clus, nclus))
        print("contiguous       = %s" % contiguous)
        print("INIT_ADDR        = %d   (0x%X, byte offset 0x%X)"
              % (init_addr, init_addr, init_addr * SECTOR))
        mp3_sector = -(-size // SECTOR)
        mp3_sector += mp3_sector & 1
        print("MP3_SECTOR       = %d   (ceil(size/512), rounded up to even)" % mp3_sector)
        first = bytearray(rd(f, init_addr)[:4])
        if first[:3] == b"ID3":
            verdict = "ID3v2 tag - strip it first (decoder expects a frame sync at the start)"
            ok = False
        elif first[0] == 0xFF and (first[1] & 0xE0) == 0xE0:
            verdict = "OK (MPEG frame sync)"
        else:
            verdict = "NOT an MP3 frame sync - wrong sector?"
            ok = False
        print("first 4 bytes    = %s  %s" % (" ".join("%02x" % b for b in first), verdict))
        if orig and len(sel) == 1:
            ref = open(orig, "rb").read()
            got = bytearray()
            lba = init_addr
            while len(got) < len(ref):
                got += rd(f, lba)
                lba += 1
            same = bytes(got[:len(ref)]) == ref
            print("content check    = %s" % ("identical to " + orig if same else "DIFFERENT from " + orig))
            if not same:
                return 1
        if not contiguous:
            print("WARNING: %s is not contiguous. Re-format the card and copy the files one by one."
                  % name)
            ok = False
        table.append((name, init_addr, mp3_sector))

    # song table for rtl/audio_sd_play_mp3.v: song i occupies 32 bits of
    # SONG_ADDRS and 18 bits of SONG_SECTORS; song 0 is the LSB entry
    print()
    print("Song order (= KEY1 next / KEY2 previous, directory order):")
    for i, (name, a, n) in enumerate(table):
        print("  song %d : %s" % (i, name))
    addrs = ", ".join("32'd%d" % a for _, a, _n in reversed(table))
    secs = ", ".join("18'd%d" % n for _, _a, n in reversed(table))
    pad_a = 256 - 32 * len(table)
    pad_s = 144 - 18 * len(table)
    print()
    print("Edit rtl/audio_sd_play_mp3.v:")
    print("  parameter           NUM_SONGS    = %d;" % len(table))
    print("  parameter   [255:0] SONG_ADDRS   = {%s%s};"
          % ("%d'd0, " % pad_a if pad_a else "", addrs))
    print("  parameter   [143:0] SONG_SECTORS = {%s%s};"
          % ("%d'd0, " % pad_s if pad_s else "", secs))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
