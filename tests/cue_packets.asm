bits 16
cpu 386
org 100h
%include "disc.inc"
    push cs
    pop ds
    push cs
    pop es
    mov bx, devices
    mov ax, 1501h
    int 2fh
    les di, [devices+1]
    cmp dword [es:di+22], 'uCDD'
    jne failed
    cmp word [es:di+26], 2
    jne failed
    mov eax, [es:di+28]
    mov [entry], eax
    push cs
    pop es
    mov [packet+16], cs
    mov byte [buffer], 10
    mov word [packet+18], 7
    call request
    cmp word [buffer+1], 0201h
    jne failed
    cmp dword [buffer+3], 00000535h
    jne failed
    mov byte [buffer], 11
    mov byte [buffer+1], 1
    call request
    cmp dword [buffer+2], 00000200h
    jne failed
    cmp byte [buffer+6], 40h
    jne failed
    mov byte [buffer+1], 2
    call request
    cmp dword [buffer+2], 00000335h
    jne failed
    cmp byte [buffer+6], 0
    jne failed
    xor bx, bx
    mov ax, 3
    mov dx, info
    call far [entry]
    test ax, ax
    jnz failed
    cmp word [info+INFO_STRIDE], 2352
    jne failed
    cmp word [info+INFO_COUNT], 2
    jne failed
    mov ax, 3
    mov dx, 0ffffh
    call far [entry]
    test ax, 8000h
    jz failed
    mov ax, 4
    mov dx, callback
    call far [entry]
    test ax, ax
    jnz failed
    mov ax, 2
    call far [entry]
    cmp ax, 8002h
    jne failed_attached
    mov byte [buffer], 15
    mov word [packet+18], 11
    mov word [packet+3], 0
    mov bx, packet
    mov cx, 5
    mov ax, 1510h
    int 2fh
    cmp word [packet+3], 0300h
    jne failed_attached
    cmp byte [called], 1
    jne failed_attached
    xor bx, bx
    mov ax, 5
    mov dx, callback+1
    call far [entry]
    test ax, 8000h
    jz failed_attached
    call detach
    test ax, ax
    jnz failed
    mov dx, success
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
request:
    mov bx, packet
    mov cx, 5
    mov ax, 1510h
    int 2fh
    cmp word [packet+3], 100h
    jne failed
    ret
callback:
    cmp byte [fs:bp], 13
    jne .bad
    cmp byte [es:di], 15
    jne .bad
    mov byte [cs:called], 1
    mov ax, 300h
    retf
.bad:
    mov ax, 810ch
    retf
detach:
    xor bx, bx
    mov dx, callback
    mov ax, 5
    call far [entry]
    ret
failed_attached:
    call detach
failed:
    mov dx, failure
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
success db 'The CUE packet tests passed.',13,10,'$'
failure db 'The CUE packet tests failed.',13,10,'$'
entry dd 0
called db 0
devices times 26*5 db 0
packet db 13,0,3
    dw 0
    times 8 db 0
    db 0
    dw buffer,0,7
buffer times 16 db 0
info times INFO_SIZE db 0
