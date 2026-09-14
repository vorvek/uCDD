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

%macro clock_at 1
    mov dword [periods], %1 >> OUTPUT_SHIFT
    mov word [physical_count], RING_WORDS-1-(%1 & (PERIOD_FRAMES*2-1))*2
%endmacro
%macro block 2
    write_port 226h, 1
    write_port 226h, 0
    write_port 0ch, 0
    write_port 2, 0
    write_port 2, 0
    write_port 83h, 6
    write_port 3, (%1-1) & 255
    write_port 3, (%1-1) >> 8
    write_port 0bh, 49h
    write_port 0ah, 1
    write_port 22ch, 40h
    write_port 22ch, 156
    write_port 22ch, 14h
    write_port 22ch, (%2-1) & 255
    write_port 22ch, (%2-1) >> 8
    cmp byte [fault], 0
    jne failed
    mov dword [game_started], 0
    mov byte [game_start_pending], 0
%endmacro
start:
    mov byte [stage], 1
    block 257,257
    cmp dword [game_block_bytes], 257
    jne failed
    cmp dword [game_exit_frame], 1134
    jne failed
    cmp dword [game_limit], 257*65536
    jne failed
    clock_at 300
    call virtual_irq_tick
    cmp byte [virtual_dsp_irq], 0
    jne failed
    write_port 22ch, 0d0h
    cmp byte [game_active], 0
    jne failed
    clock_at 600
    write_port 0ch, 0
    mov dx, 3
    call read
    cmp al, 188
    jne failed
    write_port 22ch, 0d4h
    cmp byte [game_active], 1
    jne failed
    cmp dword [game_started], 300
    jne failed
    clock_at 1433
    call virtual_irq_tick
    cmp byte [virtual_dsp_irq], 0
    jne failed
    clock_at 1434
    call virtual_irq_tick
    cmp byte [virtual_dsp_irq], 1
    jne failed
    cmp byte [game_active], 0
    jne failed
    write_port 0ch, 0
    mov dx, 3
    call read
    cmp al, 255
    jne failed
    call read
    cmp al, 255
    jne failed
    mov dx, 22eh
    call read
    clock_at 3000
    call virtual_irq_tick
    cmp byte [virtual_dsp_irq], 0
    jne failed

    mov byte [stage], 2
    block 4096,997
    clock_at 4397
    call virtual_irq_tick
    cmp byte [virtual_dsp_irq], 1
    jne failed
    write_port 0ch, 0
    mov dx, 3
    call read
    cmp al, (4095-997) & 255
    jne failed
    call read
    cmp al, (4095-997) >> 8
    jne failed

    mov byte [stage], 3
    block 257,257
    mov [game_segment], cs
    mov word [game_offset], samples
    mov dword [periods], 1
    push cs
    pop es
    mov di, output
    call mix_half
    mov si, output
    mov cx, 110*2
.check_sound:
    cmp word [si], 2000h
    jne failed
    add si, 2
    loop .check_sound
    mov cx, (PERIOD_FRAMES-110)*2
.check_silence:
    cmp word [si], 0
    jne failed
    add si, 2
    loop .check_silence

    mov byte [stage], 4
    block 65536,65536
    cmp dword [game_limit], 0
    jne failed
    cmp dword [game_block_bytes], 65536
    jne failed
    mov dword [periods], 1
    mov di, output
    call mix_half
    cmp di, output+PERIOD_BYTES
    jne failed

    mov byte [stage], 5
    block 1,1
    clock_at 4
    call virtual_irq_tick
    cmp byte [virtual_dsp_irq], 0
    jne failed
    clock_at 5
    call virtual_irq_tick
    cmp byte [virtual_dsp_irq], 1
    jne failed

    mov byte [stage], 6
    block 4096,997
    write_port 22ch, 0d3h
    cmp byte [game_active], 1
    jne failed
    write_port 22ch, 0d8h
    mov dx, 22ah
    call read
    test al, al
    jnz failed
    write_port 22ch, 0d1h
    write_port 22ch, 0d8h
    mov dx, 22ah
    call read
    cmp al, 255
    jne failed
    write_port 22ch, 0e0h
    write_port 22ch, 55h
    mov dx, 22ah
    call read
    cmp al, 0aah
    jne failed
    write_port 22ch, 0e4h
    write_port 22ch, 37h
    write_port 22ch, 0e8h
    mov dx, 22ah
    call read
    cmp al, 37h
    jne failed

    mov byte [stage], 7
    write_port 226h, 1
    write_port 226h, 0
    write_port 22ch, 48h
    write_port 22ch, 0e4h
    write_port 22ch, 3
    write_port 22ch, 91h
    cmp byte [arguments], 0
    jne failed
    cmp byte [sb_single], 1
    jne failed
    cmp dword [game_block_bytes], 997
    jne failed
    cmp byte [fault], 0
    jne failed
    mov byte [stage], 8
    block 4096,997
    clock_at 4397
    call virtual_irq_tick
    write_port 22ch, 14h
    write_port 22ch, 0e4h
    write_port 22ch, 3
    cmp dword [game_origin], 997*65536
    jne failed
    mov byte [game_start_pending], 0
    mov dword [game_started], 0
    clock_at 4397
    call virtual_irq_tick
    cmp dword [dma8+DMA_POSITION], 1994
    jne failed
    cmp word [dma8+DMA_SNAPSHOT], 2101
    jne failed

    mov byte [stage], 9
    block 1000,997
    write_port 0bh, 59h
    clock_at 4397
    call virtual_irq_tick
    write_port 22ch, 14h
    write_port 22ch, 0e4h
    write_port 22ch, 3
    cmp dword [game_origin], 997*65536
    jne failed
    mov byte [game_start_pending], 0
    mov dword [game_started], 0
    clock_at 4397
    call virtual_irq_tick
    cmp dword [dma8+DMA_POSITION], 994
    jne failed
    cmp word [dma8+DMA_SNAPSHOT], 5
    jne failed

    mov byte [stage], 10
    write_port 224h, 0eh
    write_port 225h, 2
    block 1,1
    cmp byte [game_frame_shift], 0
    jne failed
    cmp dword [game_exit_frame], 5
    jne failed
    clock_at 5
    call virtual_irq_tick
    cmp byte [game_active], 0
    jne failed
    cmp byte [virtual_dsp_irq], 1
    jne failed
    mov dx, success
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
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
    mov al, [physical_count]
    cmp byte [physical_flip], 0
    je .done
    mov al, [physical_count+1]
.done:
    xor byte [physical_flip], 1
    ret
failed:
    mov dl, [stage]
    add dl, '0'
    mov ah, 2
    int 21h
    mov dx, failure
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

physical_flip db 0
physical_count dw RING_WORDS-1
stage db 0
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
success db 'The legacy SB state test passed.',13,10,'$'
failure db 'The legacy SB state test failed.',13,10,'$'
samples times 1024 db 192
output times PERIOD_BYTES db 0
cd_samples times 16384 db 0
