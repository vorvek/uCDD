; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

HOST_REAL
dpmi_ivt_snapshot:
    pushad
    push es
    mov ah, 52h
    int 21h
    mov ax, [es:bx-2]
    mov [cs:dpmi_first_mcb], ax
%ifdef RESIDENT_HOST
    mov eax, [cs:resident_game_vector]
    mov si, ax
    and si, 15
    shr eax, 4
    mov es, ax
    mov eax, [es:si]
    mov [cs:resident_initial_game_vector], eax
%endif
    pop es
    popad
    ret

HOST_PROTECTED
dpmi_ivt_snapshot_protected:
    pushad
    xor esi, esi
    lea edi, [ebp+dpmi_initial_ivt]
    mov ecx, 256
    rep movsd
    popad
    ret

; Restore only vectors into client resources that are about to be released.
dpmi_ivt_cleanup:
    pushad
    mov eax, [ebp+mon_real_base]
    add eax, dpmi_callback_stubs
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
    xor edi, edi
.vector:
    mov eax, edi
    shr eax, 2
    call dpmi_bridge_real_vector
    mov eax, [esi]
    cmp eax, [ebp+dpmi_initial_ivt+edi]
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
    mov eax, [ebp+dpmi_initial_ivt+edi]
    mov [esi], eax
.next:
    add edi, 4
    cmp edi, 256*4
    jb .vector
%ifdef RESIDENT_HOST
    mov al, [ebp+dpmi_guest_irq]
    cmp [ebp+dpmi_audio_irq], al
    jne .done
    mov esi, [ebp+resident_game_vector]
    mov eax, [esi]
    mov edx, eax
    shr edx, 16
    shl edx, 4
    movzx eax, ax
    add eax, edx
    cmp eax, ebx
    jb .done
    cmp eax, ecx
    jae .done
    mov eax, [ebp+resident_initial_game_vector]
    mov [esi], eax
.done:
%endif
    popad
    ret

dpmi_initial_ivt times 256 dd 0
HOST_REAL
dpmi_first_mcb dw 0
%ifdef RESIDENT_HOST
resident_initial_game_vector dd 0
%endif
HOST_PROTECTED
