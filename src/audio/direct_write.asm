; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; Queue direct DAC writes in the idle DMA tail workspace.
sb_dac_write:
    cmp byte [game_active], 0
    jne .done
    push es
    push ax
    cmp byte [sb_dac_enabled], 0
    jne .ready
%ifdef RESIDENT_AUDIO
    mov ax, [cd_half_segment]
    add ax, (CD_HALF_BYTES+15)/16
    mov [sb_tail_segment], ax
%endif
    mov dword [sb_dac_head], 0
    mov byte [sb_dac_value], 128
    mov byte [sb_tail_valid], 0
    mov byte [sb_dac_enabled], 1
.ready:
    call output_clock
    add eax, PERIOD_FRAMES*2
    pop dx
    mov es, [sb_tail_segment]
    mov bx, [sb_dac_head]
    mov si, bx
    add si, 8
    and si, 2047
    cmp si, [sb_dac_tail]
    je .full
    mov [es:bx], eax
    mov [es:bx+4], dl
    mov [sb_dac_head], si
    jmp .restore
.full:
%ifdef MOUNTED_AUDIO
    mov byte [fault], 3
%else
    mov byte [fault], 1
%endif
.restore:
    pop es
.done:
    ret
