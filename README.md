# uCDD (Micro CD Drive)

uCDD is a virtual CD drive for DOS. The aim is a tool similar in use to Daemon Tools or CloneCD, with a small resident memory footprint and CD-Audio playback from disc images.

## Status

The prototype mounts ISO data images and single-file CUE/BIN images from a local hard disk. CUE images can contain a MODE1/2352 data track followed by audio tracks. DOS programs can read and copy files through the assigned CD drive letter. Tests use FreeDOS 1.4 and SHSUCDX 3.09.

`UCDDAUD.COM` runs an unmodified DOS Quake 1.06 executable with CD music and game sound through the same SB16. Quake selects its map track through the virtual CD drive. The audio service reads the BIN file into a 512 KiB XMS queue and mixes it with Quake's virtual Sound Blaster output. It supports CD play, stop, resume, status, and channel volume requests.

An interpreted Pentium test loads the start map, plays and loops a real music excerpt, plays a game sound, and exits. Captures check the complete 12-second music excerpt and the complete game sound. A separate test copies and checks the 24,684,755-byte installer archive through the mounted image. These tests use unchanged game files supplied by the tester. No game data is distributed.

The current audio service runs for the lifetime of the launched game. It refills during foreground CD requests; Quake normally polls playback status four times per second. It is not yet a general background audio TSR. Games that do not poll often enough need another refill mechanism. An empty buffer or a read error stops the CD source and reports an error when the game exits.

A user has reported successful standalone BIN playback on a real DOS PC. Shared audio on hardware, long gameplay sessions, other games, general MS-DOS compatibility, and MSCDEX compatibility remain unverified. The standalone `UCDDPLAY.COM` test and the synthetic audio tests remain available.

## Requirements and estimates

| Item | Current requirement or planning estimate |
| --- | --- |
| Processor | 386 or later for the instruction set. For games with mixed CD audio, budget a Pentium-class CPU initially. This is a planning estimate, not a measured minimum. |
| DOS | DOS 5 or later interfaces. FreeDOS 1.4 is tested. |
| CD driver memory | 9,248 resident bytes with one unit under FreeDOS. The complete driver can load into upper memory in the tested Jemm configuration. SHSUCDX and the memory manager use additional memory. |
| Audio memory | The Quake service uses a 512 KiB XMS queue, a 4 KiB disk staging buffer, a 2 KiB mixing buffer, and an 8 KiB conventional allocation for its aligned 4 KiB DMA ring. Its code and staging buffers can load high. The DPMI launcher, environments, SHSUCDX, and memory manager use additional memory. The test machine has 16 MiB. |
| Sound card | The first audio experiment uses SB16 output at 44.1 kHz, 16-bit stereo. SB Pro-compatible output at 22.05 kHz, 8-bit stereo is planned. |
| Port trapping | The audio experiment requires Jemm with QPIEMU. The protected-mode test also requires HDPMI32i. General game support remains unverified. |
| Image storage | A 60-minute uncompressed CD audio image uses about 635 MB (606 MiB). Data images vary with their contents. |
| Audio reads | Uncompressed CD audio requires 176,400 source bytes per second, plus the game's disk reads. Output downsampling does not reduce the image size or source read rate. |

Audio conversion, port trapping, and game execution share the CPU. Disk seeks and refill delays also matter. Real-hardware tests are required to establish supported processor speeds and buffer sizes. The interpreted emulator test does not establish real-386 performance.

## Build

Use NASM and Python 3.10 or later:

```text
python scripts/build.py
```

The DOS programs are `build/UCDDRV.EXE` and `build/UCDD.EXE`. They require a 386 or later processor. The driver uses the DOS 5 or later swappable data area interface.

The build also creates `build/UCDDSET.EXE`, a transient sound setup tool. It saves the physical card settings to `UCDD.CFG` in the current directory. Saved settings take priority over initial suggestions from `BLASTER`. The CD data driver does not need this file. The Quake audio service requires saved settings.

Use the arrow keys to select and change a setting. F10 saves and exits; Esc exits without saving further changes. The current choices are SB16 or SB Pro, I/O addresses 220h/240h/260h/280h, IRQ 5 or 7, 8-bit DMA 1 or 3, and 16-bit DMA 5, 6, or 7. SB Pro output remains unavailable in this build.

