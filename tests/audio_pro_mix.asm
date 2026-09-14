; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only
bits 16
cpu 386
org 100h
%define RESIDENT_AUDIO 1
%define MOUNTED_AUDIO 1
%define CD_IMAGE_TEST 1
%define OUTPUT_SHIFT 9
%define CD_QUEUE_BYTES 16384
%include "audio/layout.inc"
    jmp start
%include "audio/mix.asm"
%include "audio/cd_resample.asm"
cd_begin_half:
    jmp cd_begin_resampled
start:
    push cs
    pop es
    mov [game_segment], cs
    mov word [cd_xms+2], cs
    mov word [cd_read_address+2], cs
    mov di, queue
    mov cx, CD_QUEUE_BYTES/4
    mov eax, 0c0004000h
    rep stosd
    mov di, output
    call mix_half
    cmp byte [cd_error], 0
    jne fail
    cmp word [xms_calls], 2
    jne fail
    cmp dword [cd_take_bytes], 2076
    jne fail
    cmp dword [cd_consumed], CD_QUEUE_BYTES-4+2076
    jne fail
    cmp di, output+512
    jne fail
    mov si, output
    mov cx, 256
.check:
    cmp word [si], 40c0h
    jne fail
    add si, 2
    loop .check
    mov byte [game_frame_shift], 2
    mov word [game_offset], clip_samples
    mov di, queue
    mov cx, CD_QUEUE_BYTES/4
    mov eax, 80007fffh
    rep stosd
    mov di, output
    call mix_half
    cmp word [output], 00ffh
    jne fail
    mov eax, [cd_consumed]
    add eax, 4
    mov [cd_length], eax
    mov di, output
    call mix_half
    cmp byte [cd_error], 0
    jne fail
    cmp dword [cd_half+4], 0
    jne fail
    mov ax, 4c00h
    int 21h
fail:
    mov ax, 4c01h
    int 21h
xms:
    pushad
    push es
    mov eax, [cd_read_offset]
    add eax, [cd_read_move]
    cmp eax, CD_QUEUE_BYTES
    ja fail
    mov si, [cd_read_offset]
    add si, queue
    les di, [cd_read_address]
    mov cx, [cd_read_move]
    rep movsb
    inc word [xms_calls]
    pop es
    popad
    mov ax, 1
    retf
sound_card db 1
output_rate dd 43478
cd_step dd (44100*65536)/43478
cd_step_remainder dd (44100*65536) % 43478
cd_step_error dd 0
cd_fraction dd 0
cd_take_bytes dd 0
pro_pair_left dd 0
pro_pair_right dd 0
cd_gain dd 256,256
cd_position dw 0
cd_valid db 0
cd_started db 1
cd_error db 0
cd_length dd 32768
cd_consumed dd CD_QUEUE_BYTES-4
cd_produced dd 32768
cd_xms dw xms,0
cd_read_move dd 0
    dw 1
cd_read_offset dd 0
    dw 0
cd_read_address dw cd_half,0
xms_calls dw 0
game_active db 1
game_start_pending db 0
game_started dd 0
game_exit_frame dd 0
game_mix_frame dd 0
game_step dd 0
game_limit dd 65536
game_phase dd 0
game_frame_shift db 1
game_segment dw 0
game_offset dw samples
game_dma dw dma
dma db 0,0
periods dd 0
samples db 192,64
clip_samples dw 32767,-32768
output times PERIOD_BYTES db 0
cd_half times PERIOD_BYTES+PERIOD_BYTES/32+4 db 0
queue times CD_QUEUE_BYTES db 0
