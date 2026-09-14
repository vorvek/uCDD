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
%ifdef SHARED_IRQ5
    xor ax, ax
    mov es, ax
    mov eax, [es:0dh*4]
    mov [physical_vector], eax
    mov [rm_segment], cs
%endif
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
    mov bx, 10
.fill:
    mov al, 192
    cmp bx, 5
    ja .sample
    mov al, 64
.sample:
    stosb
    dec bx
    jnz .next_sample
    mov bx, 10
.next_sample:
    loop .fill
    push ds
    pop es
    mov bx, cd_packet
    mov cx, 5
    mov ax, 1510h
    int 2fh
    test word [cd_packet+3], 8000h
    jnz fail_real
%ifdef REAL_CLIENT
    jmp protected_start
%endif
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
%ifndef REAL_CLIENT
bits 32
%endif
protected_start:
    movzx esp, sp
    mov [data_selector], ds
    mov byte [stage], '2'
%ifdef REAL_CLIENT
    mov ax, 40h
%else
    mov bx, 40h
    mov ax, 0002h
    int 31h
    jc fail
%endif
    mov fs, ax
%ifdef SHARED_IRQ5
%ifndef REAL_CLIENT
    xor bx, bx
    mov ax, 0002h
    int 31h
    jc fail
    mov gs, ax
    mov bl, 0dh
    mov ax, 0200h
    int 31h
    jc fail
    mov [logical_vector], dx
    mov [logical_vector+2], cx
    mov cx, 1234h
    mov dx, 5678h
    mov ax, 0201h
    int 31h
    jc fail
    mov ax, 0200h
    int 31h
    cmp cx, 1234h
    jne fail
    cmp dx, 5678h
    jne fail
    mov eax, [gs:0dh*4]
    cmp eax, [physical_vector]
    jne fail
    mov cx, [logical_vector+2]
    mov dx, [logical_vector]
    mov ax, 0201h
    int 31h
    jc fail
%endif
%endif
%ifdef REAL_CLIENT
    mov ax, 350dh
    int 21h
    mov [old_irq], bx
    mov [old_irq+4], es
    mov dx, irq
    mov ax, 250dh
    int 21h
%ifdef SHARED_IRQ5
    xor ax, ax
    mov es, ax
    mov eax, [es:0dh*4]
    cmp eax, [physical_vector]
    jne fail
%endif
%else
    mov bl, 0dh
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
%endif
    in al, 21h
    mov [master_mask], al
    and al, 0dfh
    out 21h, al
    sti
    mov cx, 18
    call wait_ticks
    mov dx, 22ch
    mov al, 40h
    out dx, al
    mov al, 156
    out dx, al
    mov al, 0d1h
    out dx, al
    mov byte [stage], '3'
    mov byte [rearm], 1
    call start_block
    mov cx, 36
    call wait_ticks
    cmp word [irq_count], 15
    jb cleanup_fail
    mov byte [rearm], 0
    mov cx, 4
    call wait_ticks
    mov bx, [irq_count]
    mov byte [stage], '4'
    mov cx, 18
    call wait_ticks
    cmp bx, [irq_count]
    jne cleanup_fail
    mov byte [rearm], 1
    call start_block
    mov cx, 18
    call wait_ticks
    cmp bx, [irq_count]
    jae cleanup_fail
    mov byte [result], 0
cleanup_fail:
    mov byte [rearm], 0
    mov dx, 226h
    mov al, 1
    out dx, al
    xor al, al
    out dx, al
    mov al, [master_mask]
    out 21h, al
%ifdef REAL_CLIENT
    push ds
    mov dx, [old_irq]
    mov ds, [old_irq+4]
    mov ax, 250dh
    int 21h
    pop ds
%else
    mov bl, 0dh
    mov edx, [old_irq]
    mov cx, [old_irq+4]
    mov ax, 0205h
    int 31h
%endif
    cmp byte [result], 0
    jne fail
%ifdef SHARED_IRQ5
%ifndef REAL_CLIENT
    mov bl, 0dh
    mov cx, [rm_segment]
    mov dx, rm_stub
    mov ax, 0201h
    int 31h
    jc fail
%endif
%endif
    mov ax, 4c00h
    int 21h
fail:
    mov dx, failure
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
wait_ticks:
    mov ax, [fs:6ch]
.wait:
    mov dx, [fs:6ch]
    sub dx, ax
    cmp dx, cx
    jb .wait
    ret
start_block:
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
    mov al, 0e7h
    out 3, al
    mov al, 3
    out 3, al
    mov al, 49h
    out 0bh, al
    mov al, 1
    out 0ah, al
    mov dx, 22ch
    mov al, 14h
    out dx, al
    mov al, 0e7h
    out dx, al
    mov al, 3
    out dx, al
    ret
irq:
    pushad
    push ds
    mov ds, [cs:data_selector]
    inc word [irq_count]
    mov dx, 22eh
    in al, dx
    cmp byte [rearm], 0
    je .eoi
    call start_block
.eoi:
    mov al, 20h
    out 20h, al
    pop ds
    popad
%ifdef REAL_CLIENT
    iret
%else
    iretd
%endif
pm_entry dd protected_start
    dw 0
host dd 0
physical_vector dd 0
logical_vector dd 0
rm_segment dw 0
rm_stub: iret
dma_address dd 0
data_selector dw 0
old_irq dd 0
    dw 0
irq_count dw 0
master_mask db 0
rearm db 0
result db 1
cd_packet db 22,0,84h
    dw 0
    times 8 db 0
    db 0
    dd 22,600
failure db 'The legacy SB interrupt test failed. Step '
stage db '1',13,10,'$'
program_end:
