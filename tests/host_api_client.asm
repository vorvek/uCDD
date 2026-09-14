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
    pushf
    pop ax
    or ax, 4000h
    push ax
    popf
    mov ax, 1
    call far [host]
    jc fail16
    pushf
    pop ax
    test ax, 4000h
    jnz fail16
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
    mov byte [stage], 1
    mov bx, 40h
    mov ax, 2
    int 31h
    jc fail
    mov [segment_selector], ax
    mov ebp, 600
.cache:
    mov ax, 2
    int 31h
    jc fail
    cmp ax, [segment_selector]
    jne fail
    dec ebp
    jnz .cache
    mov bx, ax
    mov ax, 1
    int 31h
    jnc fail
    mov ax, 7
    xor cx, cx
    xor dx, dx
    int 31h
    jnc fail
    mov byte [stage], 2
    mov bx, 16
    mov ax, 0100h
    int 31h
    jc fail
    mov [dos_selector], dx
    mov bx, dx
    mov ax, 000ah
    int 31h
    jc fail
    mov [alias_selector], ax
    mov dx, ax
    mov ax, 0101h
    int 31h
    jnc fail
    cmp ax, 8022h
    jne fail
    mov bx, [dos_selector]
    mov ax, 1
    int 31h
    jnc fail
    mov dx, [dos_selector]
    mov bx, 32
    mov ax, 0102h
    int 31h
    jc fail
    mov ax, 0101h
    int 31h
    jc fail
    mov bx, [alias_selector]
    mov ax, 1
    int 31h
    jc fail
    mov byte [stage], 3
    mov bx, ds
    mov ax, 0006h
    int 31h
    jc fail
    shl ecx, 16
    mov cx, dx
    add ecx, buffer
    mov [buffer_linear], ecx
    mov cx, 1
    xor ax, ax
    int 31h
    jc fail
    mov [buffer_selector], ax
    mov bx, ax
    mov ecx, [buffer_linear]
    mov dx, cx
    shr ecx, 16
    mov ax, 7
    int 31h
    jc fail
    xor cx, cx
    mov dx, 47
    mov ax, 8
    int 31h
    jc fail
    mov es, bx
    xor edi, edi
    mov ax, 0500h
    int 31h
    jc fail
    inc edi
    mov ax, 0500h
    int 31h
    jnc fail
    cmp ax, 8021h
    jne fail
    mov cx, 0f0h
    mov ax, 9
    int 31h
    jc fail
    xor edi, edi
    mov ax, 0500h
    int 31h
    jnc fail
    cmp ax, 8022h
    jne fail
    mov cx, 0f2h
    mov ax, 9
    int 31h
    jc fail
    mov cx, 0ffffh
    mov dx, 0fff0h
    mov ax, 7
    int 31h
    jc fail
    xor edi, edi
    mov ax, 0500h
    int 31h
    jnc fail
    mov cx, 40h
    xor dx, dx
    mov ax, 7
    int 31h
    jc fail
    mov ax, 0500h
    int 31h
    jnc fail
    mov byte [stage], 4
    push ds
    push es
    pop ds
    mov ax, 3000h
    int 21h
    pop ds
    jc fail
    test al, al
    jz fail
    xor eax, eax
    inc eax
    mov ah, 1
    int 16h
    jnz fail
    push ds
    pop es
    mov bx, [buffer_selector]
    mov ax, 1
    int 31h
    jc fail
    mov byte [stage], 5
    xor bx, bx
    mov cx, 4096
    mov ax, 0501h
    int 31h
    jc fail
    mov [memory_handle], di
    mov [memory_handle+2], si
    mov ax, 0502h
    int 31h
    jc fail
    mov bx, 10h
    xor cx, cx
    xor si, si
    mov di, 4096
    mov ax, 0800h
    int 31h
    jc fail
    mov [mapping], cx
    mov [mapping+2], bx
    mov eax, [memory_handle]
    inc eax
    mov di, ax
    shr eax, 16
    mov si, ax
    xor bx, bx
    mov cx, 8192
    mov ax, 0503h
    int 31h
    jnc fail
    cmp ax, 8023h
    jne fail
    mov ax, 0502h
    int 31h
    jnc fail
    mov bx, [mapping+2]
    mov cx, [mapping]
    mov ax, 0801h
    int 31h
    jc fail
    mov ax, 0801h
    int 31h
    jnc fail
    mov byte [stage], 6
    mov ebp, 256
    mov edi, handles
.allocate:
    push edi
    xor bx, bx
    mov cx, 4096
    mov ax, 0501h
    int 31h
    jc fail
    mov eax, esi
    shl eax, 16
    mov ax, di
    pop edi
    mov [edi], eax
    add edi, 4
    dec ebp
    jnz .allocate
    xor bx, bx
    mov cx, 4096
    mov ax, 0501h
    int 31h
    jnc fail
    cmp ax, 8012h
    jne fail
    mov edi, buffer
    mov ax, 0500h
    int 31h
    jc fail
    cmp dword [buffer], 0
    jne fail
    mov ebp, 256
    mov ebx, handles
.free:
    mov di, [ebx]
    mov si, [ebx+2]
    mov ax, 0502h
    int 31h
    jc fail
    add ebx, 4
    dec ebp
    jnz .free
    mov byte [stage], 7
    mov bx, 0fc0h
    xor cx, cx
    mov ax, 0501h
    int 31h
    jnc fail
    mov byte [stage], 8
    xor bx, bx
    mov cx, 4096
    mov ax, 0501h
    int 31h
    jc fail
    mov [memory_handle], di
    mov [memory_handle+2], si
    mov dx, cx
    mov cx, bx
    push ecx
    push edx
    mov cx, 1
    xor ax, ax
    int 31h
    jc fail
    mov bx, ax
    mov [buffer_selector], ax
    pop edx
    pop ecx
    mov ax, 7
    int 31h
    jc fail
    xor cx, cx
    mov dx, 8191
    mov ax, 8
    int 31h
    jc fail
    mov es, bx
    mov byte [es:4095], 5ah
    mov edi, 4080
    mov ax, 0500h
    int 31h
    jnc fail
    push ds
    pop es
    mov di, [memory_handle]
    mov si, [memory_handle+2]
    xor bx, bx
    mov cx, 8192
    mov ax, 0503h
    int 31h
    jc fail
    mov [memory_handle], di
    mov [memory_handle+2], si
    mov dx, cx
    mov cx, bx
    mov bx, [buffer_selector]
    mov ax, 7
    int 31h
    jc fail
    mov es, bx
    cmp byte [es:4095], 5ah
    jne fail
    mov byte [es:8191], 0a5h
    push ds
    pop es
    mov di, [memory_handle]
    mov si, [memory_handle+2]
    mov ax, 0502h
    int 31h
    jc fail
    mov bx, [buffer_selector]
    mov ax, 1
    int 31h
    jc fail
    mov byte [stage], 9
    mov dx, 0beefh
    mov bx, 16
    mov ah, 48h
    int 21h
    jc fail
    cmp dx, 0beefh
    jne fail
    mov es, ax
    mov dx, 0abcdh
    mov bx, 32
    mov ah, 4ah
    int 21h
    jc fail
    cmp dx, 0abcdh
    jne fail
    mov ah, 49h
    int 21h
    jc fail
    cmp dx, 0abcdh
    jne fail
    push ds
    pop es
    mov dx, 4321h
    mov ah, 49h
    int 21h
    jnc fail
    cmp dx, 4321h
    jne fail
    mov byte [stage], 10
    mov word [callback_regs+28], 4c0fh
    mov edi, callback_regs
    mov bx, 21h
    xor cx, cx
    mov ax, 0300h
    int 31h
    jnc fail
    cmp ax, 8021h
    jne fail
    mov byte [stage], 11
    mov bx, 31h
    mov ax, 0204h
    int 31h
    jc fail
    mov [chain_vector], edx
    mov [chain_vector+4], cx
    mov ax, 0400h
    stc
    pushfd
    call far [chain_vector]
    jc fail
    mov ax, 0ffffh
    clc
    pushfd
    call far [chain_vector]
    jnc fail
    cmp ax, 8001h
    jne fail
    mov bx, 16h
    mov ax, 0204h
    int 31h
    jc fail
    mov [chain_vector], edx
    mov [chain_vector+4], cx
    mov ax, 1
    or ax, ax
    mov ah, 1
    pushfd
    call far [chain_vector]
    jnz fail
%ifdef LEAK_VECTORS
    mov bx, 16
    mov ax, 0100h
    int 31h
    jc fail
    mov cx, ax
    xor dx, dx
    mov bx, 60h
    mov ax, 0201h
    int 31h
    jc fail
    push ds
    push cs
    pop ds
    mov esi, callback
    mov edi, callback_regs
    mov ax, 0303h
    int 31h
    pop ds
    jc fail
    mov bx, 61h
    mov ax, 0201h
    int 31h
    jc fail
    xor cx, cx
    mov dx, 500h
    mov bx, 62h
    mov ax, 0201h
    int 31h
    jc fail
    mov bx, ds
    mov ax, 0006h
    int 31h
    jc fail
    shl ecx, 16
    mov cx, dx
    shr ecx, 4
    mov dx, callback
    mov bx, 63h
    mov ax, 0201h
    int 31h
    jc fail
    mov word [callback_regs+28], 4800h
    mov word [callback_regs+16], 16
    mov edi, callback_regs
    mov bx, 21h
    xor cx, cx
    mov ax, 0300h
    int 31h
    jc fail
    test byte [callback_regs+32], 1
    jnz fail
    mov cx, [callback_regs+28]
    xor dx, dx
    mov bx, 64h
    mov ax, 0201h
    int 31h
    jc fail
%ifdef FAULT_EXIT
    ud2
%endif
%endif
    mov ax, 4c00h
    int 21h
fail:
    mov al, [stage]
    mov ah, 4ch
    int 21h
callback:
    iretd
host dd 0
chain_vector dd 0
    dw 0
entry dd client
    dw 0
stage db 0
segment_selector dw 0
dos_selector dw 0
alias_selector dw 0
buffer_selector dw 0
buffer_linear dd 0
memory_handle dd 0
mapping dd 0
buffer times 48 db 0
handles times 256 dd 0
callback_regs times 50 db 0
program_end:
