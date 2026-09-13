; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

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
%ifdef CLIENT_STEREO
    movzx eax, byte [stream_codes+edx]
    sub eax, 128
    shl eax, 7
%ifdef STREAM_SILENT
    add eax, 0
%else
    add eax, 57
%endif
    and eax, 0ffffh
    add edx, 5
    and edx, 15
    movzx edx, byte [stream_codes+edx]
    sub edx, 128
    shl edx, 7
%ifdef STREAM_SILENT
    sub edx, 0
%else
    sub edx, 93
%endif
    shl edx, 16
    or eax, edx
    mov ecx, CLIENT_BLOCK_BYTES/4
    cld
    rep stosd
%else
    mov al, [stream_codes+edx]
    mov ecx, CLIENT_BLOCK_BYTES
    cld
    rep stosb
%endif
    pop es
    popad
    ret

stream_test:
    call reset
    mov ax, CLIENT_RATE
    call play
%ifdef CLIENT_STEREO
    mov dx, 22ch
    mov al, 0d0h
    out dx, al
%endif
    mov al, 40h
    call test_mark
%ifdef CD_IMAGE_TEST
    mov cx, 110
%else
    mov cx, 24
%endif
    call wait_ticks
    mov dx, 22ch
%ifdef CLIENT_STEREO
    mov al, 0d5h
%else
    mov al, 0d0h
%endif
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
