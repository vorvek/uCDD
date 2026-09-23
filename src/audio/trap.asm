; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%include "audio/sb_state.inc"

trap_install:
    mov ax, 1a06h
    call far [qpi]
    jc .fail
    mov [old_callback], di
    mov [old_callback+2], es
    ; This experiment must not replace an existing sound virtualizer.
    mov ax, es
    or ax, di
    jnz .fail
    push cs
    pop es
    mov di, port_callback
    mov ax, 1a07h
    call far [qpi]
    jc .fail
    mov byte [callback_set], 1
    mov si, trap_ports
.next:
    lodsw
    test ax, ax
    jz .done
    mov dx, ax
    mov ax, 1a09h
    call far [qpi]
    jc .fail
    inc word [trapped_count]
    jmp .next
.done:
    clc
    ret
.fail:
    stc
    ret
trap_remove:
    mov byte [trap_remove_failed], 0
    mov si, trap_ports
    mov cx, [trapped_count]
    jcxz .callback
.next:
    lodsw
    mov dx, ax
    mov ax, 1a0ah
    call far [qpi]
    jnc .next_port
    mov byte [trap_remove_failed], 1
.next_port:
    loop .next
.callback:
    cmp byte [callback_set], 0
    je .status
    mov byte [callback_set], 0
    les di, [old_callback]
    mov ax, 1a07h
    call far [qpi]
    jnc .status
    mov byte [trap_remove_failed], 1
.status:
    cmp byte [trap_remove_failed], 0
    je .ok
    stc
    ret
.ok:
    clc
    ret

output_clock:
    mov cx, 8
.retry:
    call .count
    mov bx, ax
    call .count
    cmp bx, RING_WORDS-1
    ja .again
    cmp ax, RING_WORDS-1
    ja .again
    sub bx, ax
    and bx, RING_WORDS-1
    cmp bx, 32
    jbe .stable
.again:
    loop .retry
%ifdef MOUNTED_AUDIO
    mov byte [fault], 2
%else
    mov byte [fault], 1
%endif
    mov eax, [last_clock]
    ret
.stable:
    movzx eax, ax
    mov ebx, RING_WORDS-1
    sub ebx, eax
    shr ebx, 1
    mov eax, [periods]
    shl eax, OUTPUT_SHIFT
    mov edx, eax
    xor edx, ebx
    test edx, PERIOD_FRAMES
    jz .same_half
    add eax, PERIOD_FRAMES
.same_half:
    and ebx, PERIOD_FRAMES-1
    add eax, ebx
    mov [last_clock], eax
    ret
.count:
    push bx
    mov al, 0
    mov dx, 0d8h
%ifdef RESIDENT_AUDIO
    cmp byte [sound_card], 0
    je .reset_dma
    mov dx, 0ch
.reset_dma:
%endif
    call physical_write
    mov dx, [dma_count_port]
    call physical_read
    mov bl, al
    call physical_read
    mov ah, al
    mov al, bl
%ifdef RESIDENT_AUDIO
    cmp byte [sound_card], 2
    jne .pro_count
    shr ax, 1
    jmp .count_ready
.pro_count:
    cmp byte [sound_card], 3
    jne .stereo_count
    shl ax, 2
    or ax, 3
    jmp .count_ready
.stereo_count:
    cmp byte [sound_card], 1
    jne .count_ready
    shl ax, 1
    or ax, 1
.count_ready:
%endif
    pop bx
    ret

game_elapsed:
    cmp byte [game_start_pending], 1
    je .zero
    cmp byte [game_source], 0
    jne .output
    cmp byte [sb_single], 0
    jne .output
    mov eax, [game_mix_frame]
    cmp byte [sb_paused], 0
    je .done
    mov eax, [sb_pause_mix_frame]
    ret
.output:
    call output_clock
    cmp byte [sb_paused], 0
    je .sb_clock
    mov eax, [sb_pause_clock]
.sb_clock:
%ifdef WSS_INPUT
    cmp byte [game_source], 1
    jne .clock_ready
    cmp byte [wss_paused], 0
    je .clock_ready
    mov eax, [wss_pause_clock]
.clock_ready:
%endif
    sub eax, [game_started]
    cmp byte [game_start_pending], 2
    jne .done
    test eax, eax
    js .zero
    mov byte [game_start_pending], 0
    ret
.zero:
    xor eax, eax
.done:
    ret

port_callback:
%ifdef RESIDENT_AUDIO
    cmp byte [cs:callback_set], 0
    jne .active
    stc
    retf
.active:
%endif
    pushad
    movzx ebp, sp
    push ds
    push es
    push fs
    push cs
    pop ds
%ifdef RESIDENT_AUDIO
    mov dword [ss:ebp+12], 0
    jmp .data_ready
.emm_entry:
    pushad
    mov ebp, esp
    push ds
    push es
    push fs
    mov dword [ss:ebp+12], 1
    inc byte [emm_in_callback]
    call emm_pic_sync
%endif
.data_ready:
%ifdef RESIDENT_AUDIO
    mov [callback_port], dx
    mov [callback_value], al
%endif
    inc dword [port_calls]
    test cl, 18h
    jnz .wide
%ifdef MDM_SUPPORT
    cmp dx, 60h
    jne .not_keyboard
    test cl, 4
    jnz .keyboard_write
    mov dx, 64h
    call physical_read
    mov bl, al
    mov dx, 60h
    call physical_read
    and bl, 21h
    cmp bl, 1
    jne .result
    cmp byte [mdm_key_active], 0
    jne .result
    call mdm_scan
    jmp .result
.keyboard_write:
    call physical_write
    jmp .done
.not_keyboard:
%endif
%ifdef WSS_INPUT
    cmp dx, 530h
    jb .normal_port
    cmp dx, 537h
    jbe .wss_port
.normal_port:
%endif
    cmp dx, 200h
    jb .dma_port
    mov bx, dx
    sub bx, [guest_base]
    cmp bx, 0fh
    ja .not_sb_port
    lea dx, [bx+220h]
.not_sb_port:
    jmp .dispatch
.dma_port:
    call dma_port
.dispatch:
    test cl, 4
    jz .read
%ifdef VIRTUAL_IRQ
    cmp dx, 20h
    je .pic_write
    cmp dx, 21h
    je .pic_write
%endif
    cmp dx, 226h
    je .reset
    cmp dx, 22ch
    je .command
    cmp dx, 224h
    je .mixer_index
    cmp dx, 225h
    je .mixer_data
    cmp dx, 0ch
    je .flip_reset
    cmp dx, 0eh
    je .clear_mask
    cmp dx, 0ah
    je .mask
    cmp dx, 0bh
    je .mode
    cmp dx, 83h
    je .page
    cmp dx, 2
    je .address
    cmp dx, 3
    je .count
    jmp .unsupported
.wide:
    mov bl, cl
    and bl, 1ch
    cmp bl, 0ch
    jne .unsupported
    mov bx, dx
    sub bx, [guest_base]
    cmp bx, 4
    jne .unsupported
    mov [virtual_mixer_index], al
    mov al, ah
    jmp .mixer_data
.unsupported:
%ifdef MOUNTED_AUDIO
    mov byte [fault], 3
%else
    mov byte [fault], 1
%endif
    jmp .done
.reset:
    mov byte [sb_tail_mode], 0
    mov byte [sb_tail_valid], 0
%ifdef RESIDENT_AUDIO
    mov byte [sb_patch_available], 0
%endif
    mov byte [sb_finished], 0
    mov byte [sb_paused], 0
    mov byte [sb_single], 0
    mov byte [sb_input], 0
    mov byte [sb_speaker], 1
    mov byte [sb_filter_legacy], 0
    mov byte [game_active], 0
    mov byte [game_start_pending], 0
    mov dword [game_exit_frame], 0
%ifdef VIRTUAL_IRQ
    call virtual_irq_reset
%endif
    test al, al
    jnz .done
    inc word [virtual_resets]
    mov word [reply], 0aah
    mov byte [reply_count], 1
    mov byte [arguments], 0
    jmp .done
.mixer_index:
    mov [virtual_mixer_index], al
    jmp .done
.mixer_data:
    movzx bx, byte [virtual_mixer_index]
    cmp bl, 80h
    je .done
    cmp bl, 81h
    je .done
    mov [virtual_mixer+bx], al
    cmp bl, 0eh
    jne .mixer_volume
    and al, 20h
    mov [sb_filter_bypass], al
    jmp .done
.mixer_volume:
    cmp bl, 4
    jne .done
    shr al, 5
    movzx ebx, al
    mov eax, [sb_pcm_levels+ebx*4]
    mov [sb_pcm_gain], eax
    mov al, [virtual_mixer+4]
    shr al, 1
    and al, 7
    movzx ebx, al
    mov eax, [sb_pcm_levels+ebx*4]
    mov [sb_pcm_gain+4], eax
    jmp .done
.flip_reset:
    mov byte [si+DMA_FLIP], 0
    call dma_shared_write
    jmp .done
.mask:
    mov ah, al
    and ah, 3
    mov bx, [guest_dma8]
    cmp si, dma8
    je .mask_channel
    mov bx, [guest_dma16]
    sub bl, 4
.mask_channel:
    cmp ah, bl
    jne .unowned_dma
    and al, 4
    mov [si+DMA_MASK], al
%ifdef WSS_INPUT
    test al, al
    jnz .done
    cmp si, dma8
    je .wss_arm
%endif
    jmp .done
.mode:
    mov ah, al
    and ah, 3
    mov bx, [guest_dma8]
    cmp si, dma8
    je .mode_channel
    mov bx, [guest_dma16]
    sub bl, 4
.mode_channel:
    cmp ah, bl
    jne .unowned_dma
    and al, 0fch
    or al, 1
    cmp al, 49h
    je .set_mode
    cmp al, 59h
    je .set_mode
    cmp al, 45h
    je .set_mode
    cmp al, 55h
    jne .unsupported
.set_mode:
    mov [si+DMA_MODE], al
    jmp .done
.clear_mask:
    mov byte [si+DMA_MASK], 0
    mov dx, 0ah
    mov bx, [guest_dma8]
    cmp si, dma8
    je .clear_channels
    mov bx, [guest_dma16]
    sub bl, 4
.clear_channels:
    xor al, al
.clear_channel:
    cmp al, bl
    je .next_channel
    call dma_unowned_write
.next_channel:
    inc al
    cmp al, 4
    jb .clear_channel
    jmp .done
.unowned_dma:
    call dma_unowned_write
    jmp .done
.page:
    mov [si+DMA_PAGE], al
    jmp .done
.address:
    mov bx, DMA_ADDRESS
    jmp .dma_word
.count:
    mov byte [si+3], 0
    mov bx, DMA_COUNT
.dma_word:
    mov dword [si+DMA_POSITION], 0
    mov byte [si+3], 0
    mov byte [sb_finished], 0
    movzx cx, byte [si+DMA_FLIP]
    add bx, cx
    mov [si+bx], al
    xor byte [si+DMA_FLIP], 1
    jmp .done
.command:
    cmp byte [arguments], 0
    jne .argument
    mov [dsp_command], al
    cmp al, 41h
    je .rate
    cmp al, 40h
    je .time_constant
    cmp al, 48h
    je .rate
    cmp al, 14h
    je .rate
    cmp al, 24h
    je .rate
    cmp al, 1ch
    je .legacy_start
    cmp al, 90h
    je .legacy_start
    cmp al, 91h
    je .legacy_start
    cmp al, 0c6h
    je .play
    cmp al, 0c4h
    je .play
    cmp al, 0b0h
    je .play
    cmp al, 0b2h
    je .play
    cmp al, 0b6h
    je .play
    cmp al, 0b4h
    je .play
    cmp al, 0d0h
    je .pause8
    cmp al, 0d5h
    je .pause16
    cmp al, 0dah
    je .exit8
    cmp al, 0d9h
    je .exit16
    cmp al, 0d4h
    je .resume8
    cmp al, 0d6h
    je .resume16
    cmp al, 0d3h
    je .speaker_off
    cmp al, 0d1h
    je .speaker_on
    cmp al, 0d8h
    je .speaker_status
    cmp al, 0e0h
    je .time_constant
    cmp al, 0e4h
    je .time_constant
    cmp al, 0e8h
    je .test_read
    cmp al, 0f2h
    je .force_irq
    cmp al, 0e1h
    jne .unsupported
    mov word [reply], 0504h
    mov byte [reply_count], 2
    jmp .done
.speaker_off:
    mov byte [sb_speaker], 0
    jmp .done
.speaker_on:
    mov byte [sb_speaker], 1
    jmp .done
.speaker_status:
    mov al, [sb_speaker]
    neg al
    jmp .one_reply
.test_read:
    mov al, [sb_test_register]
.one_reply:
    mov [reply], al
    mov byte [reply_count], 1
    jmp .done
.force_irq:
%ifdef VIRTUAL_IRQ
    mov byte [virtual_dsp_irq], 1
    mov al, [guest_irq_bit]
    mov [virtual_pic_request], al
%endif
    jmp .done
.resume8:
    cmp byte [game_frame_shift], 2
    je .done
    jmp .resume
.resume16:
    cmp byte [game_frame_shift], 2
    jne .done
.resume:
    cmp byte [sb_paused], 0
    je .done
    call output_clock
    sub eax, [sb_pause_clock]
    add [game_started], eax
    mov eax, [sb_pause_mix_frame]
    mov [game_mix_frame], eax
    mov byte [sb_paused], 0
    mov byte [game_active], 1
    jmp .done
.exit8:
    cmp byte [game_frame_shift], 2
    je .done
    jmp .exit_block
.exit16:
    cmp byte [game_frame_shift], 2
    jne .done
