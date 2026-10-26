; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; Carry clear when the physical card can stand in for the virtual one at the
; same port, IRQ and DMA channels: the rule the driver steps aside by, and
; the rule UCDDSET greys its "always on" box by. Shared by both.
card_pairing:
    mov ax, [sb_base]
    cmp ax, [virtual_base]
    jne .no
    mov al, [sb_irq]
    cmp al, [virtual_irq]
    jne .no
    mov al, [sb_dma8]
    cmp al, [virtual_dma8]
    jne .no
    ; AL physical model (0 SB16, 1 SB Pro, 2 WSS, 3 SB 1.5/2.0), AH virtual
    ; model (0 SB16, 1 SB Pro, 3 SB 1.5/2.0).
    mov al, [sound_card]
    mov ah, [virtual_model]
    test al, al
    jnz .not_sb16
    ; An SB16 is every virtual model; its own needs the high channel too.
    test ah, ah
    jnz .yes
    mov al, [sb_dma16]
    cmp al, [virtual_dma16]
    jne .no
    jmp .yes
.not_sb16:
    ; An SB Pro is an SB Pro or an SB 1.5/2.0; an SB 1.5/2.0 only itself. A
    ; WSS codec is nothing a Sound Blaster driver finds.
    cmp al, 1
    jne .not_pro
    cmp ah, 1
    je .yes
    cmp ah, 3
    je .yes
    jmp .no
.not_pro:
    cmp al, 3
    jne .no
    cmp ah, 3
    je .yes
.no:
    stc
    ret
.yes:
    clc
    ret

