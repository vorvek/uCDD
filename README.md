# uCDD (Micro CD Drive)

uCDD is a virtual CD drive for DOS. The aim is a tool similar in use to Daemon Tools or CloneCD, with a small resident memory footprint and CD-Audio playback from disc images.

## Status

The first prototype supports ISO data images on a local hard disk. It has been tested with FreeDOS 1.4 and SHSUCDX 3.09 in an interpreted 386 machine in IzarraVM.

CUE/BIN support and Red Book CD-Audio playback are not implemented yet. MS-DOS, MSCDEX, and physical hardware compatibility have not been verified.

## Build

Use NASM and Python 3.10 or later:

```text
python scripts/build.py
```

The DOS programs are `build/UCDDRV.EXE` and `build/UCDD.EXE`. They require a 386 or later processor. The driver uses the DOS 5 or later swappable data area interface.

## Boot setup

Copy both programs to a directory on the DOS hard disk. Add these lines to `AUTOEXEC.BAT`, using the correct program paths:

```dos
C:\UCDD\UCDDRV.EXE -units 2
C:\DOS\SHSUCDX.COM /D:UCDD0001 /L:F
```

This example creates two virtual units and assigns F: and G:. The driver supports one to four units. Install it once per boot, before SHSUCDX. Restart DOS to change the number of units.

Each unit can be empty or hold one disc image. Unmounting ejects the image but keeps the unit and its drive letter. The helper runs only while it processes a command.

The two-unit driver used 7,104 resident bytes in the FreeDOS test. SHSUCDX uses additional memory.

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
