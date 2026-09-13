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
    mov si, trap_ports
    mov cx, [trapped_count]
    jcxz .callback
.next:
    lodsw
    mov dx, ax
    mov ax, 1a0ah
    call far [qpi]
    loop .next
.callback:
    cmp byte [callback_set], 0
    je .done
    les di, [old_callback]
    mov ax, 1a07h
    call far [qpi]
.done:
    ret

output_clock:
    mov cx, 8
.retry:
    call .count
    mov bx, ax
    call .count
    cmp bx, 16383
    ja .again
    cmp ax, 16383
    ja .again
    sub bx, ax
    and bx, 16383
    cmp bx, 32
    jbe .stable
.again:
    loop .retry
    mov byte [fault], 1
    mov eax, [last_clock]
    ret
.stable:
    movzx eax, ax
    mov ebx, 16383
    sub ebx, eax
    shr ebx, 1
    movzx eax, word [periods]
    shl eax, 12
    mov edx, eax
    xor edx, ebx
    test edx, 4096
    jz .same_half
    add eax, 4096
.same_half:
    and ebx, 4095
    add eax, ebx
    mov [last_clock], eax
    ret
.count:
    mov al, 0
    out 0d8h, al
    mov dx, [dma_count_port]
    in al, dx
    mov ah, al
    in al, dx
    xchg al, ah
    ret

port_callback:
    pushad
    mov bp, sp
    push ds
    push es
    push fs
    push cs
    pop ds
    inc dword [port_calls]
    test cl, 18h
    jnz .unsupported
    test cl, 4
    jz .read
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
.unsupported:
    mov byte [fault], 1
    jmp .done
.reset:
    mov byte [game_active], 0
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
    mov [virtual_mixer+bx], al
    jmp .done
.flip_reset:
    mov byte [dma_flip], 0
    jmp .done
.mask:
    mov ah, al
    and ah, 3
    cmp ah, 1
    jne .unsupported
    and al, 4
    mov [dma_masked], al
    jmp .done
.mode:
    cmp al, 59h
    jne .unsupported
    jmp .done
.page:
    mov [dma_page], al
    jmp .done
.address:
    mov si, dma_address
    jmp .dma_word
.count:
    mov si, dma_count
.dma_word:
    movzx bx, byte [dma_flip]
    mov [si+bx], al
    xor byte [dma_flip], 1
    jmp .done
.command:
    cmp byte [arguments], 0
    jne .argument
    mov [dsp_command], al
    cmp al, 41h
    je .rate
    cmp al, 0c6h
    je .play
    cmp al, 0d0h
    je .pause
    cmp al, 0d1h
    je .done
    cmp al, 0e1h
    jne .unsupported
    mov word [reply], 0504h
    mov byte [reply_count], 2
    jmp .done
.pause:
    mov byte [game_active], 0
    jmp .done
.rate:
    mov byte [arguments], 2
    jmp .done
.play:
    mov byte [arguments], 3
    jmp .done
.argument:
    cmp byte [dsp_command], 41h
    jne .play_argument
    cmp byte [arguments], 2
    jne .rate_low
    mov [game_rate+1], al
    jmp .argument_done
.rate_low:
    mov [game_rate], al
    cmp word [game_rate], 4000
    jb .unsupported
    cmp word [game_rate], 44100
    ja .unsupported
    movzx eax, word [game_rate]
    shl eax, 16
    xor edx, edx
    mov ecx, 44100
    div ecx
    mov [game_step], eax
    jmp .argument_done
.play_argument:
    cmp byte [arguments], 3
    jne .length
    test al, al
    jnz .unsupported
    jmp .argument_done
.length:
    cmp byte [arguments], 2
    jne .start
    mov [block_low], al
    jmp .argument_done
.start:
    mov ah, al
    mov al, [block_low]
    cmp ax, [dma_count]
    jne .unsupported
    cmp ax, 4095
    jne .unsupported
    movzx eax, byte [dma_page]
    shl eax, 16
    mov ax, [dma_address]
    cmp eax, 0a0000h-4096
    ja .unsupported
    mov bx, ax
    and bx, 15
    mov [game_offset], bx
    shr eax, 4
    mov [game_segment], ax
    call output_clock
    mov [game_started], eax
    mov byte [game_active], 1
    inc word [virtual_starts]
.argument_done:
    dec byte [arguments]
    jmp .done
.read:
    cmp dx, 22ch
    je .ready
    cmp dx, 22eh
    je .status
    cmp dx, 22ah
    je .reply
    cmp dx, 225h
    je .mixer_read
    cmp dx, 3
    je .dma_read
    jmp .unsupported
.ready:
    xor al, al
    jmp .result
.status:
    xor al, al
    cmp byte [reply_count], 0
    je .result
    mov al, 80h
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
    mov al, [virtual_mixer+bx]
    jmp .result
.dma_read:
    cmp byte [dma_flip], 0
    jne .count_high
    cmp byte [game_active], 0
    je .idle_count
    call output_clock
    sub eax, [game_started]
    movzx ecx, word [game_rate]
    mul ecx
    mov ecx, 44100
    div ecx
    and ax, 4095
    mov bx, 4095
    sub bx, ax
    jmp .snapshot
.idle_count:
    mov bx, 4095
.snapshot:
    mov [count_snapshot], bx
    mov al, bl
    jmp .count_result
.count_high:
    mov al, [count_snapshot+1]
.count_result:
    xor byte [dma_flip], 1
.result:
    mov [ss:bp+28], al
.done:
    pop fs
    pop es
    pop ds
    popad
    clc
    retf

trap_ports dw 2,3,0ah,0bh,0ch,83h,224h,225h,226h,22ah,22ch,22eh,0
trapped_count dw 0
callback_set db 0
old_callback dd 0
port_calls dd 0
last_clock dd 0
virtual_resets dw 0
virtual_starts dw 0
virtual_mixer_index db 0
virtual_mixer times 256 db 0
dma_flip db 0
dma_masked db 1
dma_page db 0
dma_address dw 0
dma_count dw 0
count_snapshot dw 0
dsp_command db 0
arguments db 0
block_low db 0
reply dw 0
reply_count db 0
