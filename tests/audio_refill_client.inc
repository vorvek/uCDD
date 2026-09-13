stream_init:
    xor eax, eax
.next:
    call stream_write_block
    inc eax
    cmp eax, CLIENT_RING_BYTES/CLIENT_BLOCK_BYTES
    jb .next
    ret

stream_refill:
    mov eax, [game_interrupts]
    add eax, CLIENT_RING_BYTES/CLIENT_BLOCK_BYTES-1
    call stream_write_block
    ret

stream_write_block:
    pushad
    push es
    mov es, [buffer_selector]
    mov edx, eax
    and eax, CLIENT_RING_BYTES/CLIENT_BLOCK_BYTES-1
    imul eax, CLIENT_BLOCK_BYTES
    add eax, [buffer_offset]
    mov edi, eax
    and edx, 15
    mov al, [stream_codes+edx]
    mov ecx, CLIENT_BLOCK_BYTES
    cld
    rep stosb
    pop es
    popad
    ret

stream_test:
    call reset
    mov ax, CLIENT_RATE
    call play
    mov al, 40h
    call test_mark
    mov cx, 24
    call wait_ticks
    mov dx, 22ch
    mov al, 0d0h
    out dx, al
    mov al, 50h
    call test_mark
    mov cx, 2
    call wait_ticks
    cmp byte [event_fault], 0
    jne failed
%ifdef EXPECT_REJECT
    cmp dword [owned_irqs], 80
    jb failed
    cmp byte [bridge_fault], 0
    jne failed
    cmp dword [game_interrupts], 0
    jne failed
    mov edx, rejected
    mov ah, 9
    int 21h
    jmp failed
rejected db 'The unsafe refill buffer was rejected.',13,10,'$'
%else
    cmp dword [game_interrupts], CLIENT_RING_BYTES/CLIENT_BLOCK_BYTES*2
    jb failed
    ret
%endif

stream_codes:
%ifdef STREAM_SILENT
    times 16 db 128
%else
    db 144,176,96,192,112,64,160,80,176,144,64,160,192,96,80,112
%endif
