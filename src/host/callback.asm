; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

HOST_PROTECTED
dpmi_callback_allocate:
    mov ax, [ebx]
    mov edx, [ebx+8]
    DPMI_OFFSET16 edx, dx
    mov ecx, 50
    mov edi, 1
    call dpmi_buffer
    jc dpmi_error
    push eax
    mov ax, [ebx+4]
    mov edx, [ebx+12]
    DPMI_OFFSET16 edx, dx
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
    DPMI_OFFSET16 eax, ax
    mov [edi+4], eax
    mov ax, [ebx]
    mov [edi+8], ax
    mov eax, [ebx+8]
    DPMI_OFFSET16 eax, ax
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
    mov eax, [ebp+mon_real_base]
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
    mov eax, [ebp+mon_real_base]
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
    add eax, [ebp+mon_real_base]
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
    call dpmi_debug_host_save
    mov eax, [ebp+mon_tss+4]
    mov [ebp+dpmi_callback_context+102], eax
    mov eax, [ebp+mon_rm_stack]
    mov [ebp+dpmi_callback_context+106], eax
    mov eax, [ebp+mon_rm_irq_target]
    mov [ebp+dpmi_callback_context+110], eax
    mov al, [ebp+mon_int_opcode+1]
    mov [ebp+dpmi_callback_context+114], al
    mov al, [ebp+dpmi_reflect_vector]
    mov [ebp+dpmi_callback_context+115], al
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
    mov eax, [ebp+dpmi_sti_shadow]
    mov [ebp+dpmi_callback_sti], eax
    mov eax, [ebp+dpmi_sti_ip]
    mov [ebp+dpmi_callback_sti+4], eax
    mov byte [ebp+dpmi_sti_shadow], 0
    mov word [ebp+dpmi_vif], 0
    mov dword [ebp+mon_return+12], dpmi_callback_real_top
    mov eax, [ebp+mon_real_base]
    shr eax, 4
    mov [ebp+mon_return+16], eax
    movzx eax, word [ebp+dpmi_callback_index]
    cmp eax, 16
    jae dpmi_callback_abort
    imul eax, 20
    lea ebx, [ebp+dpmi_callbacks+eax]
    cmp word [ebx], 0
    je dpmi_callback_abort
%ifdef RESIDENT_HOST
    ; A parent's callback can run while its child is current.
    mov ax, [ebx]
    call dpmi_nested_enter
    setc [ebp+dpmi_callback_flip]
%endif
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
    cmp byte [ebp+dpmi_client16], 0
    jne .word_frame
    mov eax, 3fe000h+4096-12
    lea edx, [ebp+dpmi_callback_return]
    mov [eax], edx
    mov dword [eax+4], 23h
    mov dword [eax+8], 2
    push dword DPMI_CALLBACK_SS
    push dword 4096-12
    jmp .framed
.word_frame:
    ; A 16-bit procedure returns with a 16-bit IRET.
    mov eax, 3fe000h+4096-6
    mov word [eax], dpmi_callback_return
    mov word [eax+2], DPMI_STUB16
    mov word [eax+4], 2
    push dword DPMI_CALLBACK_SS
    push dword 4096-6
.framed:
    push dword 202h
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
    DPMI_DEBUG_STOP
    push eax
    push ebp
    call .check_base
.check_base:
    pop ebp
    sub ebp, .check_base
    cmp byte [cs:ebp+dpmi_callback_active], 1
    jne .bad_gate
    cmp word [ss:esp+12], 23h
    jne .word_gate
    lea eax, [ebp+dpmi_callback_return+2]
    cmp [ss:esp+8], eax
    jne .bad_gate
    jmp .gate_address
.word_gate:
    cmp word [ss:esp+12], DPMI_STUB16
    jne .bad_gate
    cmp dword [ss:esp+8], dpmi_callback_return+2
    jne .bad_gate
.gate_address:
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
    ; A procedure that popped an IRET frame gets the IF of that frame.
    movzx eax, word [ebp+dpmi_callback_regs+48]
    shl eax, 4
    movzx edx, word [ebp+dpmi_callback_regs+46]
    cmp edx, 6
    jb .flags_ready
    add eax, edx
    mov dx, [eax-6]
    cmp dx, [ebp+dpmi_callback_regs+42]
    jne .flags_ready
    mov dx, [eax-4]
    cmp dx, [ebp+dpmi_callback_regs+44]
    jne .flags_ready
    mov dx, [eax-2]
    and dx, 200h
    and word [ebp+dpmi_callback_regs+32], 0fdffh
    or [ebp+dpmi_callback_regs+32], dx
