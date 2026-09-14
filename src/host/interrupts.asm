; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 32
; EBX points to the normalized exception frame.
dpmi_step_check:
    pushad
.next:
    mov ax, [ebx+52]
    mov ecx, 4
    cmp ax, 23h
    je .flat_code
    call dpmi_descriptor
    jc .done
    test byte [esi+6], 40h
    jnz .code_size
    mov ecx, 2
.code_size:
    call dpmi_descriptor_base
    add eax, [ebx+48]
    mov esi, eax
    jmp .decode
.flat_code:
    mov esi, [ebx+48]
.decode:
    mov [ebp+dpmi_step_address_size], cl
    mov word [ebp+dpmi_step_segment], 0ffffh
    xor edi, edi
    xor edx, edx
.prefix:
    cmp edi, 15
    jae .done
    call .fetch
    jc .done
    inc edi
    cmp al, 66h
    jne .other_prefix
    test dl, 1
    jnz .prefix
    or dl, 1
    xor ecx, 6
    jmp .prefix
.other_prefix:
    cmp al, 26h
    je .es_prefix
    cmp al, 2eh
    je .cs_prefix
    cmp al, 36h
    je .ss_prefix
    cmp al, 3eh
    je .ds_prefix
    cmp al, 64h
    je .fs_prefix
    cmp al, 65h
    je .gs_prefix
    cmp al, 67h
    jne .opcode
    test dl, 2
    jnz .prefix
    or dl, 2
    xor byte [ebp+dpmi_step_address_size], 6
    jmp .prefix
.es_prefix:
    mov ax, [ebx]
    jmp .segment_prefix
.cs_prefix:
    mov ax, [ebx+52]
    jmp .segment_prefix
.ss_prefix:
    mov ax, [ebx+64]
    jmp .segment_prefix
.ds_prefix:
    mov ax, [ebx+4]
    jmp .segment_prefix
.fs_prefix:
    mov ax, fs
    jmp .segment_prefix
.gs_prefix:
    mov ax, gs
.segment_prefix:
    mov [ebp+dpmi_step_segment], ax
    jmp .prefix
.opcode:
    cmp al, 0fh
    je .extended
    cmp al, 17h
    je .pop_ss
    cmp al, 8eh
    je .mov_ss
    cmp al, 0fbh
    je .enable
    cmp al, 9ch
    je .push_flags
    cmp al, 0cfh
    je .iret
    cmp al, 9dh
    jne .done
    push edi
    call .stack
    jc .bad_stack
    mov edx, [ebx+56]
    cmp ecx, 4
    jne .pop_word
    mov edx, [esi]
    jmp .pop_value
.pop_word:
    mov dx, [esi]
.pop_value:
    mov eax, ecx
    call .adjust_stack
    and edx, 0fffc8effh
    test edx, 200h
    jnz .pop_enabled
    or edx, 300h
    mov [ebx+56], edx
    pop edi
    add [ebx+48], edi
    jmp .next
.pop_enabled:
    mov [ebx+56], edx
    pop edi
.enable:
    mov byte [ebp+dpmi_vif], 1
    mov byte [ebp+dpmi_step_active], 0
    and word [ebx+56], 0feffh
    or word [ebx+56], 200h
    add [ebx+48], edi
    jmp .done
.push_flags:
    push edi
    mov eax, ecx
    neg eax
    call .adjust_stack
    call .write_stack
    jc .bad_push
    mov eax, [ebx+56]
    and eax, 0fffffcffh
    cmp ecx, 4
    jne .push_word
    mov [esi], eax
    jmp .pushed
.push_word:
    mov [esi], ax
.pushed:
    pop edi
    add [ebx+48], edi
    jmp .next
.iret:
    push ecx
    imul ecx, 3
    call .stack
    pop ecx
    jc .done
    cmp ecx, 4
    jne .iret_word
    mov eax, [esi]
    mov edx, [esi+4]
    mov edi, [esi+8]
    call .iret_target
    jc .done
    push eax
    mov eax, 12
    call .adjust_stack
    pop eax
    jmp .iret_frame
.iret_word:
    movzx eax, word [esi]
    movzx edx, word [esi+2]
    movzx edi, word [esi+4]
    call .iret_target
    jc .done
    push eax
    mov eax, 6
    call .adjust_stack
    pop eax
.iret_frame:
    mov [ebx+48], eax
    mov [ebx+52], edx
    mov edx, edi
    and edx, 0fffd8effh
    test edx, 200h
    jnz .iret_enabled
    or edx, 300h
    mov [ebx+56], edx
    jmp .next
.iret_enabled:
    mov [ebx+56], edx
    xor edi, edi
    jmp .enable
.iret_target:
    push eax
    push edx
    mov edx, eax
    mov ax, [esp]
    call dpmi_code_target
    pop edx
    pop eax
    ret
.mov_ss:
    call .fetch
    jc .done
    mov dl, al
    and dl, 38h
    cmp dl, 10h
    jne .done
    cmp al, 0c0h
    jb .memory_ss
    and eax, 7
    movzx eax, byte [ebp+.register_offsets+eax]
    mov ax, [ebx+eax]
    call .ss_selector
    jc .done
    inc edi
    jmp .loaded_ss
.memory_ss:
    call .effective_address
    jc .done
    push ecx
    push edi
    mov ecx, 2
    xor edi, edi
    call dpmi_buffer
    pop edi
    pop ecx
    jc .done
    mov ax, [eax]
    call .ss_selector
    jc .done
    jmp .loaded_ss
.extended:
    call .fetch
    jc .done
    cmp al, 0b2h
    jne .done
    inc edi
    call .effective_address
    jc .done
    push ecx
    push edi
    add ecx, 2
    xor edi, edi
    call dpmi_buffer
    pop edi
    pop ecx
    jc .done
    mov esi, eax
    mov ax, [esi+ecx]
    push esi
    call .ss_selector
    pop esi
    jc .done
    push eax
    movzx edx, byte [ebp+dpmi_step_modrm]
    shr edx, 3
    and edx, 7
    movzx edx, byte [ebp+.register_offsets+edx]
    cmp ecx, 4
    jne .lss_word
    mov eax, [esi]
    mov [ebx+edx], eax
    jmp .lss_loaded
.lss_word:
    mov ax, [esi]
    mov [ebx+edx], ax
.lss_loaded:
    pop eax
    jmp .loaded_ss
.pop_ss:
    push edi
    call .stack
    jc .bad_stack
    mov ax, [esi]
    call .ss_selector
    jc .bad_stack
    push eax
    mov eax, ecx
    call .adjust_stack
    pop eax
    pop edi
.loaded_ss:
    mov [ebx+64], ax
    add [ebx+48], edi
    jmp .next
.ss_selector:
    push eax
    mov dl, al
    and dl, 3
    cmp dl, 3
    jne .bad_ss
    call dpmi_descriptor
    jc .bad_ss
    mov al, [esi+5]
    and al, 0fah
    cmp al, 0f2h
    jne .bad_ss
    pop eax
    clc
    ret
.bad_ss:
    pop eax
    stc
    ret
.register_offsets:
    db 36,32,28,24,60,16,12,8
.address16_first:
    db 24,24,16,16,12,8,16,24
.address16_second:
    db 12,8,12,8,0ffh,0ffh,0ffh,0ffh
.effective_address:
    push ecx
    mov ax, [ebx+4]
    mov [ebp+dpmi_step_ea_segment], ax
    call .fetch
    jc .ea_bad
    inc edi
    mov [ebp+dpmi_step_modrm], al
    cmp al, 0c0h
    jae .ea_bad
    xor esi, esi
    cmp byte [ebp+dpmi_step_address_size], 4
    je .address32
    and eax, 7
    cmp al, 6
    jne .base16
    test byte [ebp+dpmi_step_modrm], 0c0h
    jz .disp16
.base16:
    movzx edx, byte [ebp+.address16_first+eax]
    movzx esi, word [ebx+edx]
    movzx edx, byte [ebp+.address16_second+eax]
    cmp dl, 0ffh
    je .base16_segment
    movzx edx, word [ebx+edx]
    add esi, edx
.base16_segment:
    cmp al, 2
    je .stack_segment
    cmp al, 3
    je .stack_segment
    cmp al, 6
    je .stack_segment
    jmp .mod_displacement
.address32:
    and eax, 7
    cmp al, 4
    jne .base32
    call .fetch
    jc .ea_bad
    inc edi
    mov edx, eax
    shr edx, 3
    and edx, 7
    cmp dl, 4
    je .base32
    movzx edx, byte [ebp+.register_offsets+edx]
    mov esi, [ebx+edx]
    mov edx, eax
    shr edx, 6
    mov ecx, edx
    shl esi, cl
