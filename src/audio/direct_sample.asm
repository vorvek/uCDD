; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

sb_dac_sample:
    push eax
    push bx
    push fs
    mov fs, [sb_tail_segment]
    mov bx, [sb_dac_tail]
.next:
    cmp bx, [sb_dac_head]
    je .held
    mov eax, [sb_dac_frame]
    sub eax, [fs:bx]
    js .held
    mov al, [fs:bx+4]
    mov [sb_dac_value], al
    add bx, 8
    and bx, 2047
    mov [sb_dac_tail], bx
    jmp .next
.held:
    inc dword [sb_dac_frame]
    cmp byte [sb_speaker], 0
    je .done
    movzx edx, byte [sb_dac_value]
    sub edx, 128
    shl edx, 7
    mov esi, edx
.done:
    pop fs
    pop bx
    pop eax
    ret
