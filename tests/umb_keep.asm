; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h

%ifndef UMB_FREE_KIB
%define UMB_FREE_KIB 29
%endif
%ifndef UMB_EXTRA_KIB
%define UMB_EXTRA_KIB 0
%endif

    mov ax, 5800h
    int 21h
    jc fail
    mov [strategy], ax
    mov ax, 5802h
    int 21h
    jc fail
    mov [umb_link], al
    mov ax, 5803h
    mov bx, 1
    int 21h
    jc fail
    mov ax, 5801h
    mov bx, 40h
    int 21h
    jc restore
    mov bx, 0ffffh
    mov ah, 48h
    int 21h
    jnc restore
%if UMB_EXTRA_KIB > 0
    cmp bx, (UMB_FREE_KIB+UMB_EXTRA_KIB)*64+4
    jbe restore
    mov [largest], bx
    mov bx, UMB_FREE_KIB*64
    mov ah, 48h
    int 21h
    jc restore
    mov [temporary], ax
    mov bx, 1
    mov ah, 48h
    int 21h
    jc restore
    mov [separator], ax
    mov bx, [largest]
    sub bx, (UMB_FREE_KIB+UMB_EXTRA_KIB)*64+4
    mov ah, 48h
    int 21h
    jc restore
    mov [allocation], ax
    mov es, [temporary]
    mov ah, 49h
    int 21h
    jc restore
%else
    sub bx, UMB_FREE_KIB*64
    jbe restore
    dec bx
    jz restore
    mov ah, 48h
    int 21h
    jc restore
    mov [allocation], ax
%endif
    mov ax, 5801h
    mov bx, [strategy]
    int 21h
    jc fail
    mov es, [2ch]
    mov ah, 49h
    int 21h
    mov dx, 16
    mov ax, 3100h
    int 21h

restore:
    mov bx, [strategy]
    mov ax, 5801h
    int 21h
    movzx bx, byte [umb_link]
    mov ax, 5803h
    int 21h
fail:
    mov ax, 4c01h
    int 21h

strategy dw 0
allocation dw 0
largest dw 0
temporary dw 0
separator dw 0
umb_link db 0