.flags_ready:
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
    mov eax, [ebp+dpmi_callback_context+102]
    mov [ebp+mon_tss+4], eax
    mov eax, [ebp+dpmi_callback_context+106]
    mov [ebp+mon_rm_stack], eax
    mov eax, [ebp+dpmi_callback_context+110]
    mov [ebp+mon_rm_irq_target], eax
    mov al, [ebp+dpmi_callback_context+114]
    mov [ebp+mon_int_opcode+1], al
    mov al, [ebp+dpmi_callback_context+115]
    mov [ebp+dpmi_reflect_vector], al
    lea edi, [ebp+dpmi_callback_return_frame]
    mov dword [edi], dpmi_callback_real_return
    mov eax, [ebp+mon_real_base]
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
    push eax
    mov al, [ebp+dpmi_cb_rm]
    mov [ebp+dpmi_rm_call], al
    pop eax
%ifdef RESIDENT_HOST
    shr byte [ebp+dpmi_callback_flip], 1
    jnc .size_ready
    call dpmi_nested_toggle
.size_ready:
%endif
    cli
    mov ax, 10h
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    lea esp, [ebp+dpmi_callback_return_frame]
    sub esp, ebp
    add esp, [ebp+mon_real_base]
    clts
    mov ax, 0de0ch
    call far [ebp+mon_server]
    ud2

dpmi_callback_abort:
    mov word [ebp+mon_status], DPMI_ABORT_CALLBACK
    jmp dpmi_finish
dpmi_callback_abort_entry:
    mov ax, 10h
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov ebp, edi
    lea esp, [ebp+mon_kernel_stack_top]
    jmp dpmi_callback_abort

HOST_REAL
dpmi_callback_stubs:
%assign slot 0
%rep 16
    push strict word slot
    jmp strict near dpmi_callback_enter
%assign slot slot+1
%endrep
    times 0 / (($-dpmi_callback_stubs) = 16*6) db 0
; INT 33h 0Ch handler. Keep the event: dpmi_mouse_deliver calls the client's
; handler outside this IRQ (Igor reads the disk in its timer handler).
dpmi_mouse_stub:
    cmp word [cs:dpmi_mouse_vector+4], 0
    je .done
    pushf
    cli
    cmp byte [cs:dpmi_mouse_pending], 0
    je .new
    or [cs:dpmi_mouse_regs], ax
    jmp .stored
.new:
    mov [cs:dpmi_mouse_regs], ax
.stored:
    mov [cs:dpmi_mouse_regs+2], bx
    mov [cs:dpmi_mouse_regs+4], cx
    mov [cs:dpmi_mouse_regs+6], dx
    mov [cs:dpmi_mouse_regs+8], si
    mov [cs:dpmi_mouse_regs+10], di
    mov byte [cs:dpmi_mouse_pending], 1
    popf
.done:
    retf
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
    mov al, [cs:dpmi_rm_call]
    mov [cs:dpmi_cb_rm], al
    cmp al, 1
    jne .rm_kept
    mov byte [cs:dpmi_rm_call], 2
.rm_kept:
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
    mov esi, [mon_real_base]
    add esi, mon_switch
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
    mov esi, [mon_real_base]
    add esi, mon_switch
    mov ax, 0de0ch
    int 67h
    ud2
dpmi_callback_real_return:
    and byte [cs:dpmi_callback_regs+33], 0feh
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

dpmi_callback_active db 0
dpmi_mouse_pending db 0
dpmi_mouse_depth db 0
dpmi_mouse_vector dd 0
    dw 0
dpmi_mouse_regs times 6 dw 0
dpmi_mouse_ebx dd 0
dpmi_mouse_ax dw 0
dpmi_mouse_wide db 0
dpmi_callback_index dw 0
dpmi_callback_regs times 50 db 0
dpmi_callback_resume dd 0
dpmi_callback_return_frame times 36 db 0
    times 32 db 0
    times 512 db 0
dpmi_callback_real_top:
HOST_PROTECTED
%ifndef RESIDENT_HOST
    times 1920 db 0
dpmi_callback_kernel_top:
%endif
dpmi_callbacks times 16*20 db 0
dpmi_callback_context times 116 db 0

HOST_PROTECTED
dpmi_callback_sti times 8 db 0
