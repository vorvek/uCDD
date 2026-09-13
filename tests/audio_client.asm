; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h

    mov sp, stack_top
    mov bx, (program_end-$$+100h+15)/16
    mov ah, 4ah
    int 21h
    jc failed
    mov bx, 512
    mov ah, 48h
    int 21h
    jc failed
    mov [allocation], ax
    add ax, 0ffh
    and ax, 0ff00h
    mov [buffer], ax
    mov es, ax
    xor di, di
    mov cx, 4096
.fill:
    mov bx, di
    and bx, 63
    mov al, [waveform+bx]
    stosb
    loop .fill
    call reset
    mov ax, 22050
    call play
    call wait_second
    call reset
    call wait_second
    mov ax, 11025
    call play
    call wait_second
    call reset
    mov ax, 22050
    call play
    call wait_second
    mov dx, 22ch
    mov al, 0d0h
    out dx, al
    xor di, di
    mov cx, 4096
.check:
    mov bx, di
    and bx, 63
    mov al, [waveform+bx]
    cmp al, [es:di]
    jne failed
    inc di
    loop .check
    mov ax, 4c00h
    int 21h
failed:
    mov ax, 4c01h
    int 21h
reset:
    mov byte [playing], 0
    mov dx, 226h
    mov al, 1
    out dx, al
    xor al, al
    out dx, al
    mov dx, 22eh
    in al, dx
    test al, 80h
    jz failed
    mov dx, 22ah
    in al, dx
    cmp al, 0aah
    jne failed
    ret
play:
    mov byte [playing], 1
    push ax
    mov al, 5
    out 0ah, al
    xor al, al
    out 0ch, al
    movzx eax, word [buffer]
    shl eax, 4
    mov ebx, eax
    out 2, al
    mov al, ah
    out 2, al
    shr ebx, 16
    mov al, bl
    out 83h, al
    mov al, 0ffh
    out 3, al
    mov al, 0fh
    out 3, al
    mov al, 59h
    out 0bh, al
    mov al, 1
    out 0ah, al
    pop bx
    mov dx, 22ch
    mov al, 41h
    out dx, al
    mov al, bh
    out dx, al
    mov al, bl
    out dx, al
    mov al, 0c6h
    out dx, al
    xor al, al
    out dx, al
    mov al, 0ffh
    out dx, al
    mov al, 0fh
    out dx, al
    ret
wait_second:
    push ds
    mov ax, 40h
    mov ds, ax
    mov si, [6ch]
    xor bp, bp
.wait:
    xor al, al
    out 0ch, al
    in al, 3
    mov bl, al
    in al, 3
    mov bh, al
    cmp bx, [cs:last_count]
    je .time
    inc bp
    mov [cs:last_count], bx
.time:
    mov ax, [6ch]
    sub ax, si
    cmp ax, 19
    jb .wait
    pop ds
    cmp byte [playing], 0
    je .idle
    cmp bp, 50
    jb failed
    ret
.idle:
    cmp bp, 1
    ja failed
    ret

allocation dw 0
buffer dw 0
last_count dw 0
playing db 0
waveform:
    incbin "../build/GAMETEST.PCM"
times 512 db 0
stack_top:
program_end:
