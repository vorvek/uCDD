; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%include "audio/wss_codec.asm"

wss_start:
    mov byte [wss_output_board], 0
    mov dx, [sb_base]
    add dx, 3
    call physical_read
    and al, 3fh
    cmp al, 4
    jne .codec
    mov byte [wss_output_board], 1
.codec:
    call wss_ready
    jc .fail
    mov al, 9
    call wss_read
    test al, 3
    jnz .fail
    xor bx, bx
.save:
    mov al, bl
    call wss_read
    mov [wss_saved+bx], al
    inc bx
    cmp bx, 16
    jb .save
    mov byte [wss_saved_valid], 1
    cmp byte [wss_output_board], 0
    je .program
    mov al, 2
    cmp byte [sb_irq], 5
    je .dma_select
    add al, 8
.dma_select:
    cmp byte [sb_dma8], 1
    je .board
    inc al
.board:
    mov dx, [sb_base]
    call physical_write
.program:
    mov ax, 0c49h
    call indexed_write
    mov ax, 5b48h
    call indexed_write
    call wss_calibrate
    jc .restore_fail
    mov ax, 0006h
    call indexed_write
    mov ax, 0007h
    call indexed_write
    mov ax, 020ah
    call indexed_write
    mov ax, ((PERIOD_FRAMES-1) & 0ffh)*256+15
    call indexed_write
    mov ax, ((PERIOD_FRAMES-1) >> 8)*256+14
    call indexed_write
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
    cli
    mov dx, 21h
    call physical_read
    mov [saved_pic], al
    mov cl, [sb_irq]
    mov ah, 1
    shl ah, cl
    not ah
    and al, ah
    call physical_write
    mov dx, 0ah
    mov al, [dma_channel]
    or al, 4
    call physical_write
    mov dx, 0ch
    xor al, al
    call physical_write
    movzx eax, word [output_segment]
    shl eax, 4
    mov ebx, eax
    mov dx, [dma_address_port]
    call physical_write
    mov al, ah
    call physical_write
    shr ebx, 16
    mov al, bl
    mov dx, [dma_page_port]
    call physical_write
    mov ax, RING_BYTES-1
    mov dx, [dma_count_port]
    call physical_write
    mov al, ah
    call physical_write
    mov al, [dma_channel]
    or al, 58h
    mov dx, 0bh
    call physical_write
    mov al, [dma_channel]
    mov dx, 0ah
    call physical_write
    mov dx, [sb_base]
    add dx, 6
    xor al, al
    call physical_write
    mov ax, 0d09h
    call indexed_write
    mov byte [sb_running], 1
    sti
    clc
    ret
.restore_fail:
    call wss_restore
.fail:
    stc
    ret
wss_stop:
    cmp byte [sb_running], 0
    je .done
    mov ax, 0c09h
    call indexed_write
    mov dx, 0ah
    mov al, [dma_channel]
    or al, 4
    call physical_write
    mov dx, [sb_base]
    add dx, 6
    xor al, al
    call physical_write
    mov dx, 21h
    mov al, [saved_pic]
    call physical_write
    push ds
    lds dx, [old_irq]
    mov al, [sb_irq]
    add al, 8
    mov ah, 25h
    int 21h
    pop ds
    mov byte [sb_running], 0
    call wss_restore
.done:
    ret
wss_restore:
    cmp byte [wss_saved_valid], 0
    je .done
    mov al, 49h
    mov ah, [wss_saved+9]
    call indexed_write
    mov al, 48h
    mov ah, [wss_saved+8]
    call indexed_write
    call wss_calibrate
    xor bx, bx
.register:
    cmp bl, 8
    je .next
    cmp bl, 9
    je .next
    cmp bl, 11
    je .next
    cmp bl, 12
    je .next
    mov al, bl
    mov ah, [wss_saved+bx]
    call indexed_write
.next:
    inc bx
    cmp bx, 16
    jb .register
    mov byte [wss_saved_valid], 0
.done:
    ret
wss_saved times 16 db 0
wss_saved_valid db 0
wss_output_board db 0
