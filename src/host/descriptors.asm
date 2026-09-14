; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 32
; AX=client selector, ESI=descriptor on success. EBX/EBP stay intact.
dpmi_descriptor:
    movzx eax, ax
    mov edx, eax
    and edx, 7
    cmp edx, 7
    jne .gdt
    shr eax, 3
    test eax, eax
    jz .bad
    cmp eax, DPMI_LDT_COUNT
    jae .bad
    cmp byte [ebp+dpmi_used+eax], 0
    je .bad
    lea esi, [ebp+dpmi_ldt+eax*8]
    clc
    ret
.gdt:
    mov edx, eax
    and edx, 0fffch
    cmp edx, 20h
    je .fixed
    cmp edx, 28h
    je .fixed
    cmp edx, 38h
    je .fixed
    cmp edx, 40h
    jne .bad
.fixed:
    lea esi, [ebp+mon_gdt+edx]
    clc
    ret
.bad:
    stc
    ret
dpmi_descriptor_base:
    movzx eax, word [esi+2]
    movzx edx, byte [esi+4]
    shl edx, 16
    or eax, edx
    movzx edx, byte [esi+7]
    shl edx, 24
    or eax, edx
    ret

dpmi_descriptor_allocate:
    test ecx, ecx
    jz .bad
    cmp ecx, DPMI_LDT_COUNT-1
    ja .bad
    mov edi, 1
.scan:
    lea eax, [edi+ecx]
    cmp eax, DPMI_LDT_COUNT
    ja .bad
    xor edx, edx
.range:
    lea eax, [edi+edx]
    cmp byte [ebp+dpmi_used+eax], 0
    jne .next
    inc edx
    cmp edx, ecx
    jb .range
    push edi
.claim:
    mov byte [ebp+dpmi_used+edi], 1
    mov dword [ebp+dpmi_ldt+edi*8], 0
    mov dword [ebp+dpmi_ldt+edi*8+4], 0000f200h
    inc edi
    loop .claim
    pop eax
    lea esi, [ebp+dpmi_ldt+eax*8]
    shl eax, 3
    or al, 7
    clc
    ret
.next:
    lea edi, [edi+edx+1]
    jmp .scan
.bad:
    stc
    ret

dpmi_descriptors:
    cmp eax, 0
    je .allocate
    cmp eax, 3
    je .increment
    cmp eax, 2
    je .segment
    movzx eax, word [ebx+24]
    call dpmi_descriptor
    jc dpmi_bad_selector
    movzx eax, word [ebx+36]
    cmp eax, 6
    je .base
    cmp eax, 10
    je .alias
    cmp eax, 11
    je .get
    test byte [ebx+24], 4
    jz dpmi_bad_selector
    movzx edx, word [ebx+24]
    shr edx, 3
    cmp byte [ebp+dpmi_used+edx], 1
    jne dpmi_bad_selector
.operation:
    cmp eax, 1
    je .free
    cmp eax, 6
    je .base
    cmp eax, 7
    je .set_base
    cmp eax, 8
    je .limit
    cmp eax, 9
    je .rights
    cmp eax, 10
    je .alias
    cmp eax, 11
    je .get
    cmp eax, 12
    je .set
    jmp mon_dpmi.unsupported
.allocate:
    movzx ecx, word [ebx+32]
    call dpmi_descriptor_allocate
    jc .full
    mov [ebx+36], ax
    jmp mon_dpmi.success
.full:
    mov ax, 8011h
    jmp dpmi_error
.increment:
    mov word [ebx+36], 8
    jmp mon_dpmi.success
.segment:
    movzx eax, word [ebx+24]
    call dpmi_segment_descriptor
    jc .full
    mov [ebx+36], ax
    jmp mon_dpmi.success
.free:
    movzx eax, word [ebx+24]
    call dpmi_clear_selector
    shr eax, 3
    mov byte [ebp+dpmi_used+eax], 0
    mov dword [esi], 0
    mov dword [esi+4], 0
    jmp mon_dpmi.success
.base:
    call dpmi_descriptor_base
    mov [ebx+28], ax
    shr eax, 16
    mov [ebx+32], ax
    jmp mon_dpmi.success
