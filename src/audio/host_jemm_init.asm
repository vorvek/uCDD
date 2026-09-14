; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
host_jemm_install:
    cld
    xor ax, ax
    mov es, ax
    xor di, di
    mov ax, 1684h
    mov bx, 4354h
    int 2fh
    mov ax, es
    or ax, di
    jz .provider_ready
    mov word [audio_error_text], port_trap_rejected_message
    jmp host_fail
.provider_ready:
    mov dx, host_device
    mov ax, 3d00h
    int 21h
    jnc .opened
    mov dx, host_device_noems
    mov ax, 3d00h
    int 21h
    jc host_fail
.opened:
    mov bx, ax
    mov dx, host_info
    mov cx, 2
    mov ax, 4402h
    int 21h
    jc .close_bad
    cmp ax, 2
    jne .close_bad
    cmp word [host_info], 5605h
    jne .close_bad
    mov byte [host_info], 8
    mov dx, host_info
    mov cx, 28
    mov ax, 4402h
    int 21h
    jc .close_bad
    cmp ax, 28
    jne .close_bad
    mov ah, 3eh
    int 21h
    xor eax, eax
    mov ax, cs
    shl eax, 4
    mov [host_linear_base], eax
    mov edi, eax
    mov eax, cr3
    mov [host_switch], eax
    lea eax, [edi+host_info+12]
    mov [host_switch+4], eax
    lea eax, [edi+host_info+18]
    mov [host_switch+8], eax
    mov ax, [host_info+24]
    mov [host_switch+14], ax
    lea eax, [edi+host_protected_install]
    mov [host_switch+16], eax
    mov ax, [host_info+26]
    mov [host_switch+20], ax
    mov [host_return_frame+4], cs
    mov [host_return_frame+16], ss
    mov [host_return_frame+20], es
    mov [host_return_frame+24], ds
    mov [host_return_frame+28], fs
    mov [host_return_frame+32], gs
    mov [host_return_frame+12], sp
    lea esi, [edi+host_switch]
    mov ax, 0de0ch
    int 67h
.return:
    sti
    mov ax, 352fh
    int 21h
    mov [host_old_mux], bx
    mov [host_old_mux+2], es
    mov dx, host_mux
    mov ax, 252fh
    int 21h
    mov byte [host_installed], 1
    mov byte [host_backend], 1
    clc
    ret
.close_bad:
    mov word [audio_error_text], port_trap_rejected_message
    mov ah, 3eh
    int 21h
host_fail:
    stc
    ret
bits 32
host_protected_install:
    mov ax, cs
    add ax, 8
    mov ds, ax
    mov es, ax
    mov ss, ax
    lea esp, [edi+host_init_stack_top]
    mov ebx, edi
    mov esi, [ebx+host_info]
    mov [ebx+host_services], esi
    mov edx, [esi+48]
    lea eax, [ebx+host_io]
    xchg eax, [edx]
    mov [ebx+host_old_io], eax
    mov edx, [ebx+host_info+4]
    lea eax, [edx+4]
    mov [ebx+host_gate_slot], eax
    lea eax, [ebx+host_gate]
    xchg eax, [edx+4]
    mov [ebx+host_old_gate], eax
    mov eax, [ebx+host_info+8]
    inc ax
    mov [ebx+host_api_entry], eax
    movzx edx, word [ebx+host_info+24]
    and dl, 0f8h
    add edx, [ebx+host_info+14]
    movzx eax, word [edx+2]
    movzx ecx, byte [edx+4]
    shl ecx, 16
    or eax, ecx
    movzx ecx, byte [edx+7]
    shl ecx, 24
    or eax, ecx
    movzx ecx, word [eax+66h]
    add eax, ecx
    mov [ebx+host_io_bitmap], eax
    lea esp, [ebx+host_return_frame]
    iretd
bits 16
host_linear_base dd 0
host_switch times 22 db 0
host_return_frame dd host_jemm_install.return,0,23002h,0,0,0,0,0,0
host_info db 2
    times 27 db 0
host_device db 'EMMXXXX0',0
host_device_noems db 'EMMQXXX0',0
times 512 db 0
host_init_stack_top:
