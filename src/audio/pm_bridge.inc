; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; The bridge reuses the real-mode experiment; it is not a resident design.
port_bridge:
    pushad
    push es
    inc dword [port_calls]
    mov [port_regs+28], eax
    shl ecx, 2
    mov [port_regs+24], ecx
    mov [port_regs+20], edx
    mov eax, [parent_port]
    mov [port_regs+42], eax
    mov word [port_regs+32], 2
    mov dword [port_regs+46], 0
    push ds
    pop es
    mov edi, port_regs
    xor ebx, ebx
    xor ecx, ecx
    mov ax, 0301h
    int 31h
    jnc .done
    mov byte [bridge_fault], 1
.done:
    mov eax, [port_regs+28]
    mov [ss:esp+32], eax
    pop es
    popad
    retf

irq_bridge:
    pushad
    push ds
    push es
    mov ds, [cs:data_selector]
    push ds
    pop es
    inc dword [owned_irqs]
    mov eax, [parent_irq]
    mov [irq_regs+42], eax
    mov word [irq_regs+32], 2
    mov dword [irq_regs+46], 0
    mov edi, irq_regs
    xor ebx, ebx
    xor ecx, ecx
    mov ax, 0302h
    int 31h
    jc .error
%ifdef VIRTUAL_IRQ
%ifndef NO_DELIVERY
%ifndef BRIDGE_LAUNCHER
    cmp byte [virtual_vector_set], 0
    je .done
%endif
    mov eax, [parent_take]
    mov [irq_regs+42], eax
    mov word [irq_regs+32], 2
    mov dword [irq_regs+46], 0
    mov edi, irq_regs
    xor ebx, ebx
    xor ecx, ecx
    mov ax, 0301h
    int 31h
    jc .error
    cmp word [irq_regs+28], 1
    jne .done
    mov bl, 0dh
    mov ax, 0204h
    int 31h
    jc .error
    mov [game_vector], edx
    mov [game_vector+4], cx
    pushfd
    call far [game_vector]
%endif
%endif
    jmp .done
.error:
    mov byte [bridge_fault], 1
.done:
    pop es
    pop ds
    popad
    iretd