.exit_block:
    cmp byte [game_active], 0
    je .done
    cmp dword [game_exit_frame], 0
    jne .done
    cmp byte [sb_tail_mode], 0
    je .exit_clock
    mov eax, [sb_tail_consumed]
    xor edx, edx
    div dword [game_block_bytes]
    inc eax
    mul dword [game_block_bytes]
    mov cl, [game_frame_shift]
    shr eax, cl
    mov edx, eax
    shr edx, 16
    shl eax, 16
    div dword [game_step]
    test edx, edx
    jz .exit_store
    inc eax
    jmp .exit_store
.exit_clock:
    call game_elapsed
    movzx ecx, word [game_rate]
    mul ecx
    mov ecx, OUTPUT_RATE
    div ecx
    mov ebx, [game_block_bytes]
    mov cl, [game_frame_shift]
    shr ebx, cl
    xor edx, edx
    div ebx
    inc eax
    mul ebx
    mov ecx, OUTPUT_RATE
    mul ecx
    movzx ecx, word [game_rate]
    div ecx
    test edx, edx
    jz .exit_store
    inc eax
.exit_store:
    mov [game_exit_frame], eax
    jmp .done
.pause8:
    cmp byte [game_frame_shift], 2
    je .done
    jmp .pause
.pause16:
    cmp byte [game_frame_shift], 2
    jne .done
.pause:
    cmp byte [game_active], 0
    je .done
    call output_clock
    mov [sb_pause_clock], eax
    mov eax, [game_mix_frame]
    mov [sb_pause_mix_frame], eax
    mov eax, [sb_tail_consumed]
    cmp byte [sb_tail_mode], 0
    jne .pause_bytes
    call game_elapsed
    movzx ecx, word [game_rate]
    mul ecx
    mov ecx, OUTPUT_RATE
    div ecx
    mov cl, [game_frame_shift]
    shl eax, cl
.pause_bytes:
    mov si, [game_dma]
    cmp si, dma16
    jne .pause_units
    shr eax, 1
.pause_units:
    cmp byte [sb_single], 0
    je .pause_count
    add eax, [si+DMA_POSITION]
.pause_count:
    movzx ecx, word [si+DMA_COUNT]
    inc ecx
    xor edx, edx
    div ecx
    mov ax, [si+DMA_COUNT]
    sub ax, dx
    mov [si+DMA_SNAPSHOT], ax
    mov byte [sb_paused], 1
    mov byte [game_active], 0
    jmp .done
.rate:
    mov byte [arguments], 2
    jmp .done
.play:
    ; Both FIFO modes use the same PCM conversion and block interrupts.
    or byte [dsp_command], 2
    mov byte [arguments], 3
    jmp .done
.time_constant:
    mov byte [arguments], 1
    jmp .done
.legacy_start:
    mov ax, [legacy_block]
.legacy_format:
    push ax
    mov byte [pending_frame_shift], 0
    cmp byte [dsp_command], 24h
    je .legacy_mono
    test ax, ax
    jz .legacy_mono
    mov ax, [legacy_rate]
    test byte [virtual_mixer+0eh], 2
    jz .legacy_rate
    mov byte [pending_frame_shift], 1
    shr ax, 1
    jmp .legacy_rate
.legacy_mono:
    mov ax, [legacy_rate]
.legacy_rate:
    mov [game_rate], ax
    movzx eax, ax
    shl eax, 16
    xor edx, edx
    mov ecx, OUTPUT_RATE
    div ecx
    mov [game_step], eax
    pop ax
    jmp .validate_start
.argument:
    cmp byte [dsp_command], 0e0h
    jne .test_argument
    not al
    mov [reply], al
    mov byte [reply_count], 1
    jmp .argument_done
.test_argument:
    cmp byte [dsp_command], 0e4h
    jne .pcm_argument
    mov [sb_test_register], al
    jmp .argument_done
.pcm_argument:
    cmp byte [dsp_command], 14h
    je .length
    cmp byte [dsp_command], 24h
    je .length
    cmp byte [dsp_command], 40h
    je .set_time_constant
    cmp byte [dsp_command], 48h
    je .legacy_length
    cmp byte [dsp_command], 41h
    jne .play_argument
    cmp byte [arguments], 2
    jne .rate_low
    mov [game_rate+1], al
    jmp .argument_done
.rate_low:
    mov [game_rate], al
.set_rate:
    cmp word [game_rate], 4000
    jb .unsupported
    cmp word [game_rate], 44100
    ja .unsupported
    movzx eax, word [game_rate]
    shl eax, 16
    xor edx, edx
    mov ecx, OUTPUT_RATE
    div ecx
    mov [game_step], eax
    jmp .argument_done
.play_argument:
    cmp byte [arguments], 3
    jne .length
    mov byte [pending_frame_shift], 0
    cmp byte [dsp_command], 0b2h
    je .format16
    cmp byte [dsp_command], 0b6h
    jne .mono_mode
.format16:
    cmp al, 30h
    jne .unsupported
    mov byte [pending_frame_shift], 2
    jmp .argument_done
.mono_mode:
    cmp al, 20h
    jne .mono
    mov byte [pending_frame_shift], 1
    jmp .argument_done
.mono:
    test al, al
    jnz .unsupported
    jmp .argument_done
.set_time_constant:
    movzx ecx, al
    neg ecx
    add ecx, 256
    mov eax, 1000000
    xor edx, edx
    div ecx
    cmp eax, 65535
    ja .unsupported
    mov [legacy_rate], ax
    test byte [virtual_mixer+0eh], 2
    jz .time_mono
    shr ax, 1
.time_mono:
    mov [game_rate], ax
    jmp .set_rate
.legacy_length:
    cmp byte [arguments], 2
    jne .legacy_high
    mov [legacy_block], al
    jmp .argument_done
.legacy_high:
    mov [legacy_block+1], al
    jmp .argument_done
.length:
    cmp byte [arguments], 2
    jne .start
    mov [block_low], al
    jmp .argument_done
.start:
    mov ah, al
    mov al, [block_low]
    cmp byte [dsp_command], 24h
    je .legacy_format
    cmp byte [dsp_command], 14h
    jne .validate_start
    jmp .legacy_format
.validate_start:
    mov byte [sb_finished], 0
    mov byte [sb_single], 0
    mov byte [sb_input], 0
    cmp byte [dsp_command], 24h
    jne .output_kind
    mov byte [sb_input], 1
    jmp .single
.output_kind:
    cmp byte [dsp_command], 0b2h
    je .single
    cmp byte [dsp_command], 14h
    je .single
    cmp byte [dsp_command], 91h
    jne .start_kind
.single:
    mov byte [sb_single], 1
.start_kind:
%ifdef WSS_INPUT
    mov byte [wss_paused], 0
    and byte [wss_registers+9], 0feh
%endif
    mov byte [game_source], 0
    mov si, dma8
    mov cl, 0
    cmp byte [pending_frame_shift], 2
    jne .dma_selected
    mov si, dma16
    mov cl, 1
.dma_selected:
%ifdef RESIDENT_AUDIO
    cmp byte [host_backend], 2
    jne .dma_state_ready
    cmp dword [ss:ebp+12], 1
    jne .dma_state_ready
    cmp word [host_emm_min_port], 100h
    jb .dma_state_ready
    call emm_dma_snapshot
.dma_state_ready:
%endif
    cmp byte [sb_input], 0
    je .direction_ready
    mov bl, [si+DMA_MODE]
    and bl, 0efh
    cmp bl, 45h
    jne .unsupported
.direction_ready:
    cmp ax, [si+DMA_COUNT]
    ja .unsupported
    movzx edx, ax
    inc edx
    shl edx, cl
.validate_dma:
    cmp byte [sb_single], 1
    je .single_buffer
    cmp edx, 512
    jb .unsupported
    movzx ebx, word [si+DMA_COUNT]
    inc ebx
    shl ebx, cl
    cmp ebx, 512
    jb .unsupported
    cmp ebx, 32768
    ja .unsupported
    mov cl, [pending_frame_shift]
    mov eax, 1
    shl eax, cl
    dec eax
    test ebx, eax
    jnz .unsupported
    test edx, eax
    jz .block_aligned
    jmp .unsupported
.block_aligned:
    cmp edx, ebx
    je .buffer_address
%ifdef WSS_INPUT
    cmp byte [game_source], 1
    je .buffer_address
%endif
    mov eax, ebx
    sub eax, edx
    mov cl, [pending_frame_shift]
    shr eax, cl
    imul eax, OUTPUT_RATE
    movzx ecx, word [game_rate]
    imul ecx, PERIOD_FRAMES*2
    cmp eax, ecx
    jb .unsupported
    jmp .buffer_address
.single_buffer:
    movzx ebx, word [si+DMA_COUNT]
    inc ebx
    cmp si, dma16
    jne .single_size
    shl ebx, 1
    cmp ebx, 65536
    ja .unsupported
.single_size:
    test byte [si+DMA_MODE], 10h
    jnz .buffer_address
    mov eax, [si+DMA_POSITION]
    cmp si, dma16
    jne .single_position
    shl eax, 1
.single_position:
    cmp eax, ebx
    ja .unsupported
    neg eax
    add eax, ebx
    cmp edx, eax
    ja .unsupported
