; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

config_load:
    mov dx, config_name
    mov ax, 3d00h
    int 21h
    jnc .read
%ifdef MOUNTED_AUDIO
    stc
    ret
%else
    cmp ax, 2
    je .default
    stc
    ret
%endif
.read:
    mov bx, ax
    mov dx, config_data
    mov cx, 13
    mov ah, 3fh
    int 21h
    pushf
    push ax
    mov ah, 3eh
    int 21h
    pop ax
    popf
    jc .bad
    cmp ax, 12
    jne .bad
    cmp dword [config_data], 'uCDD'
    jne .bad
    cmp byte [config_data+4], 1
    jne .bad
    cmp byte [config_data+11], 0
    jne .bad
    cmp byte [sound_card], 1
    ja .bad
    mov ax, [sb_base]
    sub ax, 220h
    test ax, 0ff9fh
    jnz .bad
    cmp byte [sb_irq], 5
    je .dma
    cmp byte [sb_irq], 7
    jne .bad
.dma:
    cmp byte [sb_dma8], 1
    je .high
    cmp byte [sb_dma8], 3
    jne .bad
.high:
    cmp byte [sb_dma16], 5
    jb .bad
    cmp byte [sb_dma16], 7
    ja .bad
.default:
    clc
    ret
.bad:
    mov dword [config_data], 'uCDD'
    mov word [config_data+4], 1
    mov word [sb_base], 220h
    mov byte [sb_irq], 5
    mov byte [sb_dma8], 1
    mov byte [sb_dma16], 5
    mov byte [config_data+11], 0
    stc
    ret
config_save:
    mov dx, config_name
    xor cx, cx
    mov ah, 3ch
    int 21h
    jc .done
    mov bx, ax
    mov dx, config_data
    mov cx, 12
    mov ah, 40h
    int 21h
    pushf
    push ax
    mov ah, 3eh
    int 21h
    pop dx
    pop cx
    jc .done
    test cx, 1
    jnz .fail
    cmp dx, 12
    jne .fail
    clc
.done:
    ret
.fail:
    stc
    ret

config_name db 'UCDD.CFG',0
config_data db 'uCDD',1
sound_card db 0
sb_base dw 220h
sb_irq db 5
sb_dma8 db 1
sb_dma16 db 5
    db 0,0
