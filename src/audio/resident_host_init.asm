; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

own_host_install:
    mov es, [resident_psp]
    mov es, [es:2ch]
    xor di, di
    xor al, al
    mov cx, 32767
.environment:
    repne scasb
    jne .bad
    cmp byte [es:di], 0
    jne .environment
    add di, 3
    push ds
    push es
    pop ds
    mov dx, di
    mov ax, 3d00h
    int 21h
    pop ds
    jc .bad
    mov [own_host_file], ax
    mov bx, ax
    mov ax, 4200h
    mov cx, OWN_HOST_OFFSET >> 16
    mov dx, OWN_HOST_OFFSET & 0ffffh
    int 21h
    jc .close_bad
    mov ax, 5800h
    int 21h
    jc .close_bad
    mov [own_host_strategy], ax
    mov ax, 5802h
    int 21h
    jc .close_bad
    mov [own_host_umb], al
    mov ax, 5803h
    mov bx, 1
    int 21h
    mov ax, 5801h
    mov bx, 80h
    int 21h
    mov bx, (OWN_HOST_SIZE+15)/16
    mov ah, 48h
    int 21h
    pushf
    push ax
    movzx bx, byte [own_host_umb]
    mov ax, 5803h
    int 21h
    mov bx, [own_host_strategy]
    mov ax, 5801h
    int 21h
    pop ax
    popf
    jc .close_bad
    mov [own_host_entry+2], ax
    push ds
    mov bx, [own_host_file]
    mov ds, ax
    xor dx, dx
    mov cx, OWN_HOST_SIZE
    mov ah, 3fh
    int 21h
    pop ds
    jc .free_bad
    cmp ax, OWN_HOST_SIZE
    jne .free_bad
    mov bx, [own_host_file]
    mov ah, 3eh
    int 21h
    mov word [own_host_file], 0ffffh
    mov bx, port_callback
    mov dx, virtual_irq_take
    mov al, [sb_irq]
    call far [own_host_entry]
    jc .free_bad
    clc
    ret
.free_bad:
    mov es, [own_host_entry+2]
    mov ah, 49h
    int 21h
    mov word [own_host_entry+2], 0
.close_bad:
    mov bx, [own_host_file]
    cmp bx, 0ffffh
    je .bad
    mov ah, 3eh
    int 21h
.bad:
    stc
    ret
own_host_file dw 0ffffh
own_host_strategy dw 0
own_host_umb db 0
