; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h
%define VIRTUAL_IRQ 1
%define OUTPUT_SHIFT 9
%include "audio/layout.inc"
    jmp start

%include "audio/trap.asm"
%include "audio/irq.asm"

%macro write_port 2
    mov dx, %1
    mov al, %2
    call write
%endmacro
%macro start16 1
    write_port 22ch, 0b6h
    write_port 22ch, 30h
    write_port 22ch, (%1-1) & 0ffh
    write_port 22ch, (%1-1) >> 8
%endmacro

start:
    write_port 0ch, 0
    write_port 3, 34h
    write_port 0d8h, 0
    write_port 0c4h, 0
    write_port 0c4h, 90h
    write_port 8bh, 7
    write_port 0c6h, 0ffh
    write_port 0c6h, 0fh
    write_port 3, 12h
    write_port 0d4h, 1
    start16 1024
    cmp byte [fault], 0
    jne failed
    cmp word [game_dma], dma16
    jne failed
    cmp word [game_segment], 7200h
    jne failed
    cmp dword [game_limit], 2048*65536
    jne failed
    cmp word [game_block_bytes], 2048
    jne failed
    write_port 0ch, 0
    mov dx, 3
    call read
    cmp al, 34h
    jne failed
    call read
    cmp al, 12h
    jne failed
    mov byte [game_start_pending], 0
    mov dword [game_started], 0
    write_port 0d8h, 0
    mov dx, 0c6h
    call read
    cmp al, 0ffh
    jne failed
    call read
    cmp al, 0eh
    jne failed
    mov dword [periods], 2
    call virtual_irq_tick
    cmp byte [virtual_dsp_irq], 2
    jne failed
    mov dx, 22eh
    call read
    cmp byte [virtual_dsp_irq], 2
    jne failed
    mov dx, 22fh
    call read
    cmp byte [virtual_dsp_irq], 0
    jne failed
    write_port 22ch, 0d0h
    cmp byte [game_active], 1
    jne failed
    write_port 22ch, 0d5h
    cmp byte [game_active], 0
    jne failed

    write_port 0d8h, 0
    write_port 0c4h, 0
    write_port 0c4h, 7ch
    start16 1024
    cmp byte [fault], 0
    jne failed
    cmp word [game_segment], 6f80h
    jne failed
    start16 1023
    call rejected
    write_port 0d8h, 0
    write_port 0c4h, 0
    write_port 0c4h, 0fch
    start16 1024
    call rejected
    write_port 0d8h, 0
    write_port 0c4h, 0
    write_port 0c4h, 0f8h
    write_port 8bh, 8
    start16 1024
    call rejected
    write_port 0d8h, 0
    write_port 0c4h, 0
    write_port 0c4h, 0
    write_port 8bh, 6
    write_port 0c6h, 0ffh
    write_port 0c6h, 7
    write_port 22ch, 41h
    write_port 22ch, 0ach
    write_port 22ch, 44h
    start16 1024
    call rejected
    mov dx, success
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
rejected:
    cmp byte [fault], 1
    jne failed
    mov byte [fault], 0
    mov byte [arguments], 0
    ret
write:
    mov cl, 4
    push cs
    call port_callback
    ret
read:
    xor cl, cl
    push cs
    call port_callback
    ret
physical_write:
    cmp dx, 0d8h
    jne .done
    mov byte [physical_flip], 0
.done:
    ret
physical_read:
    mov al, (RING_WORDS-1-512) & 0ffh
    cmp byte [physical_flip], 0
    je .done
    mov al, (RING_WORDS-1-512) >> 8
.done:
    xor byte [physical_flip], 1
    ret
failed:
    mov dx, failure
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

physical_flip db 0
fault db 0
qpi dd 0
sb_irq db 5
game_active db 0
game_rate dw 22050
game_step dd 32768
game_limit dd 4096*65536
game_started dd 0
game_segment dw 0
game_offset dw 0
periods dd 0
dma_count_port dw 0c6h
success db 'The stereo DMA state test passed.',13,10,'$'
failure db 'The stereo DMA state test failed.',13,10,'$'
