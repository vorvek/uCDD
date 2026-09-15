; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h
%define RESIDENT_AUDIO 1
    jmp start
%include "shared_dma.inc"
start:
    mov si, dma16
    mov dx, 0ah
    mov al, 6
    call dma_unowned_write
    cmp word [writes], 0
    jne fail
    mov al, 7
    call dma_unowned_write
    cmp word [writes], 1
    jne fail
    cmp word [last_port], 0d4h
    jne fail
    cmp byte [last_value], 7
    jne fail
    mov byte [sb_dma16], 7
    call dma_unowned_write
    cmp word [writes], 1
    jne fail
    mov byte [sb_dma16], 6
    mov si, dma8
    mov al, 6
    call dma_unowned_write
    cmp word [writes], 2
    jne fail
    cmp word [last_port], 0ah
    jne fail
    mov byte [sound_card], 1
    mov al, 7
    call dma_unowned_write
    cmp word [writes], 2
    jne fail
    mov byte [sound_card], 2
    call dma_unowned_write
    cmp word [writes], 2
    jne fail
    mov byte [sound_card], 3
    call dma_unowned_write
    cmp word [writes], 2
    jne fail
    mov byte [sb_running], 0
    call dma_unowned_write
    cmp word [writes], 3
    jne fail
    mov ax, 4c00h
    int 21h
fail:
    mov ax, 4c01h
    int 21h
physical_write:
    inc word [writes]
    mov [last_port], dx
    mov [last_value], al
    ret
writes dw 0
last_port dw 0
last_value db 0
sb_running db 1
sound_card db 0
sb_dma8 db 3
sb_dma16 db 6
dma8 times 16 db 0
dma16 times 16 db 0
