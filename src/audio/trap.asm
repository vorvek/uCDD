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
    mov byte [fault], 1
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
    mov al, 0
    out 0d8h, al
    mov dx, [dma_count_port]
    in al, dx
    mov ah, al
    in al, dx
    xchg al, ah
    ret

game_elapsed:
    cmp byte [game_start_pending], 1
    je .zero
    call output_clock
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
.unsupported:
    mov byte [fault], 1
    jmp .done
.reset:
    mov byte [game_active], 0
    mov byte [game_start_pending], 0
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
.clear_mask:
    test al, al
    jnz .unsupported
    mov byte [dma_masked], 0
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
    cmp al, 40h
    je .time_constant
    cmp al, 48h
    je .rate
    cmp al, 1ch
    je .legacy_start
    cmp al, 0c6h
    je .play
    cmp al, 0d0h
    je .pause
    cmp al, 0d3h
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
    mov byte [game_start_pending], 0
    jmp .done
.rate:
    mov byte [arguments], 2
    jmp .done
.play:
    mov byte [arguments], 3
    jmp .done
.time_constant:
    mov byte [arguments], 1
    jmp .done
.legacy_start:
    mov ax, [legacy_block]
    jmp .validate_start
.argument:
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
.set_time_constant:
    movzx ecx, al
    neg ecx
    add ecx, 256
    mov eax, 1000000
    xor edx, edx
    div ecx
    cmp eax, 44100
    ja .unsupported
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
.validate_start:
    cmp ax, [dma_count]
    ja .unsupported
    inc ax
    cmp ax, 512
    jb .unsupported
    movzx ebx, word [dma_count]
    inc ebx
    cmp ebx, 512
    jb .unsupported
    cmp ebx, 32768
    ja .unsupported
    mov ecx, ebx
    dec ecx
    test ebx, ecx
    jnz .unsupported
    movzx edx, ax
    cmp edx, ebx
    je .buffer_address
    mov esi, ebx
    sub esi, edx
    imul esi, 44100
    movzx ecx, word [game_rate]
    imul ecx, PERIOD_FRAMES*2
    cmp esi, ecx
    jb .unsupported
.buffer_address:
    movzx esi, word [dma_address]
    add esi, ebx
    cmp esi, 65536
    ja .unsupported
    movzx esi, byte [dma_page]
    shl esi, 16
    mov si, [dma_address]
    mov ecx, esi
    add ecx, ebx
    cmp ecx, 0a0000h
    ja .unsupported
    mov [game_block_bytes], dx
    shl ebx, 16
    mov [game_limit], ebx
    mov bx, si
    and bx, 15
    mov [game_offset], bx
    shr esi, 4
    mov [game_segment], si
    mov byte [game_start_pending], 1
%ifdef VIRTUAL_IRQ
    call virtual_irq_reset
%endif
    mov byte [game_active], 1
    inc word [virtual_starts]
    cmp byte [dsp_command], 1ch
    je .done
.argument_done:
    dec byte [arguments]
    jmp .done
.read:
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
%ifdef VIRTUAL_IRQ
    mov byte [virtual_dsp_irq], 0
%endif
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
    cmp byte [dma_flip], 0
    jne .count_high
    cmp byte [game_active], 0
    je .idle_count
    call game_elapsed
    movzx ecx, word [game_rate]
    mul ecx
    mov ecx, 44100
    div ecx
    and ax, [dma_count]
    mov bx, [dma_count]
    sub bx, ax
    jmp .snapshot
.idle_count:
    mov bx, [dma_count]
.snapshot:
    mov [count_snapshot], bx
    mov al, bl
    jmp .count_result
.count_high:
    mov al, [count_snapshot+1]
.count_result:
    xor byte [dma_flip], 1
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
    pop fs
    pop es
    pop ds
    popad
    clc
    retf

trap_ports:
%include "audio/ports.inc"
    dw 0
trapped_count dw 0
callback_set db 0
old_callback dd 0
port_calls dd 0
last_clock dd 0
game_start_pending db 0 ; 1: wait for mixing, 2: wait for output.
game_block_bytes dw 4096
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
legacy_block dw 0
reply dw 0
reply_count db 0
