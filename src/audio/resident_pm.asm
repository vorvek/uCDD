; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
%define VIRTUAL_IRQ 1
%define BRIDGE_LAUNCHER 1
pm_abort_entry dw audio_abort,0
pm_host dd 0
pm_pm_entry dd pm_protected_start
    dw 0
pm_data_selector dw 0
pm_parent_port dd 0
pm_parent_irq dd 0
pm_parent_take dd 0
pm_irq_number db 0
pm_stage db '0'
pm_vendor db 'HDPMI',0
pm_vendor_entry dd 0
    dw 0
pm_old_route dd 0,0,0
pm_route_set db 0
pm_trap_count dd 0
pm_port_calls dd 0
pm_owned_irqs dd 0
pm_bridge_fault db 0
pm_cleanup_fault db 0
pm_trap_ports:
%define PORT_RANGES 1
%include "audio/ports.inc"
%undef PORT_RANGES
pm_port_count equ ($-pm_trap_ports)/4
%if pm_port_count > 16
%error The HDPMI port range limit is 16.
%endif
pm_trap_handles times pm_port_count dd 0
pm_port_regs times 50 db 0
pm_irq_regs times 50 db 0
pm_game_vector dd 0
    dw 0
pm_failure db 'The audio setup failed at step '
pm_failure_stage db '0',13,10,'$'
audio_enter_pm:
    cld
    mov sp, pm_stack_top
    mov [pm_abort_entry+2], cs
    mov word [pm_parent_port], port_callback
    mov [pm_parent_port+2], cs
    mov word [pm_parent_irq], audio_irq
    mov [pm_parent_irq+2], cs
    mov word [pm_parent_take], virtual_irq_take
    mov [pm_parent_take+2], cs
    mov al, [sb_irq]
    mov [pm_irq_number], al
    mov byte [pm_stage], 'C'
    mov ax, 1687h
    int 2fh
    test ax, ax
    jnz pm_failed_real
    test bl, 1
    jz pm_failed_real
    mov [pm_host], di
    mov [pm_host+2], es
    test si, si
    jz .enter
    mov bx, si
    mov ah, 48h
    int 21h
    jc pm_failed_real
    mov es, ax
.enter:
    mov byte [pm_stage], 'D'
    mov ax, 1
    call far [pm_host]
    jc pm_failed_real
    mov byte [pm_stage], 'E'
    mov [pm_data_selector], ds
    mov bx, cs
    mov ax, 000ah
    int 31h
    jc pm_failed_16
    mov [pm_pm_entry+4], ax
    mov byte [pm_stage], 'F'
    mov bx, ax
    mov cx, 40fbh
    mov ax, 0009h
    int 31h
    jc pm_failed_16
    jmp dword far [pm_pm_entry]
pm_failed_16:
    mov al, [pm_stage]
    mov [pm_failure_stage], al
    mov eax, [pm_abort_entry]
    mov [pm_tsr_regs+42], eax
    mov word [pm_tsr_regs+32], 2
    mov edi, pm_tsr_regs
    push ds
    pop es
    xor bx, bx
    xor cx, cx
    mov ax, 0301h
    int 31h
    mov edx, pm_failure
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
pm_failed_real:
    mov al, [pm_stage]
    mov [pm_failure_stage], al
    call far [pm_abort_entry]
    mov dx, pm_failure
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
bits 32
pm_protected_start:
    movzx esp, sp
    mov byte [pm_stage], '1'
    mov esi, pm_vendor
    mov ax, 168ah
    int 2fh
    test al, al
    jnz pm_failed
    mov [pm_vendor_entry], edi
    mov [pm_vendor_entry+4], es
    push ds
    pop es
    mov byte [pm_stage], '3'
    xor ebp, ebp
.trap:
    movzx esi, word [pm_trap_ports+ebp*4]
    movzx edi, word [pm_trap_ports+ebp*4+2]
    mov cx, cs
    mov bx, ds
    mov edx, pm_port_bridge
    mov eax, 6
    call far [pm_vendor_entry]
    jc pm_failed
    mov [pm_trap_handles+ebp*4], eax
    inc dword [pm_trap_count]
    inc ebp
    cmp ebp, pm_port_count
    jb .trap

    mov byte [pm_stage], '4'
    movzx esi, byte [pm_irq_number]
    mov eax, 0dh
    call far [pm_vendor_entry]
    jc pm_failed
    mov [pm_old_route], ecx
    mov [pm_old_route+4], edx
    mov [pm_old_route+8], ebx
%ifdef NO_ROUTE
    xor ecx, ecx
    xor edx, edx
    xor ebx, ebx
%else
    mov ecx, cs
    mov edx, pm_irq_bridge
    mov ebx, [pm_parent_irq]
%endif
    mov eax, 0bh
    call far [pm_vendor_entry]
    jc pm_failed
    mov byte [pm_route_set], 1

    mov edx, installed_message
    mov ah, 9
    int 21h
    mov word [pm_tsr_regs+28], 3100h
    mov ax, [resident_paragraphs]
    mov [pm_tsr_regs+20], ax
    mov edi, pm_tsr_regs
    push ds
    pop es
    mov ax, 0300h
    mov bx, 21h
    xor cx, cx
    int 31h
    jmp pm_failed

pm_failed:
    mov al, [pm_stage]
    mov [pm_failure_stage], al
    call pm_cleanup
    mov eax, [pm_abort_entry]
    mov [pm_tsr_regs+42], eax
    mov dword [pm_tsr_regs+46], 0
    mov word [pm_tsr_regs+32], 2
    mov edi, pm_tsr_regs
    push ds
    pop es
    xor bx, bx
    xor cx, cx
    mov ax, 0301h
    int 31h
    mov edx, pm_failure
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
pm_cleanup:
    pushfd
    cli
.route:
    cmp byte [pm_route_set], 0
    je .traps
    movzx esi, byte [pm_irq_number]
    mov ecx, [pm_old_route]
    mov edx, [pm_old_route+4]
    mov ebx, [pm_old_route+8]
    mov eax, 0bh
    call far [pm_vendor_entry]
    jnc .route_done
    mov byte [pm_cleanup_fault], 1
.route_done:
    mov byte [pm_route_set], 0
.traps:
    cmp dword [pm_trap_count], 0
    je .done
    dec dword [pm_trap_count]
    mov ebp, [pm_trap_count]
    mov edx, [pm_trap_handles+ebp*4]
    mov eax, 7
    call far [pm_vendor_entry]
    jnc .traps
    mov byte [pm_cleanup_fault], 1
    jmp .traps
.done:
    popfd
    ret


; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%define port_bridge pm_port_bridge
%define irq_bridge pm_irq_bridge
%define data_selector pm_data_selector
%define parent_port pm_parent_port
%define parent_irq pm_parent_irq
%define parent_take pm_parent_take
%define port_regs pm_port_regs
%define irq_regs pm_irq_regs
%define port_calls pm_port_calls
%define owned_irqs pm_owned_irqs
%define bridge_fault pm_bridge_fault
%define game_vector pm_game_vector
%include "audio/pm_bridge.inc"
%undef port_bridge
%undef irq_bridge
%undef data_selector
%undef parent_port
%undef parent_irq
%undef parent_take
%undef port_regs
%undef irq_regs
%undef port_calls
%undef owned_irqs
%undef bridge_fault
%undef game_vector

bits 16
pm_tsr_regs times 50 db 0
times 2048 db 0
pm_stack_top:
