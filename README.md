# uCDD (Micro CD Drive)

uCDD is a virtual CD drive for DOS. The aim is a tool similar in use to Daemon Tools or CloneCD, with a small resident memory footprint and CD-Audio playback from disc images.

## Status

The prototype mounts ISO data images and single-file CUE/BIN images from a local hard disk. CUE images can contain a MODE1/2352 data track followed by audio tracks. DOS programs can read and copy files through the assigned CD drive letter. Tests use FreeDOS 1.4 and SHSUCDX 3.09.

The resident audio build runs an unmodified DOS Quake 1.06 executable with CD music and game sound through the same SB16. Quake selects its map track through the virtual CD drive. The audio service reads the BIN file into a 512 KiB XMS queue and mixes it with Quake's Sound Blaster output. It supports CD seek, play, stop, resume, head position, Q-channel position, status, and channel volume requests.

The experimental resident build puts the CD driver, mixer, port interception, and uCDD's own protected-mode host in `UCDD.EXE`. It installs before an image is mounted and lets the user start Quake directly. A test loads both resident blocks high, copies the installer archive, runs Quake twice, and unmounts and remounts the image between runs. Both runs pass music and game-sound capture checks. HDPMI32i, QPIEMU, JLOAD, and separate game launchers are not required. The tested memory manager is Jemm 5.86. Support for Microsoft HIMEM/EMM386 and 386MAX remains incomplete.

An interpreted Pentium test loads the start map, plays and loops a real music excerpt, plays a game sound, and exits. Captures check the complete 12-second music excerpt and the complete game sound. A separate test copies and checks the 24,684,755-byte installer archive through the mounted image. These tests use unchanged game files supplied by the tester. No game data is distributed.

The resident build stays installed after the game exits. It refills during CD requests and from a guarded timer service. The timer checks that DOS, critical-error handling, BIOS disk access, and the CD driver are idle before reading. Each background refill reads at most 32 KiB. An empty buffer or a read error stops the CD source.

A user has reported successful standalone BIN playback and Quake with shared CD music and game sound on a real DOS PC using SHSUCDX and the earlier external-host launcher. The driver also loaded into upper memory. The new internal host still needs real-hardware testing. Long gameplay sessions and broad MS-DOS compatibility remain unverified.

In the same hardware test, MSCDEX mounted the image and allowed file access, but Quake had no CD audio and the service reported `The CD image read failed.` after the game exited. Use SHSUCDX for the current Quake experiment. The cause of the MSCDEX audio failure is not yet established.

The internal-host compatibility checks also cover Daggerfall startup with CauseWay and a forced-DPMI DOS/32A configuration, plus Ultima VIII gameplay, normal exit, and CD file checks. Ultima VIII selects VCPI directly, so its result establishes coexistence rather than use of the internal DPMI interface. The 3dfx Tomb Raider build starts a new game in Caves with CD audio and game sound through the same SB16, then exits normally in a Pentium dynarec test. The capture verifies 23 seconds of continuous CD samples mixed with its unsigned 8-bit stereo output. It also checks the Sound Blaster command that stops auto-init playback at the end of a block.

The mixer accepts the legacy Sound Blaster single-cycle and auto-init DMA playback commands, SB Pro stereo commands, SB16 PCM commands, and WSS linear PCM playback. Game input and physical output are independent: a game configured for Sound Blaster can use WSS output, and a WSS game can use Sound Blaster output. The virtual Sound Blaster resources remain A220, IRQ 5, DMA 1 and 5. The virtual WSS codec is at 530h with DMA 1; Tomb Raider selects IRQ 11 through its board configuration. Recording and compressed game PCM are not supported.

Tomb Raider also completes with SB Pro and WSS game settings, including CD music and sound effects. Tests cover SB16 input to WSS output, WSS input to SB16 and WSS output, and SB Pro input to SB16 and SB Pro output. The SB Pro capture uses wider sample bounds for its 8-bit conversion. These new card paths have emulator coverage and still need real-card tests.

Original SB, SB1.5, and SB2 share an 8-bit mono output backend. It uses single-cycle DSP commands and does not access Pro/16 mixer registers. Game DMA playback supports odd-sized and 64 KiB single-cycle blocks, chained transfers, pause/resume, and speaker control. Real-mode and 32-bit DPMI test clients mix chained PCM with both CD channels through each output. Captures check for missing sources and gaps at block boundaries. These tests pass on the interpreted Pentium profile; the tested 386 profile misses refill deadlines under this workload.

On physical IRQ 5, uCDD keeps the game vector separate through DOS and DPMI vector services. Programs that write that IVT entry directly can bypass this protection; use physical IRQ 7 for those programs. Direct DAC commands, recording, and compressed ADPCM game playback are not implemented. This is DMA PCM compatibility, not complete Sound Blaster hardware emulation.

## Requirements and estimates

