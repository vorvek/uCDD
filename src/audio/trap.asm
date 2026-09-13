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
    call physical_write
    mov dx, [dma_count_port]
    call physical_read
    mov bl, al
    call physical_read
    mov ah, al
    mov al, bl
    pop bx
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
    call dma_port
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
%ifdef MOUNTED_AUDIO
    mov byte [fault], 3
%else
    mov byte [fault], 1
%endif
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
    mov byte [si+DMA_FLIP], 0
    jmp .done
.mask:
    mov ah, al
    and ah, 3
    cmp ah, 1
    jne .unsupported
    and al, 4
    mov [si+DMA_MASK], al
    jmp .done
.mode:
    cmp al, 59h
    jne .unsupported
    jmp .done
.clear_mask:
    test al, al
    jnz .unsupported
    mov byte [si+DMA_MASK], 0
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
    cmp al, 1ch
    je .legacy_start
    cmp al, 0c6h
    je .play
    cmp al, 0b6h
    je .play
    cmp al, 0d0h
    je .pause8
    cmp al, 0d5h
    je .pause16
    cmp al, 0d3h
    je .pause
    cmp al, 0d1h
    je .done
    cmp al, 0e1h
    jne .unsupported
    mov word [reply], 0504h
    mov byte [reply_count], 2
    jmp .done
.pause8:
    cmp byte [game_frame_shift], 0
    jne .done
    jmp .pause
.pause16:
    cmp byte [game_frame_shift], 2
    jne .done
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
    mov byte [pending_frame_shift], 0
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
    mov byte [pending_frame_shift], 0
    cmp byte [dsp_command], 0b6h
    jne .mono_mode
    cmp al, 30h
    jne .unsupported
    mov byte [pending_frame_shift], 2
    jmp .argument_done
.mono_mode:
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
    mov si, dma8
    mov cl, 0
    cmp byte [pending_frame_shift], 0
    je .dma_selected
    mov si, dma16
    mov cl, 1
.dma_selected:
    cmp ax, [si+DMA_COUNT]
    ja .unsupported
    movzx edx, ax
    inc edx
    shl edx, cl
    cmp edx, 512
    jb .unsupported
    movzx ebx, word [si+DMA_COUNT]
    inc ebx
    shl ebx, cl
    cmp ebx, 512
    jb .unsupported
    cmp ebx, 32768
    ja .unsupported
    mov ecx, ebx
    dec ecx
    test ebx, ecx
    jnz .unsupported
    test edx, 3
    jz .block_aligned
    cmp byte [pending_frame_shift], 0
    jne .unsupported
.block_aligned:
    cmp edx, ebx
    je .buffer_address
    mov eax, ebx
    sub eax, edx
    mov cl, [pending_frame_shift]
    shr eax, cl
    imul eax, 44100
    movzx ecx, word [game_rate]
    imul ecx, PERIOD_FRAMES*2
    cmp eax, ecx
    jb .unsupported
.buffer_address:
    movzx eax, word [si+DMA_ADDRESS]
    cmp byte [pending_frame_shift], 0
    je .byte_address
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
    cmp byte [pending_frame_shift], 0
    jne .word_window
    cmp eax, 65536
    ja .unsupported
    jmp .address_limit
.word_window:
    cmp eax, 131072
    ja .unsupported
.address_limit:
    mov eax, ecx
    add eax, ebx
    cmp eax, 0a0000h
    ja .unsupported
    mov [game_dma], si
    mov esi, ecx
    mov [game_block_bytes], dx
    mov cl, [pending_frame_shift]
    mov [game_frame_shift], cl
    mov al, 1
    cmp cl, 0
    je .irq_bit
    inc al
.irq_bit:
    mov [game_irq_bit], al
    shr ebx, cl
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
    cmp dx, 22fh
    je .status16
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
    and byte [virtual_dsp_irq], 0feh
%endif
    xor al, al
    cmp byte [reply_count], 0
    je .result
    mov al, 80h
    jmp .result
.status16:
%ifdef VIRTUAL_IRQ
    and byte [virtual_dsp_irq], 0fdh
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
    call game_elapsed
    movzx ecx, word [game_rate]
    mul ecx
    mov ecx, 44100
    div ecx
    cmp byte [game_frame_shift], 0
    je .count_units
    shl eax, 1
.count_units:
    and ax, [si+DMA_COUNT]
    mov bx, [si+DMA_COUNT]
    sub bx, ax
    jmp .snapshot
.idle_count:
    mov bx, [si+DMA_COUNT]
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
    mov [ss:bp+28], al
.done:
    pop fs
    pop es
    pop ds
    popad
    clc
    retf

dma_port:
    mov si, dma8
    cmp dx, 8bh
    je .page
    cmp dx, 0c4h
    je .address
    cmp dx, 0c6h
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
trapped_count dw 0
callback_set db 0
old_callback dd 0
port_calls dd 0
last_clock dd 0
game_start_pending db 0 ; 1: wait for mixing, 2: wait for output.
game_dma dw dma8
game_frame_shift db 0
pending_frame_shift db 0
game_irq_bit db 1
game_block_bytes dw 4096
virtual_resets dw 0
virtual_starts dw 0
virtual_mixer_index db 0
virtual_mixer times 256 db 0
dma8 db 0,1,0,0
    dw 0,0,0
dma16 db 0,1,0,0
    dw 0,0,0
dsp_command db 0
arguments db 0
block_low db 0
legacy_block dw 0
reply dw 0
reply_count db 0
