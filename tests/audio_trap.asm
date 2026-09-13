bits 16
cpu 386
org 100h

    mov ax, 1684h
    mov bx, 4354h
    int 2fh
    test al, al
    jnz failed
    mov [qpi], di
    mov [qpi+2], es
    mov ax, 1a06h
    call far [qpi]
    jc failed
    mov [old_callback], di
    mov [old_callback+2], es
    push cs
    pop es
    mov di, callback
    mov ax, 1a07h
    call far [qpi]
    jc failed
    mov dx, 220h
    mov ax, 1a09h
    call far [qpi]
    jc restore
    mov al, 5ah
    out dx, al
    in al, dx
    cmp al, 5ah
    jne untrap
    mov dx, 03h
    mov ax, 1a09h
    call far [qpi]
    jc untrap
    mov al, 0a5h
    out dx, al
    in al, dx
    cmp al, 0a5h
    jne .dma_done
    cmp word [cs:calls], 4
    jne .dma_done
    mov byte [cs:result], 0
.dma_done:
    mov ax, 1a0ah
    call far [qpi]
untrap:
    mov dx, 220h
    mov ax, 1a0ah
    call far [qpi]
restore:
    les di, [old_callback]
    mov ax, 1a07h
    call far [qpi]
    jc failed
    cmp byte [result], 0
    jne failed
    mov dx, success
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
failed:
    mov dx, failure
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

callback:
    inc word [cs:calls]
    test cl, 4
    jz .read
    mov [cs:value], al
    clc
    retf
.read:
    mov al, [cs:value]
    clc
    retf

qpi dd 0
old_callback dd 0
calls dw 0
value db 0
result db 1
success db 'The port test passed.',13,10,'$'
failure db 'The port test failed.',13,10,'$'
