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
    call fast_dma_clear
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
    call fast_dma_set
    call host_wake
    mov byte [audio_engaged], 1
    ret
.failed:
    ; Stepped aside with a disc bound: silent CD audio. audio_report shows
    ; the fault byte.
    or byte [fault], 80h
    ret

; Platform fast DMA on the output channel (docs/platform-dma.md): the
; timing the chipset's sheet gives for an ISA DMA slave, by the method the
; platform scan found (platform.asm), while the output runs. The output only
; reads memory (single, increment), which every method allows; nothing
; records through the physical channel. Only with the UCDDSET switch on. Set
; when the output starts, the channel's old timing put back when it stops,
; steps aside or unloads. PCI registers go through the PCI BIOS. Every
; register is kept.
fast_dma_set:
    cmp byte [config_fast_dma], 0
    je .quick
    cmp byte [fast_dma_active], 0
    jne .quick
    pusha
    movzx bx, byte [fast_dma_method]
    test bx, bx
    jz .done
    ; The output channel: the high one on an SB16, the low one elsewhere.
    mov al, [sb_dma8]
    cmp byte [sound_card], 0
    jne .channel
    mov al, [sb_dma16]
.channel:
    and al, 7
    mov [fast_dma_channel], al
    shl bx, 2
    call [fast_dma_methods+bx-4]
    jc .done
    mov byte [fast_dma_active], 1
.done:
    popa
.quick:
    ret
fast_dma_clear:
    cmp byte [fast_dma_active], 0
    je .quick
    pusha
    mov byte [fast_dma_active], 0
    movzx bx, byte [fast_dma_method]
    shl bx, 2
    call [fast_dma_methods+bx-2]
    popa
.quick:
    ret
; Each method's set (CF set: nothing changed) and restore, by method number.
fast_dma_methods:
    dw fast_dma_mbdma, fast_dma_restore
    dw fast_dma_dcem_f, fast_dma_dcem_restore
    dw fast_dma_dcem_a, fast_dma_dcem_restore
    dw fast_dma_via45, fast_dma_restore
    dw fast_dma_sis71, fast_dma_restore

; Intel PIIX, PIIX3, PIIX4: Type F through MBDMA0 (76h), or MBDMA1 (77h) when
; the BIOS uses MBDMA0 for another channel: bit 7 FAST, bits 2:0 the channel
; (100b none), bits 6:3 kept as read (the PIIX3 and PIIX4 hold reserved bits
; there; the PIIX4's bit 3 reads 1). On the original PIIX bit 3 is DMC: 1
; takes the ISA slot's DREQ and DACK#; at 0 a motherboard device's pair is
; routed to the channel and the card is cut off (PIIX/PIIX3 sheet, MBDMA).
fast_dma_mbdma:
    mov di, 76h
.register:
    call fast_dma_read
    jc .refused
    mov ah, [fast_dma_channel]
    or ah, 80h
    mov al, cl
    and al, 87h
    ; Already Type F for this channel (the BIOS set it): nothing to do.
    cmp al, ah
    je .refused
    ; In use: Type F for another channel, or on the PIIX a motherboard
    ; device's DMA routed by the BIOS (DMC clear, a channel set).
    test cl, 80h
    jnz .other
    cmp word [fast_dma_device], 122eh
    jne .free
    test cl, 8
    jnz .free
    mov al, cl
    and al, 7
    cmp al, 4
    jne .other
.free:
    mov [fast_dma_saved], cl
    mov [fast_dma_register], di
    and cl, 78h
    cmp word [fast_dma_device], 122eh
    jne .bits
    and cl, 70h
    or cl, 8
.bits:
    or cl, ah
    jmp fast_dma_write
.other:
    cmp di, 77h
    je .refused
    mov di, 77h
    jmp .register
.refused:
    stc
    ret

; The DMA Channel Extended Mode register, write only: 40Bh for channels 0-3,
; 4D6h for 5-7, bits 1:0 the channel. ALi and OPTi (Viper-M, FireStar):
; Type F (bits 5:4 = 11), bits 3:2 written 0 as their sheets say (reserved,
; or not implemented; docs/platform-dma.md section 8). Intel SIO and EISA:
; Type A (01) and bits 3:2 the size as at reset, 00 8-bit, 01 16-bit words.
; The restore writes the reset value.
fast_dma_dcem_f:
    mov ah, 30h
    jmp fast_dma_dcem
fast_dma_dcem_a:
    mov ah, 10h
fast_dma_dcem:
    call fast_dma_dcem_size
    or al, ah
    out dx, al
    clc
    ret
fast_dma_dcem_restore:
    call fast_dma_dcem_size
    out dx, al
    ret
; DX=the channel's DCEM port, AL=its size bits and channel bits.
fast_dma_dcem_size:
    mov al, [fast_dma_channel]
    mov dx, 40bh
    cmp al, 4
    jb .size
    mov dx, 4d6h
    and al, 3
    cmp byte [fast_dma_method], PLATFORM_DCEM_A
    jne .size
    or al, 4
.size:
    ret

; VIA VT82C586 to VT8231 and the AMD-756: config 45h, bit n for channel n
; (0-3), bit n-1 for 5-7: the channel's DMA clock doubled, zero wait states
; on the AMD-756. VIA's 41h bit 3, the same for every channel, stays as the
; BIOS left it.
fast_dma_via45:
    mov cl, [fast_dma_channel]
    cmp cl, 4
    jb .bit
    dec cl
.bit:
    mov di, 45h
    jmp fast_dma_bit
; SiS 5597, 5598, 5582: config 71h, bit n for channel n (bit 4 reserved),
; which the chip takes only while 70h bit 7 (its DMA prefetch and post-write
; buffer) is set.
fast_dma_sis71:
    mov di, 70h
    call fast_dma_read
    jc .refused
    test cl, 80h
    jz .refused
    mov cl, [fast_dma_channel]
    mov di, 71h
    jmp fast_dma_bit
.refused:
    stc
    ret
; DI=the register, CL=the bit: set it, the old byte kept for the restore.
fast_dma_bit:
    mov al, 1
    shl al, cl
    call fast_dma_read
    jc .done
    test cl, al
    jnz .refused
    mov [fast_dma_saved], cl
    mov [fast_dma_register], di
    or cl, al
    jmp fast_dma_write
.refused:
    stc
.done:
    ret
; MBDMA, VIA, SiS: the register's byte from before.
fast_dma_restore:
    mov di, [fast_dma_register]
    mov cl, [fast_dma_saved]
    jmp fast_dma_write

; CL=the bridge's config byte DI, or CF set. AX kept.
fast_dma_read:
    push ax
    push bx
    mov bx, [fast_dma_bridge]
    mov ax, 0b108h
    int 1ah
    jc .failed
    test ah, ah
    jnz .failed
    pop bx
    pop ax
    clc
    ret
.failed:
    pop bx
    pop ax
    stc
    ret
; The bridge's config byte DI = CL; CF set when the BIOS refused.
fast_dma_write:
    mov bx, [fast_dma_bridge]
    mov ax, 0b10bh
    int 1ah
    jc .done
    test ah, ah
    jz .done
    stc
.done:
    ret

; Set at install from the platform scan (platform.asm).
fast_dma_method db 0
fast_dma_bridge dw 0
; The bridge's PCI device ID (the PIIX's DMC bit).
fast_dma_device dw 0
fast_dma_active db 0
fast_dma_channel db 0
; The register set and its byte before (MBDMA, VIA, SiS).
fast_dma_register dw 0
fast_dma_saved db 0

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
