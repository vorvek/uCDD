; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h

    mov si, 81h
    mov di, filename
.space:
    lodsb
    cmp al, ' '
    je .space
    cmp al, 13
    je fail
    mov cx, 63
.name:
    stosb
    lodsb
    cmp al, ' '
    jbe .named
    loop .name
    jmp fail
.named:
    mov byte [di], 0
    mov ax, 1500h
    xor bx, bx
    int 2fh
    test bx, bx
    jz fail
    cmp bx, 26
    ja fail
    mov [drive_count], bx
    mov ax, 1501h
    mov bx, devices
    int 2fh
    mov si, devices
.device:
    les di, [si+1]
    cmp dword [es:di+22], 'uCDD'
    je .found
    add si, 5
    dec word [drive_count]
    jnz .device
    jmp fail
.found:
    mov eax, [es:di+28]
    mov [entry], eax
    mov bl, [si]
    mov dx, report
    mov ax, 6
    call far [entry]
    test ax, ax
    jnz fail
    cmp word [report], 4
    jne fail
    mov ax, [report+4]
    test ax, ax
    jz fail
    cmp ax, 2048
    ja fail
    shl ax, 4
    mov [dump_length], ax
    mov cx, ax
    shr cx, 1
    push ds
    push ds
    pop es
    mov ds, [report+2]
    xor si, si
    mov di, buffer
    pushf
    cli
    cld
    rep movsw
    popf
    pop ds
    mov dx, filename
    xor cx, cx
    mov ax, 3c00h
    int 21h
    jc fail
    mov bx, ax
    mov dx, dump_header
    mov cx, [dump_length]
    add cx, buffer-dump_header
    mov ah, 40h
    int 21h
    jc .write_failed
    cmp ax, cx
    jne .write_failed
    mov ah, 3eh
    int 21h
    jc fail
    mov dx, saved
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
.write_failed:
    mov ah, 3eh
    int 21h
fail:
    mov dx, error
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

saved db 'CD state saved.',13,10,'$'
error db 'Cannot save CD state.',13,10,'$'
filename times 64 db 0
drive_count dw 0
devices times 26*5 db 0
entry dd 0
dump_header db 'UCDS'
    dw 1
dump_length dw 0
report times 26 db 0
buffer times 32768 db 0
