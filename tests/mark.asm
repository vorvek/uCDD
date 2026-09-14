; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
org 100h

    mov bl, [82h]
    sub bl, '0'
    mov al, 26
    out 0e4h, al
    mov al, bl
    out 0e5h, al
    mov al, 4
    out 0e6h, al
    mov ax, 4c00h
    int 21h
