; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 0
%define HOST_DPMI 1
%define VIRTUAL_IRQ 1
%define WSS_INPUT 1
    jmp resident_host_init
    db 'uCDH'
resident_host_init:
    push ds
    push es
    pushad
    mov [cs:dpmi_audio_irq], al
    mov [cs:resident_port], bx
    mov [cs:resident_port+2], ds
    mov [cs:resident_take], dx
    mov [cs:resident_take+2], ds
    movzx eax, si
    movzx ecx, word [cs:resident_take+2]
    shl ecx, 4
    add eax, ecx
    mov [cs:resident_wss_event], eax
    push cs
    pop ds
    call dpmi_install
    jc .bad
    mov eax, [mon_base]
    add eax, resident_io
    mov [mon_callback], eax
    mov ax, resident_pending
    call monitor_irq_callback
    mov si, resident_ports
    mov di, resident_port_count
.port:
    lodsw
    mov dx, ax
    mov cx, 1
    call monitor_trap
    dec di
    jnz .port
    popad
    pop es
    pop ds
    clc
    retf
.bad:
    popad
    pop es
    pop ds
    stc
    retf

resident_port dd 0
resident_take dd 0
resident_wss_event dd 0
resident_ports:
%include "audio/ports.inc"
resident_port_count equ ($-resident_ports)/2

bits 32
resident_pending:
    mov esi, [ebp+resident_wss_event]
    movzx eax, word [esi]
    cmp eax, 16
    jae .sb
    mov word [esi], 0ffffh
    bts [ebp+dpmi_pending_irqs], eax
.sb:
    call dpmi_pic_audio_allowed
    jc .none
    cmp byte [ebp+dpmi_vif], 1
    jne .none
    test byte [esp+4+52], 3
    jz .none
    lea edi, [ebp+mon_rm_regs]
    mov dword [edi+46], 0
    mov word [edi+32], 2
    mov eax, [ebp+resident_take]
    mov [edi+42], eax
    mov al, 1
    call mon_real_far
    cmp word [edi+28], 1
    jne .none
    mov eax, 0eh
    ret
.none:
    xor eax, eax
    ret
resident_io:
    cmp cl, 1
    jne .bad
    lea edi, [ebp+mon_rm_regs]
    mov [edi+28], eax
    mov [edi+20], edx
    movzx ecx, ch
    shl ecx, 2
    mov [edi+24], ecx
    mov dword [edi+46], 0
    mov word [edi+32], 2
    mov eax, [ebp+resident_port]
    mov [edi+42], eax
    mov al, 1
    call mon_real_far
    mov eax, [edi+28]
    clc
    ret
.bad:
    stc
    ret

%include "host/monitor.asm"
