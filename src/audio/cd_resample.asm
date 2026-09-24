; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

cd_begin_resampled:
    mov byte [cd_valid], 0
    cmp byte [cd_started], 0
    je .done
    cmp byte [cd_error], 0
    jne .done
    cmp dword [cd_consumed], 0
    jne .prefilled
    cmp dword [cd_remaining], 0
    je .prefilled
    cmp dword [cd_produced], CD_READ_BYTES*4
    jb .done
.prefilled:
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
    jb .restore
    test ebx, ebx
    jz .cache_miss
    cmp ebx, [cd_sample_next]
    jne .cache_miss
    movzx ecx, word [cd_sample_left]
    cmp ecx, edi
    jae .cached
.cache_miss:
    mov word [cd_sample_left], 0
    cmp edi, CD_PREFETCH_BYTES
    ja .copy
    mov ecx, [cd_length]
    sub ecx, ebx
    cmp ecx, CD_PREFETCH_BYTES
    jb .copy
    mov ecx, [cd_produced]
    sub ecx, ebx
    cmp ecx, CD_PREFETCH_BYTES
    jb .copy
    mov eax, CD_PREFETCH_BYTES
    mov edi, eax
    mov word [cd_sample_left], CD_PREFETCH_BYTES
.copy:
    mov ebp, eax
%ifdef EXTERNAL_CD_BUFFERS
    mov es, [cd_half_segment]
%else
    push ds
    pop es
%endif
    push ax
    mov cx, di
    sub cx, bp
    mov di, cd_half
    add di, bp
    xor eax, eax
    shr cx, 2
    rep stosd
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
%ifdef CD_QUEUE_HELPERS
    call cd_queue_read
%else
    mov si, cd_read_move
    mov ah, 0bh
    call far [cd_xms]
%endif
    cmp ax, 1
    jne .empty
    mov eax, [cd_read_move]
    sub ebp, eax
    jz .ready
    add [cd_read_address], ax
    mov [cd_read_move], ebp
    mov dword [cd_read_offset], 0
%ifdef CD_QUEUE_HELPERS
    call cd_queue_read
%else
    mov si, cd_read_move
    mov ah, 0bh
    call far [cd_xms]
%endif
    cmp ax, 1
    jne .empty
.ready:
    cmp word [cd_sample_left], 0
    je .uncached
    mov eax, [cd_consumed]
    mov [cd_sample_next], eax
    mov word [cd_sample_offset], 0
.cached:
%ifdef EXTERNAL_CD_BUFFERS
    mov gs, [cd_half_segment]
%else
    push ds
    pop gs
%endif
    mov ax, [cd_sample_offset]
    mov [cd_position], ax
    mov eax, [cd_take_bytes]
    add [cd_sample_next], eax
    add [cd_sample_offset], ax
    sub [cd_sample_left], ax
    mov byte [cd_valid], 1
    jmp .restore
.uncached:
%ifdef EXTERNAL_CD_BUFFERS
    mov gs, [cd_half_segment]
%else
    push ds
    pop gs
%endif
    mov word [cd_position], cd_half
    mov byte [cd_valid], 1
.restore:
    pop es
    popad
.done:
    ret
.empty:
    mov word [cd_sample_left], 0
    mov byte [cd_error], 2
    jmp .restore

cd_sample_next dd 0
cd_sample_offset dw 0
cd_sample_left dw 0

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