For the experimental SB16 sound test, run `python scripts/build_audio.py` and place `UCDDTST.COM` beside `UCDDSET.EXE` in the current directory. Load Jemm and QPIEMU first. F2 saves the settings and plays the left speaker for about 1.1 seconds, pauses, then plays the right speaker for about 1.1 seconds. The other channel stays silent. The test is not resident.

## Boot setup

Copy both programs to a directory on the DOS hard disk. Add these lines to `AUTOEXEC.BAT`, using the correct program paths:

```dos
C:\UCDD\UCDDRV.EXE
C:\DOS\SHSUCDX.COM /D:UCDD0001 /L:F
```

This example creates one virtual unit and assigns F:. The driver supports one to four units; use `-units 2` to create two. Install it once per boot, before SHSUCDX. Restart DOS to change the number of units.

Each unit can be empty or hold one disc image. Unmounting ejects the image but keeps the unit and its drive letter. The helper runs only while it processes a command.

The one-unit driver used 9,248 resident bytes in the FreeDOS test. With upper memory available, `LH C:\UCDD\UCDDRV.EXE` loaded the complete driver above conventional memory and passed the same tests. This measurement excludes the audio service. SHSUCDX uses additional memory.

## Mount and unmount

```dos
ucdd.exe -mount c:\images\disc.cue
ucdd.exe -unmount
ucdd.exe -mount c:\images\disc.iso -drive G
ucdd.exe -unmount -drive G
```

| Command | Drive selection | Action |
| --- | --- | --- |
| `-mount <image>` | First empty uCDD drive | Mount the image. |
| `-unmount` | First uCDD drive with an image mounted | Unmount the image. |
| `-mount <image> -drive <letter>` | Specified uCDD drive | Mount the image, replacing any mounted image. |
| `-unmount -drive <letter>` | Specified uCDD drive | Unmount its image. |

Automatic selection uses ascending drive-letter order and considers only uCDD drives. If all units hold images, an automatic mount displays `All uCDD drives are in use.` and fails. It does not replace an image or create another unit.

An explicit letter must identify a uCDD drive. Both `G` and `G:` are accepted. Close all files on a drive before changing its image. A locked drive, or a drive attached to the running audio service, cannot be changed. A rejected replacement leaves the current image mounted.

Commands return exit code 0 on success and 1 on failure. Use DOS paths and 8.3 file names. Images on CD drives, floppy drives, and network drives are not supported. ISO images must use 2048-byte data sectors. CUE sheets must name one BINARY file, with sequential tracks and INDEX 01 for each track. INDEX 00 is supported. Multi-file sheets, MODE2 sectors, compressed audio, FLAGS, and synthetic PREGAP commands are not supported. Image files must be smaller than 2 GiB.

## Quake audio experiment

Build with `python scripts/build_audio.py`. Boot native DOS with JemmEx, QPIEMU, and HDPMI32i. Install one uCDD unit and SHSUCDX as shown above. The virtual drive must be the first CD drive, because Quake selects the first CD drive that DOS reports.

Mount the original CUE sheet from DOS. For example:

```dos
C:\UCDD\UCDD.EXE -mount C:\IMAGES\QUAKE.CUE
F:
INSTALL
```

Use the installer on your disc. If it starts Quake at the end, quit that first run. Copy `UCDDAUD.COM`, `UCDDPM.COM`, and the saved physical-card `UCDD.CFG` into the installed game directory. Keep both the CUE and its BIN file on the local hard disk.

From the game directory, set the virtual resources that Quake will use and start the audio service:

```dos
SET BLASTER=A220 I5 D1 H5 T6
LH UCDDAUD.COM
```

The saved `UCDD.CFG` selects the actual card's resources; the virtual BLASTER values above stay fixed. The launcher starts `QUAKE.EXE` in the current directory. It attaches to the first mounted uCDD CUE image and detaches when Quake exits. Use `UCDDSET` before this step to save the actual SB16 settings. Restore your normal BLASTER line before starting other audio programs.

The audio parent can load high. DMA allocations and the game's DOS allocations are kept in conventional memory. The DPMI launcher is still a separate temporary program; complete upper-memory audio residency is not yet established. The 512 KiB queue holds about 2.97 seconds of CD audio. Avoid Quake's `-cdmediacheck` option, which reduces its normal status polling rate.

## Tests

See [tests/README.md](tests/README.md) for the FreeDOS guest tests and the optional Quake data check.
