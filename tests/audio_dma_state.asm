; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h
%define VIRTUAL_IRQ 1
%define OUTPUT_SHIFT 9
%ifndef DSP_FIFO
%define DSP_FIFO 2
%endif
%include "audio/layout.inc"
    jmp start

%include "audio/trap.asm"
%include "audio/irq.asm"
%include "audio/mix.asm"

%macro write_port 2
    mov dx, %1
    mov al, %2
    call write
%endmacro
%macro start16 1
    write_port 22ch, 0b4h | DSP_FIFO
    write_port 22ch, 30h
    write_port 22ch, (%1-1) & 0ffh
    write_port 22ch, (%1-1) >> 8
%endmacro

start:
%ifdef SHARED_DMA_TEST
    call shared_dma_checks
%endif
    write_port 0ch, 0
    write_port 2, 0
    write_port 2, 0
    write_port 83h, 6
    write_port 3, 0ffh
    write_port 3, 0fh
    write_port 0ah, 1
    write_port 22ch, 0c4h | DSP_FIFO
    write_port 22ch, 20h
    write_port 22ch, 0ffh
    write_port 22ch, 1
    cmp byte [fault], 0
    jne failed
    cmp word [game_dma], dma8
    jne failed
    cmp byte [game_frame_shift], 1
    jne failed
    cmp dword [game_limit], 2048*65536
    jne failed
    cmp word [game_block_bytes], 512
    jne failed
    mov byte [game_start_pending], 0
    write_port 0ch, 0
    mov dx, 3
    call read
    cmp al, 0ffh
    jne failed
    call read
    cmp al, 0eh
    jne failed
    mov dword [periods], 2
    call virtual_irq_tick
    cmp byte [virtual_dsp_irq], 1
    jne failed
    mov dx, 22fh
    call read
    cmp byte [virtual_dsp_irq], 1
    jne failed
    mov dx, 22eh
    call read
    cmp byte [virtual_dsp_irq], 0
    jne failed
    mov dword [periods], 4
    call virtual_irq_tick
    cmp byte [virtual_dsp_irq], 1
    jne failed
    write_port 22ch, 0d5h
    cmp byte [game_active], 1
    jne failed
    mov [game_segment], cs
    mov word [game_offset], samples
    mov dword [game_step], 65536
    mov dword [game_limit], 512*65536
    mov byte [game_start_pending], 1
    push cs
    pop es
    mov di, output
    call mix_half
    mov si, output
    mov cx, 256
.samples:
    cmp dword [si], 0e0002000h
    jne failed
    cmp dword [si+4], 0f0001000h
    jne failed
    add si, 8
    loop .samples
    write_port 22ch, 0d0h
    cmp byte [game_active], 0
    jne failed
    mov dword [periods], 0
    mov dword [game_started], 0
    mov byte [game_start_pending], 0
    mov byte [game_active], 1
    mov byte [sb_paused], 0
    mov dword [game_step], 32768
    call virtual_irq_reset
    write_port 22ch, 0d9h
    cmp byte [fault], 0
    jne failed
    write_port 22ch, 0dah
    cmp byte [fault], 0
    jne failed
    cmp byte [game_active], 1
    jne failed
    call virtual_irq_tick
    cmp byte [virtual_dsp_irq], 0
    jne failed
    mov dword [periods], 1
    mov di, output
    call mix_half
    mov si, output
    mov cx, PERIOD_BYTES/2
.stopped_samples:
    cmp word [si], 0
    jne failed
    add si, 2
    loop .stopped_samples
    call virtual_irq_tick
    cmp byte [game_active], 0
    jne failed
    cmp byte [virtual_dsp_irq], 1
    jne failed
    mov dx, 22eh
    call read
    mov dword [periods], 4
    call virtual_irq_tick
    cmp byte [virtual_dsp_irq], 0
    jne failed
    write_port 22ch, 0c4h | DSP_FIFO
    write_port 22ch, 20h
    write_port 22ch, 0
    write_port 22ch, 2
    call rejected
    write_port 226h, 1
    mov dword [periods], 0
    mov dword [game_started], 0
    mov dword [game_step], 32768

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
    write_port 22ch, 0dah
    cmp byte [fault], 0
    jne failed
    write_port 22ch, 0d9h
    cmp byte [fault], 0
    jne failed
    call virtual_irq_tick
    cmp byte [game_active], 1
    jne failed
    mov dword [periods], 3
    call virtual_irq_tick
    cmp byte [game_active], 0
    jne failed
    cmp byte [virtual_dsp_irq], 2
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
%ifdef SHARED_DMA_TEST
    push bx
    mov bx, [write_count]
    mov [write_ports+bx], dx
    mov [write_values+bx], al
    add word [write_count], 2
    pop bx
%endif
    cmp dx, 0d8h
    jne .done
    mov byte [physical_flip], 0
.done:
    ret
%ifdef SHARED_DMA_TEST
shared_dma_checks:
    write_port 0ah, 6
    cmp byte [fault], 0
    jne failed
    cmp word [write_count], 2
    jne failed
    cmp word [write_ports], 0ah
    jne failed
    cmp byte [write_values], 6
    jne failed
    write_port 0bh, 46h
    cmp word [write_ports+2], 0bh
    jne failed
    cmp byte [write_values+2], 46h
    jne failed
    write_port 0d4h, 6
    cmp word [write_ports+4], 0d4h
    jne failed
    write_port 0d6h, 46h
    cmp word [write_ports+6], 0d6h
    jne failed
    write_port 0ch, 0
    cmp word [write_ports+8], 0ch
    jne failed
    write_port 0d8h, 0
    cmp word [write_ports+10], 0d8h
    jne failed
    mov bx, [write_count]
    write_port 0ah, 5
    write_port 0bh, 49h
    cmp [write_count], bx
    jne failed
    mov word [write_count], 0
    write_port 0eh, 0ffh
    cmp word [write_count], 6
    jne failed
    cmp word [write_ports], 0ah
    jne failed
    cmp byte [write_values], 0
    jne failed
    cmp byte [write_values+2], 2
    jne failed
    cmp byte [write_values+4], 3
    jne failed
    cmp byte [dma8+DMA_MASK], 0
    jne failed
    write_port 0dch, 0
    cmp word [write_count], 12
    jne failed
    cmp word [write_ports+6], 0d4h
    jne failed
    cmp byte [write_values+6], 0
    jne failed
    cmp byte [write_values+8], 2
    jne failed
    cmp byte [write_values+10], 3
    jne failed
    cmp byte [dma16+DMA_MASK], 0
    jne failed
    mov word [write_count], 0
    ret
write_count dw 0
write_ports times 2048 db 0
write_values times 2048 db 0
%endif
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
game_phase dd 0
cd_position dw 0
periods dd 0
dma_count_port dw 0c6h
success db 'The DMA state test passed.',13,10,'$'
failure db 'The DMA state test failed.',13,10,'$'
samples times 256 db 192,64,160,96
output times PERIOD_BYTES db 0
cd_samples times 16384 db 0
