; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

HOST_PROTECTED
dpmi_get_real_vector:
    movzx eax, byte [ebx+24]
%ifdef RESIDENT_HOST
    cmp al, 0dh
    jne .physical
    cmp byte [ebp+dpmi_audio_irq], 5
    jne .physical
    mov esi, [ebp+resident_game_vector]
    mov edx, [esi]
    jmp .result
.physical:
%endif
    call dpmi_bridge_real_vector
    mov edx, [esi]
.result:
    mov [ebx+28], dx
    shr edx, 16
    mov [ebx+32], dx
    jmp mon_dpmi.success
dpmi_set_real_vector:
    movzx eax, byte [ebx+24]
    mov dx, [ebx+32]
    shl edx, 16
    mov dx, [ebx+28]
%ifdef RESIDENT_HOST
    cmp al, 0dh
    jne .physical
    cmp byte [ebp+dpmi_audio_irq], 5
    jne .physical
    mov esi, [ebp+resident_game_vector]
    mov [esi], edx
    jmp mon_dpmi.success
.physical:
%endif
    call dpmi_bridge_real_vector
    mov [esi], edx
    jmp mon_dpmi.success
dpmi_get_exception:
    movzx eax, byte [ebx+24]
    cmp eax, 32
    jae dpmi_bad_value
    imul eax, 6
    mov edx, [ebp+dpmi_exceptions+eax]
    mov [ebx+28], edx
    mov dx, [ebp+dpmi_exceptions+eax+4]
    mov [ebx+32], dx
    jmp mon_dpmi.success
dpmi_set_exception:
    movzx ecx, byte [ebx+24]
    cmp ecx, 32
    jae dpmi_bad_value
    lea edi, [ebp+dpmi_exceptions]
    jmp dpmi_write_vector
dpmi_set_vector:
    movzx ecx, byte [ebx+24]
    lea edi, [ebp+mon_vectors]
dpmi_write_vector:
    mov ax, [ebx+32]
    test ax, ax
    jz .write
    mov edx, [ebx+28]
    call dpmi_code_target
    jc dpmi_bad_selector
.write:
    imul ecx, 6
    mov eax, [ebx+28]
    mov [edi+ecx], eax
    mov ax, [ebx+32]
    mov [edi+ecx+4], ax
    lea esi, [ebp+mon_vectors]
    cmp edi, esi
    jne .done
    call dpmi_bridge_update
.done:
    jmp mon_dpmi.success

; AX=selector, EDX=offset. Keep ECX, EDX, EBX, EDI, and EBP.
dpmi_code_target:
    push ecx
    push edx
    mov cx, ax
    and cx, 3
    cmp cx, 3
    jne .bad_saved
    call dpmi_descriptor
    pop edx
    jc .bad
    mov al, [esi+5]
    and al, 0f8h
    cmp al, 0f8h
    jne .bad
    movzx ecx, byte [esi+6]
    and ecx, 0fh
    shl ecx, 16
    mov cx, [esi]
    test byte [esi+6], 80h
    jz .limit
    shl ecx, 12
    or ecx, 0fffh
.limit:
    cmp edx, ecx
    ja .bad
    pop ecx
    clc
    ret
.bad_saved:
    pop edx
.bad:
    pop ecx
    stc
    ret

dpmi_exceptions times 32*6 db 0
dpmi_exception_active db 0

; AX=return SS, EDX=return ESP. Keep all registers.
dpmi_stack_target:
    pushad
    mov cx, ax
    and cx, 3
    cmp cx, 3
    jne .bad
    call dpmi_descriptor
    jc .bad
    mov al, [esi+5]
    and al, 0fah
    cmp al, 0f2h
    jne .bad
    mov edx, [esp+20]
    dec edx
    test byte [esi+6], 40h
    jnz .span
    movzx edx, dx
.span:
    mov ax, [esp+28]
    mov ecx, 1
    mov edi, 1
    call dpmi_buffer
    popad
    ret
.bad:
    popad
    stc
    ret

dpmi_deliver_exception:
    push esi
    mov edx, [esi]
    mov ax, [esi+4]
    call dpmi_code_target
    pop esi
    jc mon_exception.unhandled
    cmp byte [ebp+dpmi_first_exception], 0ffh
    jne .recorded
    mov eax, [esp+40]
    mov [ebp+dpmi_first_exception], eax
    mov eax, [esp+44]
    mov [ebp+dpmi_first_exception+4], eax
    mov eax, [esp+48]
    mov [ebp+dpmi_first_exception+8], eax
    mov eax, [esp+52]
    mov [ebp+dpmi_first_exception+12], eax
.recorded:
    mov edi, [ebp+dpmi_locked_cursor]
    cmp edi, 4096
    ja dpmi_locked_abort
    cmp edi, 32
    jb dpmi_locked_abort
    mov [ebp+dpmi_exception_cursor], edi
    sub edi, 32
    mov [ebp+dpmi_locked_cursor], edi
    lea eax, [edi+8]
    mov [ebp+dpmi_exception_sp], eax
    add edi, 3ff000h
    mov byte [ebp+dpmi_exception_active], 1
    mov edx, [esi]
    movzx eax, word [esi+4]
    push eax
    mov dword [edi], dpmi_exception_return
    mov dword [edi+4], 3bh
    lea esi, [esp+48]
    push edi
    add edi, 8
    mov ecx, 6
    cld
    rep movsd
    pop edi
    pop eax
    mov [esp+52], eax
    mov [esp+48], edx
    mov eax, [edi+20]
    call dpmi_virtual_flags
    mov [edi+20], eax
    and eax, 0fffffcffh
    call dpmi_restore_flags
    mov [esp+56], eax
    sub edi, 3ff000h
    mov [esp+60], edi
    mov dword [esp+64], DPMI_IRQ_SS
    pop es
    pop ds
    popad
    add esp, 8
    MON_IRETD
dpmi_exception_return:
    int 0f3h
    ud2
dpmi_debug_code times 64 db 0
dpmi_first_exception times 16 db 0ffh
dpmi_exception_done:
    pushad
    push ds
    push es
    mov ax, 10h
    mov ds, ax
    mov es, ax
    call .base
.base:
    pop ebp
    sub ebp, .base
    cmp byte [ebp+dpmi_exception_active], 1
    jne .bad_return
    cmp word [esp+44], 3bh
    jne .bad_return
    mov eax, dpmi_exception_return+2
    cmp eax, [esp+40]
    jne .bad_return
    cmp word [esp+56], DPMI_IRQ_SS
    jne .bad_return
    mov esi, [esp+52]
    cmp esi, 8
    jb .bad_return
    mov eax, [ebp+dpmi_exception_cursor]
    sub eax, 24
    jc .bad_return
    cmp esi, eax
    ja .bad_return
    add esi, 3ff004h
    push esi
    mov edx, [esi]
    mov ax, [esi+4]
    call dpmi_code_target
    pop esi
    jc .bad_return
    mov edx, [esi+12]
    mov ax, [esi+16]
    call dpmi_stack_target
    jc .bad_return
    lea edi, [esp+40]
    mov ecx, 5
    cld
    rep movsd
    mov eax, [esp+48]
    call dpmi_restore_flags
    mov [esp+48], eax
    mov eax, [ebp+dpmi_exception_cursor]
    mov [ebp+dpmi_locked_cursor], eax
    mov byte [ebp+dpmi_exception_active], 0
    jmp mon_dpmi.done
.bad_return:
    mov byte [ebp+dpmi_exit_code], 1
    mov word [ebp+mon_status], 1
    jmp dpmi_finish

dpmi_reflect:
    pushad
    push ds
    push es
    mov ax, 10h
    mov ds, ax
    mov es, ax
    call .base
.base:
    pop ebp
    sub ebp, .base
    mov ebx, esp
    call dpmi_locked_capture
    cmp byte [ebp+dpmi_active], 1
    jne .bad_gate
    cmp word [ebx+44], 3bh
    jne .bad_gate
    mov eax, [ebx+40]
    sub eax, dpmi_default_vectors+7
    jc .bad_gate
    cmp eax, 255*11
    ja .bad_gate
    xor edx, edx
    mov ecx, 11
    div ecx
    test edx, edx
    jnz .bad_gate
    push eax
    mov ax, [ebx+56]
    call dpmi_descriptor
    jc .bad_stack
    mov edx, [ebx+52]
    test byte [esi+6], 40h
    jnz .stack_size
    movzx edx, dx
.stack_size:
    mov ax, [ebx+56]
    mov ecx, 4
    xor edi, edi
    call dpmi_buffer
    jc .bad_stack
    mov eax, [eax]
    pop edx
    cmp eax, edx
    jne .bad_gate
    mov [ebp+dpmi_reflect_vector], al
    cmp al, 31h
    je dpmi_dispatch
    cmp al, 21h
    jne .other
    jmp dpmi_dos.host
.other:
    cld
    jmp dpmi_dos_translate
.bad_stack:
    pop eax
.bad_gate:
    sub dword [esp+40], 2
    pop es
    pop ds
    popad
    push dword 0
    push dword 13
    jmp mon_exception
dpmi_reflect_vector db 21h

; Preserve arithmetic results across the default vector's outer IRET.
dpmi_reflect_flags:
    cmp word [ebx+44], 3bh
    jne .done
    pushad
    mov eax, [ebx+40]
    sub eax, dpmi_default_vectors+7
    jc .unchanged
    cmp eax, 255*11
    ja .unchanged
    xor edx, edx
    mov ecx, 11
    div ecx
    test edx, edx
    jnz .unchanged
    mov ax, [ebx+56]
    call dpmi_descriptor
    jc .bad
    mov edx, [ebx+52]
    test byte [esi+6], 40h
    jnz .stack_size
    movzx edx, dx
.stack_size:
    mov ax, [ebx+56]
    mov ecx, 16
    mov edi, 1
    call dpmi_buffer
    jc .bad
    mov edx, [ebx+48]
    and edx, 08d5h
    and dword [eax+12], 0fffff72ah
    or [eax+12], edx
.unchanged:
    popad
.done:
    ret
.bad:
    popad
    jmp dpmi_locked_abort

dpmi_default_vectors:
%assign vector 0
%rep 256
    push strict dword vector
    int 0f2h
    add esp, 4
    iretd
%assign vector vector+1
%endrep

; EBX=interrupt frame, ESI=protected vector.
dpmi_deliver_interrupt:
    push esi
    mov edx, [esi]
    mov ax, [esi+4]
    call dpmi_code_target
    pop esi
    jc dpmi_bad_selector
    push esi
    mov ax, [ebx+56]
    call dpmi_descriptor
    jc .bad
    mov edi, [ebx+52]
    test byte [esi+6], 40h
    jnz .wide_stack
    sub di, 12
    movzx edx, di
    jmp .stack
.wide_stack:
    sub edi, 12
    mov edx, edi
.stack:
    push edi
    mov ax, [ebx+56]
    mov ecx, 12
    mov edi, 1
    call dpmi_buffer
    pop edi
    jc .bad
    mov [ebx+52], edi
    mov edi, eax
    mov eax, [ebx+40]
    mov [edi], eax
    mov eax, [ebx+44]
    mov [edi+4], eax
    mov eax, [ebx+48]
    call dpmi_virtual_flags
    mov [edi+8], eax
    pop esi
    mov eax, [esi]
    mov [ebx+40], eax
    mov ax, [esi+4]
    mov [ebx+44], ax
    cmp byte [ebp+dpmi_step_active], 1
    jne .untraced
    or word [ebx+48], 300h
    sub ebx, 8
    call dpmi_step_check
    add ebx, 8
    jmp mon_dpmi.done
.untraced:
    and word [ebx+48], 0feffh
    or word [ebx+48], 200h
    jmp mon_dpmi.done
.bad:
    pop esi
    jmp dpmi_bad_selector

dpmi_software_interrupt:
    mov eax, [ebx+40]
    mov [ebp+dpmi_reflect_vector], al
    imul eax, 6
    lea esi, [ebp+mon_vectors+eax]
    ; Remove the exception stub's vector and error words.
    mov edi, ebx
    add edi, 44
    mov ecx, 10
.frame:
    mov eax, [edi-8]
    mov [edi], eax
    sub edi, 4
    loop .frame
    add esp, 8
    mov ebx, esp
    cmp word [esi+4], 0
    jne dpmi_deliver_interrupt
    cld
    jmp dpmi_dos_translate
