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
host_port_count dw 0
host_ports times 64 dw 0
host_port_old times 64 db 0

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

bits 16
host_gate_slot dd 0
host_remove:
    cmp byte [host_installed], 0
    je .done
    mov ax, 1a0bh
    call far [host_api_entry]
    jc .done
    push ds
    lds dx, [host_old_mux]
    mov ax, 252fh
    int 21h
    pop ds
    mov byte [host_installed], 0
.done:
    ret
