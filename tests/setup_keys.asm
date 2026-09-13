; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h

    mov ax, 40h
    mov es, ax
    cli
    mov word [es:1ah], 1eh
    mov word [es:1ch], 1eh+key_end-keys
    mov si, keys
    mov di, 1eh
    mov cx, (key_end-keys)/2
    cld
    rep movsw
    sti
    mov ax, 4c00h
    int 21h
keys:
%ifdef SAVE_ONLY
    dw 4400h
%elifdef SOUND_TEST
    dw 3c00h,4400h
%else
    dw 4d00h,5000h,4d00h,5000h,4d00h,5000h,4d00h,5000h,4d00h,4400h
%endif
key_end:
