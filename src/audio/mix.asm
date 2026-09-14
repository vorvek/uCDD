; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; ES:DI is one output half. Sources use the current virtual playback state.
mix_half:
%ifdef SPEAKER_TEST
    mov byte [test_channel], 0
    mov ax, [test_half]
    inc word [test_half]
    cmp ax, 12
    jb .test_left
    cmp ax, 16
    jb .test_ready
    cmp ax, 28
    jae .test_ready
    mov byte [test_channel], 2
    jmp .test_ready
.test_left:
    mov byte [test_channel], 1
.test_ready:
%endif
%ifdef CD_IMAGE_TEST
    push gs
    call cd_begin_half
%endif
    mov eax, [periods]
    inc eax
    shl eax, OUTPUT_SHIFT
    cmp byte [game_active], 0
    je .phase
    cmp byte [game_start_pending], 1
    jne .phase
    mov [game_started], eax
    mov byte [game_start_pending], 2
.phase:
    sub eax, [game_started]
    mul dword [game_step]
    div dword [game_limit]
    mov ebp, edx
    mov cx, PERIOD_FRAMES
    mov bx, [cd_position]
    mov fs, [game_segment]
.frame:
    xor edx, edx
    xor esi, esi
    cmp byte [game_active], 0
    je .sum
    mov si, [game_dma]
    cmp byte [si+DMA_MASK], 0
    mov si, 0
    jne .sum
    mov eax, ebp
    shr eax, 16
    cmp byte [game_frame_shift], 0
    jne .stereo
    mov si, ax
    add si, [game_offset]
    movzx edx, byte [fs:si]
    sub edx, 128
    shl edx, 7
    mov esi, edx
    jmp .advance
.stereo:
    cmp byte [game_frame_shift], 1
    je .stereo8
    shl ax, 2
    add ax, [game_offset]
    mov si, ax
    movsx edx, word [fs:si]
    movsx esi, word [fs:si+2]
    sar edx, 1
    sar esi, 1
    jmp .advance
.stereo8:
    shl ax, 1
    add ax, [game_offset]
    mov si, ax
    movzx edx, byte [fs:si]
    movzx esi, byte [fs:si+1]
    sub edx, 128
    sub esi, 128
    shl edx, 7
    shl esi, 7
.advance:
    add ebp, [game_step]
    cmp ebp, [game_limit]
    jb .sum
    sub ebp, [game_limit]
.sum:
%ifdef CD_IMAGE_TEST
    xor eax, eax
    cmp byte [cd_valid], 0
    je .left
    movsx eax, word [gs:bx]
.left:
%ifdef MOUNTED_AUDIO
    imul eax, [cd_gain]
    sar eax, 8
%endif
%else
    movsx eax, word [cd_samples+bx]
%endif
%ifdef SPEAKER_TEST
    cmp byte [test_channel], 1
    je .left_ready
    xor eax, eax
.left_ready:
%endif
    sar eax, 1
    add eax, edx
    call .clip
    stosw
%ifdef CD_IMAGE_TEST
    xor eax, eax
    cmp byte [cd_valid], 0
    je .right
    movsx eax, word [gs:bx+2]
.right:
%ifdef MOUNTED_AUDIO
    imul eax, [cd_gain+4]
    sar eax, 8
%endif
%else
    movsx eax, word [cd_samples+bx+2]
%endif
%ifdef SPEAKER_TEST
    cmp byte [test_channel], 2
    je .right_ready
    xor eax, eax
.right_ready:
%endif
    sar eax, 1
    add eax, esi
    call .clip
    stosw
    add bx, 4
%ifndef MOUNTED_AUDIO
    and bx, 16383
%endif
    dec cx
    jnz .frame
    mov [cd_position], bx
    mov [game_phase], ebp
%ifdef CD_IMAGE_TEST
    cmp byte [cd_valid], 0
    je .done_half
    add dword [cd_consumed], PERIOD_BYTES
.done_half:
    pop gs
%endif
    ret
.clip:
    cmp eax, 32767
    jle .low
    mov eax, 32767
.low:
    cmp eax, -32768
    jge .done
    mov eax, -32768
.done:
    ret
