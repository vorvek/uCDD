; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 32
dpmi_callback_allocate:
    mov ax, [ebx]
    mov edx, [ebx+8]
    mov ecx, 50
    mov edi, 1
    call dpmi_buffer
    jc dpmi_error
    push eax
    mov ax, [ebx+4]
    mov edx, [ebx+12]
    call dpmi_code_target
    jc .bad
    push dword [esi]
    push dword [esi+4]
    lea edi, [ebp+dpmi_callbacks]
    mov ecx, 16
.slot:
    cmp word [edi], 0
    je .found
    add edi, 20
    loop .slot
    add esp, 12
    mov ax, 8015h
    jmp dpmi_error
.found:
    push edi
    mov ecx, 2
    call dpmi_descriptor_allocate
    pop edi
    jc .full
    mov edx, eax
    shr edx, 3
    mov word [ebp+dpmi_used+edx], 0404h
    mov [edi], ax
    add ax, 8
    mov [edi+2], ax
    pop eax
    and eax, 0ffff00ffh
    or eax, 0fa00h
    mov [esi+4], eax
    pop eax
    mov [esi], eax
    mov eax, [ebx+12]
    mov [edi+4], eax
    mov ax, [ebx]
    mov [edi+8], ax
    mov eax, [ebx+8]
    mov [edi+12], eax
    pop eax
    mov [edi+16], eax
    sub edi, ebp
    sub edi, dpmi_callbacks
    mov eax, edi
    xor edx, edx
    mov ecx, 20
    div ecx
    imul eax, 6
    add eax, dpmi_callback_stubs
    mov [ebx+28], ax
    mov eax, ebp
    shr eax, 4
    mov [ebx+32], ax
    jmp mon_dpmi.success
.full:
    add esp, 12
    mov ax, 8011h
    jmp dpmi_error
.bad:
    add esp, 4
    jmp dpmi_bad_selector
dpmi_callback_free:
    mov eax, ebp
    shr eax, 4
    cmp ax, [ebx+32]
    jne .bad
    movzx eax, word [ebx+28]
    sub eax, dpmi_callback_stubs
    jc .bad
    xor edx, edx
    mov ecx, 6
    div ecx
    test edx, edx
    jnz .bad
    cmp eax, 16
    jae .bad
    imul eax, 20
    lea edi, [ebp+dpmi_callbacks+eax]
    cmp byte [ebp+dpmi_callback_active], 0
    je .inactive
    movzx edx, word [ebp+dpmi_callback_index]
    imul edx, 20
    cmp eax, edx
    je .bad
.inactive:
    mov ax, [edi]
    test ax, ax
    jz .bad
    pushad
    movzx eax, word [ebx+28]
    add eax, ebp
    mov ecx, 6
    call dpmi_ivt_restore_range
    popad
    call dpmi_clear_selector
    add ax, 8
    call dpmi_clear_selector
    sub ax, 8
    shr eax, 3
    mov word [ebp+dpmi_used+eax], 0
    lea esi, [ebp+dpmi_ldt+eax*8]
    mov dword [esi], 0
    mov dword [esi+4], 0
    mov dword [esi+8], 0
    mov dword [esi+12], 0
    mov word [edi], 0
    jmp mon_dpmi.success
.bad:
    mov ax, 8024h
    jmp dpmi_error

dpmi_callback_pm:
    mov ax, 10h
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov ebp, edi
    lea esp, [ebp+dpmi_callback_kernel_top]
    mov [ebp+mon_tss+4], esp
    lea esi, [ebp+mon_return]
    lea edi, [ebp+dpmi_callback_context]
    mov ecx, 9
    cld
    rep movsd
    mov eax, [ebp+mon_resume_sp]
    stosd
    mov eax, [ebp+mon_rm_target]
    stosd
    lea esi, [ebp+mon_rm_regs]
    mov ecx, 50
    rep movsb
    mov ax, [ebp+mon_rm_kind]
    stosw
    mov eax, [ebp+dpmi_callback_resume]
    stosd
    mov ax, [ebp+dpmi_vif]
    stosw
    mov word [ebp+dpmi_vif], 0100h
    mov dword [ebp+mon_return+12], dpmi_callback_real_top
    mov eax, ebp
    shr eax, 4
    mov [ebp+mon_return+16], eax
    movzx eax, word [ebp+dpmi_callback_index]
    cmp eax, 16
    jae dpmi_callback_abort
    imul eax, 20
    lea ebx, [ebp+dpmi_callbacks+eax]
    cmp word [ebx], 0
    je dpmi_callback_abort
    mov ax, [ebx+8]
    mov edx, [ebx+12]
    mov ecx, 50
    mov edi, 1
    call dpmi_buffer
    jc dpmi_callback_abort
    mov [ebx+16], eax
    lea esi, [ebp+dpmi_callback_regs]
    mov edi, [ebx+16]
    mov ecx, 50
    rep movsb
    mov ax, [ebx+2]
    call dpmi_descriptor
    mov word [esi], 0ffffh
    movzx eax, word [ebp+dpmi_callback_regs+48]
    shl eax, 4
    mov [esi+2], ax
    shr eax, 16
    mov [esi+4], al
    mov byte [esi+6], 0
    mov byte [esi+7], 0
    mov eax, 3fe000h+4096-12
    lea edx, [ebp+dpmi_callback_return]
    mov [eax], edx
    mov dword [eax+4], 23h
    mov dword [eax+8], 2
    push dword DPMI_CALLBACK_SS
    push dword 4096-12
    push dword 2
    movzx eax, word [ebx]
    push eax
    push dword [ebx+4]
    movzx esi, word [ebp+dpmi_callback_regs+46]
    mov edi, [ebx+12]
    mov es, [ebx+8]
    mov ds, [ebx+2]
    MON_IRETD
dpmi_callback_return:
    int 0f1h
    ud2
dpmi_callback_done:
    push eax
    push ebp
    call .check_base
.check_base:
    pop ebp
    sub ebp, .check_base
    cmp byte [cs:ebp+dpmi_callback_active], 1
    jne .bad_gate
    cmp word [ss:esp+12], 23h
    jne .bad_gate
    lea eax, [ebp+dpmi_callback_return+2]
    cmp [ss:esp+8], eax
    jne .bad_gate
    cmp word [ss:esp+24], DPMI_CALLBACK_SS
    jne .bad_gate
    mov eax, 4096
    cmp [ss:esp+20], eax
    jne .bad_gate
    pop ebp
    pop eax
    jmp .valid_gate
.bad_gate:
    pop ebp
    pop eax
    push dword 0
    push dword 13
    jmp mon_exception
.valid_gate:
    mov ax, 10h
    mov ds, ax
    mov es, ax
    call .base
.base:
    pop ebp
    sub ebp, .base
    movzx eax, word [ebp+dpmi_callback_index]
    imul eax, 20
    lea ebx, [ebp+dpmi_callbacks+eax]
    mov ax, [ebx+8]
    mov edx, [ebx+12]
    mov ecx, 50
    xor edi, edi
    call dpmi_buffer
    jc dpmi_callback_abort
    mov esi, eax
    lea edi, [ebp+dpmi_callback_regs]
    mov ecx, 50
    cld
    rep movsb
    lea esi, [ebp+dpmi_callback_context]
    lea edi, [ebp+mon_return]
    mov ecx, 9
    rep movsd
    lodsd
    mov [ebp+mon_resume_sp], eax
    lodsd
    mov [ebp+mon_rm_target], eax
    lea edi, [ebp+mon_rm_regs]
    mov ecx, 50
    rep movsb
    lodsw
    mov [ebp+mon_rm_kind], ax
    lodsd
    mov [ebp+mon_switch+16], eax
    lodsw
    mov [ebp+dpmi_vif], ax
    lea eax, [ebp+mon_kernel_stack_top]
    mov [ebp+mon_tss+4], eax
    lea edi, [ebp+dpmi_callback_return_frame]
    mov dword [edi], dpmi_callback_real_return
    mov eax, ebp
    shr eax, 4
    mov [edi+4], eax
    mov dword [edi+8], 23002h
    movzx eax, word [ebp+dpmi_callback_regs+46]
    mov [edi+12], eax
    movzx eax, word [ebp+dpmi_callback_regs+48]
    mov [edi+16], eax
    lea esi, [ebp+dpmi_callback_regs+34]
    add edi, 20
    mov ecx, 4
.segments:
    movzx eax, word [esi]
    stosd
    add esi, 2
    loop .segments
    mov byte [ebp+dpmi_callback_active], 0
    cli
    mov ax, 10h
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    lea esp, [ebp+dpmi_callback_return_frame]
    cmp byte [ebp+mon_vcpi_flags_slot], 0
    je .return_stack_ready
    mov word [esp-2], 0
    sub esp, 2
.return_stack_ready:
    clts
    mov ax, 0de0ch
    call far [ebp+mon_server]
    ud2

dpmi_callback_abort:
    mov word [ebp+mon_status], 14
    jmp dpmi_finish
dpmi_callback_abort_entry:
    mov ax, 10h
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov ebp, edi
    lea esp, [ebp+mon_kernel_stack_top]
    jmp dpmi_callback_abort

bits 16
dpmi_callback_stubs:
%assign slot 0
%rep 16
    push strict word slot
    jmp near dpmi_callback_enter
%assign slot slot+1
%endrep
dpmi_callback_enter:
    pushf
    cli
    cmp byte [cs:dpmi_callback_active], 0
    jne .nested
    pop word [cs:dpmi_callback_regs+32]
    mov [cs:dpmi_callback_regs], edi
    mov [cs:dpmi_callback_regs+4], esi
    mov [cs:dpmi_callback_regs+8], ebp
    mov [cs:dpmi_callback_regs+16], ebx
    mov [cs:dpmi_callback_regs+20], edx
    mov [cs:dpmi_callback_regs+24], ecx
    mov [cs:dpmi_callback_regs+28], eax
    pop word [cs:dpmi_callback_index]
    mov [cs:dpmi_callback_regs+34], es
    mov [cs:dpmi_callback_regs+36], ds
    mov [cs:dpmi_callback_regs+38], fs
    mov [cs:dpmi_callback_regs+40], gs
    mov [cs:dpmi_callback_regs+46], sp
    mov [cs:dpmi_callback_regs+48], ss
    mov byte [cs:dpmi_callback_active], 1
    mov ax, cs
    mov ds, ax
    mov ss, ax
    mov sp, dpmi_callback_real_top
    and byte [mon_gdt+24+5], 0fdh
    mov edi, [mon_base]
    mov eax, [mon_switch+16]
    mov [dpmi_callback_resume], eax
    lea eax, [edi+dpmi_callback_pm]
    mov [mon_switch+16], eax
    lea esi, [edi+mon_switch]
    mov ax, 0de0ch
    int 67h
    ud2
.nested:
    mov ax, cs
    mov ds, ax
    mov ss, ax
    mov sp, dpmi_callback_real_top
    and byte [mon_gdt+24+5], 0fdh
    mov edi, [mon_base]
    lea eax, [edi+dpmi_callback_abort_entry]
    mov [mon_switch+16], eax
    lea esi, [edi+mon_switch]
    mov ax, 0de0ch
    int 67h
    ud2
dpmi_callback_real_return:
    push word [cs:dpmi_callback_regs+32]
    push word [cs:dpmi_callback_regs+44]
    push word [cs:dpmi_callback_regs+42]
    mov edi, [cs:dpmi_callback_regs]
    mov esi, [cs:dpmi_callback_regs+4]
    mov ebp, [cs:dpmi_callback_regs+8]
    mov ebx, [cs:dpmi_callback_regs+16]
    mov edx, [cs:dpmi_callback_regs+20]
    mov ecx, [cs:dpmi_callback_regs+24]
    mov eax, [cs:dpmi_callback_regs+28]
    iret

dpmi_callbacks times 16*20 db 0
dpmi_callback_active db 0
dpmi_callback_index dw 0
dpmi_callback_regs times 50 db 0
dpmi_callback_context times 102 db 0
dpmi_callback_resume dd 0
    times 32 db 0
dpmi_callback_return_frame times 36 db 0
    times 512 db 0
dpmi_callback_real_top:
    times 2048 db 0
dpmi_callback_kernel_top:
dpmi_callback_user_top:
bits 32
