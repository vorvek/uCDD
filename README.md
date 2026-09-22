# μCDD

**Eternal betaware**

μCDD is a virtual CD-ROM driver for DOS. It mounts disc images from a local hard disk and emulates CD-Audio on the same sound card the game already uses.

## Before you load the driver

- **Set `BLASTER` first.** Run `SET BLASTER=...` before `UCDD -install`, and use those settings in the game. The driver reads the virtual I/O address, IRQ, and DMA channels once, at installation. Changing `BLASTER` later does not change the loaded driver; restart DOS to use different settings.
- **Set up the physical card with `UCDDSET`.** It saves the card type, I/O address, IRQ, and DMA channels in `UCDD.CFG`. These are separate from the virtual settings in `BLASTER`. The game's settings and the physical card's settings can differ.
- **Do not load the audio driver for games that use ADPCM sound.** ADPCM is not supported or passed through. Its playback commands would conflict with the PCM output that μCDD uses to mix game sound and CD audio. Boot DOS without `UCDD -install` before playing those games. Unmounting an image does not unload the driver.

## How it works

`UCDD.EXE` installs as a DOS CD-ROM device. It requires a redirector such as [SHSUCDX](http://adoxa.altervista.org/shsucdx/) or MSCDEX to assign it a drive letter. The installer is discarded after load. Use `-mount` and `-unmount` to change the image in the resident driver.

μCDD traps the game's sound-card I/O and DMA access, converts its PCM sound, and mixes it with CD samples from the image. The physical sound card plays the combined stream. An internal host keeps the traps in place for protected-mode games.

The virtual Sound Blaster accepts original Sound Blaster, SB Pro, and SB16 PCM commands. It identifies as an SB16 (DSP 4.05); the `T` field does not change this. Games can also use a virtual Windows Sound System codec at 530h, with the same 8-bit DMA channel selected by `D`.

Supported `BLASTER` settings are `A220`, `A240`, `A260`, or `A280`; `I5` or `I7`; `D1` or `D3`; and `H5`, `H6`, or `H7`. Set `A`, `I`, and `D`. If `H` is absent, the driver uses `H5`. If `BLASTER` is absent, it uses `A220 I5 D1 H5`. Invalid settings stop installation.

## Usage

A 386 or later, DOS 5 or later, and a CD redirector are required. CD-Audio also needs XMS, VCPI, and a supported interface for I/O port traps. HIMEM alone does not provide these interfaces.

[JEMMEX](https://github.com/Baron-von-Riedesel/Jemm) 5.86 is the tested baseline. Beta 0.9.1 also supports the changed callback interface in 5.87pre1. Installation and real-mode and protected-mode audio clients passed with both versions in IzarraVM. The published 0.9.0 binary rejects 5.87pre1.

**Protected-mode game support is incomplete.** Beta 0.9.1 fixes protected-mode CD access, interrupt handling, and several mixed-audio faults. Tomb Raider passed a menu/demo audio check with the release driver in 86Box with 128 MB. Carmageddon and Archimedean Dynasty had successful mixed-audio checks during development; they were tested with earlier builds. These checks do not establish long-session stability or support for all DOS extenders. See [the release notes](RELEASE-NOTES.md) for test scope and known limits.

**Note:** CD-Audio Performance on anything below a Pentium processor may be lacklustre. Uncompressed audio requires around 800KB/s of constant read speed.

Copy `UCDD.EXE` and `UCDDSET.EXE` into one directory. Run `UCDDSET` before the first audio install. If there's no `UCDD.CFG` file, `UCDD -install` will start `UCDDSET` itself.

AUTOEXEC.BAT:
```dos
SET BLASTER=A220 I7 D1 H5 T6
LH C:\UCDD\UCDD.EXE -install
C:\DOS\SHSUCDX.COM /D:UCDD0001 /L:F
```

`HIMEM` with `EMM386` has passed limited tests. `JEMM386` and `386MAX` support is not established. `MSCDEX` can also assign the CD drive letter.

**Microsoft EMM386 and shared DMA:** EMM386's port-trapping interface cannot trap ports below `100h`, which includes the DMA controller registers. A game can therefore replace the DMA settings used for physical audio output. Archimedean Dynasty produced clicks followed by silence when both the game and the physical SB16 used 16-bit DMA channel 5.

Use JEMMEX, or select different 16-bit DMA channels for the physical output and the game. For example, physical DMA 7 with virtual DMA 5 avoided the menu audio failure in that test. Configure the physical card first, then enter its actual settings in `UCDDSET`. Set the virtual channel with `BLASTER` (`H5` in this example) before installing uCDD, and use those virtual settings in the game. Both streams still play through the same sound card. JEMMEX 5.87pre1 passed a bounded Archimedean Dynasty mission check with shared DMA 5; this does not establish all memory-manager or hardware combinations.

Install once per boot, before the redirector. `UCDD -install -units 2` creates two empty drives (1 to 4). Restart DOS to change the unit count. `LH` loads the resident driver into upper memory when UMBs are available (requires ~38KB of contiguous space).

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

Assembler sources are in `src/`. NASM is required.

## License

Copyright (C) 2026 vorvek. μCDD is licensed under [GNU GPL version 3 only](LICENSE). No warranty; see the license for its terms.
