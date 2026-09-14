; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only
bits 16
org 100h
    mov dx, 224h
    mov al, 80h
    out dx, al
    inc dx
    mov al, 2
    out dx, al
    dec dx
    mov al, 81h
    out dx, al
    inc dx
    mov al, 22h
    out dx, al
    mov ax, 4c00h
    int 21h
