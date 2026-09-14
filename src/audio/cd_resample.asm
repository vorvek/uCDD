; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

cd_begin_resampled:
    mov byte [cd_valid], 0
    cmp byte [cd_started], 0
    je .done
    cmp byte [cd_error], 0
    jne .done
    pushad
    push es
    mov eax, [cd_step_remainder]
    imul eax, PERIOD_FRAMES
    add eax, [cd_step_error]
    xor edx, edx
    div dword [output_rate]
    mov ebx, eax
    mov eax, [cd_step]
    imul eax, PERIOD_FRAMES
    add eax, ebx
    add eax, [cd_fraction]
    shr eax, 16
    shl eax, 2
    mov [cd_take_bytes], eax
    add eax, 4
    mov edi, eax
    mov ebx, [cd_consumed]
    mov ecx, [cd_length]
    sub ecx, ebx
    jbe .restore
    cmp ecx, eax
    jae .length
    mov eax, ecx
.length:
    mov ecx, [cd_produced]
    sub ecx, ebx
    cmp ecx, eax
    jb .empty
    mov ebp, eax
    push ds
    pop es
    push ax
    mov cx, di
    mov di, cd_half
    xor ax, ax
    rep stosb
    pop ax
    and ebx, CD_QUEUE_BYTES-1
    mov [cd_read_offset], ebx
    mov ecx, CD_QUEUE_BYTES
    sub ecx, ebx
    cmp eax, ecx
    jbe .first
    mov eax, ecx
.first:
    mov [cd_read_move], eax
    mov word [cd_read_address], cd_half
    mov si, cd_read_move
    mov ah, 0bh
    call far [cd_xms]
    cmp ax, 1
    jne .empty
    mov eax, [cd_read_move]
    sub ebp, eax
    jz .ready
    add [cd_read_address], ax
    mov [cd_read_move], ebp
    mov dword [cd_read_offset], 0
    mov si, cd_read_move
    mov ah, 0bh
    call far [cd_xms]
    cmp ax, 1
    jne .empty
.ready:
    push ds
    pop gs
    mov word [cd_position], cd_half
    mov byte [cd_valid], 1
.restore:
    pop es
    popad
.done:
    ret
.empty:
    mov byte [cd_error], 2
    jmp .restore

cd_interpolate:
    cmp dword [cd_fraction], 0
    je .done
    push ecx
    push edx
    movsx edx, word [gs:bx+4]
    sub edx, eax
    mov ecx, [cd_fraction]
    shr ecx, 1
    imul edx, ecx
    sar edx, 15
    add eax, edx
    pop edx
    pop ecx
.done:
    ret
