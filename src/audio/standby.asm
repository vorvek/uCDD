; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; Stepping aside. While no mounted image is bound for CD audio and the
; virtual card is one the physical card can be at the same port, IRQ and DMA
; channels, the driver has nothing to add to the game's sound: the physical
; output stops, the card's and the controllers' ports are untrapped, and the
; host neither offers DPMI nor hides VCPI, so a game talks to the real card
; and runs as it does without the driver. The state changes only from the
; control entry, at a mount or an eject, and at the end of the install, never
; while a game runs. config_audio_always keeps the output on.

audio_engaged db 1

; Carry clear when stepping aside is allowed: the switch off and the cards
; paired (audio/pairing.asm, shared with UCDDSET).
audio_pairing:
    cmp byte [config_audio_always], 0
    jne .no
    jmp card_pairing
.no:
    stc
    ret

%include "audio/pairing.asm"

; From the control entry after a mount or an eject, and from the end of the
; install: engage or step aside as the bound disc and the pairing require.
; DS=CS, the driver's stack, interrupts on, InDOS clear (the control entry
; checks it) or inside dos_enter. Engaging must not fail where the install
; succeeded: the same calls run on the same card.
audio_reconsider:
    call audio_pairing
    jc .engage
    cmp word [cd_handle], 0ffffh
    jne .engage
%ifdef MDM_SUPPORT
    cmp byte [mdm_audio], 0
    jne .engage
%endif
    cmp byte [audio_engaged], 0
    je .done
    ; Not while a game streams through the virtual card or a client runs
    ; under the host: the next mount or eject decides again.
    cmp byte [game_active], 0
    jne .done
%ifdef OWN_HOST
    cmp word [own_host_active+2], 0
    je .release
    les di, [own_host_active]
    cmp byte [es:di], 0
    jne .done
.release:
%endif
    call audio_release
.done:
    ret
.engage:
    cmp byte [audio_engaged], 0
    jne .done
    call audio_engage
    ret

; The inverse of the install's tail: output stopped (the vector and the PIC
; mask put back, the mixer registers restored, the DSP reset), the ports
; given back, the host dormant. The keyboard port stays trapped for the
; hotkeys, and the timer and BIOS disk hooks stay: they do nothing while
; nothing is bound.
audio_release:
    ; Cleared first: sb_stop puts the old vector back through INT 21h, and
    ; sb_dos_vector must let that call through (it takes a set of the guest
    ; vector for a game's while the driver is engaged).
    mov byte [audio_engaged], 0
    call sb_stop
    call virtual_irq_reset
    mov byte [virtual_pic_service], 0
    call trap_release
    call host_dormant
    mov byte [audio_engaged], 0
    ret

; The install's tail again: the virtual PIC's view of the mask, a silent
; ring, the ports, the card, the host.
audio_engage:
    call virtual_irq_init
    call mix_fill
    call trap_engage
    jc .failed
    ; sb_start hooks the vector through INT 21h while the byte is still
    ; clear, so the call reaches DOS.
    call sb_start
    jc .failed
    call host_wake
    mov byte [audio_engaged], 1
    ret
.failed:
    ; Stepped aside with a disc bound: silent CD audio. audio_report shows
    ; the fault byte.
    or byte [fault], 80h
    ret

; The host's dormant byte: with it set, INT 2Fh AX=1687h chains (no DPMI
; offered) and INT 67h AX=DE00h chains (VCPI visible), so a protected-mode
; game runs under its own extender, as without the driver.
host_dormant:
    mov al, 1
    jmp host_dormant_set
host_wake:
    xor al, al
host_dormant_set:
%ifdef OWN_HOST
    cmp word [own_host_active+2], 0
    je .done
    les di, [own_host_active]
    ; dpmi_dormant, offset 14 of the host's state (host/dpmi.asm).
    mov [es:di+14], al
.done:
%endif
    ret