.base32:
    and eax, 7
    cmp al, 5
    jne .base32_value
    test byte [ebp+dpmi_step_modrm], 0c0h
    jz .disp32
.base32_value:
    movzx edx, byte [ebp+.register_offsets+eax]
    add esi, [ebx+edx]
    cmp al, 4
    je .stack_segment
    cmp al, 5
    jne .mod_displacement
.stack_segment:
    mov dx, [ebx+64]
    mov [ebp+dpmi_step_ea_segment], dx
.mod_displacement:
    mov al, [ebp+dpmi_step_modrm]
    and al, 0c0h
    jz .ea_done
    cmp al, 40h
    je .disp8
    cmp byte [ebp+dpmi_step_address_size], 2
    je .disp16
.disp32:
    mov ecx, 4
    jmp .displacement
.disp16:
    mov ecx, 2
    jmp .displacement
.disp8:
    mov ecx, 1
.displacement:
    call .read_code
    jc .ea_bad
    add edi, ecx
    cmp ecx, 1
    jne .unsigned_displacement
    movsx eax, al
.unsigned_displacement:
    add esi, eax
.ea_done:
    cmp byte [ebp+dpmi_step_address_size], 2
    jne .wide_address
    movzx esi, si
.wide_address:
    mov edx, esi
    mov ax, [ebp+dpmi_step_segment]
    cmp ax, 0ffffh
    jne .ea_selector
    mov ax, [ebp+dpmi_step_ea_segment]
.ea_selector:
    pop ecx
    clc
    ret
.ea_bad:
    pop ecx
    stc
    ret
.fetch:
    push ecx
    mov ecx, 1
    call .read_code
    pop ecx
    ret
.read_code:
    push edx
    push edi
    lea edx, [edi+ecx]
    cmp edx, 15
    ja .code_bad
    mov edx, [ebx+48]
    add edx, edi
    jc .code_bad
    mov ax, [ebx+52]
    mov edi, 2
    call dpmi_buffer
    jc .code_bad
    cmp ecx, 4
    je .code_dword
    cmp ecx, 2
    je .code_word
    movzx eax, byte [eax]
    jmp .code_done
.code_word:
    movzx eax, word [eax]
    jmp .code_done
.code_dword:
    mov eax, [eax]
.code_done:
    pop edi
    pop edx
    clc
    ret
.code_bad:
    pop edi
    pop edx
    stc
    ret
.bad_push:
    mov eax, ecx
    call .adjust_stack
.bad_stack:
    pop edi
.done:
    popad
    ret
.stack:
    push dword 0
    jmp .stack_access
.write_stack:
    push dword 1
.stack_access:
    mov ax, [ebx+64]
    call dpmi_descriptor
    jc .return
    mov edx, [ebx+60]
    test byte [esi+6], 40h
    jnz .stack_size
    movzx edx, dx
.stack_size:
    mov ax, [ebx+64]
    mov edi, [esp]
    call dpmi_buffer
    jc .return
    mov esi, eax
.return:
    lea esp, [esp+4]
    ret
.adjust_stack:
    pushad
    mov ecx, eax
    mov ax, [ebx+64]
    call dpmi_descriptor
    jc .adjust_done
    test byte [esi+6], 40h
    jnz .adjust_wide
    add word [ebx+60], cx
    jmp .adjust_done
.adjust_wide:
    add [ebx+60], ecx
.adjust_done:
    popad
    ret

; EAX holds physical flags on entry and client flags on return.
dpmi_virtual_flags:
    and eax, 0fffffdffh
    cmp byte [ebp+dpmi_vif], 0
    je .trace
    or eax, 200h
.trace:
    cmp byte [ebp+dpmi_step_active], 0
    je .done
    and eax, 0fffffeffh
.done:
    ret

; EAX holds client flags. Keep physical IRQ delivery enabled.
dpmi_restore_flags:
    mov byte [ebp+dpmi_vif], 0
    mov byte [ebp+dpmi_step_active], 1
    test eax, 200h
    jz .disabled
    mov byte [ebp+dpmi_vif], 1
    mov byte [ebp+dpmi_step_active], 0
    jmp .done
.disabled:
    or eax, 100h
.done:
    and eax, 0fffd8fffh
    or eax, 202h
    ret

dpmi_vif db 1
dpmi_step_active db 0
dpmi_step_address_size db 0
dpmi_step_segment dw 0
dpmi_step_ea_segment dw 0
dpmi_step_modrm db 0
