; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h
%define PERIOD_BYTES 2048
    jmp start
cd_position dw 0
%include "audio/mounted.asm"
start:
    push cs
    pop ds
    push cs
    pop fs
    push cs
    pop es
    mov bp, packet
    mov di, buffer
    mov word [cd_info+INFO_ORIGIN], 150
    mov dword [cd_start_lba], 250
    mov dword [cd_end_lba], 260
    mov dword [cd_status_end], 00000323h
    mov dword [cd_length], 23520
    mov dword [cd_consumed], 7056
    mov byte [cd_started], 1
    mov byte [packet+2], 85h
    call request
    cmp byte [cd_started], 0
    jne failed
    cmp byte [cd_paused], 1
    jne failed
    cmp dword [cd_status_start], 0000031ch
    jne failed
    mov byte [packet+2], 3
    mov byte [buffer], 15
    mov cx, 11
    call request
    cmp word [buffer+1], 1
    jne failed
    cmp dword [buffer+3], 0000031ch
    jne failed
    cmp dword [buffer+7], 00000323h
    jne failed
    mov byte [packet+2], 88h
    call request
    cmp ax, 300h
    jne failed
    cmp byte [cd_paused], 0
    jne failed
    mov byte [packet+2], 85h
    call request
    call request
    cmp byte [cd_paused], 0
    jne failed
    cmp dword [cd_status_start], 0
    jne failed
    mov byte [packet+2], 88h
    call far [callback]
    cmp ax, 810ch
    jne failed
    mov byte [packet+2], 3
    mov byte [buffer], 15
    mov byte [cd_started], 1
    mov dword [cd_consumed], 23520
    call request
    cmp ax, 100h
    jne failed
    cmp dword [buffer+3], 0
    jne failed
    cmp dword [buffer+7], 0
    jne failed
    mov byte [packet+2], 0ch
    mov byte [buffer], 3
    mov word [buffer+1], 0
    mov word [buffer+3], 8001h
    mov cx, 9
    call request
    cmp dword [cd_gain], 0
    jne failed
    cmp dword [cd_gain+4], 129
    jne failed
    mov byte [packet+2], 3
    mov byte [buffer], 4
    call request
    cmp word [buffer+1], 0
    jne failed
    cmp word [buffer+3], 8001h
    jne failed
    mov dword [cd_info+INFO_TOTAL], 6150
    mov word [cd_info+INFO_COUNT], 12
    mov si, cd_info+INFO_TRACKS
    mov eax, 150
    mov cx, 12
.tracks:
    mov [si+TRACK_START], eax
    mov [si+TRACK_INDEX0], eax
    add eax, 500
    add si, TRACK_SIZE
    loop .tracks
    mov byte [packet+2], 83h
    mov byte [packet], 24
    mov byte [packet+13], 0
    mov dword [packet+14], 0deadbeefh
    mov dword [packet+20], 4652
    call request
    cmp ax, 100h
    jne failed
    mov byte [packet+2], 3
    mov byte [buffer], 12
    mov cx, 11
    call request
    cmp word [buffer+1], 1001h
    jne failed
    cmp dword [buffer+3], 02020001h
    jne failed
    cmp dword [buffer+7], 02040100h
    jne failed
    mov byte [buffer], 1
    mov byte [buffer+1], 0
    mov cx, 6
    call request
    cmp dword [buffer+2], 4652
    jne failed
    mov byte [packet+2], 83h
    mov byte [packet+13], 1
    mov dword [packet+20], 00010402h
    call request
    mov byte [packet+13], 2
    call far [callback]
    cmp ax, 810ch
    jne failed
    mov byte [packet+13], 0
    mov dword [packet+20], 6000
    call far [callback]
    cmp ax, 810ch
    jne failed
    mov byte [packet], 23
    mov dword [packet+20], 0
    call far [callback]
    cmp ax, 810ch
    jne failed
    mov byte [packet], 24
    mov byte [packet+2], 3
    mov byte [buffer], 12
    mov cx, 10
    call far [callback]
    cmp ax, 810ch
    jne failed
    mov cx, 11
    call request
    cmp word [buffer+1], 1001h
    jne failed
    mov dword [cd_start_lba], 4650
    mov dword [cd_length], 235200
    mov dword [cd_consumed], 7056
    mov byte [cd_started], 1
    call request
    cmp ax, 300h
    jne failed
    cmp dword [buffer+3], 03000001h
    jne failed
    mov dword [cd_consumed], 235200
    mov cx, 10
    call far [callback]
    cmp ax, 810ch
    jne failed
    mov dx, success
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
request:
    mov [callback+2], cs
    call far [callback]
    test ax, 8000h
    jnz failed
    ret
failed:
    mov dx, failure
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
callback dw cd_request,0
packet db 13,0,0
    times 21 db 0
buffer times 16 db 0
success db 'The CD audio state tests passed.',13,10,'$'
failure db 'The CD audio state tests failed.',13,10,'$'
