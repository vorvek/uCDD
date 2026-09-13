poll_test:
    in al, 21h
    mov [client_pic_mask], al
    and al, 0dfh
    out 21h, al
    call reset
    mov ax, CLIENT_RATE
    call play
    mov al, 40h
    call test_mark
    mov edi, 24
.next:
    mov cx, 1
    call wait_ticks
    call read_dsp_irq
    test al, al
    jz .count
    inc dword [poll_acks]
.count:
    mov dx, 22eh
    in al, dx
    xor al, al
    out 0ch, al
    in al, 3
    mov bl, al
    in al, 3
    mov bh, al
    cmp bx, [last_count]
    je .wait
    inc dword [poll_changes]
    mov [last_count], bx
.wait:
    dec edi
    jnz .next
    mov dx, 22ch
    mov al, 0d0h
    out dx, al
    mov al, 50h
    call test_mark
    mov al, [client_pic_mask]
    out 21h, al
    mov cx, 2
    call wait_ticks
    cmp dword [poll_acks], 2
    jb failed
    cmp dword [poll_changes], 20
    jb failed
    ret

poll_acks dd 0
poll_changes dd 0
