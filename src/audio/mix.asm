; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%include "audio/sb_state.inc"

sb_mono_left dd 0

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
%ifdef RESIDENT_AUDIO
    cmp byte [sb_patch_active], 0
    jne .cd_ready
%endif
    call cd_begin_half
%ifdef RESIDENT_AUDIO
.cd_ready:
%endif
%endif
    mov eax, [periods]
    inc eax
    shl eax, OUTPUT_SHIFT
%ifdef RESIDENT_AUDIO
    cmp byte [sb_patch_active], 0
    je .normal_half
    mov eax, [sb_patch_clock]
.normal_half:
%endif
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
    add eax, [game_origin]
    adc edx, 0
    cmp dword [game_limit], 0
    je .full_ring
    div dword [game_limit]
    mov eax, edx
.full_ring:
    mov ebp, eax
    mov cx, PERIOD_FRAMES
%ifdef RESIDENT_AUDIO
    cmp byte [sb_patch_active], 0
    je .length_ready
    mov ecx, [sb_patch_limit]
    sub ecx, [sb_patch_clock]
    mov dword [pro_pair_left], 0
    mov dword [pro_pair_right], 0
.length_ready:
%endif
    mov bx, [cd_position]
    mov fs, [game_segment]
    mov ax, [game_offset]
    mov [sb_tail_read_offset], ax
    cmp byte [sb_tail_valid], 0
    je .frame
    mov fs, [sb_tail_segment]
    mov ax, [sb_tail_offset]
    sub ax, [sb_tail_start_bytes]
    mov [sb_tail_read_offset], ax
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
    cmp byte [game_source], 0
    jne .audible
    cmp byte [sb_speaker], 0
    je .advance
.audible:
    mov si, [game_dma]
    cmp byte [si+DMA_MASK], 0
    mov si, 0
    jne .sum
    mov eax, ebp
    shr eax, 16
    cmp byte [game_frame_shift], 0
    jne .stereo
    mov si, ax
    add si, [sb_tail_read_offset]
    movzx edx, byte [fs:si]
    sub edx, 128
    shl edx, 7
    mov esi, edx
    jmp .advance
.stereo:
    cmp byte [game_frame_shift], 1
    je .stereo8
    shl eax, 2
    cmp byte [game_source], 0
    jne .stereo16_normal
    cmp byte [sb_single], 0
    je .stereo16_normal
    mov edx, [dma16+DMA_POSITION]
    shl edx, 1
    add edx, eax
    movzx esi, word [dma16+DMA_COUNT]
    inc esi
    shl esi, 1
    cmp edx, esi
    jb .single16_address
    sub edx, esi
.single16_address:
    add dx, [game_offset]
    push eax
    mov si, dx
    movsx edx, word [fs:si]
    sar edx, 1
    pop eax
    add eax, 2
    cmp eax, [game_block_bytes]
    jae .single16_left
    push edx
    movzx edx, word [dma16+DMA_COUNT]
    inc edx
    shl edx, 1
    movzx eax, si
    sub ax, [game_offset]
    add eax, 2
    cmp eax, edx
    jb .single16_right
    sub eax, edx
.single16_right:
    add ax, [game_offset]
    mov si, ax
    movsx esi, word [fs:si]
    pop edx
    sar esi, 1
    jmp .advance
.single16_left:
    xor esi, esi
    jmp .advance
.stereo16_normal:
    add ax, [sb_tail_read_offset]
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
    add ax, [sb_tail_read_offset]
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
    cmp dword [game_limit], 0
    je .sum
.wrap:
    cmp ebp, [game_limit]
    jb .sum
    sub ebp, [game_limit]
    cmp byte [sb_tail_valid], 0
    je .wrap
    mov byte [sb_tail_valid], 0
    mov fs, [game_segment]
    mov ax, [game_offset]
    mov [sb_tail_read_offset], ax
    jmp .wrap
.sum:
%ifdef CD_IMAGE_TEST
    xor eax, eax
%ifdef RESIDENT_AUDIO
    cmp byte [sb_patch_active], 0
    jne .left
%endif
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
    cmp byte [sound_card], 3
    jne .pro_left
    mov [sb_mono_left], eax
    jmp .left_stored
.pro_left:
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
    cmp byte [sb_patch_active], 0
    je .encode_left
    movzx edx, byte [es:di]
    sub edx, 128
    add eax, edx
    call .clip_byte
.encode_left:
    xor al, 80h
    stosb
    jmp .left_stored
.left_word:
    cmp byte [sb_patch_active], 0
    je .left_save
    movsx edx, word [es:di]
    add eax, edx
    call .clip
.left_save:
%endif
    stosw
%ifdef RESIDENT_AUDIO
.left_stored:
%endif
%ifdef CD_IMAGE_TEST
    xor eax, eax
%ifdef RESIDENT_AUDIO
    cmp byte [sb_patch_active], 0
    jne .right
%endif
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
    cmp byte [sound_card], 3
    jne .pro_right
    add eax, [sb_mono_left]
    test cl, 1
    jnz .mono_pair
    mov [pro_pair_left], eax
    jmp .right_stored
.mono_pair:
    add eax, [pro_pair_left]
    add eax, 512
    sar eax, 10
    cmp eax, 127
    jle .mono_round
    mov eax, 127
.mono_round:
    cmp byte [sb_patch_active], 0
    je .mono_encode
    movzx edx, byte [es:di]
    sub edx, 128
    add eax, edx
    call .clip_byte
.mono_encode:
    xor al, 80h
    stosb
    jmp .right_stored
.pro_right:
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
    cmp byte [sb_patch_active], 0
    je .encode_right
    movzx edx, byte [es:di]
    sub edx, 128
    add eax, edx
    call .clip_byte
.encode_right:
    xor al, 80h
    stosb
    jmp .right_stored
.right_word:
    cmp byte [sb_patch_active], 0
    je .right_save
    movsx edx, word [es:di]
    add eax, edx
    call .clip
.right_save:
%endif
    stosw
%ifdef RESIDENT_AUDIO
.right_stored:
%endif
    inc dword [game_mix_frame]
%ifdef RESIDENT_AUDIO
    cmp byte [sb_patch_active], 0
    jne .cd_advanced
    cmp byte [cd_valid], 0
    je .cd_advanced
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
.cd_advanced:
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
    call sb_tail_prepare
    cmp byte [game_source], 0
    jne .pending_ready
    cmp byte [sb_single], 0
    jne .pending_ready
    cmp byte [game_start_pending], 2
    jne .pending_ready
    mov byte [game_start_pending], 0
.pending_ready:
%ifdef CD_IMAGE_TEST
%ifdef RESIDENT_AUDIO
    cmp byte [sb_patch_active], 0
    jne .done_half
%endif
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
%ifdef RESIDENT_AUDIO
.clip_byte:
    cmp eax, 127
    jle .byte_low
    mov eax, 127
.byte_low:
    cmp eax, -128
    jge .byte_done
    mov eax, -128
.byte_done:
    ret
%endif
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


sb_tail_start_bytes dw 0

; Save at most one old-generation tail before the producer owns the ring.
sb_tail_prepare:
    pushad
    push es
    push fs
    cmp byte [game_active], 0
    je .done
    cmp byte [game_source], 0
    jne .done
    cmp byte [sb_single], 0
    jne .done
    mov si, [game_dma]
    cmp byte [si+DMA_MASK], 0
    jne .done
%ifdef RESIDENT_AUDIO
    mov ax, [cd_half_segment]
    test ax, ax
    jz .done
    add ax, (PERIOD_BYTES+PERIOD_BYTES/32+4+15)/16
    mov [sb_tail_segment], ax
%endif
    cmp word [sb_tail_segment], 0
    je .done
    mov eax, [game_limit]
    shr eax, 16
    mov cl, [game_frame_shift]
    shl eax, cl
    cmp eax, [game_block_bytes]
    jne .done
    mov eax, [game_step]
    imul eax, PERIOD_FRAMES*2
    cmp eax, [game_limit]
    ja .done
    mov eax, [game_step]
    imul eax, PERIOD_FRAMES
    add eax, 65535
    shr eax, 16
    mov cl, [game_frame_shift]
    shl eax, cl
    cmp eax, 2048
    ja .done
    mov byte [sb_tail_mode], 1
    mov eax, [game_mix_frame]
    cmp dword [game_exit_frame], 0
    je .elapsed
    cmp eax, [game_exit_frame]
    jbe .elapsed
    mov eax, [game_exit_frame]
.elapsed:
    mul dword [game_step]
    shrd eax, edx, 16
    mov cl, [game_frame_shift]
    shl eax, cl
    cmp eax, [sb_tail_consumed]
    jbe .position_ready
    mov [sb_tail_consumed], eax
.position_ready:
    cmp byte [sb_tail_valid], 0
    jne .done
    cmp dword [game_exit_frame], 0
    jne .done
    mov eax, [game_step]
    imul eax, PERIOD_FRAMES
    add eax, [game_phase]
    cmp eax, [game_limit]
    jbe .done
    mov eax, [game_phase]
    shr eax, 16
    shl eax, cl
    mov [sb_tail_start_bytes], ax
    mov edx, [game_block_bytes]
    sub edx, eax
    cmp edx, 2048
    ja .done
    mov fs, [game_segment]
    mov si, [game_offset]
    add si, ax
    mov es, [sb_tail_segment]
    mov di, [sb_tail_offset]
    mov cx, dx
.copy:
    mov al, [fs:si]
    mov [es:di], al
    inc si
    inc di
    loop .copy
    add [sb_tail_consumed], edx
    mov byte [sb_tail_valid], 1
.done:
    pop fs
    pop es
    popad
    ret
