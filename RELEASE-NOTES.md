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

## Validation and limits

Tomb Raider passed startup, menu/demo playback, and a user listening check with the release driver in 86Box with 128 MB. Both effects and CD music sounded normal. This was a bounded test, not a long-session stability test.

Carmageddon passed an uninterrupted driving interval with effects and CD music using an earlier development build. A brief loading stutter was reported. An intermittent timer-return crash captured in an earlier build is not proven fixed by this release.

Archimedean Dynasty passed mission-start effects and CD music using an earlier development build. Its CauseWay configuration was forced to use DPMI. The fixture used physical 16-bit DMA channel 7 and virtual channel 5. Idle mission playback does not establish continuous effects playback, and shared-channel operation is not validated.

Quake passed startup, a Start-map firing interval, and a menu transition with the release driver in the same 128 MB 86Box fixture. The original CD image was mounted through uCDD. The user confirmed that both music and game sound were normal. This used uCDD's internal host, not a separate CWSDPMI host; it does not establish all CWSDPMI or memory-manager combinations.

Focused regression tests use IzarraVM in 386 interpreter mode with 128 MB. They check audio samples, DMA position and completion, interrupt capacity and return frames, deferred CD reads, callback reuse, and real/protected-mode sound-handler ownership.

The new cache uses 2 KiB of scratch storage. In the checked one-unit load-high fixture, driver code, scratch storage, and host support blocks were in upper memory; the DMA output buffer used 8192 bytes of conventional memory plus its DOS allocation header. Placement depends on available upper memory.

JEMM386 and 386MAX support is not established. Debugger coexistence is not validated. This beta has no new real-hardware validation. ADPCM remains unsupported.

## Package

The archives contain `UCDD.EXE`, `UCDDSET.EXE`, documentation, the GPL-3.0-only license, and corresponding project source in `SOURCE.ZIP`. Install external dependencies separately. See `BUILDING.md` to rebuild the programs.
