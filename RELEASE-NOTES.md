# Beta 0.9.1a

This update corrects interrupt timing in the internal protected-mode host. It retains the audio changes from Beta 0.9.1.

## Changes in 0.9.1a

- Honor the one-instruction interrupt delay after `STI`. Preserve this state across callbacks and defer pending hardware and sound interrupts until delivery is permitted.
- Allocate a separate entry stack for the standalone development host, and free it when the host exits. This avoids the layout-sensitive stack failures seen while testing the larger host.
- Document Microsoft EMM386's shared-DMA limitation and the JEMMEX or separate-channel alternatives. This release does not attempt to recover physical DMA programming after a game overwrites it.

## Validation and limits in 0.9.1a

All 11 focused interrupt-delay cases passed in 86Box. All 25 standalone host lifecycle cases passed in IzarraVM in 386 interpreter mode with 128 MB. The standalone core lifecycle case fails in 86Box with both the unchanged 0.9.1 host and this update; the lifecycle result is specific to the IzarraVM harness.

In the checked one-unit load-high fixture, the final driver used 8192 bytes of conventional memory for its DMA buffer plus the 16-byte DOS allocation header. The resident code and scratch buffer were in upper memory. Available upper-memory space affects placement.

The final release binary reached Quake gameplay and the Tomb Raider demo in 86Box with 128 MB. Game PCM and CD playback advanced with no driver fault or CD error. These were bounded runtime checks; the listening confirmations below apply to the preceding development build.

The preceding development build passed bounded Tomb Raider, Quake, and Carmageddon checks in 86Box with 128 MB. Archimedean Dynasty reached a mission with both game PCM and CD music under JEMMEX 5.87pre1 using shared physical and virtual DMA channel 5. The user confirmed normal mission audio. Crackling reported during its loading stage remains unresolved.

Microsoft EMM386 with shared DMA 5 failed the Archimedean Dynasty menu audio check. Physical DMA 7 with virtual DMA 5 sustained menu PCM; gameplay with that configuration was not checked in this review. The experimental DMA recovery code is not included in this release.

These checks do not establish long-session stability, all DOS extender combinations, or real-hardware compatibility. The limits listed for Beta 0.9.1 below still apply.

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

Tomb Raider passed startup and menu/demo playback with the release driver in 86Box with 128 MB. Both audio sources stayed active through the final untouched interval, with no driver CD error or host exit. Listening checks of the preceding development builds confirmed normal effects and CD music, without the repeated-start symptom. These were bounded checks, not long-session stability tests.

Carmageddon passed an uninterrupted driving interval with effects and CD music using an earlier development build. A brief loading stutter was reported. An intermittent timer-return crash captured in an earlier build is not proven fixed by this release.

Archimedean Dynasty passed mission-start effects and CD music using an earlier development build. Its CauseWay configuration was forced to use DPMI. The fixture used physical 16-bit DMA channel 7 and virtual channel 5. Idle mission playback does not establish continuous effects playback, and shared-channel operation is not validated.

Quake passed startup, a Start-map firing interval, and a menu transition with the release driver in the same 128 MB 86Box fixture. The original CD image was mounted through uCDD. The user confirmed that both music and game sound were normal. This used uCDD's internal host, not a separate CWSDPMI host; it does not establish all CWSDPMI or memory-manager combinations.

Focused regression tests use IzarraVM in 386 interpreter mode with 128 MB. They check audio samples, DMA position and completion, interrupt capacity and return frames, deferred CD reads, callback reuse, and real/protected-mode sound-handler ownership.

The new cache uses 2 KiB of scratch storage. In the checked one-unit load-high fixture, driver code, scratch storage, and host support blocks were in upper memory; the DMA output buffer used 8192 bytes of conventional memory plus its DOS allocation header. Placement depends on available upper memory.

JEMM386 and 386MAX support is not established. Debugger coexistence is not validated. This beta has no new real-hardware validation. ADPCM remains unsupported.

## Package

The archives contain `UCDD.EXE`, `UCDDSET.EXE`, documentation, the GPL-3.0-only license, and corresponding project source in `SOURCE.ZIP`. Install external dependencies separately. See `BUILDING.md` to rebuild the programs.
