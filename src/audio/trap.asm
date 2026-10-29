; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%include "audio/diag.inc"
%include "audio/sb_state.inc"

trap_install:
    mov ax, 1a06h
    call far [qpi]
    jc .fail
    mov [old_callback], di
    mov [old_callback+2], es
    ; Do not replace an existing sound virtualizer.
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
; Stepping aside (audio_release): give back every trapped port but the
; keyboard's, which the hotkeys read; the callback stays installed.
; trap_engage traps them again. Both walk the list, not trapped_count, which
; stays the install's figure for trap_remove.
trap_release:
    mov si, trap_ports
.next:
    lodsw
    test ax, ax
    jz .done
%ifdef MDM_SUPPORT
    cmp ax, 60h
    je .next
%endif
    mov dx, ax
    mov ax, 1a0ah
    call far [qpi]
    jmp .next
.done:
    ret
trap_engage:
    mov si, trap_ports
.next:
    lodsw
    test ax, ax
    jz .done
%ifdef MDM_SUPPORT
    cmp ax, 60h
    je .next
%endif
    mov dx, ax
    mov ax, 1a09h
    call far [qpi]
    jc .fail
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
    FAULT_SET 5, 2
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
    mov eax, ebx
    shr eax, OUTPUT_SHIFT
    and ebx, PERIOD_FRAMES-1
    ; The first period at or after [periods] in the ring slot that plays.
    push ecx
    push eax
    mov eax, [periods]
    xor edx, edx
    mov ecx, RING_PERIODS
    div ecx
    pop eax
    pop ecx
    sub eax, edx
    jge .slot_ahead
    add eax, RING_PERIODS
.slot_ahead:
    add eax, [periods]
    shl eax, OUTPUT_SHIFT
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
    ; Half rate: one ring byte is one mixed word.
    cmp byte [ess_half], 0
    jne .count_ready
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

; AL: value of the selected virtual mixer register.
mixer_read:
    movzx bx, byte [virtual_mixer_index]
    ; Reserved on the SB16. Writable storage here causes false mixer detection.
    mov al, 0ffh
    cmp bx, 0fh
    je .done
%ifdef VIRTUAL_IRQ
    cmp bx, 82h
    jne .virtual_plain
    call virtual_mpu_refresh
    mov al, [virtual_dsp_irq]
    ret
.virtual_plain:
%endif
    mov al, [virtual_mixer+bx]
.done:
    ret

%ifdef RESIDENT_AUDIO
; The mixer can use more stack than a game leaves below its own stack pointer.
%macro callback_stack_enter 0
    cmp byte [cs:callback_depth], 0
    jne %%nested
    mov [cs:callback_ss], ss
    mov [cs:callback_sp], sp
%ifdef OWN_HOST
    mov ss, [cs:cold_segment]
    mov sp, COLD_CALLBACK_TOP
%else
    push cs
    pop ss
    mov sp, callback_stack_top
%endif
%%nested:
    inc byte [cs:callback_depth]
%endmacro
%endif

port_callback:
%ifdef RESIDENT_AUDIO
    cmp byte [cs:callback_set], 0
    jne .active
    stc
    retf
.active:
    callback_stack_enter
%endif
    pushad
    movzx ebp, sp
    push ds
    push es
    push fs
    push cs
    pop ds
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
%ifdef OWN_HOST
    call far [cs:mdm_scan_far]
%else
    call mdm_scan
%endif
    jmp .result
.keyboard_write:
    call physical_write
    jmp .done
.not_keyboard:
%endif
%ifdef WSS_INPUT
    push dx
    sub dx, [virtual_wss_base]
    cmp dx, 7
    pop dx
    jbe .wss_port
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
    cmp dx, 22ah
    je .done
    cmp dx, 224h
    je .mixer_index
    cmp dx, 225h
    je .mixer_data
    cmp dx, 0ch
    je .flip_reset
    cmp dx, 0eh
    je .clear_mask
    cmp dx, 0dh
    je .master_clear
    cmp dx, 0fh
    je .all_mask
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
    cmp dx, 8
    je .dma_command
    jmp .unsupported
.wide:
    mov bl, cl
    and bl, 1ch
    cmp bl, 8
    je .wide_read
    cmp bl, 0ch
    jne .unsupported
%ifdef VIRTUAL_IRQ
    ; Oscar writes the PIC command and mask with one word output.
    cmp dx, 20h
    jne .wide_sb
    push ax
    call virtual_pic_write
    pop ax
    mov al, ah
    inc dx
    call virtual_pic_write
    jmp .done
.wide_sb:
%endif
    mov bx, dx
    sub bx, [guest_base]
    cmp bx, 4
    jne .unsupported
    mov [virtual_mixer_index], al
    mov al, ah
    jmp .mixer_data
.wide_read:
    ; Hexen reads the mixer index and data ports with one word input.
    mov bx, dx
    sub bx, [guest_base]
    cmp bx, 4
    jne .unsupported
    call mixer_read
    mov ah, al
    mov al, [virtual_mixer_index]
    mov [ss:bp+28], ax
    jmp .done
.unsupported:
%ifdef MOUNTED_AUDIO
    FAULT_SET 4, 3
%else
    mov byte [fault], 1
%endif
    jmp .done
.reset:
    mov byte [silence_active], 0
    mov byte [sb_starved], 0
    mov byte [dma_pending_command], 0
    mov byte [sb_id_value], 0aah
    mov byte [sb_id_phase], 0
    mov byte [sb_dac_enabled], 0
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
    cmp bl, 0fh
    je .done
    cmp bl, 80h
    je .done
    cmp bl, 81h
    je .dma_select
    test bl, bl
    jz .mixer_reset
    mov [virtual_mixer+bx], al
    cmp bl, 0eh
    jne .mixer_volume
    and al, 20h
    mov [sb_filter_bypass], al
    jmp .done
.mixer_volume:
    cmp bl, 22h
    je .master_pair
    cmp bl, 26h
    je .fm_pair
    cmp bl, 28h
    je .cd_pair
    cmp bl, 4
    jne .volume16
    or byte [sb_pro_curve], 1
    mov bx, 32h
    jmp .volume_pair
.dma_select:
    mov [virtual_mixer+81h], al
    test al, 0e0h
    setz byte [sb_dma16_low]
    jmp .done
.master_pair:
    or byte [sb_pro_curve], 2
    mov bx, 30h
    jmp .volume_pair
.cd_pair:
    or byte [sb_pro_curve], 4
    mov bx, 36h
    jmp .volume_pair
.fm_pair:
    mov bx, 34h
.volume_pair:
    mov ah, al
    and al, 0f0h
    or al, 8
    mov [virtual_mixer+bx], al
    shl ah, 4
    or ah, 8
    mov [virtual_mixer+bx+1], ah
    jmp .volume_update
.volume16:
    cmp bl, 30h
    jb .done
    cmp bl, 37h
    ja .done
    ; The SB16 register of a channel ends its SB Pro curve.
    push bx
    sub bl, 30h
    shr bl, 1
    xor bh, bh
    mov al, [curve_bits+bx]
    not al
    and [sb_pro_curve], al
    pop bx
    and bl, 0feh
    mov al, [virtual_mixer+bx]
    and al, 0f0h
    mov ah, [virtual_mixer+bx+1]
    shr ah, 4
    or al, ah
    cmp bl, 30h
    jne .cd_view
    mov [virtual_mixer+22h], al
    jmp .volume_update
.cd_view:
    cmp bl, 36h
    jne .fm_view
    mov [virtual_mixer+28h], al
    jmp .volume_update
.fm_view:
    cmp bl, 34h
    jne .voice_view
    mov [virtual_mixer+26h], al
    jmp .volume_update
.voice_view:
    mov [virtual_mixer+4], al
.volume_update:
%ifdef MOUNTED_AUDIO
    call cd_gain_update
%endif
%ifdef RESIDENT_AUDIO
    call fm_update
%endif
.voice_gain:
    call sb_pcm_update
    jmp .done
.mixer_reset:
    ; Register 00h restores the SB16 defaults.
    push cs
    pop es
    mov di, virtual_mixer
    mov cx, 40h
    xor eax, eax
    cld
    rep stosw
    mov [sb_filter_bypass], al
    mov [sb_pro_curve], al
    mov al, 0cch
    mov [virtual_mixer+4], al
    mov [virtual_mixer+22h], al
    mov [virtual_mixer+26h], al
    mov [virtual_mixer+28h], al
    mov eax, 0c0c0c0c0h
    mov [virtual_mixer+30h], eax
    mov [virtual_mixer+34h], ax
    mov [virtual_mixer+36h], ax
    mov dword [virtual_mixer+3ch], 0b151fh
    mov dword [virtual_mixer+44h], 80808080h
    jmp .volume_update
.flip_reset:
    mov byte [si+DMA_FLIP], 0
.dma_command:
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
    jnz .mask_set
    mov byte [sb_starved], 0
.mask_set:
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
    and al, 0bch
    or al, 41h
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
    mov byte [sb_starved], 0
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
.master_clear:
    ; A master clear masks all channels. Keep the output channel running.
    mov byte [si+DMA_MASK], 4
    mov byte [si+DMA_FLIP], 0
    call dma_shared_write
    call dma_output_channel
    cmp ah, 0ffh
    je .done
    mov al, ah
    mov dx, 0ah
    call dma_shared_write
    jmp .done
.all_mask:
    mov bx, [guest_dma8]
    cmp si, dma8
    je .all_guest
    mov bx, [guest_dma16]
    sub bl, 4
.all_guest:
    mov cl, bl
    mov ah, 1
    shl ah, cl
    mov byte [si+DMA_MASK], 0
    test al, ah
    jnz .all_masked
    mov byte [sb_starved], 0
    jmp .all_output
.all_masked:
    mov byte [si+DMA_MASK], 4
.all_output:
    or al, ah
    call dma_output_channel
    cmp ah, 0ffh
    je .all_write
    mov cl, ah
    mov ah, 1
    shl ah, cl
    not ah
    and al, ah
.all_write:
    and al, 0fh
    call dma_shared_write
    jmp .done
.page:
    mov [si+DMA_PAGE], al
    jmp .done
.address:
    mov bx, DMA_ADDRESS
    jmp .dma_word
.count:
    mov bx, DMA_COUNT
.dma_word:
    mov byte [sb_starved], 0
    mov dword [si+DMA_POSITION], 0
    mov byte [si+3], 0
    cmp si, dma16
    je .tc_rearm16
    and byte [dma_tc_reported], 0feh
    jmp .tc_rearmed
.tc_rearm16:
    and byte [dma_tc_reported], 0fdh
.tc_rearmed:
    mov byte [sb_finished], 0
    movzx cx, byte [si+DMA_FLIP]
    add bx, cx
    mov [si+bx], al
    xor byte [si+DMA_FLIP], 1
%ifdef RESIDENT_AUDIO
    cmp bx, DMA_ADDRESS+1
    jne .done
    mov al, 1
    call sb_dma_switch
%endif
    jmp .done
.command:
    cmp byte [arguments], 0
    jne .argument
    mov [dsp_command], al
    cmp al, 10h
    je .time_constant
    cmp al, 41h
    je .rate
    cmp al, 42h
    je .input_rate
    cmp al, 40h
    je .time_constant
    cmp al, 48h
    je .rate
    cmp al, 14h
    je .rate
    cmp al, 24h
    je .rate
    cmp al, 80h
    je .rate
    cmp al, 1ch
    je .legacy_start
    cmp al, 90h
    je .legacy_start
    cmp al, 91h
    je .legacy_start
    cmp al, 0c0h
    je .play
    cmp al, 0c2h
    je .play
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
    cmp al, 0e2h
    je .time_constant
    cmp al, 0e8h
    je .test_read
    cmp al, 0f2h
    je .force_irq
    cmp al, 45h
    je .continue8
    cmp al, 47h
    je .continue16
    cmp al, 04h
    je .asp_one
    cmp al, 0fh
    je .asp_one
    ; Action Soccer sends music to the DSP MIDI output (38h). Drop the byte.
    cmp al, 38h
    je .asp_one
    cmp al, 05h
    je .asp_two
    cmp al, 0eh
    je .asp_two
    mov bl, 1
    mov ah, al
    and ah, 0feh
    cmp ah, 74h
    je .adpcm
    inc bl
    cmp ah, 76h
    je .adpcm
    inc bl
    cmp ah, 16h
    je .adpcm
    ; Ignition sends 00h after a start. The DSP ignores it.
    test al, al
    jz .done
    ; E7h is an ESS command. A DSP that does not know it takes it and stays silent.
    cmp al, 0e7h
    je .done
    cmp al, 0e1h
    jne .unsupported
    mov ax, [virtual_dsp_version]
    mov [reply], ax
    mov byte [reply_count], 2
    jmp .done
.asp_two:
    mov bl, 2
    jmp .asp
.asp_one:
    mov bl, 1
.asp:
    ; ASP commands (Tornado): an SB16 without ASP takes the arguments and does not reply.
    mov byte [dsp_command], 0
    mov [arguments], bl
    jmp .done
.continue8:
    cmp byte [game_irq_bit], 2
    je .done
    jmp .continue
.continue16:
    cmp byte [game_irq_bit], 2
    jne .done
.continue:
    ; 45h and 47h cancel an auto-init exit (DAh or D9h) before the block ends.
    cmp byte [sb_single], 0
    jne .done
    mov dword [game_exit_frame], 0
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
    ; The IRQ comes some guest instructions after this OUT, not during it.
    or byte [irq_due], 1
    mov byte [irq_due_calls], 2
%ifdef RESIDENT_AUDIO
    mov byte [irq_due_steps], IRQ_DUE_STEPS
%endif
%endif
    jmp .done
.resume8:
    cmp byte [game_irq_bit], 2
    je .done
    jmp .resume
.resume16:
    cmp byte [game_irq_bit], 2
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
    mov si, dma8
    call pending_stop
    cmp byte [game_irq_bit], 2
    je .done
    jmp .exit_block
.exit16:
    mov si, dma16
    call pending_stop
    cmp byte [game_irq_bit], 2
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
    cmp byte [game_irq_bit], 2
    je .done
    jmp .pause
.pause16:
    cmp byte [game_irq_bit], 2
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
.input_rate:
    ; The SB16 uses one sample rate for output and input.
    mov byte [dsp_command], 41h
.rate:
    mov byte [pending_adpcm], 0
.adpcm_rate:
    mov byte [arguments], 2
    jmp .done
.adpcm:
    ; Single-cycle ADPCM (Tornado) starts like 14h. Odd commands send a reference byte first.
    and al, 1
    ror al, 1
    or al, bl
    mov [pending_adpcm], al
    mov byte [dsp_command], 14h
    jmp .adpcm_rate
.play:
    mov byte [pending_adpcm], 0
    mov byte [dma_pending_command], 0
    ; Both FIFO modes use the same PCM conversion and block interrupts.
    or byte [dsp_command], 2
    mov byte [arguments], 3
    jmp .done
.time_constant:
    mov byte [arguments], 1
    jmp .done
.legacy_start:
    mov byte [pending_adpcm], 0
    mov byte [dma_pending_command], 0
    mov ax, [legacy_block]
.legacy_format:
    push ax
    mov byte [pending_frame_shift], 0
    mov byte [pending_format], 0
    cmp byte [dsp_command], 24h
    je .legacy_mono
    cmp byte [pending_adpcm], 0
    jne .legacy_mono
    test ax, ax
    jz .legacy_mono
    mov ax, [legacy_rate]
    test byte [virtual_mixer+0eh], 2
    jz .legacy_rate
    mov byte [pending_frame_shift], 1
    ; A 41h rate is per channel already.
    cmp byte [legacy_per_channel], 0
    jne .legacy_rate
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
    ; Command 0 drops the arguments of a rejected command.
    cmp byte [dsp_command], 0
    je .argument_done
    cmp byte [dsp_command], 10h
    jne .normal_argument
    call sb_dac_write
    jmp .argument_done
.normal_argument:
    cmp byte [dsp_command], 0e2h
    jne .invert_argument
    call sb_identify
    jc .argument_rejected
    jmp .argument_done
.invert_argument:
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
    cmp byte [dsp_command], 80h
    je .silence
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
    ; Hold the high byte until the rate is complete.
    mov [block_low], al
    jmp .argument_done
.rate_low:
    mov ah, [block_low]
    cmp ax, 4000
    jb .argument_rejected
    ; Games can request a little more than the documented 45000 Hz.
    cmp ax, 48000
    ja .argument_rejected
    ; On DSP 4, 41h also sets the rate of 14h, 1Ch, 90h and 91h.
    cmp byte [virtual_dsp_version], 4
    jb .set_rate
    mov [legacy_rate], ax
    mov byte [legacy_per_channel], 1
    ; Each time constant is valid, down to 3906 Hz.
.set_rate:
    mov [game_rate], ax
    movzx eax, ax
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
    mov byte [pending_format], 0
    cmp byte [dsp_command], 0b2h
    je .format16
    cmp byte [dsp_command], 0b6h
    jne .mono_mode
.format16:
    ; Team F1 sets reserved mode bits. The DSP ignores them.
    and al, 30h
    cmp al, 30h
    je .stereo16
    ; Unsigned and mono 16-bit data use auto-initialized DMA only.
    test byte [dsp_command], 4
    jz .argument_rejected
    test al, 10h
    jnz .signed16
    or byte [pending_format], 2
.signed16:
    test al, 20h
    jnz .stereo16
    or byte [pending_format], 1
    mov byte [pending_frame_shift], 1
    jmp .argument_done
.stereo16:
    mov byte [pending_frame_shift], 2
    jmp .argument_done
.mono_mode:
    and al, 30h
    cmp al, 20h
    jne .mono
    mov byte [pending_frame_shift], 1
    jmp .argument_done
.mono:
    test al, al
    jnz .argument_rejected
    jmp .argument_done
.set_time_constant:
    movzx ecx, al
    neg ecx
    add ecx, 256
    mov eax, 1000000
    xor edx, edx
    div ecx
    ; IRQ probes use time constants above the playback range.
    cmp eax, 48000
    jbe .time_limit
    mov eax, 48000
.time_limit:
    mov [legacy_rate], ax
    mov byte [legacy_per_channel], 0
    test byte [virtual_mixer+0eh], 2
    jz .time_mono
    shr ax, 1
.time_mono:
    jmp .set_rate
.legacy_length:
    cmp byte [arguments], 2
    jne .legacy_high
    mov [legacy_block], al
    jmp .argument_done
.legacy_high:
    mov [legacy_block+1], al
    jmp .argument_done
.silence:
    ; The Varginha Incident waits for the IRQ after a silence block.
    cmp byte [arguments], 2
    je .length
    mov ah, al
    mov al, [block_low]
    movzx eax, ax
    inc eax
    mov ecx, OUTPUT_RATE
    mul ecx
    movzx ecx, word [legacy_rate]
    div ecx
    shr eax, OUTPUT_SHIFT
    inc eax
    add eax, [periods]
    mov [silence_deadline], eax
    mov byte [silence_active], 1
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
    je .legacy_format
    ; DSP 4 starts 1Ch with the length of the last Cxh command (Necromantics).
    cmp byte [dsp_command], 0c0h
    jb .validate_start
    mov [legacy_block], ax
.validate_start:
    mov byte [pending_short], 0
    mov byte [sb_starved], 0
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
    cmp byte [dsp_command], 0c2h
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
    je .wide_dma
    test byte [pending_format], 1
    jz .dma_selected
.wide_dma:
    mov cl, 1
    cmp byte [sb_dma16_low], 0
    jne .dma_selected
    mov si, dma16
.dma_selected:
    cmp byte [si+DMA_MASK], 0
    je .dma_ready
    ; Panic Soldier sends 90h before it unmasks the channel.
    cmp byte [arguments], 1
    ja .dma_ready
    mov [dma_pending_count], ax
    mov [dma_pending_state], si
    mov al, [dsp_command]
    mov [dma_pending_command], al
    mov byte [game_active], 0
    cmp byte [arguments], 0
    je .done
    jmp .argument_done
.dma_ready:
    cmp byte [sb_input], 0
    je .direction_ready
    mov bl, [si+DMA_MODE]
    and bl, 0efh
    cmp bl, 45h
    jne .argument_rejected
.direction_ready:
.block_length:
    movzx edx, ax
    inc edx
    shl edx, cl
.validate_dma:
    cmp byte [sb_single], 1
    je .single_buffer
    movzx ebx, word [si+DMA_COUNT]
    inc ebx
    cmp si, dma16
    jne .buffer_units
    shl ebx, 1
.buffer_units:
    cmp edx, 512
    jae .large_block
    ; Detection code loops one short block over the buffer, or a longer block (MadSpace).
    cmp edx, ebx
    jb .short_block
    mov cl, [pending_frame_shift]
    mov eax, 1
    shl eax, cl
    dec eax
    test edx, eax
    jnz .argument_rejected
    jmp .buffer_address
.short_block:
    ; A short block must last one output period.
    mov cl, [pending_frame_shift]
    mov eax, edx
    shr eax, cl
    imul eax, OUTPUT_RATE
    movzx ecx, word [game_rate]
    imul ecx, PERIOD_FRAMES
    cmp eax, ecx
    jae .buffer_size
    ; Alien Terminator loops 16-byte blocks in a 32-byte buffer. It gets one
    ; IRQ per output period and does not need the free-space rule.
    mov byte [pending_short], 1
    ; The Incredible Machine 2 loops two short blocks in a 288-byte buffer.
    jmp .buffer_size
.large_block:
    cmp ebx, 512
    jb .argument_rejected
.buffer_size:
    ; The mixer uses 16-bit buffer offsets (Team F1: 61440 bytes).
    cmp ebx, 65536
    ja .argument_rejected
    mov cl, [pending_frame_shift]
    mov eax, ebx
    shr eax, cl
    cmp eax, 65535
    ja .argument_rejected
    mov eax, 1
    shl eax, cl
    dec eax
    test ebx, eax
    jnz .argument_rejected
    cmp edx, ebx
    je .buffer_address
%ifdef WSS_INPUT
    cmp byte [game_source], 1
    je .buffer_address
%endif
    cmp byte [pending_short], 0
    jne .buffer_address
    mov eax, ebx
    sub eax, edx
    jae .free_bytes
    ; A block longer than the buffer: the game polls the DMA position.
    mov eax, ebx
.free_bytes:
    mov cl, [pending_frame_shift]
    shr eax, cl
    imul eax, OUTPUT_RATE
    movzx ecx, word [game_rate]
    imul ecx, PERIOD_FRAMES
    cmp eax, ecx
    jb .argument_rejected
    jmp .buffer_address
.single_buffer:
    movzx ebx, word [si+DMA_COUNT]
    inc ebx
    cmp si, dma16
    jne .single_size
    shl ebx, 1
    cmp ebx, 65536
    ja .argument_rejected
.single_size:
    test byte [si+DMA_MODE], 10h
    jnz .buffer_address
    mov eax, [si+DMA_POSITION]
    cmp si, dma16
    jne .single_position
    shl eax, 1
.single_position:
    cmp eax, ebx
    ja .argument_rejected
    neg eax
    add eax, ebx
    test eax, eax
    jz .argument_rejected
    cmp edx, eax
    jbe .buffer_address
    ; The 8237 ends at terminal count: the DSP waits for the missing bytes and
    ; sends no IRQ (Pinball Wizard 2000).
    mov edx, eax
    mov byte [sb_starved], 1
.buffer_address:
    mov byte [game_page_wrap], 0
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
    push eax
    push ecx
    push ebx
    call dma_source_split
    mov [pending_source_segment], cx
    mov [pending_source_offset], bx
    pop ebx
    pop ecx
    pop eax
    cmp si, dma16
    je .word_window
    ; An 8-bit block past the end of the 64 KiB page wraps to the page start
    ; (Big Red Adventure), as the DMA address counter does.
    cmp eax, 65536
    jbe .address_limit
    mov byte [game_page_wrap], 1
    jmp .linear_limit
.word_window:
    cmp eax, 131072
    ja .argument_rejected
.address_limit:
    mov eax, ecx
    and eax, 15
    add eax, ebx
    cmp eax, 65536
    ja .argument_rejected
.linear_limit:
    mov eax, ecx
    add eax, ebx
    cmp byte [game_page_wrap], 0
    je .end_ready
    mov eax, ecx
    or ax, 0ffffh
    inc eax
.end_ready:
    ; The mixer reads the game's view of memory, so a buffer in a UMB
    ; (Jurassic Park) needs no physical copy.
    cmp eax, 100000h
%ifdef OWN_HOST
    jbe .low_source
    cmp byte [host_backend], 1
    jne .argument_rejected
    cmp ecx, 100000h
    jb .argument_rejected
    cmp eax, 1000000h
    ja .argument_rejected
    cmp byte [sb_input], 0
    jne .argument_rejected
    ; Source offsets include game_offset.
    mov eax, ecx
    and al, 0f0h
    cmp byte [game_page_wrap], 0
    je .physical_ready
    and eax, 0ffff0000h
.physical_ready:
    mov [game_physical], eax
    jmp .source_ready
.low_source:
    mov dword [game_physical], 0
.source_ready:
%else
    ja .argument_rejected
%endif
    mov [game_dma], si
    mov esi, ecx
    mov [game_block_bytes], edx
    call adpcm_start
    mov cl, [pending_frame_shift]
    mov [game_frame_shift], cl
    mov al, [pending_format]
    mov [game_format], al
    mov al, 1
    mov ah, [dsp_command]
    and ah, 0f0h
    cmp ah, 0b0h
    je .wide_irq
    cmp word [game_dma], dma16
    jne .irq_bit
.wide_irq:
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
    shl eax, 16
    mov [game_origin], eax
.origin_ready:
    shr ebx, cl
    ; A buffer shorter than one frame still wraps at one frame.
    test ebx, ebx
    jnz .limit_frames
    inc ebx
.limit_frames:
    shl ebx, 16
    mov [game_limit], ebx
    cmp byte [sb_single], 0
    je .ring_ready
    cmp byte [pending_frame_shift], 0
    je .ring_ready
    mov dword [game_limit], 0
.ring_ready:
    cmp byte [game_adpcm], 0
    je .pcm_ring
    ; ADPCM sample positions count from the block start.
    mov dword [game_origin], 0
    mov dword [game_limit], 0
.pcm_ring:
    mov byte [sb_dac_enabled], 0
    mov ax, [pending_source_offset]
    mov [game_offset], ax
    mov ax, [pending_source_segment]
    mov [game_segment], ax
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
    xor eax, eax
    mov [sb_filter_state], eax
    mov [sb_filter_state+4], eax
    mov [sb_filter_state+8], eax
    mov [sb_filter_state+12], eax
    mov [sb_tail_mode], al
    mov [sb_tail_valid], al
    mov [sb_tail_consumed], eax
%ifdef VIRTUAL_IRQ
    call virtual_irq_reset
%endif
    mov bl, [game_active]
    mov byte [game_active], 1
    inc word [virtual_starts]
%ifdef RESIDENT_AUDIO
    ; The game must run before a block that starts a stream can end.
    mov dword [sb_hold_until], 0
    cmp byte [sb_single], 0
    je .hold_ready
    cmp byte [sb_patch_available], 1
    je .hold_ready
    mov dword [sb_hold_until], 1
%ifdef VIRTUAL_IRQ
    ; A block of one or two bytes ends some instructions after this write.
    cmp dword [game_block_bytes], 2
    ja .hold_ready
    or byte [irq_due], 2
    mov byte [irq_due_calls], 2
    mov byte [irq_due_steps], IRQ_DUE_STEPS
%endif
.hold_ready:
    test bl, bl
    jnz .patch
    call sb_patch_initial
.patch:
    call sb_patch
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
    jmp .argument_done
.argument_rejected:
    ; The DSP takes the byte; drop the remaining arguments.
    cmp byte [arguments], 0
    je .unsupported
    mov byte [dsp_command], 0
    dec byte [arguments]
    jmp .unsupported
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
    mov al, [virtual_mixer_index]
    cmp dx, 224h
    je .result
    cmp dx, 3
    je .dma_read
    cmp dx, 2
    je .dma_read
    cmp dx, 0bh
    je .dma_physical_read
    cmp dx, 0dh
    je .dma_physical_read
    cmp dx, 0fh
    je .dma_physical_read
    cmp dx, 8
    je .dma_status
    cmp dx, 83h
    jne .unsupported
    mov al, [si+DMA_PAGE]
    jmp .result
.dma_physical_read:
    cmp si, dma16
    jne .dma_mode_physical
    sub dx, 0ah
    shl dx, 1
    add dx, 0d4h
.dma_mode_physical:
    call physical_read
    jmp .result
.dma_status:
    ; Earth 2140 waits for the request of a DSP transfer on a masked channel.
    mov bx, [guest_dma8]
    cmp si, dma16
    jne .dma_status_read
    mov dl, 0d0h
    mov bx, [guest_dma16]
    sub bl, 4
.dma_status_read:
    call physical_read
    mov cl, bl
    mov bl, 11h
    shl bl, cl
    not bl
    and al, bl
    mov bl, 1
    shl bl, cl
    ; A status read clears the terminal count.
    cmp byte [si+3], 0
    je .dma_request
    mov ah, 1
    cmp si, dma16
    jne .tc_bit
    mov ah, 2
.tc_bit:
    test [dma_tc_reported], ah
    jnz .dma_request
    or [dma_tc_reported], ah
    or al, bl
.dma_request:
    cmp byte [dma_pending_command], 0
    je .result
    cmp si, [dma_pending_state]
    jne .result
    shl bl, 4
    or al, bl
    jmp .result
.reset_read:
    mov al, 0ffh
    jmp .result
.ready:
    ; Some games wait in a loop until they see one busy status.
    xor al, al
    inc byte [dsp_status_reads]
    test byte [dsp_status_reads], 7
    jnz .result
    mov al, 80h
    jmp .result
.status:
%ifdef VIRTUAL_IRQ
    mov ah, 0feh
    call virtual_dsp_ack
%endif
    xor al, al
    cmp byte [reply_count], 0
    je .result
    mov al, 80h
    jmp .result
.status16:
%ifdef VIRTUAL_IRQ
    mov ah, 0fdh
    call virtual_dsp_ack
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
    call mixer_read
    jmp .result
.dma_read:
    cmp byte [si+DMA_FLIP], 0
    jne .count_high
    push dx
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
    cmp byte [game_adpcm], 0
    je .count_pcm
    movzx ecx, byte [adpcm_per]
    xor edx, edx
    div ecx
    test byte [game_adpcm], 80h
    jz .count_pcm
    inc eax
.count_pcm:
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
    ; The position moves one period at a time, so after each lap it rests on
    ; the first unit of the buffer until the next period is mixed. A mixer
    ; that follows the position takes what lies behind it as played and
    ; clears frames that are not mixed yet. Report the last unit of the lap
    ; before.
    test dx, dx
    jnz .lap_ready
    test eax, eax
    jz .lap_ready
    cmp byte [sb_single], 0
    jne .lap_ready
%ifdef VIRTUAL_IRQ
    ; Not while the block-end interrupt is pending: the game's handler reads
    ; the count to find the half that ended (Assault Rigs).
    test byte [virtual_dsp_irq], 3
    jnz .lap_ready
%endif
    mov dx, cx
    dec dx
.lap_ready:
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
    sub bx, [si+DMA_POSITION]
    cmp byte [si+3], 0
    je .snapshot
    mov bx, 0ffffh
.snapshot:
    mov [si+DMA_SNAPSHOT], bx
    pop dx
.dma_value:
    cmp dx, 3
    je .count_value
    ; The current address is the start address plus the transferred units.
    mov ax, [si+DMA_ADDRESS]
    add ax, [si+DMA_COUNT]
    sub ax, bx
    mov bx, ax
.count_value:
    mov al, bl
    cmp byte [si+DMA_FLIP], 0
    je .count_result
    mov al, bh
    jmp .count_result
.count_high:
    mov bx, [si+DMA_SNAPSHOT]
    jmp .dma_value
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
    mov [ss:bp+28], al
.done:
%ifdef VIRTUAL_IRQ
    cmp byte [irq_due_calls], 0
    je .force_ready
    ; While the steps run, an access does not fire the event early. The
    ; steps or the next tick fire it.
%ifdef RESIDENT_AUDIO
    cmp byte [irq_step_left], 0
    jne .force_ready
%endif
    dec byte [irq_due_calls]
    jnz .force_ready
    DIAG_INC diag_due_access
    call virtual_irq_due_fire
.force_ready:
%endif
    cmp byte [dma_pending_command], 0
    je .pending_done
    cmp byte [arguments], 0
    jne .pending_done
    mov si, [dma_pending_state]
    cmp byte [si+DMA_MASK], 0
    jne .pending_done
    mov ax, [dma_pending_count]
    mov bl, [dma_pending_command]
    mov [dsp_command], bl
    mov byte [arguments], 1
    cmp bl, 1ch
    je .pending_legacy
    cmp bl, 90h
    je .pending_legacy
    cmp bl, 91h
    jne .pending_start
.pending_legacy:
    mov byte [arguments], 0
.pending_start:
    mov byte [dma_pending_command], 0
    jmp .validate_start
.pending_done:
%ifdef RESIDENT_AUDIO
    ; Time the hold from the end of the write that started the block, on
    ; both entries.
    cmp dword [sb_hold_until], 1
    jne .hold_timed
    call output_clock
    ; A block of one or two bytes ends the hold at its own end.
    mov ecx, SB_HOLD_FRAMES
    cmp dword [game_block_bytes], 2
    ja .hold_short
    mov ecx, [game_exit_frame]
.hold_short:
    add eax, ecx
    mov [sb_hold_until], eax
.hold_timed:
%endif
    pop fs
    pop es
    pop ds
    popad
%ifdef RESIDENT_AUDIO
    dec byte [cs:callback_depth]
    jnz .stack_ready
    mov ss, [cs:callback_ss]
    mov sp, [cs:callback_sp]
.stack_ready:
%endif
    clc
    retf
%ifdef LAYOUT_PAD
    times LAYOUT_PAD nop
%endif

sb_identify:
    movzx bx, byte [sb_id_phase]
    xor al, [.masks+bx]
    add [sb_id_value], al
    inc bl
    and bl, 3
    mov [sb_id_phase], bl
    mov si, dma8
    cmp byte [si+DMA_MASK], 0
    jne .reply
    cmp byte [si+3], 0
    jne .reply
    mov al, [si+DMA_MODE]
    and al, 0ch
    cmp al, 4
    jne .reply
    cmp byte [game_active], 0
    jne .failed
    cmp byte [si+DMA_PAGE], 10h
    jae .failed
    movzx ax, byte [si+DMA_PAGE]
    shl ax, 12
    mov es, ax
    mov bx, [si+DMA_ADDRESS]
    mov di, [si+DMA_POSITION]
    test byte [si+DMA_MODE], 20h
    jz .forward
    sub bx, di
    jmp .store
.forward:
    add bx, di
.store:
    mov al, [sb_id_value]
    mov [es:bx], al
    inc dword [si+DMA_POSITION]
    movzx eax, word [si+DMA_COUNT]
    cmp [si+DMA_POSITION], eax
    jbe .done
    test byte [si+DMA_MODE], 10h
    jz .terminal
    mov dword [si+DMA_POSITION], 0
    jmp .done
.terminal:
    mov byte [si+3], 1
    jmp .done
.reply:
    mov al, [sb_id_value]
    mov [reply], al
    mov byte [reply_count], 1
.done:
    clc
    ret
.failed:
    stc
    ret
.masks db 96h,0a5h,69h,5ah

; EDX: compressed block bytes. Converts the block length to samples.
adpcm_start:
    mov al, [pending_adpcm]
    mov [game_adpcm], al
    test al, al
    jz .done
    mov [adpcm_bytes], edx
    push bx
    mov bl, al
    and bx, 3
    imul bx, 7
    mov eax, [adpcm_params+bx-7]
    mov [adpcm_bits], eax
    mov eax, [adpcm_params+bx-4]
    mov [adpcm_up], eax
    pop bx
    mov di, [game_dma]
    mov ax, [di+DMA_POSITION]
    mov [adpcm_src], ax
    mov word [adpcm_next], 0
    mov byte [adpcm_left], 0
    mov al, [game_adpcm]
    shr al, 7
    mov [adpcm_ref], al
    movzx eax, al
    sub edx, eax
    movzx eax, byte [adpcm_per]
    imul edx, eax
    test edx, edx
    jnz .samples
    inc edx
.samples:
    mov [game_block_bytes], edx
.done:
    ret

; An exit command stops a transfer that waits for unmask.
pending_stop:
    cmp si, [dma_pending_state]
    jne .done
    mov byte [dma_pending_command], 0
.done:
    ret

; AL bits 0-1: channel. The output channel stays as it is.
dma_unowned_write:
    call dma_output_channel
    cmp ah, 0ffh
    je dma_shared_write
    xor ah, al
    test ah, 3
    jnz dma_shared_write
    ret

; SI: controller. AH: the output channel on it, or 0FFh.
dma_output_channel:
    mov ah, 0ffh
%ifdef RESIDENT_AUDIO
    cmp byte [sb_running], 0
    je .done
    cmp byte [sound_card], 0
    je .high_output
    cmp si, dma8
    jne .done
    mov ah, [sb_dma8]
    ret
.high_output:
    cmp si, dma16
    jne .done
    mov ah, [sb_dma16]
    sub ah, 4
%endif
.done:
    ret

%include "audio/direct_write.asm"

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
    cmp dx, 0d0h
    je .status
    cmp dx, 0d4h
    jb .done
    cmp dx, 0deh
    ja .done
    test dl, 1
    jnz .done
    sub dx, 0c0h
    shr dx, 1
    jmp .high
.low_page:
    mov dx, 83h
    ret
.status:
    mov dx, 8
    jmp .high
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

trap_ports:
%include "audio/ports.inc"
    dw 0
; ECX=linear DMA start, EBX=buffer bytes, SI=channel. Returns CX=segment,
; BX=offset of the mixer source. An 8-bit buffer past the end of its 64 KiB
; page gets the page as segment: the 16-bit offset then wraps like the DMA
; address counter.
dma_source_split:
    mov bx, cx
    cmp si, dma16
    je .linear
    movzx eax, cx
    add eax, ebx
    cmp eax, 65536
    jbe .linear
    shr ecx, 16
    shl cx, 12
    ret
.linear:
    and bx, 15
    shr ecx, 4
    ret

trapped_count dw 0
callback_set db 0
trap_remove_failed db 0
old_callback dd 0
port_calls dd 0
last_clock dd 0
game_page_wrap db 0
pending_source_segment dw 0
pending_source_offset dw 0
game_start_pending db 0 ; 1: wait for mixing, 2: wait for output.
dma_pending_command db 0
dma_pending_count dw 0
dma_pending_state dw 0
silence_active db 0
dma_tc_reported db 0
silence_deadline dd 0
game_dma dw dma8
game_frame_shift db 0
game_source db 0
pending_frame_shift db 0
game_irq_bit db 1
; Bit 0: 16-bit mono. Bit 1: unsigned 16-bit.
game_format db 0
pending_format db 0
; ADPCM type (1: 4-bit, 2: 2.6-bit, 3: 2-bit). Bit 7: reference byte.
pending_adpcm db 0
game_adpcm db 0
adpcm_bytes dd 0
; Bits, samples per byte, magnitude mask, step-up magnitude, top level, map.
adpcm_params:
    db 4, 2, 7, 5, 3
    dw adpcm_map4
    db 3, 3, 3, 3, 4
    dw adpcm_map3
    db 2, 4, 1, 1, 5
    dw adpcm_map2
adpcm_bits db 0
adpcm_per db 0
adpcm_mask db 0
adpcm_up db 0
adpcm_top db 0
adpcm_map dw 0
adpcm_src dw 0
adpcm_next dw 0
adpcm_left db 0
adpcm_ref db 0
adpcm_byte db 0
adpcm_level db 0
adpcm_value db 128
adpcm_prev db 128
; Step sizes per level and magnitude.
adpcm_map4 db 0,1,2,3,4,5,6,7, 1,3,5,7,9,11,13,15, 2,6,10,14,18,22,26,30, 4,12,20,28,36,44,52,60
adpcm_map3 db 0,1,2,3, 1,3,5,7, 2,6,10,14, 4,12,20,28, 5,15,25,35
adpcm_map2 db 0,1, 1,3, 2,6, 4,12, 8,24, 16,48
pending_short db 0
game_block_bytes dd 4096
game_exit_frame dd 0
game_mix_frame dd 0
virtual_resets dw 0
virtual_starts dw 0
virtual_mixer_index db 0
%include "audio/mixer.asm"
virtual_mixer:
    times 4 db 0
    db 0ffh
    times 22h-5 db 0
    db 0ffh
    times 26h-23h db 0
    db 0ffh
    db 0
    db 0ffh
    times 30h-29h db 0
    times 8 db 0f8h
    times 256-38h db 0
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
curve_bits db 2, 1, 0, 4
legacy_per_channel db 0
sb_starved db 0
reply dw 0
reply_count db 0
dsp_status_reads db 0
sb_id_value db 0aah
sb_id_phase db 0
%ifdef RESIDENT_AUDIO
callback_port dw 0
callback_value db 0
callback_ss dw 0
callback_sp dw 0
callback_depth db 0
%ifndef OWN_HOST
    align 4
times 512 db 0
callback_stack_top:
%endif
%endif
%ifdef WSS_INPUT
%include "audio/wss_state.inc"
%endif
