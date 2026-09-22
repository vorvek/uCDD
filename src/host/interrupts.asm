; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

HOST_PROTECTED
; EBX points to the normalized exception frame.
dpmi_step_check:
    pushad
    mov dword [esp+12], 0
.next:
    cmp byte [ebp+dpmi_sti_shadow], 0
    je .shadow_ready
    mov eax, [ebx+48]
    cmp eax, [ebp+dpmi_sti_ip]
    jne .done
    mov ax, [ebx+52]
    cmp ax, [ebp+dpmi_sti_cs]
    jne .done
.shadow_ready:
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
    cmp al, 0f2h
    je .rep_prefix
    cmp al, 0f3h
    je .rep_prefix
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
.rep_prefix:
    or dl, 4
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
    cmp byte [ebp+dpmi_sti_shadow], 0
    jne .ordinary_opcode
    test dl, 4
    jz .ordinary_opcode
    cmp al, 0a4h
    je .repeat
    cmp al, 0a5h
    je .repeat
    cmp al, 0aah
    je .repeat
    cmp al, 0abh
    je .repeat
.ordinary_opcode:
    cmp al, 0fh
    je .extended
    cmp al, 17h
    je .pop_ss
    cmp al, 8eh
    je .mov_ss
    cmp al, 0fbh
    je .sti_enable
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
    cmp byte [ebp+dpmi_sti_shadow], 0
    je .pop_tf_ready
    mov eax, edx
    shr eax, 8
    and al, 1
    mov [ebp+dpmi_sti_tf], al
.pop_tf_ready:
    mov eax, ecx
    call .adjust_stack
    and edx, 0fffc8effh
    test edx, 200h
    jnz .pop_enabled
    mov word [ebp+dpmi_vif], 0100h
    or edx, 300h
    mov [ebx+56], edx
    pop edi
    add [ebx+48], edi
    jmp .next
.pop_enabled:
    mov [ebx+56], edx
    pop edi
    jmp .enable
.sti_enable:
    call dpmi_sti_begin
    jmp .done
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
    call dpmi_virtual_flags
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
    cmp byte [ebp+dpmi_sti_shadow], 0
    je .iret_tf_ready
    shr edi, 8
    and edi, 1
    mov eax, edi
    mov [ebp+dpmi_sti_tf], al
.iret_tf_ready:
    and edx, 0fffd8effh
    test edx, 200h
    jnz .iret_enabled
    mov word [ebp+dpmi_vif], 0100h
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
    cmp byte [ebp+dpmi_sti_shadow], 0
    je .next
    mov eax, [ebx+48]
    mov [ebp+dpmi_sti_ip], eax
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
.repeat:
    cmp dword [esp+12], 0
    jne .done
    sub esp, 48
    mov [esp], eax
    test al, 1
    jnz .repeat_width
    mov ecx, 1
.repeat_width:
    mov [esp+4], ecx
    mov [esp+8], edi
    mov eax, [ebx+32]
    mov edx, [ebx+8]
    mov esi, [ebx+12]
    cmp byte [ebp+dpmi_step_address_size], 2
    jne .repeat_count
    movzx eax, ax
    movzx edx, dx
    movzx esi, si
.repeat_count:
    mov [esp+16], eax
    mov [esp+20], esi
    mov [esp+24], edx
    test eax, eax
    jz .repeat_complete
    cmp eax, 64
    jbe .repeat_bound
    mov eax, 64
.repeat_bound:
    mov [esp+12], eax
    cmp byte [ebp+dpmi_step_address_size], 2
    jne .repeat_validate
    mov edi, 24
.repeat_wrap:
    mov eax, [esp+edi]
    test word [ebx+56], 400h
    jnz .repeat_capacity
    xor eax, 0ffffh
.repeat_capacity:
    xor edx, edx
    div dword [esp+4]
    inc eax
    cmp eax, [esp+12]
    jae .repeat_wrap_next
    mov [esp+12], eax
.repeat_wrap_next:
    cmp edi, 20
    je .repeat_validate
    cmp byte [esp], 0aah
    jae .repeat_validate
    mov edi, 20
    jmp .repeat_wrap
.repeat_validate:
    mov ecx, [esp+12]
    imul ecx, [esp+4]
    mov [esp+36], ecx
    mov esi, ecx
    sub esi, [esp+4]
    mov [esp+40], esi
    mov edx, [esp+24]
    test word [ebx+56], 400h
    jz .repeat_destination
    sub edx, esi
    jc .repeat_done
.repeat_destination:
    mov ax, [ebx]
    mov edi, 1
    call dpmi_buffer
    jc .repeat_done
    test word [ebx+56], 400h
    jz .repeat_destination_ready
    add eax, [esp+40]
.repeat_destination_ready:
    mov [esp+32], eax
    cmp byte [esp], 0aah
    jae .repeat_copy
    mov edx, [esp+20]
    test word [ebx+56], 400h
    jz .repeat_source
    sub edx, [esp+40]
    jc .repeat_done
.repeat_source:
    mov ax, [ebp+dpmi_step_segment]
    cmp ax, 0ffffh
    jne .repeat_source_selector
    mov ax, [ebx+4]
.repeat_source_selector:
    xor edi, edi
    call dpmi_buffer
    jc .repeat_done
    test word [ebx+56], 400h
    jz .repeat_source_ready
    add eax, [esp+40]
.repeat_source_ready:
    mov [esp+28], eax
.repeat_copy:
    mov esi, [esp+28]
    mov edi, [esp+32]
    mov ecx, [esp+12]
    cld
    test word [ebx+56], 400h
    jz .repeat_direction
    std
.repeat_direction:
    cmp byte [esp], 0aah
    jae .repeat_store
    cmp dword [esp+4], 1
    je .repeat_move_byte
    cmp dword [esp+4], 2
    je .repeat_move_word
    rep movsd
    jmp .repeat_advance
.repeat_move_byte:
    rep movsb
    jmp .repeat_advance
.repeat_move_word:
    rep movsw
    jmp .repeat_advance
.repeat_store:
    mov eax, [ebx+36]
    cmp dword [esp+4], 1
    je .repeat_store_byte
    cmp dword [esp+4], 2
    je .repeat_store_word
    rep stosd
    jmp .repeat_advance
.repeat_store_byte:
    rep stosb
    jmp .repeat_advance
.repeat_store_word:
    rep stosw
.repeat_advance:
    cld
    mov dword [esp+60], 1
    mov eax, [esp+36]
    test word [ebx+56], 400h
    jz .repeat_delta
    neg eax
.repeat_delta:
    mov edx, [esp+16]
    sub edx, [esp+12]
    cmp byte [ebp+dpmi_step_address_size], 2
    je .repeat_advance16
    mov [ebx+32], edx
    add [ebx+8], eax
    cmp byte [esp], 0aah
    jae .repeat_remaining
    add [ebx+12], eax
    jmp .repeat_remaining
.repeat_advance16:
    mov [ebx+32], dx
    add [ebx+8], ax
    cmp byte [esp], 0aah
    jae .repeat_remaining
    add [ebx+12], ax
.repeat_remaining:
    test edx, edx
    jnz .repeat_done
.repeat_complete:
    mov eax, [esp+8]
    add [ebx+48], eax
    mov dword [esp+60], 1
    add esp, 48
    jmp .next
.repeat_done:
    add esp, 48
    jmp .done
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
    cmp byte [ebp+dpmi_sti_shadow], 0
    je .ordinary_tf
    and eax, 0fffffeffh
    cmp byte [ebp+dpmi_sti_tf], 0
    je .done
    or eax, 100h
    ret
.ordinary_tf:
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

HOST_REAL
dpmi_vif db 1
dpmi_step_active db 0
HOST_PROTECTED
dpmi_step_address_size db 0
dpmi_step_segment dw 0
dpmi_step_ea_segment dw 0
dpmi_step_modrm db 0

HOST_PROTECTED
; EBX is a normalized frame; EDI is the decoded STI length.
dpmi_sti_begin:
    cmp byte [ebp+dpmi_vif], 0
    jne .enabled
    mov eax, [ebx+56]
    call dpmi_virtual_flags
    shr eax, 8
    and al, 1
    mov [ebp+dpmi_sti_tf], al
    mov ax, [ebx+52]
    mov [ebp+dpmi_sti_cs], ax
    mov eax, [ebx+48]
    add eax, edi
    mov [ebp+dpmi_sti_ip], eax
    mov byte [ebp+dpmi_sti_shadow], 1
.enabled:
    mov byte [ebp+dpmi_vif], 1
    mov byte [ebp+dpmi_step_active], 0
    or word [ebx+56], 200h
    add [ebx+48], edi
    ret

; EBX is the common five-dword return frame minus40 bytes.
dpmi_sti_arrival:
    cmp byte [ebp+dpmi_sti_shadow], 0
    je .done
    test byte [ebx+44], 3
    jz .done
    mov eax, [ebx+40]
    cmp eax, [ebp+dpmi_sti_ip]
    jne dpmi_sti_retire
    mov ax, [ebx+44]
    cmp ax, [ebp+dpmi_sti_cs]
    jne dpmi_sti_retire
.done:
    ret

dpmi_sti_retire:
    mov byte [ebp+dpmi_sti_shadow], 0
    cmp byte [ebp+dpmi_step_active], 0
    jne .done
    and word [ebx+48], 0feffh
    cmp byte [ebp+dpmi_sti_tf], 0
    je .done
    or word [ebx+48], 100h
.done:
    ret
%ifndef RESIDENT_HOST
HOST_REAL
dpmi_sti_shadow db 0
dpmi_sti_tf db 0
dpmi_sti_cs dw 0
dpmi_sti_ip dd 0
HOST_PROTECTED
%endif
