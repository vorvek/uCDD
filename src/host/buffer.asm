; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

HOST_PROTECTED
; AX=selector, EDX=offset, ECX=length, EDI=read/write/execute (0/1/2).
; Returns EAX=linear address or error. Other registers stay intact.
dpmi_buffer:
    pushad
    call dpmi_descriptor
    jc .selector
    mov al, [esi+5]
    and al, 90h
    cmp al, 90h
    jne .selector
    test byte [esi+5], 8
    jz .data
    cmp dword [esp], 2
    je .span
    cmp dword [esp], 0
    jne .selector
    test byte [esi+5], 2
    jz .selector
    jmp .span
.data:
    cmp dword [esp], 2
    je .selector
    cmp dword [esp], 0
    je .span
    test byte [esi+5], 2
    jz .selector
.span:
    mov edi, [esp+20]
    mov ebx, [esp+24]
    test ebx, ebx
    jz .value
    dec ebx
    add ebx, edi
    jc .value
    movzx eax, word [esi]
    movzx edx, byte [esi+6]
    and edx, 0fh
    shl edx, 16
    or eax, edx
    test byte [esi+6], 80h
    jz .limit
    shl eax, 12
    or eax, 4095
.limit:
    mov dl, [esi+5]
    and dl, 0ch
    cmp dl, 4
    jne .up
    cmp edi, eax
    jbe .value
    test byte [esi+6], 40h
    jnz .linear
    cmp ebx, 0ffffh
    ja .value
    jmp .linear
.up:
    cmp ebx, eax
    ja .value
.linear:
    call dpmi_descriptor_base
    add ebx, eax
    jc .value
    add eax, edi
    jc .value
    mov [esp+28], eax
    and eax, 0fffff000h
    and ebx, 0fffff000h
.page:
    mov edx, eax
    shr edx, 22
    mov edx, [0fffff000h+edx*4]
    and edx, 7
    mov ecx, 5
    cmp dword [esp], 1
    jne .pde
    or cl, 2
.pde:
    and edx, ecx
    cmp edx, ecx
    jne .value
    mov edx, eax
    shr edx, 10
    mov edx, [0ffc00000h+edx]
    and edx, ecx
    cmp edx, ecx
    jne .value
    cmp eax, ebx
    je .ok
    add eax, 4096
    jmp .page
.ok:
    popad
    clc
    ret
.selector:
    mov dword [esp+28], 8022h
    jmp .bad
.value:
    mov dword [esp+28], 8021h
.bad:
    popad
    stc
    ret

HOST_PROTECTED
; Fast path for flat code and readable data.
dpmi_read_buffer:
dpmi_code_buffer:
    pushad
    test ecx, ecx
    jz .slow
    call dpmi_descriptor
    jc .slow
    cmp dword [esi], 0000ffffh
    jne .slow
    mov eax, [esi+4]
    and eax, 0fffffeffh
    cmp edi, 2
    je .code
    test edi, edi
    jnz .slow
    cmp eax, 00cff200h
    je .flat
.code:
    cmp eax, 00cffa00h
    jne .slow
.flat:
    mov eax, [esp+20]
    mov edx, eax
    add edx, [esp+24]
    jc .slow
    dec edx
    xor edx, eax
    shr edx, 12
    jnz .slow
    mov edx, eax
    shr edx, 22
    mov edx, [0fffff000h+edx*4]
    and edx, 5
    cmp edx, 5
    jne .slow
    mov edx, eax
    shr edx, 12
    mov edx, [0ffc00000h+edx*4]
    and edx, 5
    cmp edx, 5
    jne .slow
    mov [esp+28], eax
    popad
    clc
    ret
.slow:
    popad
    jmp dpmi_buffer
