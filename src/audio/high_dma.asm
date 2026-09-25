; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; Jemm maps the physical source for INT 15h/87h. Single-cycle mono only.
sb_high_sample:
    pushf
    pushad
    push ds
    push es
    push fs
    push gs
    movzx edi, si
    add edi, [game_physical]
    mov ebx, edi
    and ebx, 0ffffff00h
    cmp ebx, [sb_high_tag]
    je .cached
    mov [sb_high_source], bx
    mov eax, ebx
    shr eax, 16
    mov [sb_high_source+2], al
    movzx eax, word [cd_half_segment]
    add eax, (CD_HALF_BYTES+15)/16
    mov [sb_high_segment], ax
    shl eax, 4
    mov [sb_high_destination], ax
    shr eax, 16
    mov [sb_high_destination+2], al
    push ds
    pop es
    mov si, sb_high_table
    mov cx, 128
    mov ax, 8700h
    push ebx
    push edi
    int 15h
    push cs
    pop ds
    pop edi
    pop ebx
    jc .failed
    mov [sb_high_tag], ebx
.cached:
    mov es, [sb_high_segment]
    and di, 255
    mov al, [es:di]
    mov [sb_high_value], al
    jmp .done
.failed:
    mov byte [fault], 3
    mov byte [game_active], 0
    mov byte [sb_high_value], 128
.done:
    pop gs
    pop fs
    pop es
    pop ds
    popad
    popf
    mov al, [sb_high_value]
    ret

sb_high_tag dd -1
sb_high_segment dw 0
sb_high_value db 128
sb_high_table:
    times 16 db 0
    dw 0ffffh
sb_high_source:
    dw 0
    db 0,93h,0,0
    dw 0ffffh
sb_high_destination:
    dw 0
    db 0,93h,0,0
    times 16 db 0
