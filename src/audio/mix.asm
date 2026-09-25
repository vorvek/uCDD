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
    mov [sb_dac_frame], eax
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
%ifdef OWN_HOST
    mov dword [sb_high_tag], -1
%endif
    cmp byte [sb_tail_valid], 0
    je .fast_dispatch
    mov fs, [sb_tail_segment]
    mov ax, [sb_tail_offset]
    sub ax, [sb_tail_start_bytes]
    mov [sb_tail_read_offset], ax
    jmp .frame
%ifdef RESIDENT_AUDIO
.fast_dispatch:
    cmp byte [sb_dac_enabled], 0
    jne .frame
%ifdef OWN_HOST
    cmp dword [game_physical], 0
    jne .frame
%endif
    cmp byte [sound_card], 0
    jne .frame
    cmp byte [sb_patch_active], 0
    jne .frame
    cmp dword [cd_step], 65536
    jne .frame
    cmp dword [cd_step_remainder], 0
    jne .frame
    cmp dword [cd_fraction], 0
    jne .frame
    cmp byte [sb_filter_legacy], 0
    jne .frame
    cmp byte [game_active], 0
    jne .fast_active
    cmp byte [cd_valid], 0
    jne .cd_only
    movzx eax, cx
    add [game_mix_frame], eax
    shl cx, 1
    xor ax, ax
    rep stosw
    jmp .half_complete
.cd_only:
    cmp dword [cd_gain], 256
    ja .fast_frame
    cmp dword [cd_gain+4], 256
    ja .fast_frame
    movzx eax, cx
    add [game_mix_frame], eax
.cd_only_frame:
    movsx eax, word [gs:bx]
    imul eax, [cd_gain]
    sar eax, 9
    stosw
    movsx eax, word [gs:bx+2]
    imul eax, [cd_gain+4]
    sar eax, 9
    stosw
    add bx, 4
    dec cx
    jnz .cd_only_frame
    jmp .half_complete
.fast_active:
    cmp byte [game_source], 0
    jne .frame
    cmp byte [sb_single], 0
    jne .frame
    cmp byte [sb_tail_valid], 0
    jne .frame
    cmp byte [sb_input], 0
    jne .frame
    cmp byte [sb_speaker], 1
    jne .frame
    cmp byte [sb_filter_legacy], 0
    jne .frame
    cmp byte [game_frame_shift], 2
    jne .frame
    cmp dword [game_step], 65536
    jne .frame
    cmp dword [game_exit_frame], 0
    jne .frame
    mov si, [game_dma]
    cmp byte [si+DMA_MASK], 0
    jne .frame
    cmp dword [game_limit], 0
    je .frame
    cmp dword [sb_pcm_gain], 32768
    jne .fast_frame
    cmp dword [sb_pcm_gain+4], 32768
    jne .fast_frame
    cmp dword [cd_gain], 256
    ja .fast_frame
    cmp dword [cd_gain+4], 256
    ja .fast_frame
    cmp byte [cd_valid], 0
    jne .unity_frame
    push bx
    movzx edx, cx
    add [game_mix_frame], edx
.unity_chunk:
    mov eax, ebp
    shr eax, 16
    shl ax, 2
    mov si, ax
    add si, [game_offset]
    mov eax, [game_limit]
    sub eax, ebp
    add eax, 65535
    shr eax, 16
    cmp eax, edx
    jbe .unity_amount
    mov eax, edx
.unity_amount:
    sub edx, eax
    mov cx, ax
    shl eax, 16
    add ebp, eax
    cmp ebp, [game_limit]
    jb .unity_copy
    sub ebp, [game_limit]
.unity_copy:
    mov eax, [fs:si]
    mov ebx, eax
    and ebx, 80008000h
    shr eax, 1
    and eax, 7fff7fffh
    or eax, ebx
    mov [es:di], eax
    add si, 4
    add di, 4
    dec cx
    jnz .unity_copy
    test edx, edx
    jnz .unity_chunk
    pop bx
    jmp .half_complete
.unity_frame:
    movzx eax, cx
    add [game_mix_frame], eax
.cd_chunk:
    mov eax, ebp
    shr eax, 16
    shl ax, 2
    mov si, ax
    add si, [game_offset]
    mov eax, [game_limit]
    sub eax, ebp
    add eax, 65535
    shr eax, 16
    cmp ax, cx
    jbe .cd_amount
    movzx eax, cx
.cd_amount:
    sub cx, ax
    push cx
    mov cx, ax
    shl eax, 16
    add ebp, eax
    cmp ebp, [game_limit]
    jb .cd_copy
    sub ebp, [game_limit]
.cd_copy:
    cmp dword [cd_gain], 256
    jne .cd_gain_copy
    cmp dword [cd_gain+4], 256
    jne .cd_gain_copy
.cd_full_copy:
    mov eax, [fs:si]
    mov edx, [gs:bx]
    shr eax, 1
    shr edx, 1
    and eax, 7fff7fffh
    and edx, 7fff7fffh
    xor eax, 40004000h
    xor edx, 40004000h
    add eax, edx
    xor eax, 80008000h
    mov [es:di], eax
    add si, 4
    add bx, 4
    add di, 4
    dec cx
    jnz .cd_full_copy
    jmp .cd_chunk_done
.cd_gain_copy:
    movsx edx, word [fs:si]
    sar edx, 1
    movsx eax, word [gs:bx]
    imul eax, [cd_gain]
    sar eax, 9
    add eax, edx
    stosw
    movsx edx, word [fs:si+2]
    sar edx, 1
    movsx eax, word [gs:bx+2]
    imul eax, [cd_gain+4]
    sar eax, 9
    add eax, edx
    stosw
    add si, 4
    add bx, 4
    dec cx
    jnz .cd_gain_copy
.cd_chunk_done:
    pop cx
    test cx, cx
    jnz .cd_chunk
    jmp .half_complete
.fast_frame:
    xor edx, edx
    xor esi, esi
    cmp byte [game_active], 0
    je .fast_pcm_ready
    mov eax, ebp
    shr eax, 16
    shl ax, 2
    add ax, [game_offset]
    mov si, ax
    movsx edx, word [fs:si]
    movsx esi, word [fs:si+2]
    sar edx, 1
    sar esi, 1
    imul edx, [sb_pcm_gain]
    imul esi, [sb_pcm_gain+4]
    sar edx, 15
    sar esi, 15
.fast_pcm_ready:
    xor eax, eax
    cmp byte [cd_valid], 0
    je .fast_left
    movsx eax, word [gs:bx]
    imul eax, [cd_gain]
    sar eax, 9
.fast_left:
    add eax, edx
    call .clip
    stosw
    xor eax, eax
    cmp byte [cd_valid], 0
    je .fast_right
    movsx eax, word [gs:bx+2]
    imul eax, [cd_gain+4]
    sar eax, 9
    add bx, 4
.fast_right:
    add eax, esi
    call .clip
    stosw
    cmp byte [game_active], 0
    je .fast_phase
    add ebp, 65536
    cmp ebp, [game_limit]
    jb .fast_phase
    sub ebp, [game_limit]
.fast_phase:
    inc dword [game_mix_frame]
    dec cx
    jnz .fast_frame
    jmp .half_complete
%else
.fast_dispatch:
%endif
.frame:
    xor edx, edx
    xor esi, esi
    cmp byte [sb_dac_enabled], 0
    je .dma_frame
    call sb_dac_sample
    jmp .sum
.dma_frame:
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
    cmp byte [sb_input], 0
    jne .audible
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
    cmp byte [sb_input], 0
    je .output_sample
    mov si, ax
    add si, [game_offset]
    ; The virtual input supplies unsigned PCM silence.
    mov byte [fs:si], 128
    xor esi, esi
    jmp .advance
.output_sample:
    cmp byte [game_frame_shift], 0
    jne .stereo
    mov si, ax
%ifdef OWN_HOST
    cmp dword [game_physical], 0
    je .mono_low
    call sb_high_sample
    movzx edx, al
    jmp .mono_value
.mono_low:
%endif
    add si, [sb_tail_read_offset]
    movzx edx, byte [fs:si]
%ifdef OWN_HOST
.mono_value:
%endif
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
    jae .single_left
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
.single_left:
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
    shl eax, 1
    cmp byte [game_source], 0
    jne .stereo8_normal
    cmp byte [sb_single], 0
    je .stereo8_normal
    mov edx, [dma8+DMA_POSITION]
    add edx, eax
    movzx esi, word [dma8+DMA_COUNT]
    inc esi
    cmp edx, esi
    jb .single8_address
    sub edx, esi
.single8_address:
    add dx, [game_offset]
    push eax
    mov si, dx
    movzx edx, byte [fs:si]
    sub edx, 128
    shl edx, 7
    pop eax
    inc eax
    cmp eax, [game_block_bytes]
    jae .single_left
    push edx
    movzx edx, word [dma8+DMA_COUNT]
    inc edx
    movzx eax, si
    sub ax, [game_offset]
    inc eax
    cmp eax, edx
    jb .single8_right
    sub eax, edx
.single8_right:
    add ax, [game_offset]
    mov si, ax
    movzx esi, byte [fs:si]
    sub esi, 128
    shl esi, 7
    pop edx
    jmp .advance
.stereo8_normal:
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
    cmp byte [game_source], 0
    jne .filtered
    cmp byte [sb_filter_legacy], 0
    je .pcm_gain
    cmp byte [sb_filter_bypass], 0
    jne .pcm_gain
    call sb_filter
.pcm_gain:
    imul edx, [sb_pcm_gain]
    sar edx, 15
    imul esi, [sb_pcm_gain+4]
    sar esi, 15
.filtered:
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
.half_complete:
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


; Two-pole 3.2 kHz filter at the nominal 44.1 kHz mix rate, Q14.
sb_filter:
    push ecx
%macro filter_channel 2
    imul ecx, %1, 638
    mov eax, ecx
    add eax, [sb_filter_state+%2]
    sar eax, 14
    mov %1, eax
    imul eax, 22436
    lea eax, [eax+ecx*2]
    add eax, [sb_filter_state+%2+4]
    mov [sb_filter_state+%2], eax
    imul eax, %1, -8604
    add eax, ecx
    mov [sb_filter_state+%2+4], eax
%endmacro
    filter_channel edx, 0
    filter_channel esi, 8
%unmacro filter_channel 2
    pop ecx
    ret

sb_tail_start_bytes dw 0

%include "audio/direct_sample.asm"

%ifdef OWN_HOST
%include "audio/high_dma.asm"
%endif

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
    add ax, (CD_HALF_BYTES+15)/16
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