| Item | Current requirement or planning estimate |
| --- | --- |
| Processor | 386 or later for the instruction set. For games with mixed CD audio, budget a Pentium-class CPU initially. This is a planning estimate, not a measured minimum. |
| DOS | DOS 5 or later interfaces. FreeDOS 1.4 is tested. |
| CD driver memory | 9,264 resident bytes with one unit under FreeDOS. The complete driver can load into upper memory in the tested Jemm configuration. SHSUCDX and the memory manager use additional memory. |
| Resident audio, one unit | 32,112 bytes for the driver/mixer and 61,216 bytes for the internal host. Both blocks load high in the test. A separate 8 KiB conventional allocation supplies the aligned 4 KiB DMA ring: 101,520 resident DOS bytes in total, of which 8 KiB remain conventional in the tested high-memory configuration. SHSUCDX and the memory manager use additional memory. |
| SB / SB1.5 / SB2 conventional memory | A 512-byte mono DMA ring uses a 1 KiB conventional allocation. The resident code blocks load high. |
| SB Pro conventional memory | Its aligned 1 KiB DMA ring uses a 2 KiB conventional allocation. The same driver and host blocks load high in the test. |
| Extended memory | A 512 KiB XMS audio queue, plus 12 KiB of private stacks and allocation records while a protected client is active. Client memory and VCPI page tables use additional extended memory. The Quake test machine has 16 MiB. |
| Sound card | SB / SB1.5 / SB2 at about 22.22 kHz, 8-bit mono; SB16 or WSS at 44.1 kHz, 16-bit stereo; SB Pro at its nominal 22.05 kHz, 8-bit stereo setting. The SB Pro time constant gives about 21.74 kHz; CD conversion compensates for that clock. |
| Port trapping | The resident experiment uses Jemm 5.86's real-mode interface and uCDD's own VCPI/DPMI host. General game support remains unverified. |
| Image storage | A 60-minute uncompressed CD audio image uses about 635 MB (606 MiB). Data images vary with their contents. |
| Audio reads | Uncompressed CD audio requires 176,400 source bytes per second, plus the game's disk reads. Output downsampling does not reduce the image size or source read rate. |

Audio conversion, port trapping, and game execution share the CPU. Disk seeks and refill delays also matter. Real-hardware tests are required to establish supported processor speeds and buffer sizes. The interpreted emulator test does not establish real-386 performance.

The audio queue uses the standard XMS allocation, move, and free calls. HIMEM.SYS compatibility is a target and has not yet been tested. HIMEM alone does not supply the port-trapping interface used by the audio service or the upper-memory blocks used by `LH`. The data driver does not require XMS or port trapping.

[Jemm's documentation](https://github.com/Baron-von-Riedesel/Jemm/blob/master/Readme.txt) supports HIMEM.SYS followed by JEMM386 as an alternative to JEMMEX. That combination remains untested with uCDD. Do not load a separate HIMEM with JEMMEX, which includes its own XMS manager.

## Build

Use NASM and Python 3.10 or later:

```text
python scripts/build.py
```

The DOS programs are `build/UCDD.EXE` and `build/UCDDSET.EXE`. They require a 386 or later processor. The default `UCDD.EXE` installs the CD data driver and handles mount and unmount commands. The driver uses the DOS 5 or later swappable data area interface. Use the resident audio build below to include the mixer.

The build also creates `build/UCDDSET.EXE`, a transient sound setup tool. It saves the physical card settings to `UCDD.CFG` in the current directory. Saved settings take priority over initial suggestions from `BLASTER`. The CD data driver does not need this file. The Quake audio service requires saved settings.

Use the arrow keys to select and change a setting. F10 saves and exits; Esc exits without saving further changes. Select Sound Blaster / 1.5 / 2, SB Pro, SB16, or WSS. SB cards use I/O addresses 220h/240h/260h/280h, IRQ 5 or 7, and 8-bit DMA 1 or 3. SB16 also uses 16-bit DMA 5, 6, or 7. The initial physical WSS backend supports addresses 530h/604h/E80h/F40h, IRQ 7, and DMA 1 or 3. Configure the actual card with its jumpers or vendor utility first; the setup fields must match it.

F2 saves the settings and runs the built-in sound test for the selected card. It plays the left speaker for about 1.1 seconds, pauses for about 0.37 seconds, then plays the right speaker for about 1.1 seconds. The other channel stays silent on stereo cards. On original SB cards, both test tones use the mono output. The test returns to the setup screen and can be repeated. It needs no separate test program, Jemm, QPIEMU, or DPMI host. The test releases its DMA allocation when it stops: 8 KiB for SB16/WSS, 2 KiB for SB Pro, or 1 KiB for original SB.

Run the sound test before installing resident audio. If resident uCDD audio is active, F2 asks you to restart DOS before testing. F10 can still save settings for the next boot.

## Boot setup

Copy both programs to a directory on the DOS hard disk. Add these lines to `AUTOEXEC.BAT`, using the correct program paths:

```dos
C:\UCDD\UCDD.EXE -install
C:\DOS\SHSUCDX.COM /D:UCDD0001 /L:F
```

This example creates one virtual unit and assigns F:. The driver supports one to four units; use `UCDD -install -units 2` to create two. Install it once per boot, before SHSUCDX. Restart DOS to change the number of units. Running `UCDD` without arguments shows usage and does not install a driver.

Each unit can be empty or hold one disc image. Unmounting ejects the image but keeps the unit and its drive letter. Mount and unmount commands run in a temporary copy of `UCDD.EXE` and communicate with the installed driver.

The one-unit driver used 9,264 resident bytes in the FreeDOS test. With upper memory available, `LH C:\UCDD\UCDD.EXE -install` loaded the complete driver above conventional memory and passed the same tests. Installation and mount-command code are discarded after installation. This measurement excludes the audio service. SHSUCDX uses additional memory.

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

An explicit letter must identify a uCDD drive. Both `G` and `G:` are accepted. Close all files on a drive before changing its image. A locked drive cannot be changed. The earlier external audio launcher also locks its image while it runs. The resident build permits image changes and stops the old CD source when its image is ejected. A rejected replacement leaves the current image mounted.

Commands return exit code 0 on success and 1 on failure. Use DOS paths and 8.3 file names. Images on CD drives, floppy drives, and network drives are not supported. ISO images must use 2048-byte data sectors. CUE sheets must name one BINARY file, with sequential tracks and INDEX 01 for each track. INDEX 00 is supported. Multi-file sheets, MODE2 sectors, compressed audio, FLAGS, and synthetic PREGAP commands are not supported. Image files must be smaller than 2 GiB.

## Resident audio experiment

Build the two uCDD programs with:

```text
python scripts/build.py --resident-audio
```

This experimental build supports one unit with original SB, SB Pro, SB16, or WSS output. Install Jemm 5.86 and SHSUCDX separately. Save the physical card settings with `UCDDSET` before installing the driver. The settings stay in `UCDD.CFG` across boots. Keep that file in the directory from which you install uCDD.

Example `CONFIG.SYS` for native DOS, using your installed Jemm path:

```dos
DEVICE=C:\DOS\JEMMEX.EXE NOEMS
DOS=HIGH,UMB
FILES=64
LASTDRIVE=Z
```

FreeDOS uses `FDCONFIG.SYS` if that file is present. Example `AUTOEXEC.BAT`:

```dos
CD \UCDD
LH C:\UCDD\UCDD.EXE -install
IF ERRORLEVEL 1 GOTO UCDDERR
C:\DOS\SHSUCDX.COM /D:UCDD0001 /L:F
IF ERRORLEVEL 246 GOTO UCDDERR
SET BLASTER=A220 I5 D1 H5 T6
GOTO UCDDDONE
:UCDDERR
ECHO The uCDD setup failed.
:UCDDDONE
```

Mount an image with `UCDD -mount C:\IMAGES\QUAKE.CUE`, then install or start the game normally. There is no game launcher or audio program to copy into the game directory. The saved settings select the physical card; the BLASTER line selects the virtual resources used by games. The data-only build remains the default while the resident build's host support and refill mechanism are developed.

The internal host supports one active 32-bit DPMI client, descriptor and memory services, real-mode calls and callbacks, protected interrupts, and exception returns. It is a tested subset of DPMI 0.9, not a general replacement for every DOS extender. Sixteen-bit DPMI clients, nested clients, nested callbacks, and general copied-stack real-mode calls are unsupported. Games that select VCPI directly can bypass the protected audio interception. Do not install another DPMI host before resident uCDD; installation rejects an existing host.

## Tests

See [tests/README.md](tests/README.md) for the FreeDOS guest tests and the optional Quake data check.

## License and external components

Copyright (C) 2026 vorvek. uCDD source code, build and test scripts, and documentation are licensed under [GNU GPL version 3 only](LICENSE) (`GPL-3.0-only`). uCDD is supplied without warranty; see the license for its terms.

External tools retain their own licenses. uCDD packages do not include DOS, memory managers, port-trapping hosts, CD redirectors, sound-card initialization tools, or game files. Install the required tools separately:

- [Jemm 5.86](https://github.com/Baron-von-Riedesel/Jemm/releases/tag/v5.86): JEMMEX for the tested resident setup.
- [SHSUCDX](http://adoxa.altervista.org/shsucdx/): the CD redirector. Tests use version 3.09 from suite 3-7.

The test runners download or use private local copies of their dependencies. These copies are excluded from the source repository and distribution packages.

Historical comparison tests use QPIEMU/JLOAD and [HDPMI32i from SBEMU beta 6](https://github.com/crazii/SBEMU/releases/tag/Release_1.0.0-beta.6). Those tools are not dependencies of the internal-host resident build.
