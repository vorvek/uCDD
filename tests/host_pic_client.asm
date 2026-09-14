; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h
    mov sp, program_end+512
    mov bx, (program_end-$$+100h+512+15)/16
    mov ah, 4ah
    int 21h
    jc fail16
    mov ax, 1687h
    int 2fh
    test ax, ax
    jnz fail16
    mov [host], di
    mov [host+2], es
    mov ax, 1
    call far [host]
    jc fail16
    mov bx, cs
    mov ax, 000ah
    int 31h
    jc fail16
    mov [entry+4], ax
    mov bx, ax
    mov cx, 40fah
    mov ax, 0009h
    int 31h
    jc fail16
    jmp dword far [entry]
fail16:
    mov ax, 4c7fh
    int 21h
bits 32
client:
%ifdef LOCKED_NESTING
    mov [client_ds], ds
    call setup_callback
%endif
    mov ax, 0400h
    int 31h
    jc fail
    mov [timer_vector], dh
    movzx ebx, dh
    mov ax, 0204h
    int 31h
    jc fail
    mov [previous], edx
    mov [previous+4], cx
    mov ax, 0900h
    int 31h
    movzx ebx, byte [timer_vector]
    mov cx, cs
    mov edx, timer
    mov ax, 0205h
    int 31h
    jc fail
    mov ecx, 1500000
.wait:
    loop .wait
    cmp dword [timer_count], 0
    jne fail
    mov al, 0ah
    out 20h, al
    in al, 20h
    test al, 1
    jz fail
    mov ax, 0901h
    int 31h
    cmp dword [timer_count], 0
    je fail
    cmp byte [bad_isr], 0
    jne fail
    mov ax, 0900h
    int 31h
    movzx ebx, byte [timer_vector]
    mov cx, [previous+4]
    mov edx, [previous]
    mov ax, 0205h
    int 31h
    jc fail
    mov ax, 0901h
    int 31h
%ifdef LOCKED_NESTING
    cmp byte [nested_done], 1
    jne fail
    mov cx, [callback_address+2]
    mov dx, [callback_address]
    mov ax, 0304h
    int 31h
    jc fail
%endif
    mov ax, 4c00h
    int 21h
fail:
    mov ax, 4c01h
    int 21h
timer:
%ifdef BAD_IRQ_CODE
    mov dword [ss:esp+16], 10h
%endif
%ifdef BAD_IRQ_STACK
    mov dword [ss:esp+28], 10h
%endif
%ifdef BAD_IRQ_CURSOR
    mov dword [ss:esp+32], 4095
%endif
%ifdef LOCKED_NESTING
    jmp locked_timer
%endif
    push eax
    inc dword [timer_count]
    mov al, 0bh
    out 20h, al
    in al, 20h
    test al, 1
    jnz .eoi
    mov byte [bad_isr], 1
.eoi:
    mov al, 20h
    out 20h, al
    in al, 20h
    test al, 1
    jz .done
    mov byte [bad_isr], 1
.done:
    mov al, 0ah
    out 20h, al
    pop eax
    iretd
%ifdef LOCKED_NESTING
setup_callback:
    push ds
    pop es
    push ds
    push cs
    pop ds
    mov esi, nested_callback
    mov edi, callback_regs
    mov ax, 0303h
    int 31h
    pop ds
    jc fail
    mov [callback_address], dx
    mov [callback_address+2], cx
    mov bx, ds
    mov ax, 0006h
    int 31h
    jc fail
    shl ecx, 16
    mov cx, dx
    shr ecx, 4
    mov [real_regs+44], cx
    mov [real_regs+36], cx
    mov word [real_regs+42], real_callback
    ret
locked_timer:
    pushad
    push ds
    mov ds, [cs:client_ds]
    inc dword [timer_count]
    mov ax, ss
    lsl eax, eax
    jnz .bad
    cmp eax, 4095
    jne .bad
    pushfd
    pop eax
    test eax, 100h
    jnz .bad
    mov ax, 0902h
    int 31h
    test al, al
    jnz .bad
    cmp byte [nested_started], 0
    jne .leaf
    mov byte [nested_started], 1
    sub esp, 2048
    mov dword [ss:esp], 1234abcch
    mov al, 20h
    out 20h, al
    push es
    push ds
    pop es
    mov edi, real_regs
    xor cx, cx
    mov ax, 0301h
    int 31h
    pop es
    jnc .canary
    mov byte [bad_isr], 1
.canary:
    cmp dword [ss:esp], 1234abcch
    je .restore
    mov byte [bad_isr], 1
.restore:
    add esp, 2048
    mov byte [nested_done], 1
    jmp .done
.bad:
    mov byte [bad_isr], 1
.leaf:
    mov al, 20h
    out 20h, al
.done:
    pop ds
    popad
    iretd
nested_callback:
    mov eax, [esi]
    mov [es:edi+42], eax
    add word [es:edi+46], 4
    sub esp, 3072
    mov dword [ss:esp], 5678abcch
    sti
    mov ecx, 3000000
.wait:
    cmp dword [es:timer_count], 2
    jae .returned
    loop .wait
    mov byte [es:bad_isr], 1
.returned:
    cli
    cmp dword [ss:esp], 5678abcch
    je .stack_ok
    mov byte [es:bad_isr], 1
.stack_ok:
    add esp, 3072
    iretd
bits 16
real_callback:
    call far [cs:callback_address]
    retf
bits 32
client_ds dw 0
nested_started db 0
nested_done db 0
callback_address dd 0
callback_regs times 50 db 0
real_regs times 50 db 0
%endif
host dd 0
entry dd client
    dw 0
previous dd 0
    dw 0
timer_count dd 0
timer_vector db 8
bad_isr db 0
program_end:
