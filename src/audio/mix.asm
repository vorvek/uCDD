; ES:DI is one output half. Sources use the current virtual playback state.
mix_half:
    mov eax, [periods]
    inc eax
    shl eax, OUTPUT_SHIFT
    cmp byte [game_active], 0
    je .phase
    cmp byte [game_start_pending], 1
    jne .phase
    mov [game_started], eax
    mov byte [game_start_pending], 2
.phase:
    sub eax, [game_started]
    mul dword [game_step]
    div dword [game_limit]
    mov ebp, edx
    mov cx, PERIOD_FRAMES
    mov bx, [cd_position]
    mov fs, [game_segment]
.frame:
    xor edx, edx
    cmp byte [game_active], 0
    je .sum
    cmp byte [dma_masked], 0
    jne .sum
    mov eax, ebp
    shr eax, 16
    mov si, ax
    add si, [game_offset]
    movzx edx, byte [fs:si]
    sub edx, 128
    shl edx, 7
    add ebp, [game_step]
    cmp ebp, [game_limit]
    jb .sum
    sub ebp, [game_limit]
.sum:
    movsx eax, word [cd_samples+bx]
    sar eax, 1
    add eax, edx
    call .clip
    stosw
    movsx eax, word [cd_samples+bx+2]
    sar eax, 1
    add eax, edx
    call .clip
    stosw
    add bx, 4
    and bx, 16383
    loop .frame
    mov [cd_position], bx
    mov [game_phase], ebp
    ret
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
