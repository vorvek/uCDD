; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only
bits 16
cpu 386
org 100h
    mov sp, program_end+512
    mov bx, (program_end-$$+100h+512+15)/16
    mov ah, 4ah
    int 21h
    jc fail_real
    mov bx, 512
    mov ah, 48h
    int 21h
    jc fail_real
    add ax, 255
    and ax, 0ff00h
    mov es, ax
    movzx eax, ax
    shl eax, 4
    mov [dma_address], eax
    xor di, di
    mov cx, 2048
    mov ax, 40c0h
    rep stosw
    mov ax, 1687h
    int 2fh
    test ax, ax
    jnz fail_real
    mov [host], di
    mov [host+2], es
    mov ax, 1
    call far [host]
    jc fail_real
    mov bx, cs
    mov ax, 000ah
    int 31h
    jc fail_real
    mov [pm_entry+4], ax
    mov bx, ax
    mov cx, 40fah
    mov ax, 0009h
    int 31h
    jc fail_real
    jmp dword far [pm_entry]
fail_real:
    mov dx, failure
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
bits 32
protected_start:
    movzx esp, sp
    mov [data_selector], ds
    mov byte [stage], '2'
    mov bx, 40h
    mov ax, 0002h
    int 31h
    jc fail
    mov fs, ax
    mov bl, 73h
    mov ax, 0204h
    int 31h
    jc fail
    mov [old_irq], edx
    mov [old_irq+4], cx
    mov edx, irq
    mov cx, cs
    mov ax, 0205h
    int 31h
    jc fail
    in al, 21h
    mov byte [stage], '3'
    mov [master_mask], al
    and al, 0fbh
    out 21h, al
    in al, 0a1h
    mov [slave_mask], al
    and al, 0f7h
    out 0a1h, al
    mov al, 5
    out 0ah, al
    xor al, al
    out 0ch, al
    mov eax, [dma_address]
    out 2, al
    mov al, ah
    out 2, al
    shr eax, 16
    out 83h, al
    mov al, 0ffh
    out 3, al
    mov al, 0fh
    out 3, al
    mov al, 59h
    out 0bh, al
    mov al, 22h
    mov dx, 530h
    out dx, al
    mov ax, 1748h
    call codec
    mov ax, 0449h
    call codec
    mov ax, 000ah
    call codec
    mov ax, 0006h
    call codec
    mov ax, 0007h
    call codec
    mov ax, 0ff0fh
    call codec
    mov ax, 010eh
    call codec
    mov al, 1
    out 0ah, al
    mov ax, 0509h
    call codec
    sti
    mov byte [stage], '4'
    call wait_ticks
    cmp word [irq_count], 0
    jne cleanup_fail
    mov ax, 020ah
    mov byte [stage], '5'
    call codec
    call wait_ticks
    cmp word [irq_count], 3
    jb cleanup_fail
    in al, 0a1h
    or al, 8
    mov byte [stage], '6'
    out 0a1h, al
    mov bx, [irq_count]
    call wait_ticks
    cmp bx, [irq_count]
    jne cleanup_fail
    in al, 0a1h
    and al, 0f7h
    mov byte [stage], '7'
    out 0a1h, al
    call wait_ticks
    cmp bx, [irq_count]
    jae cleanup_fail
    mov byte [result], 0
cleanup_fail:
    mov ax, 0409h
    call codec
    mov ax, 000ah
    call codec
    mov dx, 536h
    xor al, al
    out dx, al
    mov al, [slave_mask]
    out 0a1h, al
    mov al, [master_mask]
    out 21h, al
    mov bl, 73h
    mov edx, [old_irq]
    mov cx, [old_irq+4]
    mov ax, 0205h
    int 31h
    cmp byte [result], 0
    jne fail
    mov al, [result]
    mov ah, 4ch
    int 21h
fail:
    mov dx, failure
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
codec:
    mov dx, 534h
    out dx, al
    inc dx
    mov al, ah
    out dx, al
    ret
wait_ticks:
    mov ax, [fs:6ch]
.wait:
    mov dx, [fs:6ch]
    sub dx, ax
    cmp dx, 4
    jb .wait
    ret
irq:
    push eax
    push edx
    push ds
    mov ds, [cs:data_selector]
    inc word [irq_count]
    mov dx, 536h
    xor al, al
    out dx, al
    mov al, 20h
    out 0a0h, al
    out 20h, al
    pop ds
    pop edx
    pop eax
    iretd
pm_entry dd protected_start
    dw 0
host dd 0
dma_address dd 0
data_selector dw 0
old_irq dd 0
    dw 0
irq_count dw 0
master_mask db 0
slave_mask db 0
result db 1
failure db 'The WSS interrupt test failed. Step '
stage db '1',13,10,'$'
program_end:
