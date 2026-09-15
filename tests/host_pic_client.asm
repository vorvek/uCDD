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
    mov [client_ds], ds
%ifdef LOCKED_NESTING
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
%ifdef BRIDGE_REAL
    call bridge_test
%else
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
%endif
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
%ifdef BRIDGE_REAL
%ifdef BRIDGE_NESTED
    jmp bridge_timer
%endif
    push ds
    mov ds, [cs:client_ds]
    inc dword [timer_count]
    pushfd
    call far [previous]
    pop ds
    iretd
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
nested_started db 0
nested_done db 0
callback_address dd 0
callback_regs times 50 db 0
real_regs times 50 db 0
%endif
%ifdef BRIDGE_REAL
bridge_test:
    mov bx, ds
    mov ax, 0006h
    int 31h
    jc fail
    shl ecx, 16
    mov cx, dx
    shr ecx, 4
    mov [bridge_regs+44], cx
    mov [bridge_regs+36], cx
    mov word [bridge_regs+42], bridge_wait
    mov word [bridge_regs+32], 202h
    push ds
    pop es
%ifdef BRIDGE_NESTED
    push esi
    mov esi, bridge_regs
    mov edi, bridge_nested_regs
    mov ecx, 50
    rep movsb
    pop esi
%endif
    mov edi, bridge_regs
    xor cx, cx
    mov ax, 0301h
    int 31h
    jc fail
    cmp dword [bridge_regs+28], 0
    jne fail
    cmp dword [timer_count], 0
    jne fail
    mov ax, 0901h
    int 31h
    cmp dword [timer_count], 0
    je fail
    mov dword [timer_count], 0
    mov word [bridge_regs+32], 202h
    mov edi, bridge_regs
    xor cx, cx
    mov ax, 0301h
    int 31h
    jc fail
    cmp dword [bridge_regs+28], 0
    je fail
%ifdef BRIDGE_NESTED
    cmp byte [bridge_nested_done], 1
    jne fail
    cmp byte [bad_isr], 0
    jne fail
%endif
    ret
%ifdef BRIDGE_NESTED
bridge_timer:
    pushad
    push ds
    push es
    mov ds, [cs:client_ds]
    inc dword [timer_count]
    pushfd
    call far [previous]
    cmp byte [bridge_real_active], 1
    jne .done
    cmp byte [bridge_nested_started], 0
    jne .done
    mov byte [bridge_nested_started], 1
    sub esp, 512
    mov dword [ss:esp], 0b12d9e55h
    sti
    push ds
    pop es
    mov edi, bridge_nested_regs
    xor cx, cx
    mov ax, 0301h
    int 31h
    jc .bad
    cmp dword [ss:esp], 0b12d9e55h
    je .restore
.bad:
    mov byte [bad_isr], 1
.restore:
    add esp, 512
    mov byte [bridge_nested_done], 1
.done:
    pop es
    pop ds
    popad
    iretd
bridge_nested_regs times 50 db 0
bridge_nested_started db 0
bridge_nested_done db 0
%endif
bits 16
bridge_wait:
    mov byte [cs:bridge_real_active], 1
    sti
    mov ecx, 500000
.wait:
    dec ecx
    jnz .wait
    cli
    mov byte [cs:bridge_real_active], 0
    mov eax, [cs:timer_count]
    retf
bits 32
bridge_regs times 50 db 0
bridge_real_active db 0
%endif
client_ds dw 0
host dd 0
entry dd client
    dw 0
previous dd 0
    dw 0
timer_count dd 0
timer_vector db 8
bad_isr db 0
program_end:
