; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h

%ifdef KEY_SCAN
    mov ax, 3509h
    int 21h
    mov [key_segment], es
%endif
    mov si, 81h
.space:
    lodsb
    cmp al, ' '
    je .space
    sub al, '1'
    cmp al, 9
    jb .number
    cmp al, '0'-'1'
    jne failed
    mov al, 9
.number:
    add al, 2
    mov [number], al
    cmp byte [si], 13
    je .modifiers
    mov al, [si+1]
    mov [mode], al
.modifiers:
    cmp byte [mode], 'P'
    jne .start_keys
    mov si, pause_keys
.pause:
    lodsb
    call send
    cmp si, pause_keys+6
    jb .pause
.start_keys:
    cmp byte [mode], 'N'
    je .digit
    cmp byte [mode], 'A'
    je .alt
    call prefix
    mov al, 1dh
    call send
.alt:
    cmp byte [mode], 'C'
    je .digit
    call prefix
    mov al, 38h
    call send
.digit:
    mov al, [number]
    call send
    mov al, [number]
    call send
    mov al, [number]
    or al, 80h
    call send
    cmp byte [mode], 'N'
    je .settling
    cmp byte [mode], 'C'
    je .control_up
    call prefix
    mov al, 0b8h
    call send
.control_up:
    cmp byte [mode], 'A'
    je .settling
    call prefix
    mov al, 9dh
    call send
.settling:
    mov cx, 3
.settle:
    call tick
    loop .settle
    mov ax, 4c00h
    int 21h
prefix:
    cmp byte [mode], 'R'
    jne .done
    mov al, 0e0h
    call send
.done:
    ret
send:
%ifdef KEY_SCAN
    push cs
    push .returned
    push word KEY_RETF
    push word [key_segment]
    push word KEY_SCAN
    retf
.returned:
    call tick
    ret
%else
    push ax
    mov cx, 0ffffh
.ready:
    in al, 64h
    test al, 3
    jz .inject
    loop .ready
    jmp failed
.inject:
    mov al, 0d2h
    out 64h, al
    mov cx, 0ffffh
.input:
    in al, 64h
    test al, 2
    jz .data
    loop .input
    jmp failed
.data:
    pop ax
    out 60h, al
    call tick
    ret
%endif
tick:
    push ax
    push es
    mov ax, 40h
    mov es, ax
    mov ax, [es:6ch]
.wait:
    sti
    hlt
    cmp ax, [es:6ch]
    je .wait
    pop es
    pop ax
    ret
failed:
    mov ax, 4c01h
    int 21h
number db 0
mode db 0
pause_keys db 0e1h,1dh,45h,0e1h,9dh,0c5h
%ifdef KEY_SCAN
key_segment dw 0
%endif