.buffer_address:
    movzx eax, word [si+DMA_ADDRESS]
    cmp si, dma16
    jne .byte_address
    shl eax, 1
    ; High DMA uses a 128 KiB window; page bit zero is ignored.
    movzx ecx, byte [si+DMA_PAGE]
    and cl, 0feh
    shl ecx, 16
    jmp .address_window
.byte_address:
    movzx ecx, byte [si+DMA_PAGE]
    shl ecx, 16
.address_window:
    add ecx, eax
    add eax, ebx
    cmp si, dma16
    je .word_window
    cmp eax, 65536
    ja .unsupported
    jmp .address_limit
.word_window:
    cmp eax, 131072
    ja .unsupported
.address_limit:
    cmp byte [sb_single], 0
    je .linear_limit
    cmp si, dma16
    jne .linear_limit
    mov eax, ecx
    and eax, 15
    add eax, ebx
    cmp eax, 65536
    ja .unsupported
.linear_limit:
    mov eax, ecx
    add eax, ebx
    cmp eax, 0a0000h
    ja .unsupported
    mov [game_dma], si
    mov esi, ecx
    mov [game_block_bytes], edx
    mov cl, [pending_frame_shift]
    mov [game_frame_shift], cl
    mov al, 1
    cmp cl, 2
    jne .irq_bit
    inc al
.irq_bit:
    mov [game_irq_bit], al
    mov dword [game_origin], 0
    cmp byte [sb_single], 0
    je .origin_ready
    mov di, [game_dma]
    cmp byte [pending_frame_shift], 0
    jne .origin_ready
    mov eax, [di+DMA_POSITION]
    shr eax, cl
    shl eax, 16
    mov [game_origin], eax
.origin_ready:
    shr ebx, cl
    shl ebx, 16
    mov [game_limit], ebx
    cmp byte [sb_single], 0
    je .ring_ready
    cmp byte [pending_frame_shift], 0
    je .ring_ready
    mov dword [game_limit], 0
.ring_ready:
    mov bx, si
    and bx, 15
    mov [game_offset], bx
    shr esi, 4
    mov [game_segment], si
    mov byte [game_start_pending], 1
    mov dword [game_exit_frame], 0
    mov byte [sb_paused], 0
    cmp byte [sb_single], 0
    je .duration_ready
    mov eax, [game_block_bytes]
    mov ecx, OUTPUT_RATE
    mul ecx
    movzx ebx, word [game_rate]
    mov cl, [game_frame_shift]
    shl ebx, cl
    mov ecx, ebx
    div ecx
    test edx, edx
    jz .duration
    inc eax
.duration:
    mov [game_exit_frame], eax
.duration_ready:
    mov byte [sb_filter_legacy], 0
    cmp byte [dsp_command], 0a0h
    jae .filter_ready
    cmp byte [sb_input], 0
    jne .filter_ready
    mov byte [sb_filter_legacy], 1
.filter_ready:
    mov dword [sb_filter_state], 0
    mov dword [sb_filter_state+4], 0
    mov dword [sb_filter_state+8], 0
    mov dword [sb_filter_state+12], 0
    mov byte [sb_tail_mode], 0
    mov byte [sb_tail_valid], 0
    mov dword [sb_tail_consumed], 0
%ifdef VIRTUAL_IRQ
    call virtual_irq_reset
%endif
    mov byte [game_active], 1
    inc word [virtual_starts]
%ifdef RESIDENT_AUDIO
    cmp dword [ss:ebp+12], 1
    je .patch_deferred
    call sb_patch
.patch_deferred:
%endif
%ifdef WSS_INPUT
    cmp byte [game_source], 1
    jne .sb_started
    call wss_hold
    jmp .done
.sb_started:
%endif
    cmp byte [dsp_command], 1ch
    je .done
    cmp byte [dsp_command], 90h
    je .done
    cmp byte [dsp_command], 91h
    je .done
.argument_done:
    dec byte [arguments]
    jmp .done
%ifdef WSS_INPUT
%include "audio/wss_input.inc"
%endif
.read:
    cmp dx, 226h
    je .reset_read
%ifdef VIRTUAL_IRQ
    cmp dx, 20h
    je .pic_read
    cmp dx, 21h
    je .pic_read
%endif
    cmp dx, 22ch
    je .ready
    cmp dx, 22eh
    je .status
    cmp dx, 22fh
    je .status16
    cmp dx, 22ah
    je .reply
    cmp dx, 225h
    je .mixer_read
    cmp dx, 3
    je .dma_read
    jmp .unsupported
.reset_read:
    mov al, 0ffh
    jmp .result
.ready:
    xor al, al
    jmp .result
.status:
%ifdef VIRTUAL_IRQ
    and byte [virtual_dsp_irq], 0feh
%ifdef RESIDENT_AUDIO
    call emm_irq_ack
%endif
%endif
    xor al, al
    cmp byte [reply_count], 0
    je .result
    mov al, 80h
    jmp .result
.status16:
%ifdef VIRTUAL_IRQ
    and byte [virtual_dsp_irq], 0fdh
%ifdef RESIDENT_AUDIO
    call emm_irq_ack
%endif
%endif
    xor al, al
    jmp .result
.reply:
    mov al, [reply]
    cmp byte [reply_count], 0
    je .result
    shr word [reply], 8
    dec byte [reply_count]
    jmp .result
.mixer_read:
    movzx bx, byte [virtual_mixer_index]
%ifdef VIRTUAL_IRQ
    cmp bx, 82h
    jne .mixer_value
    mov al, [virtual_dsp_irq]
    jmp .result
.mixer_value:
%endif
    mov al, [virtual_mixer+bx]
    jmp .result
.dma_read:
    cmp byte [si+DMA_FLIP], 0
    jne .count_high
    cmp si, [game_dma]
    jne .idle_count
    cmp byte [game_active], 0
    je .idle_count
    mov eax, [sb_tail_consumed]
    cmp byte [sb_tail_mode], 0
    jne .count_bytes
    call game_elapsed
    movzx ecx, word [game_rate]
    mul ecx
    mov ecx, OUTPUT_RATE
    div ecx
    mov cl, [game_frame_shift]
    shl eax, cl
.count_bytes:
    cmp si, dma16
    jne .count_units
    shr eax, 1
    cmp byte [sb_single], 0
    je .count_units
    mov ecx, [game_block_bytes]
    shr ecx, 1
    cmp eax, ecx
    jbe .count_units
    mov eax, ecx
.count_units:
    cmp byte [sb_single], 0
    je .cyclic_count
    add eax, [si+DMA_POSITION]
    test byte [si+DMA_MODE], 10h
    jnz .cyclic_count
    movzx ebx, word [si+DMA_COUNT]
    cmp eax, ebx
    ja .terminal_count
    sub ebx, eax
    jmp .snapshot
.terminal_count:
    mov bx, 0ffffh
    jmp .snapshot
.cyclic_count:
    movzx ecx, word [si+DMA_COUNT]
    inc ecx
    xor edx, edx
    div ecx
    mov bx, [si+DMA_COUNT]
    sub bx, dx
    jmp .snapshot
.idle_count:
    cmp si, [game_dma]
    jne .idle_snapshot
    cmp byte [sb_finished], 0
    jne .held_count
    cmp byte [sb_paused], 0
    je .idle_snapshot
.held_count:
    mov bx, [si+DMA_SNAPSHOT]
    jmp .snapshot
.idle_snapshot:
    mov bx, [si+DMA_COUNT]
    cmp byte [si+3], 0
    je .snapshot
    mov bx, 0ffffh
.snapshot:
    mov [si+DMA_SNAPSHOT], bx
    mov al, bl
    jmp .count_result
.count_high:
    mov al, [si+DMA_SNAPSHOT+1]
.count_result:
    xor byte [si+DMA_FLIP], 1
    jmp .result
%ifdef VIRTUAL_IRQ
.pic_write:
    call virtual_pic_write
    jmp .done
.pic_read:
    call virtual_pic_read
%endif
.result:
%ifdef RESIDENT_AUDIO
    cmp dword [ss:ebp+12], 1
    jne .real_result
    mov [ss:ebp+28], al
    jmp .done
.real_result:
%endif
    mov [ss:bp+28], al
.done:
%ifdef RESIDENT_AUDIO
    cmp dword [ss:ebp+12], 1
    jne .restore
    dec byte [emm_in_callback]
.restore:
%endif
    pop fs
    pop es
    pop ds
    popad
    clc
    retf

dma_unowned_write:
%ifdef RESIDENT_AUDIO
    cmp byte [sb_running], 0
    je dma_shared_write
    mov ah, al
    and ah, 3
    cmp byte [sound_card], 0
    je .high_output
    cmp si, dma8
    jne dma_shared_write
    cmp ah, [sb_dma8]
    je .done
    jmp dma_shared_write
.high_output:
    cmp si, dma16
    jne dma_shared_write
    add ah, 4
    cmp ah, [sb_dma16]
    jne dma_shared_write
.done:
    ret
%else
    jmp dma_shared_write
%endif

dma_shared_write:
    push dx
    cmp si, dma16
    jne .write
    sub dx, 0ah
    shl dx, 1
    add dx, 0d4h
.write:
    call physical_write
    pop dx
    ret

dma_port:
    mov si, dma8
    cmp dx, [guest_dma_ports+4]
    je .low_page
    cmp dx, [guest_dma_ports]
    je .low_address
    cmp dx, [guest_dma_ports+2]
    je .low_count
    cmp dx, [guest_dma_ports+10]
    je .page
    cmp dx, [guest_dma_ports+6]
    je .address
    cmp dx, [guest_dma_ports+8]
    je .count
    cmp dx, 0d4h
    jb .done
    cmp dx, 0dch
    ja .done
    test dl, 1
    jnz .done
    sub dx, 0c0h
    shr dx, 1
    jmp .high
.low_page:
    mov dx, 83h
    ret
.low_address:
    mov dx, 2
    ret
.low_count:
    mov dx, 3
    ret
.page:
    mov dx, 83h
    jmp .high
.address:
    mov dx, 2
    jmp .high
.count:
    mov dx, 3
.high:
    mov si, dma16
.done:
    ret

%ifdef RESIDENT_AUDIO
emm_pic_sync:
    cmp word [host_emm_min_port], 100h
    jb .done
    push ax
    mov al, [guest_irq_bit]
    cmp al, [physical_irq_bit]
    je .restore_ax
    push bx
    push dx
    mov dx, 21h
    call physical_read
    mov ah, al
    xor ah, [emm_pic_mask_shadow]
    and ah, [guest_irq_bit]
    jz .save
    mov bl, [guest_irq_bit]
    not bl
    and [virtual_pic_mask], bl
    not bl
    and bl, al
    or [virtual_pic_mask], bl
.save:
    mov [emm_pic_mask_shadow], al
    pop dx
    pop bx
.restore_ax:
    pop ax
.done:
    ret

emm_irq_ack:
    cmp byte [host_backend], 2
    jne .done
    cmp dword [ss:ebp+12], 1
    jne .done
    cmp word [host_emm_min_port], 100h
    jb .done
    mov byte [virtual_pic_service], 0
.done:
    ret

emm_dma_snapshot:
    push ax
    push bx
    push dx
    cmp si, dma16
    je .high
    mov bx, [guest_dma8]
    mov dx, 0ch
    xor al, al
    call physical_write
    mov dx, bx
    shl dx, 1
    jmp .ports_ready
.high:
    mov bx, [guest_dma16]
    sub bx, 4
    mov dx, 0d8h
    xor al, al
    call physical_write
    mov dx, bx
    shl dx, 2
    add dx, 0c0h
.ports_ready:
    call physical_read
    mov [si+DMA_ADDRESS], al
    call physical_read
    mov [si+DMA_ADDRESS+1], al
    inc dx
    cmp si, dma16
    jne .count_ready
    inc dx
.count_ready:
    call physical_read
    mov [si+DMA_COUNT], al
    call physical_read
    mov [si+DMA_COUNT+1], al
    cmp si, dma16
    je .high_page
    mov dx, [guest_dma_ports+4]
    jmp .page_ready
.high_page:
    mov dx, [guest_dma_ports+10]
.page_ready:
    call physical_read
    mov [si+DMA_PAGE], al
    mov byte [si+DMA_MASK], 0
    mov dword [si+DMA_POSITION], 0
    pop dx
    pop bx
    pop ax
    ret

%endif

trap_ports:
%include "audio/ports.inc"
    dw 0
trapped_count dw 0
callback_set db 0
trap_remove_failed db 0
old_callback dd 0
port_calls dd 0
last_clock dd 0
game_start_pending db 0 ; 1: wait for mixing, 2: wait for output.
game_dma dw dma8
game_frame_shift db 0
game_source db 0
pending_frame_shift db 0
game_irq_bit db 1
game_block_bytes dd 4096
game_exit_frame dd 0
game_mix_frame dd 0
virtual_resets dw 0
virtual_starts dw 0
virtual_mixer_index db 0
sb_pcm_levels dd 164,2067,3276,5193,8230,13045,20675,32768
virtual_mixer:
    times 4 db 0
    db 0eeh
    times 251 db 0
dma8 db 0,1,0,0
    dw 0,0,0
    dd 0
    db 49h
dma16 db 0,1,0,0
    dw 0,0,0
    dd 0
    db 59h
dsp_command db 0
arguments db 0
block_low db 0
legacy_block dw 0
legacy_rate dw 22050
reply dw 0
reply_count db 0
%ifdef RESIDENT_AUDIO
callback_port dw 0
callback_value db 0
%endif
%ifdef WSS_INPUT
%include "audio/wss_state.inc"
%endif
