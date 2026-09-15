; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h

    mov ax, 4310h
    int 2fh
    mov [xms], bx
    mov [xms+2], es
    xor bl, bl
    mov ah, 8
    call far [xms]
    mov [state], dx
    xor dx, dx
    mov ah, 9
    call far [xms]
    cmp ax, 1
    jne fail
    push dx
    mov byte [step], '2'
    mov ah, 0eh
    call far [xms]
    cmp ax, 1
    jne fail
    mov [state+4], bl
    pop dx
    mov byte [step], '3'
    mov ah, 0ah
    call far [xms]
    cmp ax, 1
    jne fail
    mov bx, 0ffffh
    mov byte [step], '4'
    mov ah, 48h
    int 21h
    jnc fail
    mov [state+2], bx
    mov si, 81h
.space:
    lodsb
    cmp al, ' '
    je .space
    cmp al, 9
    je .space
    cmp al, 13
    jne .check
    mov byte [step], '5'
    mov dx, filename
    xor cx, cx
    mov ah, 3ch
    int 21h
    jc fail
    mov bx, ax
    mov byte [step], '6'
    mov dx, state
    mov cx, 5
    mov ah, 40h
    int 21h
    jc fail
    cmp ax, 5
    jne fail
    jmp .close
.check:
    mov byte [step], '7'
    mov dx, filename
    mov ax, 3d00h
    int 21h
    jc fail
    mov bx, ax
    mov byte [step], '8'
    mov dx, saved
    mov cx, 5
    mov ah, 3fh
    int 21h
    jc fail
    cmp ax, 5
    jne fail
    mov eax, [state]
    mov byte [step], '9'
    cmp eax, [saved]
    jne fail
    mov al, [state+4]
    cmp al, [saved+4]
    jne fail
.close:
    mov ah, 3eh
    int 21h
    jc fail
    mov ax, 4c00h
    int 21h
fail:
    mov dx, message
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
xms dd 0
state times 5 db 0
saved times 5 db 0
filename db 'MDMMEM.BIN',0
message db 'The memory test failed at step '
step db '1'
    db '.',13,10,'$'
