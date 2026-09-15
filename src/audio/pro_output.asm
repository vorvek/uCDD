; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

pro_start:
    call physical_reset
    jc .fail
    cmp byte [sound_card], 3
    je .dma
    mov si, pro_registers
    mov di, pro_saved
    mov cx, 3
.save:
    mov dx, [sb_base]
    add dx, 4
    lodsb
    call physical_write
    inc dx
    call physical_read
    mov [di], al
    inc di
    loop .save
    mov al, 22h
    mov ah, 0ffh
    call indexed_write
    mov ax, 0ff04h
    call indexed_write
    mov al, 0eh
    mov ah, [pro_saved+2]
    or ah, 22h
    call indexed_write
.dma:
    mov al, [sb_dma8]
    mov [dma_channel], al
    movzx bx, al
    shl bx, 1
    mov [dma_address_port], bx
    inc bx
    mov [dma_count_port], bx
    mov word [dma_page_port], 83h
    cmp al, 1
    je .irq
    mov word [dma_page_port], 82h
.irq:
    mov al, [sb_irq]
    add al, 8
    mov ah, 35h
    int 21h
    mov [old_irq], bx
    mov [old_irq+2], es
    mov dx, audio_irq
    mov al, [sb_irq]
    add al, 8
    mov ah, 25h
    int 21h
    mov dx, 21h
    call physical_read
    mov [saved_pic], al
    mov cl, [sb_irq]
    mov ah, 1
    shl ah, cl
    not ah
    and al, ah
    call physical_write
    mov byte [sb_running], 1
    cmp byte [sound_card], 3
    je .mono
    mov byte [pro_priming], 1
    mov es, [output_segment]
    mov byte [es:RING_BYTES/4], 80h
    mov bx, RING_BYTES/4
    xor cx, cx
    mov ah, 48h
    call pro_dma
    mov al, 0d1h
    call dsp_write
    mov al, 14h
    call dsp_write
    xor al, al
    call dsp_write
    xor al, al
    call dsp_write
    jc .stop_failed
    mov cx, 65535
.prime:
    cmp byte [pro_priming], 0
    je .start
    loop .prime
    call pro_stop
    stc
    ret
.start:
    xor bx, bx
    mov cx, RING_BYTES/4-1
    mov ah, 58h
    call pro_dma
    mov al, 40h
    call dsp_write
    mov al, 233
    call dsp_write
    mov al, 48h
    call dsp_write
    mov al, (PERIOD_BYTES/4-1) & 0ffh
    call dsp_write
    mov al, (PERIOD_BYTES/4-1) >> 8
    call dsp_write
    mov al, 90h
    call dsp_write
    jc .stop_failed
    clc
    ret
.mono:
    xor bx, bx
    mov cx, RING_BYTES/8-1
    mov ah, 58h
    call pro_dma
    mov al, 40h
    call dsp_write
    mov al, 211
    call dsp_write
    mov al, 0d1h
    call dsp_write
    call sb_mono_next
    jc .stop_failed
    clc
    ret
.stop_failed:
    call pro_stop
.fail:
    stc
    ret

sb_mono_next:
    mov al, 14h
    call dsp_write
    mov al, (PERIOD_BYTES/8-1) & 0ffh
    call dsp_write
    mov al, (PERIOD_BYTES/8-1) >> 8
    jmp dsp_write

pro_dma:
    pushf
    cli
    push ax
    mov dx, 0ah
    mov al, [dma_channel]
    or al, 4
    call physical_write
    mov dx, 0ch
    xor al, al
    call physical_write
    movzx eax, word [output_segment]
    shl eax, 4
    movzx ebx, bx
    add eax, ebx
    mov ebx, eax
    mov dx, [dma_address_port]
    call physical_write
    mov al, ah
    call physical_write
    shr ebx, 16
    mov al, bl
    mov dx, [dma_page_port]
    call physical_write
    mov ax, cx
    mov dx, [dma_count_port]
    call physical_write
    mov al, ah
    call physical_write
    pop ax
    mov al, [dma_channel]
    or al, ah
    mov dx, 0bh
    call physical_write
    mov al, [dma_channel]
    mov dx, 0ah
    call physical_write
    popf
    ret

pro_stop:
    cmp byte [sb_running], 0
    je .done
    call physical_reset
    mov al, 0d3h
    call dsp_write
    mov dx, 0ah
    mov al, [dma_channel]
    or al, 4
    call physical_write
    mov dx, [sb_base]
    add dx, 0eh
    call physical_read
    mov dx, 21h
    mov al, [saved_pic]
    call physical_write
    push ds
    mov al, [sb_irq]
    add al, 8
    lds dx, [old_irq]
    mov ah, 25h
    int 21h
    pop ds
    cmp byte [sound_card], 3
    je .stopped
    xor bx, bx
.restore:
    mov al, [pro_registers+bx]
    mov ah, [pro_saved+bx]
    call indexed_write
    inc bx
    cmp bx, 3
    jb .restore
.stopped:
    mov byte [sb_running], 0
.done:
    ret

pro_registers db 22h,04h,0eh
pro_saved times 3 db 0
pro_priming db 0
