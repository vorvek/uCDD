; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

HOST_SCRATCH
host_v86_prepare:
    pushf
    pushad
    push es
    cmp byte [cs:resident_irq_slot], 1
    jne .done
    ; CDF4 and CDF5 differ in one bit.
    mov eax, [ds:bp+8]
    and eax, 0feffffffh
    cmp eax, 34464443h
    jne .done
.fields:
    mov si, [ds:bp+22]
    mov ax, [si]
    cmp ax, 5605h
    je .version
    cmp ax, 5705h
    jne .done
.version:
    mov [cs:host_v86_version], ax
    mov si, [ds:bp+20]
    push cs
    pop es
    mov di, host_v86_info
    mov cx, 14
    cld
    rep movsw
    mov byte [cs:host_v86_ready], 1
.done:
    pop es
    popad
    popf
    ret

host_v86_install:
    cmp byte [host_v86_ready], 1
    jne .done
    push ds
    push es
    pushad
    movzx eax, word [host_gateway_segment]
    shl eax, 4
    mov [host_v86_gateway], eax
    xor edi, edi
    mov di, cs
    shl edi, 4
    mov eax, cr3
    mov [host_v86_switch], eax
    lea eax, [edi+host_v86_info+12]
    mov [host_v86_switch+4], eax
    lea eax, [edi+host_v86_info+18]
    mov [host_v86_switch+8], eax
    mov ax, [host_v86_info+24]
    mov [host_v86_switch+14], ax
    lea eax, [edi+host_v86_install_pm]
    mov [host_v86_switch+16], eax
    mov ax, [host_v86_info+26]
    mov [host_v86_switch+20], ax
    mov [host_v86_return+4], cs
    mov [host_v86_return+16], ss
    mov [host_v86_return+20], es
    mov [host_v86_return+24], ds
    mov [host_v86_return+28], fs
    mov [host_v86_return+32], gs
    mov [host_v86_return+12], sp
    lea esi, [edi+host_v86_switch]
    mov ax, 0de0ch
    int 67h
.return:
    sti
    popad
    pop es
    pop ds
.done:
    ret

bits 32
host_v86_install_pm:
    cli
    mov ax, cs
    add ax, 8
    mov ds, ax
    mov es, ax
    mov ss, ax
    lea esp, [edi+host_v86_stack_top]
    mov ebx, edi
    mov esi, [ebx+host_v86_info]
    test esi, esi
    jz .return
    lea edx, [esi+60]
    cmp word [ebx+host_v86_version], 5705h
    je .slot
    lea edx, [esi+68]
.slot:
    cmp dword [edx], 0
    je .return
    mov ecx, [ebx+host_v86_gateway]
    lea eax, [ecx+resident_v86_fault]
    xchg eax, [edx]
    mov [ecx+resident_v86_previous], eax
    mov [ecx+resident_v86_slot], edx
.return:
    lea esp, [ebx+host_v86_return]
    iretd
bits 16
host_v86_ready db 0
host_v86_version dw 0
host_v86_info times 28 db 0
host_v86_gateway dd 0
host_v86_switch times 22 db 0
host_v86_return dd host_v86_install.return,0,23002h,0,0,0,0,0,0
    times 128 db 0
host_v86_stack_top:

HOST_REAL
resident_v86_previous dd 0
resident_v86_slot dd 0
resident_v86_clts_count dd 0
bits 32
resident_v86_fault:
    ; Jemm supplies EAX=exception and EBP=V86 frame.
    push dword 0
    pushfd
    pushad
    call .base
.base:
    pop ebx
    sub ebx, .base
    cmp eax, 0dh
    jne .chain
    cmp dword [ebp+36], 0
    jne .chain
    test dword [ebp+48], 20000h
    jz .chain
    mov eax, cr0
    test al, 8
    jnz .chain
    movzx eax, word [ebp+44]
    shl eax, 4
    mov edx, [ebp+40]
    cmp edx, 0fffeh
    ja .chain
    add eax, edx
    cmp word [eax], 060fh
    jne .chain
    add word [ebp+40], 2
    inc dword [ebx+resident_v86_clts_count]
    popad
    popfd
    lea esp, [esp+4]
    ret
.chain:
    mov eax, [ebx+resident_v86_previous]
    mov [esp+36], eax
    popad
    popfd
    ret
bits 16
