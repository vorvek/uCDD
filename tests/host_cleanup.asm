; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h
    mov sp, program_end+512
    mov bx, (program_end-$$+100h+512+15)/16
    mov ah, 4ah
    int 21h
    jc fail
    mov ax, 3560h
    int 21h
    mov [vectors], bx
    mov [vectors+2], es
    mov ax, 3561h
    int 21h
    mov [vectors+4], bx
    mov [vectors+6], es
    mov ax, 3562h
    int 21h
    mov [vectors+8], bx
    mov [vectors+10], es
    mov ax, 3563h
    int 21h
    mov [vectors+12], bx
    mov [vectors+14], es
    mov ax, 3564h
    int 21h
    mov [vectors+16], bx
    mov [vectors+18], es
    mov bx, 0ffffh
    mov ah, 48h
    int 21h
    mov [largest], bx
    push cs
    pop es
    mov [block+4], cs
    mov [block+8], cs
    mov [block+12], cs
    mov bx, block
    mov dx, child
    mov ax, 4b00h
    int 21h
    mov ax, cs
    cli
    mov ss, ax
    mov sp, program_end+512
    sti
    mov ds, ax
    jc fail
    mov ax, 3560h
    int 21h
    cmp bx, [vectors]
    jne fail
    mov ax, es
    cmp ax, [vectors+2]
    jne fail
    mov ax, 3561h
    int 21h
    cmp bx, [vectors+4]
    jne fail
    mov ax, es
    cmp ax, [vectors+6]
    jne fail
    mov ax, 3562h
    int 21h
    cmp bx, 500h
    jne fail
    mov ax, es
    test ax, ax
    jnz fail
    mov ax, 3563h
    int 21h
    cmp bx, [vectors+12]
    jne fail
    mov ax, es
    cmp ax, [vectors+14]
    jne fail
    mov ax, 3564h
    int 21h
    cmp bx, [vectors+16]
    jne fail
    mov ax, es
    cmp ax, [vectors+18]
    jne fail
    mov bx, 0ffffh
    mov ah, 48h
    int 21h
    cmp bx, [largest]
    jne fail
    xor al, al
    jmp done
fail:
    mov al, 1
done:
    push ax
    lds dx, [vectors+8]
    mov ax, 2562h
    int 21h
    pop ax
    mov ah, 4ch
    int 21h
child db 'HOSTEXT.COM',0
block dw 0,tail,0,5ch,0,6ch,0
tail db 0,13
vectors times 20 db 0
largest dw 0
program_end:
