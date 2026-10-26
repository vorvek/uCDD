; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%include "audio/sb_state.inc"
%include "audio/diag.inc"

; One virtual, edge-triggered master-PIC input.
virtual_irq_init:
    mov dx, 21h
    call physical_read
    mov [virtual_pic_mask], al
    mov [physical_pic_initial], al
    mov cl, [sb_irq]
    mov al, 1
    shl al, cl
    mov [physical_irq_bit], al
    or al, [guest_irq_bit]
    not al
    mov [pic_visible_bits], al
    ret

virtual_irq_reset:
    call virtual_mpu_refresh
    mov byte [irq_due], 0
    mov byte [irq_due_calls], 0
    push ax
    call virtual_pic_late_mask
    pop ax
    ; The MPU-401's request (bit 2) is not the DSP's to clear.
    and byte [virtual_dsp_irq], 4
    jnz .mpu_held
    mov byte [virtual_pic_request], 0
.mpu_held:
    mov byte [virtual_pic_taken], 0
    mov dword [virtual_block_seen], 0
    ret

; AH: DSP interrupt bits to keep. A request without a DSP interrupt is stale,
; unless the host took it. The output IRQ must not run in between.
virtual_dsp_ack:
    call virtual_mpu_refresh
    pushf
    cli
    and [virtual_dsp_irq], ah
    jnz .done
    cmp byte [virtual_pic_taken], 0
    jne .done
    mov byte [virtual_pic_request], 0
    push ax
    call virtual_pic_late_mask
    pop ax
.done:
    popf
    ret

; A delayed interrupt of a command: bit 0 the F2h interrupt, bit 1 the end of
; a short single-cycle block. The registers stay.
virtual_irq_due_fire:
    pushad
    push es
    mov al, [irq_due]
    mov byte [irq_due], 0
    mov byte [irq_due_calls], 0
    test al, 1
    jz .block
    push ax
    call virtual_force_raise
    pop ax
.block:
%ifdef RESIDENT_AUDIO
    test al, 2
    jz .done
    cmp dword [sb_hold_until], 0
    je .done
    mov dword [sb_hold_until], 0
    call virtual_irq_tick
.done:
%endif
    pop es
    popad
    ret

%ifdef RESIDENT_AUDIO
%ifdef OWN_HOST
; From the protected host, which has counted the steps.
virtual_irq_due_far:
    push ds
    push cs
    pop ds
    cmp byte [audio_irq_busy], 0
    jne .leave
    cmp byte [callback_depth], 0
    jne .leave
    mov [callback_ss], ss
    mov [callback_sp], sp
    push cs
    pop ss
    mov sp, callback_stack_top
    inc byte [callback_depth]
    DIAG_INC diag_due_step
    call virtual_irq_due_fire
    dec byte [callback_depth]
    mov ss, [callback_ss]
    mov sp, [callback_sp]
.leave:
    pop ds
    retf
%endif
%endif

; The F2h interrupt of the DSP.
virtual_force_raise:
    or byte [virtual_dsp_irq], 1
virtual_request_raise:
    DIAG_INC diag_raised
    mov al, [guest_irq_bit]
    mov [virtual_pic_request], al
    ret

virtual_irq_tick:
    call virtual_mpu_refresh
    ; A delayed interrupt that no access and no step has fired yet.
    cmp byte [irq_due_calls], 0
    je .force_done
    DIAG_INC diag_due_tick
    call virtual_irq_due_fire
.force_done:
    cmp byte [silence_active], 0
    je .silence_done
    mov eax, [periods]
    sub eax, [silence_deadline]
    js .silence_done
    mov byte [silence_active], 0
    or byte [virtual_dsp_irq], 1
    call virtual_request_raise
.silence_done:
    cmp byte [game_active], 0
    je .done
    mov si, [game_dma]
    cmp byte [si+DMA_MASK], 0
    jne .done
    call game_elapsed
%ifdef RESIDENT_AUDIO
    cmp byte [sb_single], 0
    je .elapsed_ready
    cmp byte [game_start_pending], 1
    je .done
    mov eax, [game_mix_frame]
.elapsed_ready:
%endif
    cmp dword [game_exit_frame], 0
    je .position
    cmp eax, [game_exit_frame]
    jb .position
%ifdef RESIDENT_AUDIO
    cmp byte [sb_single], 0
    je .no_patch
    add eax, [game_started]
    mov [sb_patch_limit], eax
    mov eax, [game_exit_frame]
    add eax, [game_started]
    mov [sb_patch_clock], eax
    mov byte [sb_patch_available], 1
.no_patch:
%endif
    mov eax, [game_exit_frame]
    mov byte [game_active], 0
    cmp byte [sb_single], 0
    je .position
    mov eax, [game_block_bytes]
    cmp byte [game_adpcm], 0
    je .pcm_units
    mov eax, [adpcm_bytes]
