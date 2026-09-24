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
