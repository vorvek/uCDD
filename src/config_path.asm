; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

config_path_init:
    pushad
    push es
    mov ah, 62h
    int 21h
    mov es, bx
    mov ax, [es:2ch]
    test ax, ax
    jz .bad
    mov es, ax
    xor di, di
    xor al, al
    mov cx, 32767
    cld
.environment:
    repne scasb
    jne .bad
    cmp byte [es:di], 0
    jne .environment
    cmp word [es:di+1], 1
    jb .bad
    add di, 3
    mov si, config_path
    xor bx, bx
    mov cx, 128
.copy:
    mov al, [es:di]
    inc di
    test al, al
    jz .name
    mov [si], al
    inc si
    cmp al, '\'
    jne .next
    mov bx, si
.next:
    loop .copy
    jmp .bad
.name:
    test bx, bx
    jz .bad
    cmp bx, config_path+116
    ja .bad
    mov [config_directory_end], bx
    mov dword [bx], 'UCDD'
    mov dword [bx+4], '.CFG'
    mov byte [bx+8], 0
    pop es
    popad
    clc
    ret
.bad:
    pop es
    popad
    stc
    ret

config_directory_end dw 0
config_path times 128 db 0
