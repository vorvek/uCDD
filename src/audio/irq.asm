; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%include "audio/sb_state.inc"

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
    mov byte [virtual_dsp_irq], 0
    mov byte [virtual_pic_request], 0
    mov dword [virtual_block_seen], 0
    ret

virtual_irq_tick:
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
    push eax
    mov eax, [game_block_bytes]
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
    pop eax
.position:
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
    cmp byte [virtual_dsp_irq], 0
    jne .done
    mov al, [game_irq_bit]
    mov [virtual_dsp_irq], al
    mov al, [guest_irq_bit]
    mov [virtual_pic_request], al
.done:
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
    cmp byte [virtual_pic_service], 0
    jne .done
    cmp byte [virtual_pic_request], 0
    je .done
    call physical_pic_isr
    test al, [guest_irq_priority]
    jnz .done
    mov byte [virtual_pic_request], 0
    mov al, [guest_irq_bit]
    mov [virtual_pic_service], al
    inc bx
.done:
    mov ax, bx
    pop dx
    pop cx
    pop bx
    pop ds
    retf

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
    ret
.mask:
    and al, [pic_visible_bits]
    mov ah, [pic_visible_bits]
    not ah
    and ah, [virtual_pic_mask]
    or al, ah
    ret

virtual_pic_write:
    cmp dx, 21h
    je .mask
    cmp al, 0ah
    je .select
    cmp al, 0bh
    je .select
    cmp al, 20h
    je .eoi
    cmp al, [guest_eoi]
    je .virtual_eoi
    mov ah, al
    and ah, 0f8h
    cmp ah, 60h
    je .physical
%ifdef MOUNTED_AUDIO
    mov byte [fault], 5
%else
    mov byte [fault], 1
%endif
    ret
.select:
    mov [physical_pic_read], al
.physical:
    call physical_write
    ret
.eoi:
    call physical_pic_isr
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
    ret
.physical_eoi:
    mov al, 20h
    jmp .physical
.mask:
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
    jmp .physical

virtual_dsp_irq db 0
virtual_pic_mask db 0ffh
virtual_pic_request db 0
virtual_pic_service db 0
virtual_block_seen dd 0
physical_pic_initial db 0ffh
physical_irq_bit db 20h
pic_visible_bits db 0dfh
physical_pic_read db 0ah