.set_base:
    movzx eax, word [ebx+32]
    shl eax, 16
    mov ax, [ebx+28]
.write_base:
    mov [esi+2], ax
    shr eax, 16
    mov [esi+4], al
    mov [esi+7], ah
    jmp mon_dpmi.success
.limit:
    movzx eax, word [ebx+32]
    shl eax, 16
    mov ax, [ebx+28]
    xor edx, edx
    cmp eax, 0fffffh
    jbe .write_limit
    mov edx, eax
    and edx, 0fffh
    cmp edx, 0fffh
    jne dpmi_bad_value
    shr eax, 12
    mov dl, 80h
.write_limit:
    mov [esi], ax
    shr eax, 16
    and byte [esi+6], 70h
    or [esi+6], al
    or [esi+6], dl
    jmp mon_dpmi.success
.rights:
    mov cx, [ebx+32]
    mov al, cl
    and al, 70h
    cmp al, 70h
    jne dpmi_bad_value
    test ch, 20h
    jnz dpmi_bad_value
    mov [esi+5], cl
    and byte [esi+6], 0fh
    and ch, 0f0h
    or [esi+6], ch
    jmp mon_dpmi.success
.alias:
    push dword [esi]
    push dword [esi+4]
    mov ecx, 1
    call dpmi_descriptor_allocate
    pop edx
    pop ecx
    jc .full
    mov [esi], ecx
    and edx, 0ffff00ffh
    or edx, 0000f200h
    mov [esi+4], edx
    mov [ebx+36], ax
    jmp mon_dpmi.success
.get:
    push dword [esi]
    push dword [esi+4]
    mov ax, [ebx]
    mov edx, [ebx+8]
    mov ecx, 8
    mov edi, 1
    call dpmi_buffer
    jc .bad_buffer
    pop edx
    mov [eax+4], edx
    pop edx
    mov [eax], edx
    jmp mon_dpmi.success
.set:
    pushad
    mov esi, ebx
    lea edi, [ebp+dpmi_set_frame]
    mov ecx, 15
    rep movsd
    popad
    push esi
    mov ax, [ebx]
    mov edx, [ebx+8]
    mov ecx, 8
    xor edi, edi
    call dpmi_buffer
    jc .bad_set
    pop esi
    mov dl, [eax+5]
    and dl, 70h
    cmp dl, 70h
    jne dpmi_bad_value
    test byte [eax+6], 20h
    jnz dpmi_bad_value
    mov edx, [eax]
    mov [esi], edx
    mov edx, [eax+4]
    mov [esi+4], edx
    jmp mon_dpmi.success
.bad_buffer:
    add esp, 8
    jmp dpmi_error
.bad_set:
    add esp, 4
    jmp dpmi_error

dpmi_clear_selector:
    cmp ax, [ebx]
    jne .ds
    mov word [ebx], 0
.ds:
    cmp ax, [ebx+4]
    jne .fs
    mov word [ebx+4], 0
.fs:
    push edx
    mov dx, fs
    cmp ax, dx
    jne .gs
    xor edx, edx
    mov fs, dx
.gs:
    mov dx, gs
    cmp ax, dx
    jne .done
    xor edx, edx
    mov gs, dx
.done:
    pop edx
    ret
dpmi_set_frame times 60 db 0

; AX=real segment. Returns AX=cached immutable selector.
dpmi_segment_descriptor:
    push ebx
    push ecx
    push edi
    movzx ebx, ax
    shl ebx, 4
    mov edi, 1
.scan:
    cmp byte [ebp+dpmi_used+edi], 2
    jne .next
    lea esi, [ebp+dpmi_ldt+edi*8]
    call dpmi_descriptor_base
    cmp eax, ebx
    je .found
.next:
    inc edi
    cmp edi, DPMI_LDT_COUNT
    jb .scan
    mov ecx, 1
    call dpmi_descriptor_allocate
    jc .done
    mov edi, eax
    shr edi, 3
    mov byte [ebp+dpmi_used+edi], 2
    mov word [esi], 0ffffh
    mov [esi+2], bx
    shr ebx, 16
    mov [esi+4], bl
.found:
    lea eax, [edi*8+7]
    clc
.done:
    pop edi
    pop ecx
    pop ebx
    ret

%include "host/buffer.asm"
