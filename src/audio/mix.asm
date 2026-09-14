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
    mov [game_mix_frame], eax
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
%ifdef WSS_INPUT
    cmp byte [game_source], 1
    jne .playing
    cmp byte [wss_paused], 0
    jne .sum
.playing:
%endif
    cmp dword [game_exit_frame], 0
    je .source
    mov eax, [game_mix_frame]
    cmp eax, [game_exit_frame]
    jae .sum
.source:
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
%ifdef WSS_INPUT
    cmp byte [game_source], 1
    jne .bytes
    test byte [wss_registers+8], 40h
    jnz .mono16
.bytes:
%endif
    shl ax, 1
    add ax, [game_offset]
    mov si, ax
    movzx edx, byte [fs:si]
    movzx esi, byte [fs:si+1]
    sub edx, 128
    sub esi, 128
    shl edx, 7
    shl esi, 7
%ifdef WSS_INPUT
    jmp .advance
.mono16:
    shl ax, 1
    add ax, [game_offset]
    mov si, ax
    movsx edx, word [fs:si]
    sar edx, 1
    mov esi, edx
%endif
.advance:
%ifdef WSS_INPUT
    cmp byte [game_source], 1
    jne .phase_step
    imul edx, [wss_gain]
    sar edx, 16
    imul esi, [wss_gain+4]
    sar esi, 16
.phase_step:
%endif
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
%ifdef RESIDENT_AUDIO
    call cd_interpolate
%endif
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
%ifdef RESIDENT_AUDIO
    cmp byte [sound_card], 1
    jne .left_word
    test cl, 1
    jnz .left_pair
    mov [pro_pair_left], eax
    jmp .left_stored
.left_pair:
    add eax, [pro_pair_left]
    add eax, 256
    sar eax, 9
    cmp eax, 127
    jle .round_left
    mov eax, 127
.round_left:
    xor al, 80h
    stosb
    jmp .left_stored
.left_word:
%endif
    stosw
%ifdef RESIDENT_AUDIO
.left_stored:
%endif
%ifdef CD_IMAGE_TEST
    xor eax, eax
    cmp byte [cd_valid], 0
    je .right
    movsx eax, word [gs:bx+2]
%ifdef RESIDENT_AUDIO
    add bx, 2
    call cd_interpolate
    sub bx, 2
%endif
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
%ifdef RESIDENT_AUDIO
    cmp byte [sound_card], 1
    jne .right_word
    test cl, 1
    jnz .right_pair
    mov [pro_pair_right], eax
    jmp .right_stored
.right_pair:
    add eax, [pro_pair_right]
    add eax, 256
    sar eax, 9
    cmp eax, 127
    jle .round_right
    mov eax, 127
.round_right:
    xor al, 80h
    stosb
    jmp .right_stored
.right_word:
%endif
    stosw
%ifdef RESIDENT_AUDIO
.right_stored:
%endif
    inc dword [game_mix_frame]
%ifdef RESIDENT_AUDIO
    mov eax, [cd_fraction]
    add eax, [cd_step]
    mov edx, [cd_step_error]
    add edx, [cd_step_remainder]
    cmp edx, [output_rate]
    jb .cd_phase
    sub edx, [output_rate]
    inc eax
.cd_phase:
    mov [cd_step_error], edx
    mov edx, eax
    and edx, 65535
    mov [cd_fraction], edx
    shr eax, 16
    shl ax, 2
    add bx, ax
%else
    add bx, 4
%endif
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
%ifdef RESIDENT_AUDIO
    mov eax, [cd_take_bytes]
    add [cd_consumed], eax
%else
    add dword [cd_consumed], PERIOD_BYTES
%endif
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
