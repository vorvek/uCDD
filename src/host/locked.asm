; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

HOST_PROTECTED
%define DPMI_LOCK_BASE 3e0000h
%define DPMI_LOCK_LEVELS 4
%define DPMI_LOCK_PAGES 7
dpmi_locked_init:
    pushad
    xor ebx, ebx
.page:
%ifdef DPMI_LOCK_FAIL_PAGE
    cmp ebx, DPMI_LOCK_FAIL_PAGE
    je .bad
%endif
%ifdef DPMI_LOCK_FAIL_SECOND
    cmp ebx, 1
    je .bad
%endif
    call dpmi_page_allocate
    jc .bad
    mov [ebp+dpmi_locked_pages+ebx*4], edx
    mov edi, [ebp+dpmi_locked_linear+ebx*4]
    shr edi, 10
    add edi, 0ffc00000h
    mov eax, [edi]
    mov [ebp+dpmi_locked_ptes+ebx*4], eax
    or edx, 7
    mov [edi], edx
    call dpmi_flush
    mov edi, [ebp+dpmi_locked_linear+ebx*4]
    xor eax, eax
    mov ecx, 1024
    cld
    rep stosd
    inc ebx
    cmp ebx, DPMI_LOCK_PAGES
    jb .page
    mov dword [ebp+dpmi_ldt+6*8], 00003fffh
    mov dword [ebp+dpmi_ldt+6*8+4], 0040f23eh
    mov dword [ebp+dpmi_ldt+7*8], 0e0000fffh
    mov dword [ebp+dpmi_ldt+7*8+4], 0040f23fh
    mov word [ebp+dpmi_used+6], 0404h
    mov dword [ebp+dpmi_locked_cursor], 4096
    mov dword [ebp+dpmi_locked_depth], 0
    mov dword [ebp+dpmi_stack_depth], 0
    popad
    clc
    ret
.bad:
    call dpmi_locked_free
    popad
    stc
    ret

dpmi_locked_free:
    pushad
    xor ebx, ebx
.page:
    mov edx, [ebp+dpmi_locked_pages+ebx*4]
    test edx, edx
    jz .next
    mov eax, [ebp+dpmi_locked_ptes+ebx*4]
    mov edi, [ebp+dpmi_locked_linear+ebx*4]
    shr edi, 10
    mov [0ffc00000h+edi], eax
    call dpmi_flush
    call dpmi_page_free
    mov dword [ebp+dpmi_locked_pages+ebx*4], 0
.next:
    inc ebx
    cmp ebx, DPMI_LOCK_PAGES
    jb .page
    popad
    ret

; EBX points to a five-dword protected interrupt frame minus 40 bytes.
dpmi_locked_capture:
    test byte [ebx+44], 3
    jz .done
    cmp word [ebx+56], DPMI_IRQ_SS
    jne .done
    push eax
    mov eax, [ebx+52]
    mov [ebp+dpmi_locked_cursor], eax
    pop eax
.done:
    ret

dpmi_deliver_hardware:
    call dpmi_locked_capture
    call dpmi_stack_acquire
    push esi
    mov edx, [esi]
    mov ax, [esi+4]
    call dpmi_code_target
    pop esi
    jc dpmi_locked_abort
    mov edi, [ebp+dpmi_locked_cursor]
    mov edx, edi
    sub edi, 28
    mov [ebp+dpmi_locked_cursor], edi
    add edi, DPMI_LOCK_BASE
    mov [edi+20], edx
    mov dword [edi+24], 48495251h
    mov eax, [ebx+40]
    mov [edi], eax
    mov eax, [ebx+44]
    mov [edi+4], eax
    mov eax, [ebx+48]
    call dpmi_virtual_flags
    mov [edi+8], eax
    mov eax, [ebx+52]
    mov [edi+12], eax
    mov eax, [ebx+56]
    mov [edi+16], eax
    sub edi, 12
    mov dword [edi], dpmi_locked_return
    mov dword [edi+4], 3bh
    mov dword [edi+8], 2
    sub edi, DPMI_LOCK_BASE
    mov [ebx+52], edi
    mov dword [ebx+56], DPMI_IRQ_SS
    mov eax, [esi]
    mov [ebx+40], eax
    movzx eax, word [esi+4]
    mov [ebx+44], eax
    and word [ebx+48], 0feffh
    or word [ebx+48], 200h
    mov word [ebp+dpmi_vif], 0
    inc dword [ebp+dpmi_locked_depth]
    jmp mon_dpmi.done

