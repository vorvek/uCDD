bits 16
cpu 386
org 100h

    cld
    mov [psp], ds
    mov sp, program_end+512
    mov bx, (program_end-$$+100h+512+15)/16
    mov ah, 4ah
    int 21h
    jc fail
    mov bx, 3100h
    mov ah, 48h
    int 21h
    jc fail
    mov [buffer_segment], ax
    mov bx, device_list
    mov ax, 1501h
    int 2fh
    les di, [device_list+1]
    mov ax, [es:di+6]
    mov [strategy], ax
    mov ax, [es:di+8]
    mov [interrupt], ax
    mov [strategy+2], es
    mov [interrupt+2], es
    mov ax, es
    cmp byte [80h], 0
    je .placement_ok
    cmp ax, 0a000h
    jb fail
    mov dx, high_message
    mov ah, 9
    int 21h
    mov ax, es
.placement_ok:
    sub ax, 17
    mov es, ax
    mov ax, [es:3]
    shl ax, 4
    mov [resident_bytes], ax
    push ds
    pop es
    mov dx, dta
    mov ah, 1ah
    int 21h

    mov byte [stage], 1
    mov byte [packet], 27
    mov byte [packet+2], 80h
    mov word [packet+14], 0fff0h
    mov ax, [buffer_segment]
    mov [packet+16], ax
    mov word [packet+18], 64
    mov dword [packet+20], 22
    call send
    cmp word [packet+3], 0100h
    jne fail
    cmp word [packet+18], 64
    jne fail
    mov ax, [buffer_segment]
    add ax, 0fffh
    mov es, ax
    mov al, 22
.sector:
    xor di, di
    mov cx, 2048
    repe scasb
    jne fail
    mov dx, es
    add dx, 128
    mov es, dx
    inc al
    cmp al, 86
    jne .sector
    mov ah, 62h
    int 21h
    cmp bx, [psp]
    jne fail
    mov ah, 2fh
    int 21h
    cmp bx, dta
    jne fail
    mov ax, es
    cmp ax, [psp]
    jne fail

    mov byte [stage], 2
    mov word [packet+18], 1
    mov dword [packet+20], 128
    call send
    cmp word [packet+3], 8108h
    jne fail
    cmp word [packet+18], 0
    jne fail

    mov byte [stage], 3
    mov word [packet+18], 1
    mov dword [packet+20], 0ffffffffh
    call send
    cmp word [packet+3], 8108h
    jne fail

    mov byte [stage], 4
    mov byte [packet+24], 1
    mov word [packet+18], 1
    mov dword [packet+20], 0
    call send
    cmp word [packet+3], 8103h
    jne fail
    mov byte [packet+24], 0

    mov byte [stage], 5
    mov byte [packet+1], 4
    mov bx, packet
    push ds
    pop es
    call far [strategy]
    call far [interrupt]
    cmp word [packet+3], 8101h
    jne fail
    mov byte [packet+1], 0

    mov byte [stage], 6
    mov byte [packet+2], 3
    mov byte [packet], 19
    call send
    cmp word [packet+3], 810ch
    jne fail

    mov byte [stage], 7
    mov byte [packet], 20
    mov word [packet+14], 0fffbh
    mov ax, [buffer_segment]
    mov [packet+16], ax
    mov es, ax
    mov byte [es:0fffbh], 6
    mov word [packet+18], 5
    call send
    cmp word [packet+3], 0100h
    jne fail

    mov byte [stage], 8
    mov word [packet+18], 6
    call send
    cmp word [packet+3], 810ch
    jne fail

    mov byte [stage], 9
    mov byte [packet+2], 84h
    call send
    cmp word [packet+3], 8103h
    jne fail

    mov byte [stage], 10
    mov byte [packet+2], 0ch
    mov word [packet+14], ioctl_data
    mov [packet+16], ds
    mov word [packet+18], 2
    mov word [ioctl_data], 0101h
    call send
    cmp word [packet+3], 0100h
    jne fail
    mov word [ioctl_data], 0
    mov word [packet+18], 1
    call send
    test word [packet+3], 8000h
    jz fail
    mov word [ioctl_data], 0001h
    mov word [packet+18], 2
    call send
    cmp word [packet+3], 0100h
    jne fail

    push ds
    pop es
    mov dx, memory_message
    mov ah, 9
    int 21h
    mov ax, [resident_bytes]
    call decimal
    mov dx, pass_message
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h

send:
    push ds
    pop es
    mov bx, packet
    mov cx, 5
    mov ax, 1510h
    int 2fh
    ret
decimal:
    xor cx, cx
    mov bx, 10
.divide:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .divide
.print:
    pop dx
    add dl, '0'
    mov ah, 2
    int 21h
    loop .print
    ret
fail:
    push cs
    pop ds
    mov dx, fail_message
    mov ah, 9
    int 21h
    movzx ax, byte [stage]
    call decimal
    mov ax, 4c01h
    int 21h
stage db 0
psp dw 0
buffer_segment dw 0
resident_bytes dw 0
strategy dd 0
interrupt dd 0
packet times 32 db 0
ioctl_data times 16 db 0
device_list times 26*5 db 0
dta times 128 db 0
memory_message db 'Resident bytes: $'
high_message db 'The driver is in upper memory.',13,10,'$'
pass_message db 13,10,'The packet tests passed.',13,10,'$'
fail_message db 'Packet test failed: $'
program_end:
