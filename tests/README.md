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

The baseline checks that no CD extensions are installed, loads SHSUCDHD and SHSUCDX, and reads a generated ISO. The uCDD test checks the same initial state, then runs `UCDD -install` and loads SHSUCDX. The test disk contains no separate driver executable. Invalid installation options and a second installation must fail.

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

The single-unit run uses the driver's default unit count. It checks mounting, replacement, full-drive handling, repeated commands, and direct CD packets. The upper-memory run adds Jemm, runs `LH C:\UCDD.EXE -install`, and checks that the resident segment is above conventional memory. Both runs require the driver's DOS memory block to remain at 9,264 bytes; the two-unit run requires 10,608 bytes. Download Jemm with the audio test runner before the upper-memory test.

## Integrated speaker test

```powershell
python scripts/test_setup.py --izarra-source D:\dev\IzarraVM
python scripts/test_setup.py --izarra-source D:\dev\IzarraVM --jemm
```

These interpreted 386 tests run the release configurator in FreeDOS, first without a memory manager and then with Jemm. Neither disk contains QPIEMU, JLOAD, a DPMI host, or UCDDTST.COM. They check repeated F2 tests, alternate IRQ/DMA settings, failure at a missing I/O address, and correction of that address in the same setup session. The Jemm run also checks linked UMBs with an upper-memory allocation preference. Captures check six left/pause/right sequences without Jemm and eight with Jemm. A DOS probe checks that the interrupt vectors, PIC mask, saved mixer registers, DOS allocation policy, and largest available memory block are restored after each setup session.

```text
python scripts/test_config_path.py --izarra-source D:\dev\IzarraVM
```

This interpreted 386 test places both programs in a subdirectory and leaves a different configuration in the working directory. It checks absolute paths, PATH lookup, loading high, automatic setup when settings are missing, save/test/cancel, a missing helper, invalid settings, and standalone setup. The working directory and its configuration must remain unchanged. A cancelled installation must restore DOS allocation policy, available memory, interrupt vectors, PIC masks, and mixer state.

## Resident audio

```powershell
python scripts/test_audio_resident_boot.py --izarra-source D:\dev\IzarraVM
python scripts/test_audio_resident.py --izarra-source D:\dev\IzarraVM --quake-dir C:\games\quake --quake-bin C:\images\quake.bin --load-high --own-host
python scripts/test_audio_resident.py --izarra-source D:\dev\IzarraVM --quake-dir C:\games\quake --quake-bin C:\images\quake.bin --load-high --own-host --runs 1 --mscdex C:\DOS\MSCDEX.EXE
```

These commands build the internal-host resident UCDD.EXE and release UCDDSET.EXE. Their guests contain no HDPMI32i, QPIEMU, JLOAD, UCDDAUD, or UCDDPM. Jemm 5.86 and SHSUCDX remain external dependencies. Run `scripts/fetch_test_deps.py` first to obtain the DOS and CD-extension archives. Omitting `--own-host` from the game runner selects the historical external-host comparison.

The interpreted 386 boot test forces a wrong physical I/O address. It checks failed-install rollback of interrupt vectors, PIC mask, saved mixer registers, DOS allocation policy, and largest available DOS block. The driver header and private port interface must be absent afterward. A corrected configuration must then install successfully. F2 in the configurator must produce no speaker-test tone while resident audio owns the card; F10 must preserve the settings. Reports are under `.local/audio/resident-boot-own-host/`.

The interpreted 586 game test installs before mounting an image, checks duplicate installation and rejected mount commands, copies and verifies RESOURCE.1, then starts Quake directly twice with an unmount/remount between runs. Each run must finish, leave no reported audio fault, and pass separate checks of the complete 12-second music excerpt and centered game sound. Each capture must also reject four deliberate corruptions. The phase markers delimit the two game runs in the capture. `--mscdex` replaces SHSUCDX with a caller-supplied MSCDEX executable; MSCDEX 2.25 passes the one-run data and mixed-audio case. Original game files, images, and redirector binaries are read-only inputs.

With `--load-high`, both one-unit resident blocks must be above conventional memory, while the DMA ring and its allocation must remain below A0000h. The measured driver/mixer block is 33,056 bytes and the internal host is 61,424 bytes, plus an 8 KiB conventional DMA allocation and a 512 KiB XMS queue. Reports are under `.local/audio/resident-high-own-host/`, or `resident-low-own-host/` without `--load-high`. These checks establish the tested Jemm/internal-host path. Tomb Raider covers timer refills without frequent CD status polling.

