; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h
    jmp install
old_vector dd 0
handler:
    cmp ax, 0de00h
    jne .chain
    mov ah, 84h
    iret
.chain:
    jmp far [cs:old_vector]
resident_end:
install:
    mov ax, 3567h
    int 21h
    mov [old_vector], bx
    mov [old_vector+2], es
    mov dx, handler
    mov ax, 2567h
    int 21h
    mov es, [2ch]
    mov ah, 49h
    int 21h
    mov dx, (resident_end-$$+100h+15)/16
    mov ax, 3100h
    int 21h
