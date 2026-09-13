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

## One unit and upper memory

```powershell
python scripts/test_dos.py --emulator D:\dev\IzarraVM\target\release\izarravm.exe --single-unit
python scripts/test_dos.py --emulator D:\dev\IzarraVM\target\release\izarravm.exe --single-unit --load-high
```

The single-unit run uses the driver's default unit count. It checks mounting, replacement, full-drive handling, repeated commands, and direct CD packets. The upper-memory run adds Jemm, starts the driver with `LH`, and checks that its resident segment is above conventional memory. Both runs report the size of the driver's DOS memory block. Download Jemm with the audio test runner before the upper-memory test.

## Shared-card audio experiment

```powershell
python scripts/test_audio.py --emulator D:\dev\IzarraVM\target\release\izarravm.exe --izarra-source D:\dev\IzarraVM
```

This runner downloads Jemm 5.86 from its upstream release and checks a pinned SHA-256 hash. It boots a separate FreeDOS disk with Jemm and QPIEMU. A small client sends SB16-style 8-bit mono auto-initialized DMA commands to virtual ports at 220h. It polls DMA position, changes between 22.05 and 11.025 kHz, and resets its virtual DSP. The client checks that its sample buffer was not changed.

The audio experiment owns the physical SB16 output, IRQ, and 16-bit DMA ring. An interrupt handler mixes a preloaded stereo signal with the client's samples. It does not call DOS from the audio interrupt. Tests also cover setup navigation, saved settings, BLASTER suggestions, the setup sound test, alternate IRQ/DMA settings, and rejection of invalid configuration files and unsupported output configurations.

With `--izarra-source`, the runner builds a separate capture executable against that checkout's public machine API. Rust and IzarraVM's native build dependencies are required. It does not change IzarraVM source. The capture machine uses interpreted 386 mode, disables WSS, and mounts no CD image. Audio is drained at short intervals from the emulated card's output. The host checks both CD marker frequencies, channel separation, the client's two rates, and continued CD output while the virtual DSP is reset. Logs, build hashes, a WAV file, and a setup-screen snapshot are stored under `.local/audio/`.

This is a bounded experiment, not a general sound emulator. It supports one client with a 4 KiB unsigned 8-bit mono source ring. Full PIC and mixer semantics and disc streaming remain unimplemented. The virtual interface remains at 220h while the physical output uses the saved settings. The preloaded CD signal and 32 KiB output ring use temporary DOS allocations. These allocations are not the final resident memory design.

## Protected-mode audio and IRQ ownership

```powershell
python scripts/test_audio_pm.py --izarra-source D:\dev\IzarraVM
```

This runner uses the same interpreted 386 capture machine. It adds HDPMI32i from the pinned SBEMU 1.0.0 beta 6 archive, verifies its SHA-256 hash, and extracts only the DPMI host. It does not load SBEMU or change IzarraVM source.

`APSHARE.COM` starts the physical audio backend and launches `APM.COM`, a 32-bit DPMI test client. HDPMI port traps call the existing real-mode virtual DSP through a temporary bridge. The client installs a competing protected-mode handler for the physical sound IRQ and reads back that vector. A separate HDPMI IRQ route retains control for the audio backend. The test requires 25 to 55 interrupts at that route and none at the competing handler.

The client polls DMA position, changes sample rates, resets its virtual DSP, and checks that its source buffer is unchanged. Host waveform checks cover both CD channels, both game rates, and CD playback during reset. Tests use physical IRQ 5 with DMA 1/5 and IRQ 7 with DMA 3/6. Each configuration runs the protected-mode client twice, then the real-mode client, to check trap and route cleanup. Waveform checks inspect the first protected-mode run in each capture.

A negative control clears IRQ routing and requires the competing handler to receive at least 25 card interrupts. That guest must fail with the specific IRQ-ownership message; an unrelated failure or timeout does not pass the control. Images, WAV files, logs, and hash records are stored under `.local/audio/protected/`.

This establishes a path for protected-mode port interception and physical IRQ ownership. It does not protect against real-mode vector replacement or establish compatibility with DOS extenders and games. The mode-switching bridge is test code, not the planned resident audio service.

## Virtual DMA interrupts and PIC handling

The same protected-mode runner also tests `AISHARE.COM` with `AIPM.COM`. This client uses completion interrupts instead of DMA-position polling. It installs a handler at virtual IRQ 5 while the physical output uses IRQ 5 or IRQ 7. The backend keeps the physical PIC operations separate from the virtual DSP interrupt, PIC request, and PIC in-service state.

The implemented subset includes the IRQ mask at port 21h, IRR/ISR selection with OCW3 values 0Ah/0Bh, specific and nonspecific EOI, DSP interrupt status at mixer register 82h, and 8-bit DSP acknowledgement at port 22Eh. Other physical PIC inputs remain visible. Unsupported PIC commands fail the experiment; PIC initialization, priority rotation, special mask modes, and spurious IRQ behavior are not implemented. The interfaces are described in the [Intel 8259A data sheet](https://www.pcjs.org/documents/datasheets/intel/INTEL_8259A_PIC.pdf) and [Creative hardware programming guide](https://www.phatcode.net/res/243/files/sbhwpg.pdf).

The guest checks completion counts at both sample rates, pending requests while masked, delivery after unmasking, and independent DSP acknowledgement and EOI. It withholds each acknowledgement in turn and checks that interrupts do not repeat incorrectly. DSP reset cancels pending virtual requests but leaves an interrupt already in service until EOI. Tests cover reset both while masked and while in service. BIOS timer ticks must continue during the checks, including while a virtual IRQ remains in service.

`AISTATE.COM` also checks interrupt priority with simulated physical ISR values. A higher-priority physical interrupt must receive nonspecific EOI before the virtual IRQ; a lower-priority physical interrupt must remain in service while the virtual IRQ receives EOI.

Waveform checks verify continued CD and game output during IRQ masking and delayed acknowledgements, as well as the original rate and reset checks. Both physical configurations run the interrupt client twice and then the original polling client. A second negative control disables virtual delivery and must report missing virtual interrupts while physical output interrupts still occur.

A further run starts the output-period counter at 65,520 and crosses the old 16-bit boundary during playback. Completion checks and captured signals must still pass. The counter now uses 32 bits.

The interrupt test uses a 4 KiB physical output ring with 512 frames per interrupt, about 11.6 ms at 44.1 kHz. Its aligned ring requires an 8 KiB temporary DOS allocation, reduced from the polling experiment's 64 KiB allocation for a 32 KiB ring. The preloaded source data, code, and DPMI host use additional memory; this is not a resident-memory measurement. Virtual dispatch from a real-mode game, arbitrary DMA block sizes, and buffer refill timing still require work. These tests exercise a purpose-built client, not a commercial game.
