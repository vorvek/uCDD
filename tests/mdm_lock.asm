; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
org 100h
    mov al, [82h]
    sub al, '0'
    cmp al, 1
    ja fail
    mov [lock_value], al
    mov word [packet+14], buffer
    mov [packet+16], ds
    mov bx, packet
    mov cx, 5
    mov ax, 1510h
    int 2fh
    test word [packet+3], 8000h
    jnz fail
    mov ax, 4c00h
    int 21h
fail:
    mov ax, 4c01h
    int 21h
packet:
    db 20,0,0ch
    dw 0
    times 8 db 0
    db 0
    dd 0
    dw 2
buffer db 1
lock_value db 0
