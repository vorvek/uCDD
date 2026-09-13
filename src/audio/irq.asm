; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; One virtual, edge-triggered master-PIC input at IRQ 5.
virtual_irq_init:
    mov dx, 21h
    call physical_read
    mov [virtual_pic_mask], al
    mov [physical_pic_initial], al
    mov cl, [sb_irq]
    mov al, 1
    shl al, cl
    mov [physical_irq_bit], al
    or al, 20h
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
    movzx ecx, word [game_rate]
    mul ecx
    mov ecx, 44100
    div ecx
    mov cl, [game_frame_shift]
    shl eax, cl
    xor edx, edx
    movzx ecx, word [game_block_bytes]
    div ecx
    cmp eax, [virtual_block_seen]
    je .done
    mov [virtual_block_seen], eax
    cmp byte [virtual_dsp_irq], 0
    jne .done
    mov al, [game_irq_bit]
    mov [virtual_dsp_irq], al
    mov byte [virtual_pic_request], 20h
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
    test byte [virtual_pic_mask], 20h
    jnz .done
    cmp byte [virtual_pic_service], 0
    jne .done
    cmp byte [virtual_pic_request], 0
    je .done
    call physical_pic_isr
    test al, 3fh
    jnz .done
    mov byte [virtual_pic_request], 0
    mov byte [virtual_pic_service], 20h
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
    cmp al, 65h
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
    test al, 1fh
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
    and al, 0dfh
    mov ah, [physical_pic_initial]
    and ah, 20h
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
