# uCDD (Micro CD Drive)

uCDD is a virtual CD drive for DOS. The aim is a tool similar in use to Daemon Tools or CloneCD, with a small resident memory footprint and CD-Audio playback from disc images.

## Status

The first prototype supports ISO data images on a local hard disk. It has been tested with FreeDOS 1.4 and SHSUCDX 3.09 in an interpreted 386 machine in IzarraVM.

CUE/BIN mounting and game-controlled Red Book playback are not implemented yet. MS-DOS, MSCDEX, and physical hardware compatibility have not been verified.

A separate audio experiment mixes CD-format audio with a test program's audio through the same SB16. Real-mode and 32-bit protected-mode test clients pass port trapping, DMA polling, sample-rate changes, and virtual DSP resets in an interpreted 386 machine. IRQ routing preserves physical card control when the protected-mode client installs its own handler. Captured output contains both signals. General game compatibility remains unverified.

The streaming experiment reads raw CD audio from a BIN file through a 16 KiB queue. A host tool selects an audio track from a single-file CUE sheet. Captures verify disk refills, the selected end, and simultaneous stereo test-client audio. `UCDDPLAY.COM` provides standalone playback for testing. Shared streaming currently requires a cooperative client to run foreground refills; it is not yet a resident service for unmodified games.

An interrupt-driven protected-mode client also passes virtual DMA completion, IRQ masking, DSP acknowledgement, and end-of-interrupt checks. CD output continues while the client masks its IRQ or delays acknowledgement. This test uses a 4 KiB output ring with a 512-frame interrupt period, about 11.6 ms at 44.1 kHz. General game compatibility remains unverified.

Further waveform tests preserve the opening samples and check live game-buffer refills across repeated ring cycles. Tested source rings are 2, 4, and 8 KiB, with separate completion blocks. Six starts at each of two physical card configurations measured 13.2 to 20.3 ms from the play command marker to captured output. These are emulator measurements, not physical-card latency results.

A separate launcher runs an unmodified DOS Quake 1.06 executable in its normal SB16 mode, with 16-bit stereo game audio and virtual DMA 5. The earlier 8-bit mono mode remains available as a test. In an interpreted Pentium machine, the test loads a level, plays a sound, and exits. The complete captured sound matches the original asset while the CD test signal continues through the same SB16. A separate interpreted-386 client checks stereo channel order, sample precision, DMA state, and live refills. These are limited integration tests, not general game compatibility; capture timing limits are documented in the test guide.

## Requirements and estimates

| Item | Current requirement or planning estimate |
| --- | --- |
| Processor | 386 or later for the instruction set. For games with mixed CD audio, budget a Pentium-class CPU initially. This is a planning estimate, not a measured minimum. |
| DOS | DOS 5 or later interfaces. FreeDOS 1.4 is tested. |
| ISO driver memory | 7,088 resident bytes with one unit under FreeDOS. The complete driver can load into upper memory in the tested Jemm configuration. SHSUCDX and the memory manager use additional memory. |
| Audio memory | Streaming uses a 16 KiB source queue and a 4 KiB output ring, with an 8 KiB allocation for DMA alignment. Code, stacks, and the memory manager use additional memory. These temporary DOS allocations do not establish the final resident footprint. The test machine has 16 MiB. |
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

The build also creates `build/UCDDSET.EXE`, a transient sound setup tool. It saves the physical card settings to `UCDD.CFG` in the current directory. Saved settings take priority over initial suggestions from `BLASTER`. The ISO driver does not need this file.

Use the arrow keys to select and change a setting. F10 saves and exits; Esc exits without saving further changes. The current choices are SB16 or SB Pro, I/O addresses 220h/240h/260h/280h, IRQ 5 or 7, 8-bit DMA 1 or 3, and 16-bit DMA 5, 6, or 7. SB Pro output remains unavailable in this build.

For the experimental SB16 sound test, run `python scripts/build_audio.py` and place `UCDDTST.COM` beside `UCDDSET.EXE` in the current directory. Load Jemm and QPIEMU first. F2 saves the settings and plays a tone through each channel. The test is not resident. Hardware compatibility remains unverified.

## Boot setup

Copy both programs to a directory on the DOS hard disk. Add these lines to `AUTOEXEC.BAT`, using the correct program paths:

```dos
C:\UCDD\UCDDRV.EXE
C:\DOS\SHSUCDX.COM /D:UCDD0001 /L:F
```

This example creates one virtual unit and assigns F:. The driver supports one to four units; use `-units 2` to create two. Install it once per boot, before SHSUCDX. Restart DOS to change the number of units.

Each unit can be empty or hold one disc image. Unmounting ejects the image but keeps the unit and its drive letter. The helper runs only while it processes a command.

The one-unit driver used 7,088 resident bytes in the FreeDOS test. With upper memory available, `LH C:\UCDD\UCDDRV.EXE` loaded the complete driver above conventional memory and passed the same tests. This measurement excludes audio support. SHSUCDX uses additional memory.

## Mount and unmount

```dos
ucdd.exe -mount c:\images\disc.iso
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

An explicit letter must identify a uCDD drive. Both `G` and `G:` are accepted. Close all files on a drive before changing its image. A locked drive cannot be changed. A rejected replacement leaves the current image mounted.

Commands return exit code 0 on success and 1 on failure. Use DOS paths and 8.3 file names. Images on CD drives, floppy drives, and network drives are not supported. ISO images must use 2048-byte data sectors and be smaller than 2 GiB.

## Tests

See [tests/README.md](tests/README.md) for the FreeDOS guest tests and the optional Quake data check.