.pcm_units:
    cmp si, dma16
    jne .single_units
    shr eax, 1
.single_units:
    add eax, [si+DMA_POSITION]
    movzx ecx, word [si+DMA_COUNT]
    inc ecx
    test byte [si+DMA_MODE], 10h
    jz .single_position
    xor edx, edx
    div ecx
    mov eax, edx
.single_position:
    mov [si+DMA_POSITION], eax
    mov bx, [si+DMA_COUNT]
    sub bx, ax
    mov [si+DMA_SNAPSHOT], bx
    cmp bx, 0ffffh
    jne .single_done
    mov byte [si+3], 1
.single_done:
    mov byte [sb_finished], 1
    mov eax, [game_block_bytes]
    jmp .byte_position
.position:
    cmp byte [sb_tail_mode], 0
    je .render_position
    mov eax, [sb_tail_consumed]
    jmp .byte_position
.render_position:
    movzx ecx, word [game_rate]
    mul ecx
    mov ecx, OUTPUT_RATE
    div ecx
    mov cl, [game_frame_shift]
    shl eax, cl
%ifdef WSS_INPUT
    cmp byte [game_source], 1
    jne .block_position
    sub eax, [wss_block_origin]
.block_position:
%endif
.byte_position:
    xor edx, edx
    mov ecx, [game_block_bytes]
    div ecx
    cmp eax, [virtual_block_seen]
    je .done
    mov [virtual_block_seen], eax
%ifdef WSS_INPUT
    cmp byte [game_source], 1
    jne .sb
    test byte [wss_status], 1
    jnz .done
    or byte [wss_status], 1
    call wss_hold
    test byte [wss_registers+10], 2
    jz .done
    mov ax, [wss_guest_irq]
    mov [wss_irq_event], ax
    ret
.sb:
%endif
    cmp byte [sb_starved], 0
    jne .done
    test byte [virtual_dsp_irq], 3
    jnz .overrun
    ; The block's bit joins the MPU-401's bit 2 at 82h. A request that is
    ; pending already stays one; one the game has ended is raised again.
    mov al, [game_irq_bit]
    or [virtual_dsp_irq], al
    jmp virtual_request_raise
.done:
    ret
; A block ended and the game had not acknowledged the last interrupt.
.overrun:
    DIAG_INC diag_overrun
    ret

; From audio_irq: the card's MPU-401 requested an interrupt. The virtual SB16
; shows it at 82h bit 2 on its line. The other models have no MPU-401 there.
; An interrupt at the 8259 is a new edge, so the game has read 330h since.
virtual_mpu_raise:
    cmp byte [virtual_model], 0
    jne .done
    ; One request per MPU-401 interrupt: virtual_mpu_refresh clears the bit
    ; when the card's request ends.
    test byte [virtual_dsp_irq], 4
    jnz .done
    test byte [virtual_dsp_irq], 3
    jnz .held
    mov byte [virtual_dsp_irq], 4
    jmp virtual_request_raise
.done:
    ret
.held:
    or byte [virtual_dsp_irq], 4
    ret

; Bit 2 of virtual_dsp_irq follows the card's 82h bit 2. The game ends the
; request with a read of 330h, which the driver does not see. Every register
; is kept.
virtual_mpu_refresh:
    test byte [virtual_dsp_irq], 4
    jnz .look
    ret
.look:
    push ax
    push dx
    pushf
    cli
    call card_irq_status
    test al, 4
    jnz .done
    and byte [virtual_dsp_irq], 0fbh
.done:
    popf
    pop dx
    pop ax
    ret

virtual_irq_take:
    push ds
    push bx
    push cx
    push dx
    push cs
    pop ds
    xor bx, bx
    mov al, [guest_irq_bit]
    test [virtual_pic_mask], al
    jnz .done
    mov al, [virtual_pic_service]
    or al, [virtual_pic_taken]
    jnz .done
    cmp byte [virtual_pic_request], 0
    je .done
    call physical_pic_isr
%ifdef OWN_HOST
    call virtual_pic_host_service
    and al, ah
%endif
    test al, [guest_irq_priority]
    jnz .done
    ; The IRQ stays a request until the host or the real chain delivers it.
    mov al, [guest_irq_bit]
    mov [virtual_pic_taken], al
    call virtual_pic_late_mask
    DIAG_INC diag_taken
%ifndef OWN_HOST
    call virtual_irq_deliver
%endif
    inc bx
.done:
    mov ax, bx
    pop dx
    pop cx
    pop bx
    pop ds
    retf

; The handler runs now: the IRQ is in service, like an INTA on a real PIC.
virtual_irq_deliver:
    mov al, [virtual_pic_taken]
    test al, al
    jz .done
    mov byte [virtual_pic_taken], 0
    mov byte [virtual_pic_request], 0
    mov [virtual_pic_service], al
.done:
    ret

; The handler of an F2h interrupt is on its way: the mask write that came
; after the interrupt takes effect now.
virtual_pic_late_mask:
    mov al, [pic_mask_late]
    or [virtual_pic_mask], al
    mov byte [pic_mask_late], 0
    ret

physical_pic_isr:
    mov dx, 20h
    mov al, 0bh
    call physical_write
    call physical_read
    push ax
    mov al, [physical_pic_read]
    call physical_write
    pop ax
    ret

virtual_pic_read:
    cmp dx, 21h
    je .read
    mov al, [physical_pic_read]
    call physical_write
.read:
    call physical_read
    cmp dx, 21h
    je .mask
    and al, [pic_visible_bits]
    cmp byte [physical_pic_read], 0bh
    je .service
    or al, [virtual_pic_request]
    ret
.service:
    or al, [virtual_pic_service]
%ifdef OWN_HOST
    call virtual_pic_host_service
%endif
    ret
.mask:
    and al, [pic_visible_bits]
%ifdef RESIDENT_AUDIO
    cmp byte [cd_refill_masked], 0
    je .mask_shown
    and al, 0fdh
    mov ah, [cd_refill_old_mask]
    and ah, 2
    or al, ah
.mask_shown:
%endif
    mov ah, [pic_visible_bits]
    not ah
    and ah, [virtual_pic_mask]
    or al, ah
    or al, [pic_mask_late]
    ret

virtual_pic_write:
    ; ICW2-ICW4 follow ICW1 on the data port (pMAX under VCPI).
    cmp dx, 21h
    jne .command
    cmp byte [pic_init_words], 0
    je .mask
    dec byte [pic_init_words]
    jmp .physical
.command:
    test al, 10h
    jnz .init
    cmp al, 48h
    je .physical
    cmp al, 68h
    je .physical
    cmp al, 0ah
    je .select
    cmp al, 0bh
    je .select
    cmp al, 20h
    je .eoi
    mov ah, al
    and ah, 0f8h
    ; Set the priority on the physical controller.
    cmp ah, 0c0h
    je .physical
    cmp ah, 60h
    jne .unsupported
%ifdef OWN_HOST
    call virtual_pic_host_specific
    jc .done
%endif
    cmp al, [guest_eoi]
    je .virtual_eoi
    jmp .physical
.unsupported:
%ifdef MOUNTED_AUDIO
    FAULT_SET 7, 5
%else
    mov byte [fault], 1
%endif
    ret
.init:
    ; ICW2, ICW3 unless single, ICW4 if requested.
    mov ah, 2
    test al, 2
    jz .cascade
    dec ah
.cascade:
    test al, 1
    jz .words
    inc ah
.words:
    mov [pic_init_words], ah
    mov byte [virtual_pic_taken], 0
    mov byte [virtual_pic_service], 0
    mov byte [virtual_pic_mask], 0
    mov byte [physical_pic_read], 0ah
    jmp .physical
.select:
    mov [physical_pic_read], al
.physical:
    call physical_write
    ret
.eoi:
%ifdef OWN_HOST
    call virtual_pic_host_eoi
    jc .done
%else
    call physical_pic_isr
%endif
    cmp byte [virtual_pic_service], 0
    je .hardware_service
    test al, [guest_irq_higher]
    jnz .physical_eoi
    jmp .virtual_eoi
.hardware_service:
    test al, al
    jnz .physical_eoi
.virtual_eoi:
    mov byte [virtual_pic_service], 0
    DIAG_INC diag_ended
.done:
    ret
.physical_eoi:
    mov al, 20h
    jmp .physical
.mask:
    ; A real DSP sends the F2h interrupt some microseconds after the command.
    ; A game that masks the IRQ again before its next DSP access gets the
    ; interrupt before the mask (Earth 2140).
    mov ah, [guest_irq_bit]
    test al, ah
    jz .mask_open
    ; A second mask write before the take keeps the delivery due.
    cmp [pic_mask_late], ah
    je .mask_held
    cmp byte [irq_due], 0
    je .mask_clear
    test [virtual_pic_mask], ah
    jnz .mask_clear
    mov [pic_mask_late], ah
    DIAG_INC diag_due_mask
    push ax
    call virtual_irq_due_fire
    pop ax
    ; Nothing came of it: no delivery is late.
    cmp byte [virtual_pic_request], 0
    jne .mask_held
    mov byte [pic_mask_late], 0
    jmp .mask_ready
.mask_held:
    mov ah, [guest_irq_bit]
    not ah
    and al, ah
    jmp .mask_ready
.mask_open:
    mov byte [pic_mask_late], 0
    jmp .mask_ready
.mask_clear:
    mov byte [pic_mask_late], 0
.mask_ready:
    mov [virtual_pic_mask], al
    mov ah, [guest_irq_bit]
    not ah
    and al, ah
    mov ah, [physical_pic_initial]
    and ah, [guest_irq_bit]
    or al, ah
    mov ah, [physical_irq_bit]
    not ah
    and al, ah
    or al, [audio_irq_mask_bit]
%ifdef RESIDENT_AUDIO
    cmp byte [cd_refill_masked], 0
    je .refill_free
    ; The keyboard bit takes effect when the refill ends.
    mov ah, al
    and ah, 2
    and byte [cd_refill_old_mask], 0fdh
    or [cd_refill_old_mask], ah
    or al, 2
.refill_free:
%endif
    jmp .physical

%ifdef OWN_HOST
virtual_pic_host_service:
    push es
    push di
    mov ah, 0ffh
    cmp word [own_host_active+2], 0
    je .done
    les di, [own_host_active]
    cmp byte [es:di], 1
    jne .done
    or al, [es:di+4]
    mov ah, [es:di+5]
.done:
    pop di
    pop es
    ret

; Complete real handlers do not change virtual audio ownership.
virtual_pic_host_eoi:
virtual_pic_host_specific:
    push bx
    push cx
    push es
    push di
    mov bh, al
    cmp word [own_host_active+2], 0
    je .no_host
    les di, [own_host_active]
    cmp byte [es:di], 2
    je .complete
    cmp byte [es:di], 1
    jne .no_host
    cmp al, 20h
    jne .specific
    call physical_pic_isr
    and al, [es:di+5]
    push ax
    mov bl, [es:di+4]
    and bl, [es:di+5]
    test bl, bl
    jz .not_owned
    mov bh, al
    or al, bl
    or al, [virtual_pic_service]
    movzx cx, al
    bsf cx, cx
    mov al, 1
    shl al, cl
    test bl, al
    jz .not_owned
    ; The host ended the owned IRQ in hardware. A physical IRQ of the same
    ; level is nested in its handler, and this EOI ends that IRQ.
    test bh, al
    jnz .not_owned
    not al
    and [es:di+4], al
    pop ax
    stc
    jmp .restore
.specific:
    mov cl, al
    and cl, 7
    mov ch, 1
    shl ch, cl
    push ax
    push dx
    call physical_pic_isr
    pop dx
    test [es:di+4], ch
    jz .not_owned
    test al, ch
    jnz .not_owned
    not ch
    and [es:di+4], ch
    pop ax
    stc
    jmp .restore
.not_owned:
    pop ax
    jmp .none
.no_host:
    cmp bh, 20h
    jne .none
    call physical_pic_isr
.none:
    clc
    jmp .restore
.complete:
    call physical_write
    stc
.restore:
    pop di
    pop es
    pop cx
    pop bx
    ret
%endif

virtual_dsp_irq db 0
virtual_pic_mask db 0ffh
virtual_pic_request db 0
virtual_pic_service db 0
virtual_block_seen dd 0
physical_pic_initial db 0ffh
physical_irq_bit db 20h
pic_visible_bits db 0dfh
physical_pic_read db 0ah
pic_init_words db 0
virtual_pic_taken db 0
pic_mask_late db 0
%ifdef RESIDENT_AUDIO
; Unused. Keeps the CDF2 offsets below.
    db 0
%endif
irq_due db 0
%ifdef RESIDENT_AUDIO
irq_due_steps db 0
irq_step_left db 0
irq_step_swapped db 0
irq_step_guest dd 0
%endif
irq_due_calls db 0

; CDF2 exposes these offsets to the protected host.
cdf2_service_check equ 1 / ((virtual_pic_service-virtual_pic_request) = 1)
cdf2_visible_check equ 1 / ((pic_visible_bits-virtual_pic_request) = 8)
cdf2_mode_check equ 1 / ((physical_pic_read-virtual_pic_request) = 9)
cdf2_taken_check equ 1 / ((virtual_pic_taken-virtual_pic_request) = 11)
%ifdef RESIDENT_AUDIO
cdf2_due_check equ 1 / ((irq_due-virtual_pic_request) = 14)
cdf2_steps_check equ 1 / ((irq_due_steps-virtual_pic_request) = 15)
cdf2_left_check equ 1 / ((irq_step_left-virtual_pic_request) = 16)
cdf2_swap_check equ 1 / ((irq_step_swapped-virtual_pic_request) = 17)
cdf2_guest_check equ 1 / ((irq_step_guest-virtual_pic_request) = 18)
%endif
