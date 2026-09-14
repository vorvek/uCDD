; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
dpmi_ivt_snapshot:
    pushad
    push ds
    push es
    mov ah, 52h
    int 21h
    mov ax, [es:bx-2]
    mov [cs:dpmi_first_mcb], ax
    push cs
    pop es
    xor ax, ax
    mov ds, ax
    xor si, si
    mov di, dpmi_initial_ivt
    mov cx, 256
    cld
    rep movsd
    pop es
    pop ds
    popad
    ret

bits 32
; Restore only vectors into client resources that are about to be released.
dpmi_ivt_cleanup:
    pushad
    lea eax, [ebp+dpmi_callback_stubs]
    mov ecx, 16*6
    call dpmi_ivt_restore_range
    movzx edi, word [ebp+dpmi_first_mcb]
.mcb:
    test edi, edi
    jz .main_block
    mov esi, edi
    shl esi, 4
    mov al, [esi]
    cmp al, 'M'
    je .mcb_valid
    cmp al, 'Z'
    jne .main_block
.mcb_valid:
    movzx edx, word [esi+3]
    inc edx
    add edx, edi
    cmp edx, 10000h
    ja .main_block
    mov ax, [ebp+dpmi_psp]
    cmp [esi+1], ax
    jne .next_mcb
    lea eax, [esi+16]
    movzx ecx, word [esi+3]
    shl ecx, 4
    call dpmi_ivt_restore_range
.next_mcb:
    cmp byte [esi], 'Z'
    je .main_block
    cmp edx, 10000h
    je .main_block
    mov edi, edx
    jmp .mcb
.main_block:
    movzx esi, word [ebp+dpmi_psp]
    dec esi
    shl esi, 4
    mov ax, [ebp+dpmi_psp]
    cmp [esi+1], ax
    jne .typed
    lea eax, [esi+16]
    movzx ecx, word [esi+3]
    shl ecx, 4
    call dpmi_ivt_restore_range
.typed:
    mov edi, 1
.descriptor:
    cmp byte [ebp+dpmi_used+edi], 3
    jne .next
    lea esi, [ebp+dpmi_ldt+edi*8]
    call dpmi_descriptor_base
    mov dx, [ebp+dpmi_psp]
    cmp [eax-15], dx
    jne .next
    movzx ecx, byte [esi+6]
    and ecx, 0fh
    shl ecx, 16
    mov cx, [esi]
    inc ecx
    call dpmi_ivt_restore_range
.next:
    inc edi
    cmp edi, DPMI_LDT_COUNT
    jb .descriptor
    popad
    ret

; EAX=linear start, ECX=bytes. Other real-mode hooks stay intact.
dpmi_ivt_restore_range:
    pushad
    mov ebx, eax
    add ecx, eax
    xor esi, esi
.vector:
    mov eax, [esi]
    cmp eax, [ebp+dpmi_initial_ivt+esi]
    je .next
    mov edx, eax
    shr edx, 16
    shl edx, 4
    movzx eax, ax
    add eax, edx
    cmp eax, ebx
    jb .next
    cmp eax, ecx
    jae .next
    mov eax, [ebp+dpmi_initial_ivt+esi]
    mov [esi], eax
.next:
    add esi, 4
    cmp esi, 256*4
    jb .vector
    popad
    ret

dpmi_initial_ivt times 256 dd 0
dpmi_first_mcb dw 0