`test_audio_sb.py --cpu 486 --output sb16 --mscdex <MSCDEX.EXE> --himem <HIMEM.SYS> --emm386 <EMM386.EXE>` checks the Microsoft manager adapter with caller-supplied private binaries. Protected and real-mode 8-bit clients pass through SB16 output. Microsoft EMM386's 4A15h service cannot trap DMA and PIC ports below 100h. A real-mode client that programs the same DMA channel as the physical output is therefore outside this tested path. The driver suspends its external 4A15h trap during a protected-client session, so a sound driver called through an INT 31h real-mode transfer is outside the supported path. The 386MAX options build a disk for its published 4A15h interface, but no 386MAX runtime pass is claimed.

## uCDD-owned protected-mode host

```powershell
python scripts/test_host.py --emulator D:\dev\IzarraVM\target\release\izarravm.exe --no-vcpi
python scripts/test_host.py --emulator D:\dev\IzarraVM\target\release\izarravm.exe --audio --izarra-source D:\dev\IzarraVM --load-high
python scripts/test_host.py --emulator D:\dev\IzarraVM\target\release\izarravm.exe --audio --izarra-source D:\dev\IzarraVM --alternate
python scripts/test_host.py --emulator D:\dev\IzarraVM\target\release\izarravm.exe --audio --izarra-source D:\dev\IzarraVM --no-delivery
python scripts/test_host_audit.py --emulator D:\dev\IzarraVM\target\release\izarravm.exe --izarra-source D:\dev\IzarraVM
```

These interpreted 386 tests exercise `src/host/monitor.asm` without HDPMI32i, CWSDPMI, QPIEMU, or JLOAD on the guest disk. The monitor uses standard VCPI entry and return calls and owns its page tables, descriptor tables, task state, and protected-mode interrupt handlers. The tested manager is Jemm 5.86; other VCPI providers have not been tested. Without VCPI, initialization must fail cleanly. The [VCPI specification](https://www.edm2.com/index.php/Virtual_Control_Program_Interface_specification_v1) defines the manager interface.

The monitor test runs a controlled 32-bit client at CPL 3 and IOPL 0. It checks repeated entry/exit, trapped byte/word/dword I/O with immediate and DX port operands, untrapped I/O, CLI/STI, timer forwarding, and a DOS call through the register-frame interface. Invalid port ranges and unsupported requests must fail. A rejected port callback and a privileged HLT instruction must return a fault to DOS, after which another client run must succeed. `--load-high` adds a run that requires the complete monitor test program to be in upper memory.

The audio test runs the existing mixer against a protected-mode Sound Blaster client. The physical IRQ is reflected to the real-mode mixer; virtual IRQ 5 is delivered to the client's installed handler and acknowledged through the virtual DSP/PIC. Captures check separate CD channels and game sound at 22.05 kHz, a reset interval, 11.025 kHz, and 22.05 kHz again. The default physical resources are IRQ 5/DMA 1/5; `--alternate` uses IRQ 7/DMA 3/6. `--no-delivery` must fail with zero virtual interrupts while physical output continues. A DOS probe checks restoration of vectors, PIC mask, mixer registers, allocation policy, and the largest available DOS block. Reports and captures are under `.local/host/`.

The internal host is linked into the resident UCDD.EXE build. `test_host_audit.py` checks the external 32-bit DPMI client interface in 19 cases: core services, descriptor and buffer validation, allocation exhaustion, virtual PIC routing, nested IRQ/callback stacks, revoked callbacks, callback faults and exits, private entry rejection, malformed return frames, IVT cleanup, and allocation rollback. Each case runs its client twice and requires exact VCPI free-page recovery. It records source and executable hashes, guest logs, and memory dumps under `.local/host/audit/`. Use `--case` to select a case.

The API tests cover immutable segment descriptors, DOS allocation ownership, 256 extended-memory allocation records, page permissions, arithmetic flags through chained interrupt vectors, inherited NT clearing, and high-selector register-only DOS calls. Exception tests relocate their return frames on the locked stack. A nested test combines 2 KiB of IRQ locals, 3 KiB of callback locals, and another IRQ, with stack canaries.

This remains a subset for one active 32-bit client. Sixteen-bit DPMI clients, nested clients and callbacks, and general real-mode stack copying are unsupported. Direct VCPI extenders can bypass the protected audio interception. The audit does not establish general DOS or real-hardware compatibility.

## Additional game fixtures

`test_host.py --game tomb|u8 --game-dir <directory> --cd-bin <image.bin> --cd-cue <image.cue> --resident --cpu 486 --izarra-source <checkout> --emulator <executable>` creates an isolated disk from local game files. `--game-exe` selects an alternate executable without changing the source installation. `--mouse-driver` supplies a DOS mouse driver for Ultima VIII. A mounted Ultima VIII test copies and CRC-checks `INSTALL.BAT` before and after the game; it has no Redbook requirement.

The Tomb fixture renames the BIN and removes unsupported FLAGS and PREGAP lines from its test CUE sheet. Its input BIN is unchanged. A successful fixture test would not establish support for those CUE commands. `--legacy-host` selects the previous HDPMI resident path for a controlled comparison.

`test_host_causeway.py --help` describes the Daggerfall CauseWay and DOS/32A fixtures. Supply extracted local game files and the ISO. The original executable, extender choice, configuration adjustments, and hashes are recorded with the run. A test-only VCPI discovery filter can force DOS/32A to use DPMI; that case does not establish automatic host selection by the unmodified extender environment.

Capture controls include `UCDD_TEST_STEPS`, `UCDD_TEST_TIMEOUT`, `UCDD_TEST_MEMORY_MIB` (default 16), and `UCDD_TEST_KEYS` (`step:hex-scancode` entries separated by commas). `UCDD_TEST_LIVE` names an existing directory for periodic frames and an `input.txt` file containing `key <hex-scancodes>` or `mouse <dx> <dy> <buttons>` commands. A cycle limit is an incomplete run, never a test pass. Emulator instruction stepping and protected CLI/STI must work correctly; the validated IzarraVM interpreter changes are tracked in [PR 883](https://github.com/vorvek/IzarraVM/pull/883).

## Shared-card audio experiment

```powershell
python scripts/test_audio.py --emulator D:\dev\IzarraVM\target\release\izarravm.exe --izarra-source D:\dev\IzarraVM
```

This runner downloads Jemm 5.86 from its upstream release and checks a pinned SHA-256 hash. It boots a separate FreeDOS disk with Jemm and QPIEMU. A small client sends SB16-style 8-bit mono auto-initialized DMA commands to virtual ports at 220h. It polls DMA position, changes between 22.05 and 11.025 kHz, and resets its virtual DSP. The client checks that its sample buffer was not changed.

The audio experiment owns the physical SB16 output, IRQ, and 16-bit DMA ring. An interrupt handler mixes a preloaded stereo signal with the client's samples. It does not call DOS from the audio interrupt. Tests also cover setup navigation, saved settings, BLASTER suggestions, the setup sound test, alternate IRQ/DMA settings, and rejection of invalid configuration files and unsupported output configurations. Captures require each setup sound test to play left alone for about 1.1 seconds, pause for about 0.37 seconds, then play right alone for about 1.1 seconds.

With `--izarra-source`, the runner builds a separate capture executable against that checkout's public machine API. Rust and IzarraVM's native build dependencies are required. It does not change IzarraVM source. The capture machine uses interpreted 386 mode, disables WSS, and mounts no CD image. Audio is drained at short intervals from the emulated card's output. The host checks both CD marker frequencies, channel separation, the client's two rates, and continued CD output while the virtual DSP is reset. Logs, build hashes, a WAV file, and a setup-screen snapshot are stored under `.local/audio/`.

This is a bounded experiment, not a general sound emulator. The polling client uses a 4 KiB unsigned 8-bit mono source ring. Full PIC and mixer semantics and disc streaming remain unimplemented. The virtual interface remains at 220h while the physical output uses the saved settings. The preloaded CD signal and 32 KiB output ring use temporary DOS allocations. These allocations are not the final resident memory design.

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

The interrupt test uses a 4 KiB physical output ring with 512 frames per interrupt, about 11.6 ms at 44.1 kHz. Its aligned ring requires an 8 KiB temporary DOS allocation, reduced from the polling experiment's 64 KiB allocation for a 32 KiB ring. The preloaded source data, code, and DPMI host use additional memory; this is not a resident-memory measurement. Virtual dispatch from a real-mode game and arbitrary DMA layouts still require work. These tests exercise a purpose-built client, not a commercial game.

## Sound onset and live buffer refill

```powershell
python scripts/test_audio_onset.py --izarra-source D:\dev\IzarraVM
python scripts/test_audio_refill.py --izarra-source D:\dev\IzarraVM
```

Both runners use the interpreted 386 machine, the 512-frame output period, and both physical IRQ/DMA configurations. Each case has a signal capture and an otherwise identical silent-source capture. Guest test-device markers record the play and stop commands. The host requires matching command times and capture lengths, then subtracts the silent capture to isolate the game samples from the continuous CD signal.

The onset client makes six starts, alternating 22.05 and 11.025 kHz. Four distinct opening levels must appear in full and in order, followed by a constant level until stop. This caught a bug that skipped the opening source samples while filling the future output block. Playback now starts at source sample zero, and the virtual DMA clock waits until that output reaches the card. The test measured start delays of 13.2 to 20.3 ms and stop delays of 12.1 to 20.0 ms. These are command-marker-to-capture measurements in the emulator; they do not establish physical-card latency.

The refill client replaces each completed source block in its virtual IRQ handler. The host checks every block's sample level and order across at least two complete ring cycles, including the partially played final block.

| Source ring | Completion block | Source rate | Complete blocks checked per capture |
| --- | --- | --- | --- |
| 4 KiB | 1 KiB | 22.05 kHz | 28 |
| 4 KiB | 2 KiB | 22.05 kHz | 14 |
| 8 KiB | 2 KiB | 22.05 kHz | 14 |
| 2 KiB | 512 bytes | 44.1 kHz | 113 |

The virtual DSP accepts unsigned 8-bit mono on virtual DMA 1 and signed 16-bit stereo on virtual DMA 5. Rings must have power-of-two sizes from 512 bytes to 32 KiB and stay below A0000h. Byte DMA uses a 64 KiB window; word DMA uses a 128 KiB window. Completion blocks range from 512 bytes to the ring size, with complete frames for stereo. For blocks smaller than the ring, the remaining ring duration must cover at least two physical output periods, so the mixer does not reuse a block before the game can refill it. A negative control requires rejection of a 1 KiB mono ring with 512-byte blocks at 44.1 kHz while physical output interrupts continue. Full-ring completion blocks remain available for preloaded samples; interrupt-driven refill of that layout is not established.

Reports, paired WAV files, command timestamps, logs, and build hashes are stored in `.local/audio/onset/` and `.local/audio/refill/`. The tested layouts do not establish general game compatibility or tolerance of delayed refills under disk and CPU load.

## Independent protected-mode client

```powershell
python scripts/test_audio_launch.py --izarra-source D:\dev\IzarraVM
```

`ALAUNCH.COM` owns the HDPMI port traps and physical IRQ route, then uses DOS EXEC to run a separate DPMI child. The child receives an empty command tail and uses standard DPMI services and Sound Blaster ports. Its build excludes the bridge routines and does not install a vendor port trap or IRQ route. The launcher restores its route and removes its traps after the child exits.

Paired captures verify live refills at both physical card configurations in interpreted 386 mode. One client uses SB16 C6h commands at 22.05 kHz. Another uses DSP commands 40h, 48h, and 1Ch at 10 kHz, plus the DMA clear-mask command. Both use a 4 KiB source ring and 1 KiB completion blocks. Reports are under `.local/audio/launcher/`. The bridge still uses temporary DOS memory and mode switches; it is not the final resident service.

## Polling client and reflected interrupts

```powershell
python -m pip install numpy
python scripts/test_audio_poll.py --izarra-source D:\dev\IzarraVM
```

The independent polling client leaves the default DPMI sound vector in place. It checks DSP completion status and DMA progress without installing an IRQ handler. The test uses interpreted 386 mode and crosses physical IRQ 5/7 with DMA 1/5 and 3/6. It needs no game files.

When a virtual IRQ reflects through the default vector to the real-mode audio handler, the handler checks the physical SB16 interrupt status. A call without a pending 16-bit DSP interrupt goes to the saved handler. It does not acknowledge the physical DSP, advance the mixer, or send a physical PIC EOI.

The old handler produces a 1,024-frame CD phase change in this test. The regression checks the captured CD phase and requires DSP acknowledgements and continued DMA progress. Some 386 captures repeat one sample, and its occurrence changes with the host capture interval. The check permits at most one frame of total phase change and rejects larger changes. This tolerance does not establish sample-exact continuity. Captures, phase changes, logs, and build hashes are under `.local/audio/poll/`.

## Signed 16-bit stereo client

```powershell
python -m pip install numpy
python scripts/test_audio_stereo.py --izarra-source D:\dev\IzarraVM
```

The independent DPMI client uses B6h with format 30h, virtual DMA 5, and an 8 KiB source ring with 2 KiB completion blocks at 22.05 kHz. Paired captures check independent left/right values, signed samples with nonzero low bytes, and 54 complete refilled blocks. The test also checks that reading the 8-bit acknowledgement port does not clear a 16-bit interrupt and that D0h does not stop the 16-bit stream. D5h stops that stream. Resume commands are not implemented.

`ADMA.COM` checks the same virtual port callback with a fixed physical clock. It covers separate controller byte flip-flops and counts, word-count progress, page-bit handling, a valid 64 KiB crossing, and rejection of a 128 KiB crossing, an address above conventional memory, an incomplete stereo frame, and insufficient refill headroom. The address rules follow the [x86 ISA DMA interface](https://github.com/torvalds/linux/blob/master/arch/x86/include/asm/dma.h).

The physical SB16 still uses 44.1 kHz, 16-bit stereo. Its DMA operations bypass the virtual ports, including when both the game and physical card use DMA 5. Adjacent ports share registrations within HDPMI's 16-range limit. Both physical IRQ/DMA configurations run in interpreted 386 mode. Reports and paired captures are under `.local/audio/stereo/`.

## Optional unmodified Quake audio test

Install NumPy for this host waveform check. Supply your own DOS Quake installation with `QUAKE.EXE` and `ID1/PAK0.PAK`:

```powershell
python -m pip install numpy
python scripts/test_audio_quake.py --izarra-source D:\dev\IzarraVM --quake-dir C:\games\quake
python scripts/test_audio_quake.py --izarra-source D:\dev\IzarraVM --quake-dir C:\games\quake --legacy
```

The test copies those files unchanged to a disposable FreeDOS disk. It adds a test configuration that loads the start level, stops other game sounds, plays `misc/menu1`, waits, and exits through the console. The source installation is opened read-only. Game binaries, assets, extracted files, and generated disks are not included in the repository.

This test uses the interpreted Pentium profile and 16 MiB. Quake requires an FPU and lists a Pentium as its minimum processor; the initial 386 tests remain unchanged. `--cpu 486` is available for comparison, but the slower test did not preserve the complete sound. This does not establish a hardware speed requirement for uCDD.

Quake runs in normal SB16 mode with virtual DMA 5 and a signed 16-bit stereo source at 11,025 Hz. `--legacy` selects `-dsp 2`, virtual DMA 1, and 8-bit mono at an effective 10,989 Hz after time-constant rounding. Both mix with the preloaded CD-format signal on the physical SB16 at 44.1 kHz, 16-bit stereo. The relevant game interface is in id Software's [DOS sound source](https://github.com/id-Software/Quake/blob/master/WinQuake/snd_dos.c). WSS and emulator CD playback remain disabled. This test does not use the ISO driver or stream CD audio from a disc image.

The runner checks the guest exit, level and sequence markers, DSP version, and DMA channel in Quake's console log, plus the complete reference sound from the supplied PAK. The centered test sound has equal left/right values in both formats, so subtracting the channels isolates the known CD signal. The reference match must exceed 0.97 correlation, and both CD channels must retain their phase throughout that sound. A muted-game control must not match the reference. The independent stereo client checks unequal channels separately.

The Quake and polling checks permit at most one frame of total capture phase change between complete signal windows, including game startup. A window that crosses that single-frame change can contain the two adjacent phases; other interior signal errors fail. This accounts for the capture effect described above and does not prove sample-exact output. The first 256-frame capture window and final output stop are excluded. The earlier 1,024-frame IRQ 5 buffer jump remains rejected. Longer gameplay under load, other games, abnormal child termination, and physical hardware for these preloaded-audio builds remain unverified. A later mounted-image hardware report is described below. Captures, console logs, disk exports, and input/build hashes are under `.local/audio/quake/` and `.local/audio/quake-legacy/`.

## CD image streaming

```powershell
python -m unittest discover -s tests -p test_cd_selection.py
python scripts/test_audio_image.py --izarra-source D:\dev\IzarraVM
python scripts/test_audio_image.py --izarra-source D:\dev\IzarraVM --cue C:\images\quake.cue
```

The streaming runner uses an interpreted 386, one physical SB16, and no WSS or emulator CD playback. It reads signed 16-bit stereo samples at 44.1 kHz from a DOS BIN file, starting at a selected byte offset. DOS reads fill a 16 KiB queue in 4 KiB blocks. The sound interrupt consumes published blocks and never calls DOS. The final read is padded with silence; subsequent bytes in the image must not play. Empty buffers and read errors stop the CD source and produce an error result.

The protected-mode stereo client calls a foreground refill service while its virtual IRQ handler refills the game's separate DMA ring. The service uses its own 2 KiB stack, preserves the caller's PSP, and checks InDOS before file access. The image handle belongs to the parent and is not inherited by the client. This is an explicit cooperative interface, not a background scheduler for unmodified games. The earlier Quake test uses a preloaded signal; the mounted-image test below uses real track data.

The main cases stream 220,637 frames, slightly over five seconds, through 216 reads. Paired captures at physical IRQ 5/DMA 1/5 and IRQ 7/DMA 3/6 verify CD samples and 259 complete stereo game blocks, including game output after the selected CD range ends. The optional CUE case copies the opening excerpt of track 2 to a disposable BIN file at its original byte offset; surrounding bytes are test sentinels. It does not copy or play the complete image. The original CUE and BIN are read-only inputs. No game data is distributed.

Controls stop foreground refills after the initial queue, force a DOS read failure after eight successful reads, and reject a short BIN, a missing BIN, and a truncated descriptor. The stalled case must play exactly the initial 16 KiB, then keep its CD output silent while game audio continues. A standalone case checks playback without a DPMI client. The waveform verifier checks both channels and end silence; it excludes the first 256 capture frames and allows at most one frame of phase change, as in the earlier capture tests. Reports include that change rather than claiming sample-exact output. Results, input hashes, guest counters, and captures are under `.local/audio/image/`.

The queue covers about 93 ms at CD rate. It uses conventional memory, as do the output allocation and transient program. The standalone player is 6,656 bytes in this build, excluding its PSP, environment, and 24 KiB of buffer allocations. It does not stay resident. This standalone test does not use the XMS queue or CD request interface of the mounted-image service below.

### Standalone hardware test

Build with `python scripts/build_audio.py`. On the host, select a complete audio track and name the BIN's intended DOS path:

```powershell
python scripts/prepare_cd_stream.py --cue C:\images\disc.cue --track 2 --dos-path C:\IMAGES\DISC.BIN --output build\CDSTREAM.DAT
```

The selector accepts one `FILE ... BINARY`, sequential tracks with `AUDIO` or `MODE1/2352`, and `INDEX 00`/`INDEX 01`. It ends playback before the next track's index 00, or index 01 if no index 00 exists. Multi-file sheets, compressed audio, synthetic gaps, emphasis flags, and other layouts are rejected. The selected track must contain audio. The original BIN must contain complete 2352-byte sectors and be smaller than 2 GiB. Use DOS 8.3 names on a local hard disk.

Copy the original BIN to that DOS path. Copy `UCDDPLAY.COM`, `CDSTREAM.DAT`, and `UCDDSET.EXE` to the same working directory. In native DOS, load Jemm and QPIEMU, then use `UCDDSET` to save the actual physical SB16 settings to `UCDD.CFG`. Run `UCDDPLAY` from that directory. HDPMI is not required for standalone playback. Press Esc to stop, or let the selected track finish. Exit code 0 indicates normal completion or Esc; code 1 indicates failure. A fresh invocation starts the selected track again.

This test does not install a virtual CD drive or exercise shared audio with an unmodified game. A user reported that the setup produced sound and that `UCDDPLAY.COM` played the first music track from a Quake BIN image on a real DOS PC. That result covers standalone playback. A later shared-audio hardware report is described below.

## Mounted CUE/BIN and Quake music

```powershell
python scripts/build.py
python scripts/test_audio_mounted.py --izarra-source D:\dev\IzarraVM --quake-dir C:\games\quake --quake-bin C:\images\quake.bin --load-high
python scripts/test_audio_mounted.py --izarra-source D:\dev\IzarraVM --quake-dir C:\games\quake --quake-bin C:\images\quake.bin --load-high --quiet --irq 5 --name mounted-quiet
```

The runner copies the data track and 12-second excerpts of audio tracks 2, 3, and 4 into a disposable single-file image. Its CUE sheet retains the track numbers and adjusts the excerpt offsets. Quake selects track 4 for the start map, streams beyond the initial XMS queue, and loops the excerpt. The original installation and image are read-only inputs. PAK1.PAK is included when present. No game data enters the public repository.

The test runs unmodified Quake in interpreted 586 mode with one physical SB16 and no emulator CD drive or WSS output. It checks Quake's console log, the guest exit, read counters, stream errors, and captured output. The mixed run checks the complete music excerpt's stereo difference and the complete centered game sound. The quiet run checks both music channels directly. At most one capture frame of phase change is allowed; the report records it. The first 512 source frames are excluded from the sample comparison. Corrupted captures must fail: repeated blocks, a 1,024-frame phase jump, swapped channels, and a missing game sound.

`--load-high` checks that the reporting audio parent is above A000h and that both the physical DMA ring and its allocation are below A0000h. The service temporarily selects conventional DOS allocations before allocating DMA memory or launching the game, then restores the caller's allocation policy. This avoids inheriting LH's upper-memory allocation policy for DMA buffers. The separate DPMI launcher still occupies conventional memory.

Use `--copy-installer` to copy RESOURCE.1 through F: to the DOS hard disk and check its CRC in DOS, then compare the copied bytes against the source on the host. This validates the installer archive's data path; it does not automate the interactive installer. `--release` tests the delivered UCDDAUD.COM without diagnostic counters. The normal reporting build is ACDMOUNT.COM.

`--failure starve` stops refills after the initial 512 KiB. `--failure read` closes the source handle after 160 reads. These controls require Quake to finish while the service reports the intended CD error. A fresh test disk is used for each case. Reports, file hashes, counters, console logs, and captures are stored under `.local/audio/<name>/`.

The 386 DOS suite also checks CUE TOC values, stored leading pregaps, data reads, rejected replacements, the 13-byte request-header convention used by Quake, and audio-service attach/detach ownership. It tests one and multiple units, including a driver loaded high.

The foreground polling behavior is defined by id Software's [DOS CD implementation](https://github.com/id-Software/Quake/blob/master/WinQuake/cd_audio.c). Buffer copies use the [XMS interface](https://www.phatcode.net/res/219/files/xms30.txt); the interrupt uses a separate move descriptor and never calls DOS. These tests do not establish a general background scheduler or real-hardware performance.

### Mounted-image hardware report

A user reported that the current Quake experiment works on a real DOS PC with SHSUCDX, with CD music and game sound sharing the SB16. The user also confirmed that `LH UCDDRV.EXE` loads the driver into upper memory. This report does not establish measured latency, sample accuracy, long-session stability, or a minimum processor speed.

With MSCDEX on the same machine, the image mounted and its files could be accessed, but Quake produced no CD audio. After the game exited, the service reported `The CD image read failed.`. Switching to SHSUCDX worked. This comparison records a redirector-dependent result; it does not identify the cause. MSCDEX audio compatibility remains unresolved.

## Tomb Raider CD audio

The resident SB16 test starts a new game in Caves, moves Lara, returns to the title, and exits to DOS. The 3dfx fixture runs with the Pentium dynarec, one physical SB16, WSS disabled, and no emulator CD image. A trace identified seek 83h and Q-channel input 0Ch requests. Background refill permits playback without frequent game status polls.

`check_tomb_audio.py --capture capture.wav --bin disc.bin --track-lba 102044` checks 23 seconds of track 3 from this disc layout. Supply the actual INDEX 01 sector for another pressing. The check compares every stereo frame against the source and the 8-bit game output grid, then requires game sound in the residual. It rejects repeated blocks, phase jumps, exchanged channels, absent game sound, and absent CD audio. This check assumes the tested SB16 output gain and unsigned 8-bit game format. No game files or captures are distributed.

The interpreted 386 CD-state tests cover seek addresses, BCD track numbers, head position, short requests, and completion. The background-state test covers DOS and BIOS exclusion, nested timer calls, stack restoration, and BIOS result flags. The DMA-state tests cover 8-bit and 16-bit exit commands, block completion, final IRQ, and silence afterward. The seek and Q-channel layouts follow Microsoft's [MSCDEX driver specification](https://gist.github.com/abrasive/7a615e6dde0c1da962f9930cc63ee43d).

## WSS and SB Pro

```powershell
python scripts/test_setup.py --izarra-source D:\dev\IzarraVM --wss
python scripts/test_setup.py --izarra-source D:\dev\IzarraVM --sbpro --jemm
python scripts/test_audio_cards.py --izarra-source D:\dev\IzarraVM --load-high
```

The card test uses interpreted 386 execution. Protocol tests check WSS masked startup, active counter reload, transfer holds, and source changes; SB Pro checks the silent-byte initialization, high-speed stereo, and legacy mono. The codec test rejects writes made before INIT clears. A conversion test checks stereo samples, saturation, the fractional CD clock, XMS queue wrap, and a partial final buffer.

A protected client then runs twice through the internal host, requests WSS IRQ 11, and checks disabled codec interrupts, PIC masking, and resumed delivery. This runs with each physical output. Direct real-mode WSS interrupt delivery is not implemented. The lifecycle wrapper compares DOS allocation state, vectors, PIC mask, and mixer registers. The high-memory cases check both resident blocks and read the DMA allocation size from its DOS memory control block. SB16/WSS use 8 KiB; SB Pro uses 2 KiB. Reports are under `.local/audio/cards-<output>-high/`.

For the same Tomb Raider Caves movement sequence, `check_tomb_audio.py --sbpro` checks nine seconds of music in intervals 1-6 and 14-18, where game effects are absent, and requires effects during seconds 6-14. Its 128-unit sample bound allows 8-bit conversion and capture filtering. It rejects repeated blocks, phase jumps, swapped channels, missing game sound, and missing CD music. This is a bounded check of this fixture, not the continuous 16-bit comparison. The physical clock uses the conventional SB Pro time constant; the CD resampler compensates for its actual rate.

## Original Sound Blaster DMA audio

```powershell
python scripts/test_setup.py --izarra-source D:\dev\IzarraVM --sb --jemm
python scripts/test_audio_cards.py --izarra-source D:\dev\IzarraVM --load-high
python scripts/test_audio_sb.py --izarra-source D:\dev\IzarraVM --cpu 586
python scripts/test_audio_sb.py --izarra-source D:\dev\IzarraVM --cpu 586 --irq 5
```

The initial protocol, setup, and residency tests use the 386 interpreter. `audio_sb_state.asm` checks single-cycle lengths of 1, 257, 997, and 65,536 bytes, chained DMA cursor retention, auto-init wrapping, pause/resume, speaker control, final IRQ delivery, and stereo-enabled one-byte priming. Existing Pro, SB16, and WSS protocol tests still run. The original SB output uses a 1 KiB conventional DMA allocation.

The mixed streaming test uses a generated CUE/BIN with separate 733 Hz and 1237 Hz CD channels. Real-mode and 32-bit DPMI clients submit chained 1,000-byte PCM blocks at 10 kHz from their IRQ handlers. Captures require all three sources and check 10 ms windows for gaps between PCM blocks. Controls remove the game, remove the CD, and insert a 20 ms gap. The lifecycle wrapper checks memory, vectors, PIC state, and mixer state after each client. IRQ 5 tests also check DOS and DPMI real-vector isolation and cleanup of a client-owned logical vector.

This workload passes with the interpreted 486 and Pentium profiles through SB, SB Pro, SB16, and WSS output. The interpreted 386 misses refill deadlines, so it is not a passing mixed-streaming configuration. The emulator exposes ReSonique 2 compatibility paths; these results are not separate physical SB1, SB1.5, or SB2 certifications. No game or third-party files are distributed by these tests.
