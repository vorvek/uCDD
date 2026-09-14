; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h

    mov ax, 1500h
    xor bx, bx
    int 2fh
    cmp bx, 1
    jne fail
    mov ax, 1501h
    mov bx, device
    int 2fh
    les di, [device+1]
    cmp dword [es:di+22], 'uCDD'
    jne fail
    mov eax, [es:di+28]
    mov [entry], eax
    mov bl, [device]
    mov dx, report
    mov ax, 6
    call far [entry]
    test ax, ax
    jnz fail
    cmp word [report], 1
    jne fail
    cmp word [report+10], 0
    jne fail
    cmp byte [80h], 0
    je .dma
    cmp word [report+2], 0a000h
    jb fail
.dma:
    mov ax, [report+6]
    add ax, 512
    cmp ax, 0a000h
    ja fail
%ifdef OWN_HOST
    mov ax, 1687h
    int 2fh
    test ax, ax
    jnz fail
    mov ax, es
    mov [report+12], ax
    cmp byte [80h], 0
    je .host_mcb
    cmp ax, 0a000h
    jb fail
.host_mcb:
    dec ax
    mov es, ax
    mov ax, [report+2]
    sub ax, 16
    cmp [es:1], ax
    jne fail
    mov ax, [es:3]
    mov [report+14], ax
%endif
    mov ax, [report+8]
    add ax, 256
    cmp ax, 0a000h
    ja fail
    mov dx, filename
    xor cx, cx
    mov ah, 3ch
    int 21h
    jc fail
    mov bx, ax
    mov dx, report
    mov cx, report_size
    mov ah, 40h
    int 21h
    jc fail
    cmp ax, report_size
    jne fail
    mov ah, 3eh
    int 21h
    jc fail
    mov ax, 4c00h
    int 21h
fail:
    mov ax, 4c01h
    int 21h

device times 5 db 0
entry dd 0
%ifdef OWN_HOST
report_size equ 16
%else
report_size equ 12
%endif
report times report_size db 0
filename db 'RESSTAT.DAT',0
