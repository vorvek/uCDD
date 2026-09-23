; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

.wss_port:
    sub dx, 530h
    test cl, 4
    jz .wss_read
    cmp dx, 4
    jb .wss_board
    je .wss_index_write
    cmp dx, 5
    je .wss_data_write
    cmp dx, 6
    jne .unsupported
    and byte [wss_status], 0feh
    call wss_release
    jmp .done
.wss_board:
    mov [wss_board], al
    mov ah, al
    and al, 3
    mov bl, 2
    cmp byte [guest_dma8], 1
    je .wss_dma_channel
    mov bl, 3
.wss_dma_channel:
    cmp al, bl
    jne .unsupported
    mov al, ah
    shr al, 3
    and al, 7
    movzx bx, al
    movzx ax, byte [wss_irqs+bx]
    mov [wss_guest_irq], ax
    test byte [wss_board], 40h
    jz .done
    mov [wss_irq_event], ax
    jmp .done
.wss_index_write:
    mov ah, [wss_index]
    and al, 7fh
    mov [wss_index], al
    and ah, 40h
    test al, 40h
    jz .wss_mce_clear
    cmp byte [game_source], 1
    jne .done
    mov byte [game_active], 0
    jmp .done
.wss_mce_clear:
    push ax
    test byte [wss_index], 20h
    jz .wss_unhold
    call wss_hold
    jmp .wss_hold_ready
.wss_unhold:
    call wss_release
.wss_hold_ready:
    pop ax
    test ah, ah
    jz .done
    call output_clock
    add eax, 1024
    mov [wss_aci_end], eax
    jmp .wss_arm
.wss_data_write:
    movzx bx, byte [wss_index]
    and bx, 15
    cmp bl, 11
    je .done
    cmp bl, 12
    je .done
    cmp bl, 8
    je .wss_format
    cmp bl, 9
    je .wss_interface
    mov [wss_registers+bx], al
    cmp bl, 6
    je .wss_volume
    cmp bl, 7
    je .wss_volume
    cmp bl, 14
    je .wss_count
    cmp bl, 10
    jne .done
    test al, 2
    jz .done
    test byte [wss_status], 1
    jz .done
    mov ax, [wss_guest_irq]
    mov [wss_irq_event], ax
    jmp .done
.wss_volume:
    sub bx, 6
    shl bx, 2
    xor ecx, ecx
    test al, 80h
    jnz .wss_gain
    and ax, 3fh
    mov si, ax
    shl si, 2
    mov ecx, [wss_attenuation+si]
.wss_gain:
    mov [wss_gain+bx], ecx
    jmp .done
.wss_format:
    test byte [wss_index], 40h
    jz .done
    test al, 0a0h
    jnz .unsupported
    mov [wss_registers+8], al
    jmp .done
.wss_interface:
    test byte [wss_index], 40h
    jnz .wss_interface_mce
    and al, 3
    mov ah, [wss_registers+9]
    and ah, 0fch
    or al, ah
.wss_interface_mce:
    test al, 0c2h
    jnz .unsupported
    mov [wss_registers+9], al
    test al, 1
    jnz .wss_arm
    cmp byte [game_source], 1
    jne .done
    mov byte [game_active], 0
    jmp .done
.wss_count:
    mov byte [wss_count_valid], 1
    mov dword [virtual_block_seen], 0
    cmp byte [game_source], 1
    jne .wss_arm
    cmp byte [game_active], 0
    je .wss_arm
    mov ah, [wss_registers+14]
    mov al, [wss_registers+15]
    movzx edx, ax
    inc edx
    mov cl, [game_frame_shift]
    shl edx, cl
    cmp edx, 65535
    ja .unsupported
    mov [game_block_bytes], edx
    call game_elapsed
    movzx ecx, word [game_rate]
    mul ecx
    mov ecx, OUTPUT_RATE
    div ecx
    mov cl, [game_frame_shift]
    shl eax, cl
    mov [wss_block_origin], eax
    jmp .done
.wss_arm:
    cmp byte [dma8+DMA_MASK], 0
    jne .done
    test byte [wss_index], 40h
    jnz .done
    test byte [wss_registers+9], 1
    jz .done
    cmp byte [wss_count_valid], 0
    je .done
    cmp byte [game_source], 1
    jne .wss_start
    cmp byte [game_active], 1
    je .done
.wss_start:
    mov byte [sb_single], 0
    mov byte [sb_input], 0
    mov byte [sb_finished], 0
    mov byte [sb_paused], 0
    mov byte [wss_paused], 0
    mov dword [wss_block_origin], 0
    movzx bx, byte [wss_registers+8]
    mov ax, bx
    and bx, 15
    shl bx, 1
    mov dx, [wss_rates+bx]
    test dx, dx
    jz .unsupported
    mov [game_rate], dx
    mov byte [pending_frame_shift], 0
    test al, 10h
    jz .wss_width
    inc byte [pending_frame_shift]
.wss_width:
    test al, 40h
    jz .wss_rate
    inc byte [pending_frame_shift]
.wss_rate:
    movzx eax, dx
    shl eax, 16
    xor edx, edx
    mov ecx, OUTPUT_RATE
    div ecx
    mov [game_step], eax
    mov ah, [wss_registers+14]
    mov al, [wss_registers+15]
    movzx edx, ax
    inc edx
    mov cl, [pending_frame_shift]
    shl edx, cl
    cmp edx, 65535
    ja .unsupported
    mov byte [game_source], 1
    mov si, dma8
    xor cl, cl
    jmp .validate_dma
.wss_read:
    cmp dx, 4
    jb .wss_board_read
    je .wss_index_read
    cmp dx, 5
    je .wss_data_read
    cmp dx, 6
    je .wss_status_read
    mov al, 80h
    jmp .result
.wss_board_read:
    mov al, [wss_board]
    and al, 40h
    or al, 4
    jmp .result
.wss_index_read:
    mov al, [wss_index]
    jmp .result
.wss_status_read:
    mov al, [wss_status]
    jmp .result
.wss_data_read:
    movzx bx, byte [wss_index]
    and bx, 15
    cmp bl, 11
    je .wss_aci
    mov al, [wss_registers+bx]
    jmp .result
.wss_aci:
    call output_clock
    sub eax, [wss_aci_end]
    sar eax, 31
    and al, 20h
    jmp .result
