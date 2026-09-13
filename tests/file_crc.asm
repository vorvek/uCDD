; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h

    cld
    mov si, 81h
.spaces:
    lodsb
    cmp al, ' '
    je .spaces
    dec si
    mov dx, si
.path:
    lodsb
    cmp al, 13
    je fail
    cmp al, ' '
    jne .path
    mov byte [si-1], 0
    mov ax, 3d00h
    int 21h
    jc fail
    mov [handle], ax
    xor edx, edx
    mov cx, 8
.hex:
    lodsb
    sub al, '0'
    cmp al, 9
    jbe .digit
    sub al, 7
    cmp al, 10
    jb fail
    cmp al, 15
    ja fail
.digit:
    shl edx, 4
    or dl, al
    loop .hex
    mov [expected], edx
.read:
    mov bx, [handle]
    mov dx, buffer
    mov cx, 8192
    mov ah, 3fh
    int 21h
    jc fail
    test ax, ax
    jz .done
    mov cx, ax
    mov si, buffer
    mov eax, [crc]
.byte:
    movzx ebx, byte [si]
    xor bl, al
    shr eax, 8
    xor eax, [crc_table+ebx*4]
    inc si
    loop .byte
    mov [crc], eax
    jmp .read
.done:
    mov bx, [handle]
    mov ah, 3eh
    int 21h
    mov eax, [crc]
    not eax
    cmp eax, [expected]
    jne fail
    mov dx, passed
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
fail:
    mov dx, failed
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
handle dw 0
expected dd 0
crc dd 0ffffffffh
passed db 'The file check passed.',13,10,'$'
failed db 'The file check failed.',13,10,'$'
    align 4
crc_table:
%assign value 0
%rep 256
    %assign entry value
    %rep 8
        %if entry & 1
            %assign entry (entry >> 1) ^ 0edb88320h
        %else
            %assign entry entry >> 1
        %endif
    %endrep
    dd entry
    %assign value value+1
%endrep
buffer times 8192 db 0