dpmi_locked_return:
    int 0f4h
    ud2

dpmi_locked_done:
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
    cmp dword [ebp+dpmi_locked_depth], 0
    je dpmi_locked_abort
    cmp word [esp+44], 3bh
    jne dpmi_locked_abort
    cmp dword [esp+40], dpmi_locked_return+2
    jne dpmi_locked_abort
    cmp word [esp+56], DPMI_IRQ_SS
    jne dpmi_locked_abort
    mov esi, [esp+52]
    mov eax, [ebp+dpmi_stack_depth]
    test eax, eax
    jz dpmi_locked_abort
    shl eax, 12
    sub eax, 28
    cmp esi, eax
    ja dpmi_locked_abort
    sub eax, 4096-28
    cmp esi, eax
    jb dpmi_locked_abort
    add esi, DPMI_LOCK_BASE
    cmp dword [esi+24], 48495251h
    jne dpmi_locked_abort
    mov eax, [esi+20]
    mov edx, [esp+52]
    add edx, 28
    cmp eax, edx
    jne dpmi_locked_abort
    push esi
    mov edx, [esi]
    mov ax, [esi+4]
    call dpmi_code_target
    pop esi
    jc dpmi_locked_abort
    mov edx, [esi+12]
    mov ax, [esi+16]
    call dpmi_stack_target
    jc dpmi_locked_abort
    lea edi, [esp+40]
    mov ecx, 5
    cld
    rep movsd
    mov eax, [esp+48]
    call dpmi_restore_flags
    mov [esp+48], eax
    dec dword [ebp+dpmi_locked_depth]
    call dpmi_stack_release
    jmp mon_dpmi.done

dpmi_hardware_room:
    cmp dword [ebp+dpmi_stack_depth], DPMI_LOCK_LEVELS
    jb .available
    stc
    ret
.available:
    clc
    ret

dpmi_stack_acquire:
    push eax
    mov eax, [ebp+dpmi_stack_depth]
    cmp eax, DPMI_LOCK_LEVELS
    jae dpmi_locked_abort
    push edx
    mov edx, [ebp+dpmi_locked_cursor]
    mov [ebp+dpmi_stack_cursors+eax*4], edx
    pop edx
    inc eax
    mov [ebp+dpmi_stack_depth], eax
    shl eax, 12
    mov [ebp+dpmi_locked_cursor], eax
    pop eax
    ret

dpmi_stack_release:
    push eax
    mov eax, [ebp+dpmi_stack_depth]
    test eax, eax
    jz dpmi_locked_abort
    dec eax
    mov [ebp+dpmi_stack_depth], eax
    mov eax, [ebp+dpmi_stack_cursors+eax*4]
    mov [ebp+dpmi_locked_cursor], eax
    pop eax
    ret

dpmi_stack_depth dd 0
dpmi_stack_cursors times DPMI_LOCK_LEVELS dd 0

dpmi_locked_abort:
    mov word [ebp+mon_status], 14
    mov byte [ebp+dpmi_exit_code], 1
    jmp dpmi_finish

dpmi_locked_linear dd 3fe000h,DPMI_LOCK_BASE,3fa000h,3fb000h,DPMI_LOCK_BASE+4096,DPMI_LOCK_BASE+8192,DPMI_LOCK_BASE+12288
dpmi_locked_pages times DPMI_LOCK_PAGES dd 0
dpmi_locked_ptes times DPMI_LOCK_PAGES dd 0
dpmi_locked_cursor dd 4096
HOST_REAL
dpmi_locked_depth dd 0
HOST_PROTECTED
dpmi_exception_sp dd 0
dpmi_exception_cursor dd 0
