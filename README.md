# μCDD

**Eternal betaware**

μCDD is a virtual CD-ROM driver for DOS. It mounts disc images from a local hard disk and emulates CD-Audio on the same sound card the game already uses.

## How it works

`UCDD.EXE` installs as a DOS CD-ROM device named `UCDD0001`. A redirector such as [SHSUCDX](http://adoxa.altervista.org/shsucdx/) assigns it a drive letter. Later `-mount` and `-unmount` commands talk to that resident driver. The installer is discarded after load.

CD-Audio is mixed, not played on a second device. μCDD traps the game's sound-card I/O ports and DMA channel. When the game sends PCM, the driver mixes CD samples from the image into the same DMA buffer and outputs the mix on the physical card. A small internal host keeps those traps in place for protected-mode games.

The virtual Sound Blaster is fixed at `A220 I5 D1 H5`. It identifies as an SB16 (DSP 4.05) and accepts original Sound Blaster, Sound Blaster Pro, and SB16 PCM commands, so a game can be set to any of those types. Games can also use a virtual Windows Sound System codec at 530h.

`UCDDSET.EXE` stores the physical card (Sound Blaster / 1.5 / 2, SB Pro, SB16, or Windows Sound System) and its I/O address, IRQ, and DMA in `UCDD.CFG`. The game's card and the physical card do not have to match.

## Usage

A 386 or later, DOS 5 or later, and a CD redirector are required. CD-Audio also needs XMS and a memory manager that can trap I/O ports. [JEMMEX](https://github.com/Baron-von-Riedesel/Jemm) is the usual choice.

**Note:** CD-Audio Performance on anything below a Pentium processor may be lacklustre. Uncompressed audio requires around 800KB/s of constant read speed.

Copy `UCDD.EXE` and `UCDDSET.EXE` into one directory. Run `UCDDSET` before the first audio install. If there's no `UCDD.CFG` file, `UCDD -install` will start `UCDDSET` itself.

```dos
REM CONFIG.SYS
DEVICE=C:\DOS\JEMMEX.EXE NOEMS
DOS=HIGH,UMB
FILES=64
LASTDRIVE=Z
```

```dos
REM AUTOEXEC.BAT
LH C:\UCDD\UCDD.EXE -install
C:\DOS\SHSUCDX.COM /D:UCDD0001 /L:F
SET BLASTER=A220 I5 D1 H5 T6
```

`HIMEM` with `EMM386` and `MSCDEX` are also supported.

Install once per boot, before the redirector. `UCDD -install -units 2` creates two empty drives (1 to 4). Restart DOS to change the unit count. `LH` loads the resident driver into upper memory when UMBs are available (requires ~38KB of contiguous space).

Point Sound Blaster games at the virtual card (`BLASTER=A220 I5 D1 H5 T6`), not at the physical settings in `UCDD.CFG`. Windows Sound System games use port 530h. `BLASTER` does not move the virtual ports.

```dos
UCDD -mount C:\IMAGES\GAME.CUE
UCDD -mount C:\IMAGES\DATA.ISO -drive G
UCDD -unmount
UCDD -unmount -drive G
```

Without `-drive`, mount uses the first empty μCDD letter and unmount uses the first mounted one. Close files on a drive before you change its image. A locked drive cannot be changed.

`UCDD /?` and `UCDDSET /?` print command help.

### Multiple discs

Make a text file with a `.MDM` extension and one image path per line:

```text
DISC1.ISO
DISC2.CUE
DISC3.BIN
```

```dos
UCDD -mount C:\IMAGES\GAME.MDM
UCDD -unmount C:\IMAGES\GAME.MDM
```

The first disc is mounted. At the game's disc-change prompt, press **Ctrl+Alt+1** through **Ctrl+Alt+9** for discs 1 through 9, or **Ctrl+Alt+0** for disc 10. Left and right Ctrl/Alt both work. The number key still reaches the game. A held number selects its disc once. A number with no disc assigned does nothing.

Only one MDM file can be mounted at a time, on one virtual unit. The usual `-drive` selection applies. Mounting a single image over that unit releases the list. It can also be unmounted normally.

Paths may be absolute or relative to the MDM file. A CUE sheet's BIN path is relative to the CUE sheet. Nested MDM files are not supported. Blank lines and spaces at the start or end of a line are ignored. Only the first ten non-empty lines count.

All listed images are opened before the mount replaces the current disc. If a listed image is missing or invalid, the current image stays mounted. Give DOS enough file handles. If the drive is in use, μCDD waits, then applies the last requested disc. MDM files require XMS.

### Images

Use DOS 8.3 names on a local hard disk. Image files must be smaller than 2 GiB. Images on CD, floppy, or network drives are not supported.

| Format | Notes |
| --- | --- |
| `.ISO` | 2048-byte data sectors |
| `.CUE` / `.BIN` | One BINARY file, sequential tracks, INDEX 01 on each track. INDEX 00 is accepted |
| `.BIN` alone | MODE1/2352 data, no audio track table. Use a CUE sheet for CD-Audio |
| `.MDM` | Disc list, as above |

MODE2 sectors, compressed audio, FLAGS, synthetic PREGAP, and multi-file CUE sheets are not supported.

## Build

NASM and Python 3.10 or later:

```text
python scripts/build.py --resident-audio
```

That writes `build/UCDD.EXE` and `build/UCDDSET.EXE`. Omit `--resident-audio` for a data-only driver with no mixer.

## License

Copyright (C) 2026 vorvek. μCDD is licensed under [GNU GPL version 3 only](LICENSE). No warranty; see the license for its terms.
