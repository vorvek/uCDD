# DOS tests

Install NASM and Python 3.10 or later. Build IzarraVM separately. The initial tests use 386 mode, the interpreter, and 16 MiB of memory.

```powershell
python scripts/fetch_test_deps.py
python scripts/build.py
python scripts/test_dos.py --emulator D:\dev\IzarraVM\target\release\izarravm.exe --baseline
python scripts/test_dos.py --emulator D:\dev\IzarraVM\target\release\izarravm.exe
```

The dependency script downloads the FreeDOS 1.4 LiteUSB archive and SHSUCD suite 3-7. It checks both archives against pinned SHA-256 values. The FreeDOS hash comes from the distribution's published verification file. The SHSUCD hash pins the suite archive used for these tests.

The test runner creates a disposable FAT16 disk from the FreeDOS image. It copies the stock kernel and command interpreter into that disk, then adds the test programs and images. It does not modify the source archive or a physical disk.

The baseline checks that no CD extensions are installed, loads SHSUCDHD and SHSUCDX, and reads a generated ISO. The uCDD test checks the same initial state, then loads UCDDRV and SHSUCDX.

The tests cover automatic and explicit drive selection, the full-drive error text, image replacement, invalid images, empty drives, repeated commands, and immediate cache updates. Packet tests cover a 128 KiB transfer across a segment boundary, PSP and DTA restoration, invalid requests, buffer bounds, and drive locking. A guest program reports success or failure through IzarraVM's test device.

Downloads, disk images, logs, and hash records are stored under `.local/`, which is Git-ignored. Built DOS programs are under `build/`, which is also Git-ignored. FreeDOS, SHSUCD, and game files are not included in this repository.

## Optional Quake data check

For a Quake BIN image with a MODE1/2352 data track:

```powershell
python scripts/test_dos.py --emulator D:\dev\IzarraVM\target\release\izarravm.exe --quake-bin C:\images\Quake.bin
```

The runner extracts a temporary ISO from the data track and selects the largest file in its root directory. A DOS program reads that file through uCDD and checks its CRC32 against the source bytes. The source BIN is opened read-only.

This checks real disc data through the ISO driver. It does not test CUE parsing, game execution, or CD-Audio playback.
