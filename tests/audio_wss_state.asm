; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only
bits 16
cpu 386
org 100h
%define VIRTUAL_IRQ 1
%define WSS_INPUT 1
%define OUTPUT_SHIFT 9
%include "audio/layout.inc"
    jmp start
%include "audio/trap.asm"
%include "audio/irq.asm"
%include "audio/mix.asm"
%macro write_port 2
    mov dx, %1
    mov al, %2
    mov cl, 4
    push cs
    call port_callback
%endmacro
%macro codec 2
    write_port 534h, %1
    write_port 535h, %2
%endmacro
start:
    write_port 0ch, 0
    write_port 2, 0
    write_port 2, 0
    write_port 83h, 6
    write_port 3, 0ffh
    write_port 3, 0fh
    codec 48h, 17h
    codec 0ah, 0
    write_port 530h, 22h
    codec 6, 0
    codec 7, 0
    codec 49h, 5
    codec 4ah, 2
    codec 15, 0ffh
    codec 14, 0fh
    cmp byte [game_active], 0
    jne failed
    write_port 0ah, 1
    cmp byte [fault], 0
    jne failed
    cmp byte [game_source], 1
    jne failed
    cmp byte [game_active], 1
    jne failed
    cmp byte [game_frame_shift], 1
    jne failed
    cmp word [game_rate], 22050
    jne failed
    cmp word [game_block_bytes], 8192
    jne failed
    cmp word [game_dma], dma8
    jne failed
    mov [game_segment], cs
    mov word [game_offset], samples
    mov dword [game_step], 65536
    push cs
    pop es
    mov di, output
    call mix_half
    mov si, output
    mov cx, 256
.check:
    cmp dword [si], 0e0002000h
    jne failed
    cmp dword [si+4], 0f0001000h
    jne failed
    add si, 8
    loop .check
    mov byte [game_start_pending], 0
    mov dword [game_started], 0
    mov dword [periods], 16
    call virtual_irq_tick
    cmp word [wss_irq_event], 11
    jne failed
    test byte [wss_status], 1
    jz failed
    cmp byte [virtual_pic_request], 0
    jne failed
    mov word [wss_irq_event], 0ffffh
    write_port 536h, 0
    codec 10, 0
    mov dword [periods], 32
    call virtual_irq_tick
    cmp word [wss_irq_event], 0ffffh
    jne failed
    test byte [wss_status], 1
    jz failed
    write_port 536h, 0
    codec 10, 2
    codec 15, 0ffh
    codec 14, 1fh
    cmp word [game_block_bytes], 16384
    jne failed
    call virtual_irq_tick
    cmp word [wss_irq_event], 0ffffh
    jne failed
    mov dword [periods], 62
    call virtual_irq_tick
    cmp word [wss_irq_event], 0ffffh
    jne failed
    mov dword [periods], 64
    call virtual_irq_tick
    cmp word [wss_irq_event], 11
    jne failed
    write_port 534h, 20h
    call game_elapsed
    mov [hold_frame], eax
    mov dword [periods], 70
    call game_elapsed
    cmp eax, [hold_frame]
    jne failed
    write_port 536h, 0
    call game_elapsed
    cmp eax, [hold_frame]
    jne failed
    mov dword [periods], 72
    call game_elapsed
    cmp eax, [hold_frame]
    jbe failed
    write_port 534h, 0
    mov byte [wss_paused], 1
    mov dword [wss_pause_clock], 10
    mov byte [game_source], 0
    mov dword [game_started], 20
    write_port 536h, 0
    cmp dword [game_started], 20
    jne failed
    cmp byte [wss_paused], 0
    jne failed
    mov byte [game_source], 1
    codec 9, 4
    cmp byte [game_active], 0
    jne failed
    codec 48h, 47h
    codec 49h, 5
    write_port 534h, 9
    cmp byte [game_frame_shift], 1
    jne failed
    cmp word [game_dma], dma8
    jne failed
    cmp byte [fault], 0
    jne failed
    mov [game_segment], cs
    mov word [game_offset], words
    mov di, output
    call mix_half
    cmp dword [output], 20002000h
    jne failed
    codec 9, 4
    mov dx, success
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
failed:
    mov dx, failure
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
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
physical_flip db 0
hold_frame dd 0
fault db 0
qpi dd 0
sb_irq db 7
game_active db 0
game_rate dw 22050
game_step dd 32768
game_limit dd 4096*65536
game_started dd 0
game_segment dw 0
game_offset dw 0
game_phase dd 0
cd_position dw 0
periods dd 0
dma_count_port dw 0c6h
success db 'The WSS state test passed.',13,10,'$'
failure db 'The WSS state test failed.',13,10,'$'
samples times 256 db 192,64,160,96
words times 512 dw 16384
output times PERIOD_BYTES db 0
cd_samples times 16384 db 0
