; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
host_old_mux dd 0
host_api_entry dd 0
host_services dd 0
host_old_gate dd 0
host_old_io dd 0
host_io_bitmap dd 0
host_callback dd 0
host_installed db 0
host_backend db 0
host_port_count dw 0
host_ports times 64 dw 0
host_port_old times 64 db 0
host_irq_slot dd 0
host_irq_previous dd 0
host_irq_root dd 0
host_irq_dispatch_previous dd 0
host_irq_table times 256 dd 0

host_mux:
    cmp ax, 1684h
    jne .chain
    cmp bx, 4354h
    jne .chain
    les di, [cs:host_api_entry]
    xor al, al
    iret
.chain:
    jmp far [cs:host_old_mux]

bits 32
host_gate:
    push ebx
    call .base
.base:
    pop ebx
    sub ebx, .base
    mov eax, [ebp+28]
    cmp ah, 1ah
    jne .chain
    movzx edx, word [ebp+20]
    and byte [ebp+48], 0feh
    cmp al, 0
    je .input
    cmp al, 1
    je .output
    cmp al, 6
    je .get
    cmp al, 7
    je .set
    cmp al, 9
    je .trap
    cmp al, 10
    je .untrap
    cmp al, 11
    je .remove_host
.error:
    or byte [ebp+48], 1
.done:
    mov eax, [ebx+host_services]
    pop ebx
    jmp dword [eax+12]
.chain:
    mov eax, [ebx+host_old_gate]
    pop ebx
    jmp eax
.input:
    in al, dx
    mov [ebp+16], al
    jmp .done
.remove_host:
    cmp word [ebx+host_port_count], 0
    jne .error
    cmp dword [ebx+host_callback], 0
    jne .error
    call host_irq_remove
    jc .error
    mov esi, [ebx+host_services]
    mov esi, [esi+48]
    mov eax, [ebx+host_old_io]
    mov [esi], eax
    mov esi, [ebx+host_gate_slot]
    mov eax, [ebx+host_old_gate]
    mov [esi], eax
    jmp .done
.output:
    mov al, [ebp+16]
    out dx, al
    jmp .done
.get:
    mov eax, [ebx+host_callback]
    mov [ebp], ax
    shr eax, 16
    mov [ebp+60], ax
    jmp .done
.set:
    movzx eax, word [ebp+60]
    shl eax, 16
    mov ax, [ebp]
    mov [ebx+host_callback], eax
    jmp .done
.trap:
    movzx ecx, word [ebx+host_port_count]
    cmp ecx, 64
    jae .error
    xor esi, esi
.find:
    cmp esi, ecx
    jae .add
    cmp dx, [ebx+host_ports+esi*2]
    je .error
    inc esi
    jmp .find
.add:
    mov [ebx+host_ports+ecx*2], dx
    mov esi, [ebx+host_io_bitmap]
    bts [esi], edx
    setc byte [ebx+host_port_old+ecx]
    inc word [ebx+host_port_count]
    jmp .done
.untrap:
    movzx ecx, word [ebx+host_port_count]
    xor esi, esi
.search:
    cmp esi, ecx
    jae .error
    cmp dx, [ebx+host_ports+esi*2]
    je .remove
    inc esi
    jmp .search
.remove:
    cmp byte [ebx+host_port_old+esi], 0
    jne .compact
    mov edi, [ebx+host_io_bitmap]
    btr [edi], edx
.compact:
    dec ecx
    mov ax, [ebx+host_ports+ecx*2]
    mov [ebx+host_ports+esi*2], ax
    mov al, [ebx+host_port_old+ecx]
    mov [ebx+host_port_old+esi], al
    mov [ebx+host_port_count], cx
    jmp .done

host_io:
    push ebx
    push esi
    call .base
.base:
    pop ebx
    sub ebx, .base
    movzx esi, word [ebx+host_port_count]
.find:
    test esi, esi
    jz .chain
    dec esi
    cmp dx, [ebx+host_ports+esi*2]
    jne .find
    cmp dword [ebx+host_callback], 0
    je .chain
    push ecx
    push edx
    push dword [ebp+48]
    push dword [ebp+24]
    push dword [ebp+20]
    mov ch, [ebp+49]
    and ch, 2
    mov [ebp+24], cx
    mov [ebp+20], dx
    and byte [ebp+49], 0fch
    mov esi, [ebx+host_services]
    call dword [esi+16]
    movzx ecx, word [ebx+host_callback+2]
    movzx edx, word [ebx+host_callback]
    call dword [esi+8]
    call dword [esi+24]
    call dword [esi+28]
    mov eax, [ebp+28]
    pop dword [ebp+20]
    pop dword [ebp+24]
    pop dword [ebp+48]
    pop edx
    pop ecx
    pop esi
    pop ebx
    ret
.chain:
    pop esi
    push dword [ebx+host_old_io]
    mov ebx, [esp+4]
    ret 4

; Jemm calls this before it reflects a hardware interrupt through the IVT.
    dd host_irq_previous
host_irq_dispatch:
    pushad
    call .base
.base:
    pop ebx
    sub ebx, .base
    cmp byte [ebx+sb_running], 1
    jne .chain
    mov cl, [ebx+sb_irq]
    mov al, 0bh
    out 20h, al
    in al, 20h
    mov ah, al
    mov al, [ebx+physical_pic_read]
    out 20h, al
    mov al, 1
    shl al, cl
    test ah, al
    jz .chain
    movzx ecx, word [ebp+56]
    shl ecx, 4
    movzx edx, word [ebp+52]
    mov eax, [ebp+48]
    sub dx, 2
    mov [ecx+edx], ax
    and ah, 0fch
    mov [ebp+48], eax
    mov ax, [ebp+44]
    sub dx, 2
    mov [ecx+edx], ax
    mov ax, [ebp+40]
    sub dx, 2
    mov [ecx+edx], ax
    mov [ebp+52], dx
    mov dword [ebp+40], audio_irq
    mov eax, ebx
    shr eax, 4
    mov [ebp+44], eax
    popad
    clc
    ret
.chain:
    popad
    stc
    ret

host_irq_call:
    jmp ecx

host_irq_remove:
    mov edx, [ebx+host_irq_slot]
    test edx, edx
    jz .ok
    lea eax, [ebx+host_irq_dispatch]
    cmp [edx], eax
    jne .bad
    mov esi, [ebx+host_irq_root]
    movzx ecx, byte [ebx+sb_irq]
    mov eax, [esi]
    lea ecx, [eax+ecx*4+8*4]
    cmp ecx, edx
    jne .bad
    lea eax, [ebx+host_irq_table]
    cmp [esi], eax
    jne .restore
    lea ecx, [ebx+host_irq_call]
    cmp [esi+4], ecx
    jne .bad
    xor ecx, ecx
.check:
    lea edi, [eax+ecx*4]
    cmp edi, edx
    je .next
    cmp dword [edi], 0
    jne .bad
.next:
    inc ecx
    cmp ecx, 256
    jb .check
    mov dword [esi], 0
    mov eax, [ebx+host_irq_dispatch_previous]
    mov [esi+4], eax
.restore:
    mov eax, [ebx+host_irq_previous]
    mov [edx], eax
    mov dword [ebx+host_irq_slot], 0
.ok:
    clc
    ret
.bad:
    stc
    ret

bits 16
host_gate_slot dd 0
host_remove:
    cmp byte [host_installed], 0
    je .ok
    cmp byte [host_backend], 2
    je host_emm_remove
    mov ax, 1a0bh
    call far [host_api_entry]
    jc .failed
    push ds
    lds dx, [host_old_mux]
    mov ax, 252fh
    int 21h
    pop ds
    mov byte [host_installed], 0
    mov byte [host_backend], 0
.ok:
    clc
    ret
.failed:
    stc
    ret
