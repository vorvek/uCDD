# Beta 0.9.5-a2

## Changes in 0.9.5-a2

- Remove the Microsoft EMM386 support for CD-Audio. CD-Audio now needs JEMMEX or JEMM386. The EMM386 port traps could not catch the DMA ports below 100h.
- Send the IRQs of PCI disk controllers, and IRQ 14 and 15, directly to their DOS handlers, also during a protected-mode game. UCDDSET has a new Disk row that shows the IRQs that `UCDD -install` finds, and a field for the IRQ of an ISA or VLB disk card. `SET UCDDPCI=OFF` turns off the PCI scan. Backported from the EarBoye/uCDD fork.
- Step aside while no image with CD-Audio is mounted, when the physical card can also be the virtual card. μCDD then stops its output, releases the sound ports, and does not supply DPMI, so a game uses the card directly. A mount of an image with CD-Audio starts μCDD again. Tick "uCDD always on" in UCDDSET to keep μCDD on. `UCDD -status` shows whether μCDD is active. Backported from the EarBoye/uCDD fork.
- Add the Fast DMA option (experimental, off by default) in the new UCDDSET Chipset row. With the box ticked, μCDD uses the fast ISA DMA timing of the chipset on the output channel while it plays. Backported from the EarBoye/uCDD fork.
- DPMI host: when an interrupt handler starts with zero bytes, start it at its first code byte. This fixes the freeze at the stage load of World Rally Fever.
- DPMI host: hold a new virtual Sound Blaster interrupt until the game's Sound Blaster handler returns. This fixes the drop to DOS ("child error #1") in World Rally Fever.
- Refuse EMS map calls into the pages that hold μCDD. JEMMEX makes the regions given with `I=` into EMS pages, also with `NOEMS`. The Legacy: Realm of Terror mapped EMS pages over μCDD there, and the PC restarted. The game now stops with an EMS error.
- Split the resident driver into an audio block of 28 KB and a driver block of 8 KB. μCDD now fits a 32 KB upper memory block. The install-only code is given back after the installation. The stacks, the SDA copy, and the IRQ table for JEMMEX are in their own small blocks.
- Free the environment of UCDD.EXE before the CD buffers move to upper memory. With `LH`, the CD work buffer stayed in conventional memory on a PC with small UMBs.
- Give back the page alignment space of the DPMI host gateway, in upper and in conventional memory.
- When UMBs exist but none holds the audio block, `UCDD -install` shows the size of the block that it needs.
- Add World Rally Fever: Born on the Road to the [compatibility list](https://github.com/vorvek/uCDD/wiki/Compatibility).

# Beta 0.9.5-a1

## Changes in 0.9.5-a1

- Add native output for ESS AudioDrive cards (experimental). UCDDSET has two new physical models: ESS AudioDrive, 16-bit stereo at about 44.1 kHz, and ESS AudioDrive 22 kHz, 16-bit stereo at about 22.05 kHz. The ESS port can be 220h, 230h, 240h, 250h, 260h, or 280h. Detect identifies an ESS AudioDrive with DSP command E7h. At installation, μCDD measures the output rate and makes sure that the IRQ and DMA channel of the card agree with the UCDDSET settings. In games, select Sound Blaster Pro or Sound Blaster 16, not ESS. Backported from the EarBoye/uCDD fork.
- Add `UCDD -status`. It shows the sound interrupts, CD-Audio reads, and refused reads that μCDD counted since installation, the first sound fault, and the last program that the DPMI host stopped. `UCDD -status -reset` sets the counts to 0. Add this output to a bug report. The interrupt counters come from the EarBoye/uCDD fork.
- The CD-ROM device status now reports that the drive can read XA discs. From the EarBoye/uCDD fork.
- Read CD-Audio for a DPMI program that waits in a long real-mode call. This fixes the late CD-Audio start and the silent mission briefing in Judge Dredd, and the CD-Audio stall in Dominus.
- While μCDD reads CD-Audio, a game that reads the PIC mask gets its own keyboard bit, not the bit that μCDD holds. This fixes the keyboard in The Even More Incredible Machine.
- Play CD-Audio at the DOS prompt. μCDD reads CD-Audio from the DOS idle interrupt while COMMAND.COM waits for a key.
- Ignore Ctrl+C during CD reads, so that Ctrl+C does not stop the driver. From the EarBoye/uCDD fork.
- Fill the CD-Audio queue from the audio interrupt only when the timer stops or the queue is almost empty.
- Use the rate of DSP command 41h for the older play commands. This fixes the pitch of the voices in The Incredible Machine 2 and The Even More Incredible Machine.
- Raise the interrupt of DSP command F2h, and of a single-cycle block of one or two bytes, a few program instructions after the command write, not during the write. μCDD counts the instructions with single steps. If the program masks its IRQ or touches a sound port first, μCDD raises the interrupt at that time. Remove an old test interrupt when the game reads the DSP status. Lemmings 3D now finds its sound card.
- Start a single-cycle block that is longer than the DMA count, as a real card does.
- Send the interrupt of a single-cycle block that starts a stream after one output period, not during the start command. From the EarBoye/uCDD fork.
- At the exact start of a new lap of an auto-initialize transfer, report the DMA count of the end of the previous lap. A game that writes its buffer up to the reported position no longer erases sound that μCDD did not mix yet. From the EarBoye/uCDD fork.
- Accept DSP command E7h without a reply. A game that looks for an ESS chip finds a Sound Blaster, and μCDD records no sound fault.
- On an SB16, the driver now ends MPU-401 interrupts on the card's IRQ and gives them to the virtual SB16 through mixer register 82h. Before, they went to the BIOS. From the EarBoye/uCDD fork.
- Use the SB Pro volume curve for each channel that a game sets through the SB Pro mixer registers. This makes the sound effects in Battle Chess audible.
- Halve the game sound only while CD-Audio plays. At other times, the game sound has its full level.
- Keep a virtual Sound Blaster interrupt as a request until the game gets it. Before, a BIOS end of interrupt in that time removed it, and the game sound in Mortal Kombat Trilogy stopped.
- Restore the interrupt vector before the PIC mask when the output stops. The WSS output reads the IRQ number before it restores the vector, and the SB Pro output masks the IRQ before the DSP reset. This prevents a hang after the UCDDSET sound test with a WSS card on IRQ 7. From the EarBoye/uCDD fork.
- On SB Pro and ESS output, read port 2xEh also for a late card interrupt. The card sends no more interrupts until this read, so a late interrupt could stop the output.
- Align the audio interrupt stack on 4 bytes. A stack at an odd address makes the audio interrupt slower.
- Wait for the DSP after command D1h on SB Pro and SB 2.0 cards. Before, a slow card stopped the output. Add a note to the README: do not use the JEMMEX option `VME`. From the EarBoye/uCDD fork.
- Put the DPMI host stack in its gateway block. When no UMB is free, allocate it at the top of conventional memory, so that free conventional memory stays in one block. The EarBoye/uCDD fork found this fault.
- Install when DOS has no UMB support (`DOS=LOW`).
- Give the caller its interrupt flag back after a BIOS disk call (INT 13h) through μCDD. This fixes the keyboard in the Pinball Wizard 2000 installer.
- DPMI host: clear the direction flag at each entry from a program. This fixes the stop at the loading screen of MadSpace.
- DPMI host: accept code and data descriptors of all privilege levels in functions 0009h and 000Ch. This fixes the start of Dominus.
- DPMI host: return from a reflected INT 16h with interrupts on at the program's top level. This fixes the freeze in Mortal Kombat Trilogy. From the EarBoye/uCDD fork.
- DPMI host: reflect a flat data segment with base 0 to real mode as segment A000h, answer INT 2Fh function 1686h in protected mode, and support nested exceptions in programs. From the EarBoye/uCDD fork.
- DPMI host: give the end of interrupt to the BIOS for a disk IRQ that a program calls through DPMI function 0300h. This fixes GT Racing 97.
- DPMI host: check only the stack selector when an interrupt returns. This fixes Time Warriors.
- DPMI host: let the disk IRQs through while μCDD reads a disc image through the BIOS. This fixes Zyclunt.
- DPMI host: limit the single steps through a program that keeps interrupts off while an interrupt waits. After 32 steps, the program runs at full speed until it turns interrupts on. This fixes the lost sound interrupts and the slow game in Iron Man and X-O Manowar in Heavy Metal.
- DPMI host: run INT 0, 1, 2, 5, 6, and 7 from a protected-mode program as software interrupts, not as processor exceptions. This fixes the exit on the ice level of WHAM!.
- UCDDSET shows the SB Pro rate as an approximate rate.
- Add a Copper Tunnel visualization to UCDDPLAY. Copper rings rush out of a dark center. The bass makes the rings faster and brighter and moves the center.
- Add Dominus, Eojjeonji Joheun Il-i Saenggil Geot Gateun Jeonyeok (Night), Firo & Klawd, GT Racing 97, Johnny Bazookatone, Judge Dredd, Lemmings 3D, MadSpace: To Hell and Beyond, Mortal Kombat Trilogy, Pete Sampras Tennis 97, Quake, Scorcher, The Patrician, Time Warriors, WHAM!, and Zyclunt to the [compatibility list](https://github.com/vorvek/uCDD/wiki/Compatibility).

# Beta 0.9.4-a6

## Changes in 0.9.4-a6

- Run the Sound Blaster port trap on its own stack when a game leaves little stack below its stack pointer. This fixes the JemmEx exception in The 7th Guest.
- Play 8-bit sound blocks that run past the end of a 64 KiB DMA page. The DMA address wraps to the start of the same page, as on the hardware. This fixes the missing sound and the stop at the Kremlin picture in the intro of The Big Red Adventure.
- Keep three output periods in the audio ring instead of two. When an audio interrupt comes late, μCDD mixes the missed periods and does not play an old period again. This fixes the crackling CD-Audio in the hotel room of The Big Red Adventure, whose mouse driver keeps interrupts off for longer than one period. The resident driver uses about 1 KB more conventional memory.
- Do not refill the CD-Audio queue from the audio interrupt while a protected-mode game is in a real-mode call. The DPMI host now refills the queue when the call returns. This prevents a JemmEx exception during a BIOS disk call.
- DPMI host: give a protected-mode mouse driver call (INT 33h) its 32-bit EBX back after the real-mode call. This fixes the cursor in The Big Red Adventure.
- Add an FM fader to the UCDDSET mixer. μCDD now passes the FM volume that a game sets through the Sound Blaster mixer to the physical card, scaled by the fader. Before, a game's FM volume change had no effect under μCDD. At 100 percent, the FM level that the card had before installation stays. An existing `UCDD.CFG` keeps its settings and gets the FM level when it is saved again.
- Add volume hotkeys for the master, FM, and PCM levels. By default, Ctrl+Alt+Keypad + and - change the master volume, R and F the CD-Audio volume, T and G the FM volume, and Y and H the PCM volume. The hotkey step applies to all levels. The volume hotkeys of an existing `UCDD.CFG` take these defaults.
- Add The 7th Guest and The Big Red Adventure to the [compatibility list](https://github.com/vorvek/uCDD/wiki/Compatibility).

# Beta 0.9.4-a5

## Changes in 0.9.4-a5

- Read small CD-ROM data requests from raw images with one disk read for six sectors. Small data reads are about four times faster, and the intro video of The End of the World now plays at about native speed. The CD work buffer is about 10 KB larger. It goes to upper memory when a UMB is free; otherwise it uses conventional memory.
- DPMI host: pass the mouse event handler call (INT 33h function 0Ch) from protected-mode programs to the mouse driver. This fixes the mouse in Igor: Objetivo Uikokahonia.
- Remove duplicate code in the driver and the DPMI host.
- Add a Fireworks visualization to UCDDPLAY. Rockets rise on bass hits and burst into gold, chrome, and burgundy sparks. Louder music starts more rockets.
- Add Future Dimension, Igor: Objetivo Uikokahonia (Spanish CD version), Mortal Kombat Trilogy, PowerSlave, Sensible World of Soccer, Sensible World of Soccer 96/97, and Witchaven to the [compatibility list](https://github.com/vorvek/uCDD/wiki/Compatibility).

# Beta 0.9.4-a4

## Changes in 0.9.4-a4

- Mix game sound correctly when a game starts a new sound block before the old block ends, or changes its DMA buffer at a block end. This fixes the crackling sound effects in Prototype and the echoes and crackling in Savage Warriors. The resident driver uses about 0.9 KB more upper memory. Conventional memory use does not change.
- Give the DPMI host's locked interrupt stack eight levels instead of four, and keep two levels free for software interrupts. This fixes Fantasy General, which stopped on the map when the mouse moved.
- Move the list of working games to the [compatibility list](https://github.com/vorvek/uCDD/wiki/Compatibility) in the wiki. Add Prototype, Savage Warriors, and Fantasy General to the list.

# Beta 0.9.4-a3

## Changes in 0.9.4-a3

- Play single-cycle Creative ADPCM sound. μCDD converts it to PCM and mixes it with the CD-Audio. This fixes the missing sound effects in Tornado, The Patrician, and Town With No Name.
- Accept short Sound Blaster DMA blocks, blocks shorter than one output period, and DMA buffers up to 64 KB. This fixes the sound in The Incredible Machine 2 and Alien Terminator.
- Accept DSP commands 00h and 38h, the busy bit on DSP status reads, the length of DSP 4 Cxh commands, starts without arguments, and DSP commands 04h, 05h, 0Eh, and 0Fh. This fixes the sound startup in The Case of the Cautious Condor, Murder Makes Strange Deadfellows, Necromantics, Panic Soldier, Tornado, and Unlimited Warriors.
- Trap the DMA master clear and mask-all ports, and split word writes to the PIC and wide Sound Blaster port access into bytes. This fixes the sound in Assault Rigs, Oscar, and The End of the World.
- Pass the PIC initialization words, follow the rotated PIC priority, and send the EOI to the hardware for an owned interrupt that is in service. Sound no longer stops while the mouse moves in Magic Carpet 2 and XS, and Creature Shock starts.
- Fill the CD-Audio queue from the Sound Blaster interrupt when a game stops the timer. This fixes the CD-Audio in Future Dimension and Judge Dredd.
- Do not let a key that skips an intro stop a CD-Audio refill in DOS. Wait for the rest of a DSP command before a refill. This fixes the stopped CD-Audio and the hang in Prototype.
- Remove old mouse bytes before each BIOS mouse setup call. The mouse no longer stays still in On the Ball, Golden Immortal, Syndicate Wars, Thunderscape, and XS when it moves while the game loads.
- Ignore the request length of CD-ROM IOCTL and read requests, and stop reads at the lead-out. This fixes the CD access in Jetstrike, Lollypop, Tao, Angst, Necromantics, and Pinball Prelude.
- Mount CUE sheets that have only audio tracks. This fixes Edna and Defender of the Crown.
- Return the status for a repeated INIT request and follow the file table entry of open handles. This fixes Ultimate Body Blows.
- Start the disk cache after DOS starts. This fixes the exception when MechWarrior 2: Ghost Bear's Legacy asks for the next disc during installation.
- DPMI host: run the handlers of a parent program with the parent's settings while a child program runs, and share the parent's descriptors, callbacks, and interrupt vectors. This fixes the start and the sound effects of Judge Dredd, and Track Attack and Maximum Roadkill.
- DPMI host: reflect INT 2Bh, translate DOS EXEC and more 32-bit DOS calls, and pass register-only mouse and multiplex calls. This fixes B.I.G., Genocide 2, Crusade, and Napion 3D.
- DPMI host: report the real memory totals, detect the CPU, clear new pages, reuse freed blocks, and find free linear space faster. This fixes Hardball 4, X-Men: Children of the Atom, and Tao, and makes Mr. Tomato, Star Command: Revolution, and Queen: The Eye load faster.
- DPMI host: handle STI, interrupt-flag, and INT nn faults from programs, and deliver real-mode interrupts that wait at the end of the audio interrupt. This fixes the Command & Conquer expansions, On the Ball, and Metal Rage.
- Add a Chorus Line visualization to UCDDPLAY. A row of gold and chrome vector dancers with linked arms kicks in a wave. Louder frequency bands give higher kicks.
- Add 133 games to the list of working Redbook-audio games. FIFA International Soccer and Rugby World Cup 95 need `UCDD -install -vcpi`.

# Beta 0.9.4-a2

## Changes in 0.9.4-a2

- Accept CD-ROM requests with a short or zero length field when the command uses only the static header, and accept play requests with a zero length field. This fixes the missing CD music in Tunnel B1.
- Mount CD images whose ISO volume descriptor states a volume larger than the image or has a nonstandard root directory record. This fixes the mount of The City of Lost Children, FX Fighter, and Hexen.
- Support word reads of the Sound Blaster mixer index and data ports, and byte reads of the mixer index port. This fixes the startup crash in Hexen.
- Play Sound Blaster PCM from DMA buffers above 1 MB for 8-bit and 16-bit, mono and stereo, single-cycle and auto-initialize transfers. Accept detection blocks that are longer than their DMA buffer. This fixes the sound initialization error in MadSpace.
- Pass display configuration, palette, and VBE mode and window calls (INT 10h) from 16-bit protected-mode programs to the BIOS. This fixes the "not VGA" error in MadSpace.
- Report a pending DMA request and the terminal count in the DMA status registers. This fixes the sound initialization error in Earth 2140.
- Support the DSP silence command (80h). This fixes the stopped sound effects in The Varginha Incident.
- Add a Vector Balls visualization to UCDDPLAY. A gold and a chrome strand of shaded balls turn as a double helix. Louder frequency bands make the helix wider and the balls larger.
- Use a 128-frame audio output period instead of 32 frames. Sound no longer crackles or stops while a mouse driver holds the mouse interrupt for several milliseconds. The resident driver uses about 1.5 KB more conventional memory.
- Add Earth 2140, Extreme Assault, Grand Theft Auto, Hexen: Beyond Heretic, Ignition, Iron Man and X-O Manowar in Heavy Metal, MadSpace, Mass Destruction, Network Q RAC Rally Championship, Nihilist, Nitro Racers, Power F1, Redneck Rampage, Roketz, Shadow Warrior, Star General, Syndicate Wars, Tempest 2000, The City of Lost Children, The Varginha Incident, Tunnel B1, X-Men: The Ravages of Apocalypse, XS, Z.A.R., and the English edition of Dráscula to the list of working Redbook-audio games.

# Beta 0.9.4-a1

## Changes in 0.9.4-a1

- Extend bounded protected-mode instruction decoding for stack operations, address calculations, zero-extension loads, and register arithmetic.
- Skip virtual debug-register scans when no client breakpoints are enabled.
- Run protected-mode code with the virtual interrupt flag off at full speed. The host marks these regions with the NT flag and steps the program only while an interrupt waits. Settlers II missions load in about 19 seconds instead of about 115 seconds.
- Start CD-Audio tracks faster. A play request reads 32 KB before it returns, and the timer fills the rest of the queue. A play request in Fascination takes about 34 ms instead of about 550 ms, and the mouse no longer stops at each track start.
- Move the command parser, help text, and CUE and MDM code of UCDD.EXE into a second segment. This gives about 19.5 KB of room for resident code. The resident size does not change.
- Keep the interrupted program's stack frame when a raw mode switch returns to protected mode during a host real-mode call. This fixes the crash on the table load in Absolute Pinball, a regression from 0.9.3a.
- Seek and the location IOCTL now work on ISO images. Data reads accept Red Book addresses.
- An application eject on a multi-disc set no longer releases the whole set.
- `UCDD -unmount` accepts the CUE file name. CUE files with a UTF-8 byte-order mark or with INDEX 02 and higher now mount.
- Apply the game volume once to direct DAC output. Reject invalid DSP sample rates and drop the remaining bytes of a rejected DSP command.
- UCDDSET keeps the old UCDD.CFG when a save fails, ignores Ctrl+Break, and stops the capture of the key that started it.
- UCDDPLAY: fix the calendar click on track 10, discs that start after track 1, and the READ LONG request length.
- Show the version in the startup notice of UCDD, UCDDSET, and UCDDPLAY, and in the installation message.
- Recommend that the mouse driver loads before uCDD.

# Beta 0.9.4

## Changes in 0.9.4

- Add a Cubes visualization to UCDDPLAY. Eight rotating wireframe cubes change size with the frequency levels.

- Support the Borland runtime used by Super Street Fighter II Turbo. Translate its protected-mode DOS buffers and PSP queries, supply its vendor API, and accept unchanged CR0 writes.
- Clear the direction flag before preparing DOS register frames and preserve interrupted registers across protected-mode hardware handlers. This fixes startup and gameplay crashes in Super Street Fighter II Turbo.
- Add Super Street Fighter II Turbo to the list of working Redbook-audio games. Start SF2TURBO directly to bypass MAKESWP.
- Grow the DPMI memory-block table in extended memory when needed. This fixes false out-of-memory errors in Carmageddon's high-resolution and 3dfx modes when the game needs more than 256 memory blocks.
- Add MechWarrior 2: 31st Century Combat and MechWarrior 2: Mercenaries to the list of working Redbook-audio games.
- Forward real-mode BIOS timer callbacks to protected-mode DPMI handlers.
- Support demand-mode DMA and PIC special mask mode used by Wipeout. Use a specific EOI for the output IRQ so that the mixer can run when the game masks an interrupt.
- Accept word and dword PIC acknowledgements used by the Wipeout intro. Keep the interrupt mask unchanged and preserve real IRQ acknowledgement ownership.
- Preserve deferred physical IRQs when a protected-mode program ends. Complete them on the restored real-mode interrupt chain, and keep pending IRQs when a child returns to its parent. This fixes ignored keyboard input after the Wipeout intro.
- Decode simple 16-bit register instructions in bounded groups, and read the code size again for each instruction.
- Add The Settlers II: Veni, Vidi, Vici (DOS Gold Edition 1.51) to the list of working Redbook-audio games.
- Add Wipeout to the list of working Redbook-audio games.
- Preserve the saved real-mode interrupt chain when a protected-mode handler returns through the same hardware interrupt bridge. This fixes the Fatal Racing intro startup freeze.
- Hide VCPI detection from child programs while a protected-mode parent is active. This keeps movie sound inside the audio host and fixes the return from movies in Fatal Racing and Worms United.
- Accept Sound Blaster playback requests made before the game programs its masked DMA channel. Read the selected DMA mode port through the physical backend. This fixes missing sound effects and the sound setup error in Manic Karts.
- Add Fatal Racing and Manic Karts to the list of working Redbook-audio games.
- Add Hyper 3-D Pinball to the list of working Redbook-audio games.
- Add Earthworm Jim to the list of working Redbook-audio games.
- Add Earthworm Jim 2 to the list of working Redbook-audio games.
- Put the CD-ROM device header at offset zero. This fixes the driver entry address used by Mortal Kombat 3 during startup.
- Add Mortal Kombat 3 to the list of working Redbook-audio games.
- Add Worms United to the list of working Redbook-audio games.
- Add World Rally Fever: Born on the Road to the list of working Redbook-audio games.
- Add Rise 2: Resurrection (Director's Cut DOS edition) to the list of working Redbook-audio games.
- Add Eradicator (DOS Release Version 1.0) to the list of working Redbook-audio games.
- Add Shattered Steel (DOS 1.14) to the list of working Redbook-audio games.
- Accept a CLTS instruction in virtual-8086 mode when the task-switched bit is already clear. This fixes the first startup fault in the DOS4GW 1.6 runtime used by Diggers 2.
- Hide VCPI detection through simulated real-mode interrupts. Keep VCPI access available for the host's own startup query.
- Preserve virtual interrupt flags when a CLI call uses different return paths. This fixes the timer wait during Diggers 2 startup.
- Accept stereo DMA blocks with an odd number of 16-bit samples. This fixes missing sound effects in Surface Tension.
- Add Surface Tension to the list of working Redbook-audio games.
- Add Heroes of Might and Magic II: The Succession Wars (DOS base game from Deluxe Edition) to the list of working Redbook-audio games.
- Add Diggers 2: Extractors to the list of working Redbook-audio games.

# Beta 0.9.3d

## Changes in 0.9.3d

- Add a Landscape visualization to UCDDPLAY. Frequency levels form wireframe ridges that move from the horizon toward the listener.
- Correct DPMI free-memory information. This fixes false insufficient-memory errors in Warcraft and Warcraft II.
- Accept the fixed CD-ROM control blocks used by Warcraft II and the short control request headers used by SuperKarts.
- Support Sound Blaster interrupt detection with high DSP time constants and 16-bit audio through an 8-bit DMA channel. This fixes sound card detection and sound effects in The Horde.
- Improve conversion of low-rate Sound Blaster PCM with linear interpolation. This reduces distortion in The Horde.
- Keep CD audio refills active when games stop the BIOS timer, as SuperKarts does. Prevent retrace timing from delaying an urgent refill, which caused gaps in The Horde.
- Grow DPMI memory blocks in place when the adjacent address range is free. This fixes a page fault in Inferno.
- Support unsigned 8-bit Sound Blaster 16 single-cycle audio commands with and without FIFO. This fixes sound effects in Inferno.
- Add Alien Logic: A Skyrealms of Jorune Adventure, Inferno, Quarantine, Quarantine II: Road Warrior, SuperKarts, The Horde, and Warcraft II: Tides of Darkness to the list of working Redbook-audio games. Add a note about Alien Logic's CD music behavior.

# Beta 0.9.3c

## Changes in 0.9.3c

- Add a Lissajous visualization to UCDDPLAY. The stereo channels draw an XY trace with fading trails.
- Preserve interrupt ownership when protected-mode programs call real-mode interrupt handlers. This prevents unrelated BIOS interrupt acknowledgments from clearing the virtual Sound Blaster interrupt state and fixes silent or repeating sound effects in Batman Forever.
- Use 16-bit interrupt and callback stacks for 16-bit DPMI programs. This fixes the startup failure in Chasm: The Rift.
- Return the data-read status expected by SHSUCDX while CD audio plays. This fixes the CD check in affected Carmageddon editions with a full installation.
- Add Alpha Storm and Chasm: The Rift to the list of working Redbook-audio games.
- Add a Carmageddon compatibility note for the European editions' SHSUCDX requirement and the high-resolution font repair.

# Beta 0.9.3b

## Changes in 0.9.3b

- Add a Tunnel visualization to UCDDPLAY. Wireframe rings move toward the edge of the bottom window, with speed set by the audio level.
- Allow a DPMI program to start another 16-bit or 32-bit DPMI program and resume when it exits. This lets the Batman Forever installer run its video test and lets Battle Arena Toshinden SETUP start SSETUP.
- Preserve the driver information passed through interrupt E9h by 32-bit programs. This fixes the "DLL load aborted" error when 3dfx games load GLIDE2X.OVL.

# Beta 0.9.3a

## Changes in 0.9.3a

- Add physical audio CD playback to UCDDPLAY.EXE through digital audio extraction. Select a compatible CD drive in Open and use the equalizer, track controls, volume, and eject without an internal audio cable.
- Add a Plasma visualization to UCDDPLAY and rename Stars to Warp Speed.
- Show bordered buttons in UCDDSET and make the virtual-card setup instruction clearer.
- Accept PRE, DCP, 4CH, and SCMS flags in CUE sheets. This lets Destruction Derby mount its CUE sheet without removing the flags.
- Apply CD de-emphasis to audio tracks marked PRE.
- Reduce loading delays caused by protected-mode timer calibration loops, including those in Rayman By His Fans and Rayman Designer.
- Support debug-register access and exception reflection in protected-mode games. This fixes the startup failure in Rayman.
- Support CUE images with a MODE1/2048 data track followed by raw audio tracks. This fixes mounting the CD edition of Betrayal at Krondor.
- Support protected-mode CPU checks used by Little Big Adventure 2 and word writes to the Sound Blaster mixer used by Little Big Adventure.
- Allow larger parameter lists for DPMI real-mode calls. This fixes VESA initialization in Little Big Adventure.
- Fix real-mode interrupt chaining from protected-mode programs. This fixes the startup freeze in Soccer Kid.
- Correct Sound Blaster mixer detection, volume steps, and CD volume control used by Corridor 7.
- Add Betrayal at Krondor, Corridor 7: Alien Invasion, Destruction Derby, Destruction Derby 2, Little Big Adventure, Little Big Adventure 2, Rayman, Rayman 60 Levels, Rayman By His Fans, Rayman Designer, Return to Zork, and ShadowCaster to the list of working Redbook-audio games.
- Add a special thanks section for davidmorom's game testing and compatibility reports.

# Beta 0.9.3

This update adds support for 16-bit DPMI programs, changes how protected-mode games use DPMI and VCPI, and moves all sound card settings into UCDDSET. It adds UCDDPLAY, a CD player for uCDD drives. It also fixes CD-Audio and game sound in many protected-mode games.

## Changes in 0.9.3

- Keep all settings in a new version of UCDD.CFG. `UCDD -install` runs UCDDSET, which must be in the directory of UCDD.EXE. UCDDSET loads the settings, copies them into the driver, and sets BLASTER for the virtual Sound Blaster. It keeps the other BLASTER fields. UCDD no longer reads BLASTER. UCDDSET opens its menu when UCDD.CFG is missing, from an older version, or not valid.
- Initialize the physical card before `UCDD -install`. uCDD no longer sets the IRQ and DMA channels of Sound Blaster 16 and WSS cards.
- Redesign UCDDSET with settings for the physical card, the virtual Sound Blaster, and the virtual WSS codec, and with Hotkeys and Mixer pages.
- Detect the physical card. UCDDSET finds Sound Blaster 16 cards through the mixer, older Sound Blaster cards through an interrupt and DMA test, and WSS codecs. BLASTER supplies only the values that the tests cannot find.
- Select the virtual Sound Blaster model: Sound Blaster 16, Sound Blaster Pro, or Sound Blaster 1.5/2.0. The model sets the DSP version and the BLASTER type. Set the port and the start IRQ of the virtual WSS codec.
- Select the hotkey modifiers, including the Windows key, the disc keys (1 to 0 or F1 to F10), and keys for the next disc, the previous disc, eject, and the CD-Audio volume. Eject and insert discs with a hotkey, for MDM lists and single images.
- Set the start level of CD-Audio, the wave output level, the master volume of the physical card, and the step of the volume hotkeys.
- Fix a crash after UCDDSET returned when UCDD.CFG was missing at installation.
- Shorten the command help of UCDD and UCDDSET.
- Add UCDDPLAY, a VGA CD player for uCDD drives. It has a 10-band equalizer for CD-Audio, a spectrum analyzer, VU meters, shuffle and repeat modes, mouse support, and a requester that mounts and ejects images and MDM lists.
- Support 16-bit DPMI programs, including DOS call translation for Borland Pascal 7 programs, and allow more protected-mode selectors. This fixes the startup failure in Chasm: The Rift.
- Hide the JEMMEX VCPI interface from protected-mode games while uCDD provides DPMI, so that game sound goes through uCDD. Add the `-vcpi` install option for programs that need VCPI. This fixes missing sound and music in Cyberball and Amazing Learning Games with Rayman, and the freeze at the name prompt in An Elder Scrolls Legend: Battlespire.
- Reduce the cost of interrupt-flag emulation for protected-mode games. This removes the slowdown during file access in DOS/4GW games such as Bust-A-Move 2.
- Stop single-stepping protected-mode interrupt and exception handlers.
- Support nested raw mode switches and preserve FS and GS across them. Let disk interrupts reach the BIOS during background CD reads. Accept CD IOCTL input requests with a zero transfer count. This fixes the startup freeze in Absolute Pinball.
- Report the busy status during CD-Audio playback on every request. This fixes repeated music restarts in Batman Forever: The Arcade Game.
- Report the DMA current address and page registers, and accept DSP command 42h. This fixes the startup exception and slow sound setup in Blood.
- Deliver Sound Blaster interrupts during real-mode calls from protected-mode games, and keep interrupt vectors that sound drivers change during a host call. This fixes the freeze at the loading screen in Bust-A-Move 2.
- Accept short auto-initialize blocks, and blocks longer than the DMA buffer. This fixes missing table sounds in Cyberball and missing effects in Cyber Police.
- Support Sound Blaster 16 mixer resets and voice volume registers. This fixes quiet effects in Battle Race.
- Accept Sound Blaster output rates up to 48000 Hz. Support 16-bit mono and unsigned 16-bit game sound.
- Apply the voice level and the wave output level to direct DAC output.
- Support MODE2/2352 Form 1 data tracks in CUE sheets.
- Keep free conventional memory contiguous when DOS loads UCDD into conventional memory and uCDD moves the audio service into upper memory.
- Add Absolute Pinball, Amazing Learning Games with Rayman, An Elder Scrolls Legend: Battlespire, Batman Forever: The Arcade Game, Battle Race, Blood, Bust-A-Move 2 Arcade Edition, Chasm: The Rift, Cyber Police (CYBERPO1.EXE), and Cyberball to the list of working Redbook-audio games.

# Beta 0.9.2c

## Changes in 0.9.2c

- Support advisory CD prefetch requests used by Gobliiins and Gobliins 2.
- Support Sound Blaster direct DAC speech and effects. Support single-cycle 8-bit mono DMA samples above 1 MiB with the JEMM audio backend.
- Prevent a lockup when background CD reads interrupt hardware interrupt handlers.
- Accept contiguous CD reads with a nonzero interleave size and allow reads beyond the ISO volume size within the data track. This fixes resource reads in Fascination.
- Preserve CD information buffer counts and report active CD playback correctly. This fixes repeated music restarts in Future Wars.
- Improve Sound Blaster detection and short-sample interrupt response for The Secret of Monkey Island.
- Correct the DOS startup stack layout for larger executables.
- Keep free conventional memory contiguous when loading the audio service into upper memory.
- Add Fascination, Future Wars, Gobliiins, Gobliins 2: The Prince Buffoon, Goblins Quest 3, and Lost in Time to the list of working Redbook-audio games.
- Add Descent II: Vertigo Series, The Manhole, The Secret of Monkey Island, Realms of Arkania III: Shadows over Riva, and the German CD editions of Realms of Arkania: Blade of Destiny and Star Trail to the list of working Redbook-audio games.
- Add Alien Trilogy, Battle Arena Toshinden, BC Racers, Big Red Racing, and Blam! Machinehead to the list of working Redbook-audio games.

# Beta 0.9.2b

## Changes in 0.9.2b

- Support PREGAP in CUE sheets, with silent gaps and corrected track positions. This lets Loom use its original disc layout and play complete voice prompts.
- Preserve the physical audio interrupt handler when real-mode games write interrupt vectors directly under JEMMEX. This fixes stalled playback and sustained tones in the Alone in the Dark games.
- Add Loom and Alone in the Dark 1, 2, and 3 to the list of working Redbook-audio games.

# Beta 0.9.2a

## Changes in 0.9.2a

- Improve WSS compatibility with Plug and Play codecs, including Crystal CS4236B cards.
- Support IRQ 5 for WSS output and let UCDDSET select IRQ 5 or 7.
- Document the WSS settings for Plug and Play cards.

# Beta 0.9.2

## Changes in 0.9.2

- Batch raw BIN sector reads and compact their payloads in place. This reduces DOS reads and seeks for multi-sector requests.
- Defer blocked timer, keyboard, and mouse interrupts for protected-mode games. This fixes missed key releases and mouse-triggered slowdown in Descent II.
- Add a build-time audio output period option for testing. The standard build retains its 32-frame period.
- Add Descent II to the list of working Redbook-audio games.

# Beta 0.9.1e

This update improves sound playback in Pro Pinball: The Web, reduces audio and protected-mode processing overhead, and lowers conventional-memory use.

## Changes in 0.9.1e

- Support shorter game DMA buffers and reduce audio output latency. This fixes the repeated sound-effect stutter in Pro Pinball: The Web.
- Reduce mixer overhead for silent output, CD-Audio, and 16-bit stereo game sound. Reuse CD samples between output blocks to reduce extended-memory transfers.
- Schedule background CD reads to give games more time to refill their sound buffers. Avoid redundant seeks and add an optional extended-memory cache for disc-image file metadata.
- Preserve pending hardware interrupts while a protected-mode game disables virtual interrupts. Reduce overhead when games poll the timer, display status, or sound card.
- Process simple protected-mode instructions in bounded batches and reduce repeated code and buffer checks.
- Release the host's page-setup workspace after installation. This saves 7.5 KiB of conventional memory when the driver is loaded high.
- Add Pro Pinball: The Web and Pro Pinball: Timeshock! to the list of working Redbook-audio games.

# Beta 0.9.1c

This update fixes Battle Chess Enhanced CD-ROM sound and disc compatibility, and Tomb Raider's shared-IRQ startup failure.

## Changes in 0.9.1c

- Accept mixed-mode disc images whose ISO volume size extends into the audio tracks, while keeping data access within the data track. This fixes mounting the original Battle Chess CUE/BIN image without changing its track boundaries.
- Accept legacy CD control requests used by Battle Chess. This restores CD-Audio playback.
- Support the short Sound Blaster recording transfer used for DMA detection. This fixes Battle Chess's DMA-channel error in original Sound Blaster mode.
- Support combined SB Pro mixer writes and odd-length stereo transfers. This fixes missing or incorrect Battle Chess sound effects in SB Pro mode.
- Honor SB Pro PCM volume and output-filter settings for cleaner legacy sound effects. CD-Audio and SB16 PCM playback retain their existing output quality.
- Preserve the physical audio interrupt handler when protected-mode games write interrupt vectors directly. This fixes Tomb Raider's startup failure when the physical and virtual cards share IRQ5 under JEMMEX.
- Use JEMMEX as the default memory manager in the setup instructions. EMM386 support remains best effort.

# Beta 0.9.1b

This update improves CD access and loading speed in protected-mode DOS games.

## Changes in 0.9.1b

- Support stack arguments in DPMI real-mode interrupt and far-call services. This fixes CD-ROM initialization errors in Pro Pinball: The Web and Timeshock.
- Accept short, non-interleaved CD read requests. This fixes the CD prompts in Screamer, Screamer 2, and Screamer Rally.
- Reuse extended-memory pages and reduce page-table updates, memory clearing, and interrupt-stepping overhead to improve loading speed with resident audio.
- Correct the distinction between a protection fault and physical IRQ 5 under EMM386. This prevents the Screamer reset when CD audio starts with that interrupt configuration.
- Add an optional host-profiling build without adding counters to the normal release build.

# Beta 0.9.1a

This update corrects interrupt timing in the internal protected-mode host. It retains the audio changes from Beta 0.9.1.

## Changes in 0.9.1a

- Honor the one-instruction interrupt delay after `STI`. Preserve this state across callbacks and defer pending hardware and sound interrupts until delivery is permitted.
- Allocate a separate entry stack for the standalone development host, and free it when the host exits. This avoids the layout-sensitive stack failures seen while testing the larger host.
- Document Microsoft EMM386's shared-DMA limitation and the JEMMEX or separate-channel alternatives. This release does not attempt to recover physical DMA programming after a game overwrites it.


# Beta 0.9.1

This beta fixes CD access and mixed-audio problems in protected-mode DOS games. CD music and game PCM still use the same physical Sound Blaster output.

## Changes

- Correct interrupt delivery during protected-mode disk calls and real-mode callbacks. This fixes the reproduced Tomb Raider startup stall after the DOS/4GW banner.
- Run background CD reads after the protected interrupt handler returns. This fixes Tomb Raider effects that played a short beginning and then restarted while CD music was active.
- Keep hardware interrupt requests pending when all four interrupt stacks are in use. This prevents the reproduced interrupt-stack exhaustion abort without adding more stacks.
- Correct interrupt stepping, mixed-width return frames, and nested stack ownership. Process supported REP copy/fill instructions in bounded batches.
- Preserve the physical audio interrupt route when games change their virtual PIC mask. Keep real-mode port traps active during protected-mode calls and route sound interrupts to the handler that owns them.
- Correct the PCM consumption clock, pause behavior, non-power-of-two DMA rings, and single-cycle 16-bit transfers. A small tail cache preserves samples while a game refills its ring buffer.
- Support the reset-port read and short stereo transfer used by Archimedean Dynasty during sound detection.
- Recover CD playback after a queue underrun and increase the refill budget. Failed XMS operations still stop playback.
- Correct callback-slot reuse and host cleanup ordering.
- Support the changed port-trap callback interface tested with JEMMEX 5.87pre1, as well as 5.86.
