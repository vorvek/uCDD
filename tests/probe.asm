bits 16
org 100h

    cld
    mov dx, critical_error
    mov ax, 2524h
    int 21h
    mov si, 81h
.space:
    lodsb
    cmp al, ' '
    je .space
    dec si
    cmp byte [si], 'a'
    je absent
    xor bp, bp
    cmp byte [si], '!'
    jne .path
    inc bp
    inc si
.path:
    mov dx, si
.end:
    lodsb
    cmp al, 13
    jne .end
    mov byte [si-1], 0
    mov ax, 3d00h
    int 21h
    jc .missing
    test bp, bp
    jnz fail
    mov bx, ax
    mov dx, buffer
    mov cx, 128
    mov ah, 3fh
    int 21h
    jc fail
    cmp ax, expected_end-expected
    jne fail
    mov si, buffer
    mov di, expected
    mov cx, expected_end-expected
    repe cmpsb
    jne fail
    mov ah, 3eh
    int 21h
    jmp pass
.missing:
    test bp, bp
    jz fail
    jmp pass
absent:
    xor bx, bx
    mov ax, 1500h
    int 2fh
    test bx, bx
    jnz fail
pass:
    mov ax, 4c00h
    int 21h
fail:
    mov dx, message
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
message db 'The test failed.',13,10,'$'
critical_error:
    mov al, 3
    iret
expected db 'uCDD test file.',13,10
expected_end:
buffer times 128 db 0
