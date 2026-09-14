; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only
bits 16
cpu 386
org 100h
    call wss_calibrate
    jc fail
    cmp byte [bad_write], 0
    jne fail
    cmp byte [aci_reads], 2
    jne fail
    mov ax, 4c00h
    int 21h
fail:
    mov ax, 4c01h
    int 21h
%include "audio/wss_codec.asm"
physical_write:
    cmp dx, 534h
    jne .done
    cmp byte [busy_reads], 0
    je .index
    mov byte [bad_write], 1
    ret
.index:
    mov [codec_index], al
.done:
    ret
physical_read:
    cmp dx, 534h
    jne .data
    xor al, al
    cmp byte [busy_reads], 0
    je .done
    dec byte [busy_reads]
    mov al, 80h
    ret
.data:
    xor al, al
    cmp byte [codec_index], 11
    jne .done
    inc byte [aci_reads]
    cmp byte [aci_reads], 1
    jne .done
    mov al, 20h
.done:
    ret
sb_base dw 530h
busy_reads db 3
bad_write db 0
aci_reads db 0
codec_index db 40h
