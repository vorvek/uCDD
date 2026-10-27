; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

HOST_PROTECTED
%define DPMI_LOCK_BASE 3e0000h
%define DPMI_LOCK_LEVELS 8
%define DPMI_HARDWARE_FRAME 68
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
    mov dword [ebp+dpmi_ldt+6*8], 00007fffh
    mov dword [ebp+dpmi_ldt+6*8+4], 0040f23eh
    mov dword [ebp+dpmi_ldt+7*8], 0e0000fffh
    mov dword [ebp+dpmi_ldt+7*8+4], 0040f23fh
    cmp byte [ebp+dpmi_client16], 0
    je .stack_ready
    and byte [ebp+dpmi_ldt+6*8+6], 0bfh
    and byte [ebp+dpmi_ldt+7*8+6], 0bfh
.stack_ready:
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

; EBX=client frame that starts with ES and DS. Keep the segments of the
; client's last protected-mode entry for interrupts that arrive in real mode.
dpmi_record_segments:
    test byte [ebx+44], 3
    jz .done
    test byte [ebx+50], 2
    jnz .done
    push eax
    mov eax, [ebx]
    mov [ebp+dpmi_client_segs], ax
    mov eax, [ebx+4]
    mov [ebp+dpmi_client_segs+2], ax
    mov [ebp+dpmi_client_segs+4], fs
    mov [ebp+dpmi_client_segs+6], gs
    pop eax
.done:
    ret

; Load the recorded FS and GS. Return ES in AX and DS in DX.
dpmi_client_segments:
    push ecx
    mov ecx, [ebp+dpmi_client_segs+4]
    call dpmi_load_fs_gs
    mov dx, 2bh
    mov ax, [ebp+dpmi_client_segs+2]
    call dpmi_usable_selector
    push eax
    mov ax, [ebp+dpmi_client_segs]
    call dpmi_usable_selector
    pop edx
    pop ecx
    ret

; ECX=FS in the low word and GS in the high word. Unusable selectors load 0.
dpmi_load_fs_gs:
    push eax
    push edx
    xor edx, edx
    mov ax, cx
    call dpmi_usable_selector
    mov fs, ax
    shr ecx, 16
    mov ax, cx
    call dpmi_usable_selector
    mov gs, ax
    pop edx
    pop eax
    ret

; Replace AX with DX when AX is not a present readable segment.
dpmi_usable_selector:
    push ecx
    verr ax
    jnz .other
    lar ecx, ax
    test ch, 80h
    jnz .done
.other:
    mov ax, dx
.done:
    pop ecx
    ret

dpmi_client_segs times 4 dw 0
dpmi_raw_segs dd 0

dpmi_deliver_hardware:
    push dword 48495251h
    jmp dpmi_deliver_locked

dpmi_deliver_software:
    push dword 53495251h

dpmi_deliver_locked:
    call dpmi_locked_capture
    call dpmi_stack_acquire
%ifdef RESIDENT_HOST
    cmp byte [ebp+dpmi_sb_next], 0
    je .sb_marked
    mov byte [ebp+dpmi_sb_next], 0
    mov byte [ebp+dpmi_sb_handler], 1
    mov eax, [ebp+dpmi_stack_depth]
    mov [ebp+dpmi_sb_level], eax
.sb_marked:
    mov ax, [esi+4]
    call dpmi_nested_enter
    setc [ebp+dpmi_nested_entered]
%endif
    push esi
    mov edx, [esi]
    mov ax, [esi+4]
    call dpmi_code_target
    pop esi
    jc dpmi_locked_abort
    mov edi, [ebp+dpmi_locked_cursor]
    mov edx, edi
    sub edi, DPMI_HARDWARE_FRAME
    mov [ebp+dpmi_locked_cursor], edi
    add edi, DPMI_LOCK_BASE
    mov [edi+20], edx
    pop dword [edi+24]
    push dword [edi+24]
    ; Keep the interrupted registers across the client handler.
%assign saved_reg 0
%rep 10
    mov eax, [ebx+saved_reg]
    mov [edi+28+saved_reg], eax
%assign saved_reg saved_reg+4
%endrep
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
%ifdef RESIDENT_HOST
    ; Bit 0 of the marker is clear when the handler belongs to the other client.
    shr byte [ebp+dpmi_nested_entered], 1
    jnc .size_ready
    and byte [edi+24], 0feh
.size_ready:
%endif
    cmp byte [ebp+dpmi_client16], 0
    jne .word_frame
    sub edi, 12
    mov dword [edi], dpmi_locked_return
    mov dword [edi+4], 3bh
    mov dword [edi+8], 2
    jmp .framed
.word_frame:
    ; A 16-bit handler returns with a 16-bit IRET.
    sub edi, 6
    mov word [edi], dpmi_locked_return
    mov word [edi+2], DPMI_STUB16
    mov word [edi+4], 2
.framed:
    shr byte [ebp+dpmi_mouse_frame], 1
    jnc .frame_ready
    ; A mouse handler returns with RETF to an IRET.
    cmp byte [ebp+dpmi_client16], 0
    jne .word_return
    sub edi, 8
    mov dword [edi], dpmi_mouse_return
    mov dword [edi+4], 3bh
    jmp .mouse_registers
.word_return:
    sub edi, 4
    mov word [edi], dpmi_mouse_return
    mov word [edi+2], DPMI_STUB16
.mouse_registers:
    xor eax, eax
    mov [ebx], eax
    mov [ebx+4], eax
    mov ax, [ebp+dpmi_mouse_regs]
    mov [ebx+36], eax
    mov ax, [ebp+dpmi_mouse_regs+2]
    mov [ebx+24], eax
    mov ax, [ebp+dpmi_mouse_regs+4]
    mov [ebx+32], eax
    mov ax, [ebp+dpmi_mouse_regs+6]
    mov [ebx+28], eax
    mov ax, [ebp+dpmi_mouse_regs+8]
    mov [ebx+12], eax
    mov ax, [ebp+dpmi_mouse_regs+10]
    mov [ebx+8], eax
.frame_ready:
    sub edi, DPMI_LOCK_BASE
    mov [ebx+52], edi
    mov dword [ebx+56], DPMI_IRQ_SS
    mov eax, [esi]
    call dpmi_handler_entry
    mov [ebx+40], eax
    movzx eax, word [esi+4]
    mov [ebx+44], eax
    and word [ebx+48], 0feffh
    or word [ebx+48], 200h
    pop eax
    cmp eax, 53495251h
    je .software_flags
    mov word [ebp+dpmi_vif], 0
.software_flags:
    inc dword [ebp+dpmi_locked_depth]
    jmp mon_dpmi.done

; EAX=handler offset, ESI=vector (selector at +4). Return the offset past
; zero bytes at its start. World Rally Fever sets its IRQ 0 vector 4 bytes
; before the handler, on zero padding: 00 00 is ADD [EAX],AL, and with EAX
; from the interrupted code it wrote into the IVT. Natively EAX is 0 there.
dpmi_handler_entry:
    push ecx
    push edx
    push esi
    push edi
    mov edi, eax
    mov ax, [esi+4]
    call dpmi_descriptor
    jc .done
    call dpmi_descriptor_base
    add eax, edi
    mov ecx, eax
    and ecx, 0fffh
    cmp ecx, 0ff0h
    ja .done
    mov ecx, eax
    shr ecx, 22
    test byte [0fffff000h+ecx*4], 1
    jz .done
    mov ecx, eax
    shr ecx, 12
    test byte [0ffc00000h+ecx*4], 1
    jz .done
    cmp word [eax], 0
    jne .done
    mov ecx, 2
.zero:
    cmp byte [eax+ecx], 0
    jne .code
    inc ecx
    cmp ecx, 16
    jb .zero
    jmp .done
.code:
    test cl, 1
    jnz .done
    add edi, ecx
    inc dword [ebp+dpmi_entry_skips]
.done:
    mov eax, edi
    pop edi
    pop esi
    pop edx
    pop ecx
    ret

dpmi_locked_return:
    int 0f4h
    ud2
dpmi_mouse_return:
    iret

; EBX=frame. Call the client's INT 33h 0Ch handler with the last event.
dpmi_mouse_deliver:
    mov byte [ebp+dpmi_mouse_pending], 0
    mov byte [ebp+dpmi_mouse_frame], 1
    lea esi, [ebp+dpmi_mouse_vector]
    jmp dpmi_deliver_hardware

dpmi_locked_done:
    DPMI_DEBUG_STOP
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
    je .stub
    cmp word [esp+44], DPMI_STUB16
    jne dpmi_locked_abort
.stub:
    cmp dword [esp+40], dpmi_locked_return+2
    jne dpmi_locked_abort
    cmp word [esp+56], DPMI_IRQ_SS
    jne dpmi_locked_abort
    mov esi, [esp+52]
    mov eax, [ebp+dpmi_stack_depth]
    test eax, eax
    jz dpmi_locked_abort
    shl eax, 12
    sub eax, DPMI_HARDWARE_FRAME
    cmp esi, eax
    ja dpmi_locked_abort
    sub eax, 4096-DPMI_HARDWARE_FRAME
    cmp esi, eax
    jb dpmi_locked_abort
    add esi, DPMI_LOCK_BASE
%ifdef RESIDENT_HOST
    ; The interrupted code gets its code size back.
    bts dword [esi+24], 0
    jc .size_ready
    call dpmi_nested_toggle
.size_ready:
%endif
    cmp dword [esi+24], 48495251h
    je .marker_ready
    cmp dword [esi+24], 53495251h
    jne dpmi_locked_abort
.marker_ready:
    mov eax, [esi+20]
    mov edx, [esp+52]
    add edx, DPMI_HARDWARE_FRAME
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
    call dpmi_stack_selector
    jc dpmi_locked_abort
    cmp dword [esi+24], 53495251h
    je .registers_ready
%assign saved_reg 0
%rep 10
    mov eax, [esi+28+saved_reg]
    mov [esp+saved_reg], eax
%assign saved_reg saved_reg+4
%endrep
.registers_ready:
    lea edi, [esp+40]
    mov ecx, 5
    cld
    rep movsd
    dec dword [ebp+dpmi_locked_depth]
    mov eax, [esp+48]
    call dpmi_restore_flags
    mov [esp+48], eax
    call dpmi_stack_release
%ifdef RESIDENT_HOST
    cmp byte [ebp+dpmi_sb_resume], 0
    jne dpmi_sb_resume_deliver
%endif
    jmp mon_dpmi.done

%ifdef RESIDENT_HOST
; The SB handler returned. Deliver the SB IRQ that waited for it, as the
; step check of dpmi.asm does.
dpmi_sb_resume_deliver:
    mov byte [ebp+dpmi_sb_resume], 0
    cmp byte [ebp+dpmi_sti_shadow], 0
    jne .later
    cmp byte [ebp+dpmi_sti_sb_held], 0
    jne .later
    cmp byte [ebp+dpmi_vif], 1
    jne .later
    test byte [esp+44], 3
    jz .later
    movzx eax, byte [ebp+dpmi_guest_vector]
    imul eax, 6
    cmp word [ebp+mon_vectors+eax+4], 0
    je .later
    call dpmi_pic_audio_allowed
    jc .later
    call resident_audio_take
    cmp ax, 1
    jne .later
    call resident_audio_deliver
    jc .later
    movzx eax, byte [ebp+dpmi_guest_vector]
    imul eax, 6
    lea esi, [ebp+mon_vectors+eax]
    mov byte [ebp+dpmi_sb_next], 1
    inc dword [ebp+dpmi_sb_resumed]
    mov ebx, esp
    jmp dpmi_deliver_hardware
.later:
    jmp mon_dpmi.done
%endif

dpmi_hardware_room:
%ifdef RESIDENT_HOST
    ; Hold client interrupts while the CD refill runs inside DOS.
    cmp byte [ebp+resident_refill_busy], 0
    jne .full
%endif
    ; Keep two levels for software interrupts and exceptions in a handler.
    cmp dword [ebp+dpmi_stack_depth], DPMI_LOCK_LEVELS-2
    jb .available
.full:
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
%ifdef RESIDENT_HOST
    ; The SB handler has returned: a held SB IRQ can run now.
    cmp eax, [ebp+dpmi_sb_level]
    jae .sb_kept
    cmp byte [ebp+dpmi_sb_handler], 0
    je .sb_kept
    mov byte [ebp+dpmi_sb_handler], 0
    mov byte [ebp+dpmi_sb_resume], 1
.sb_kept:
%endif
    mov eax, [ebp+dpmi_stack_cursors+eax*4]
    mov [ebp+dpmi_locked_cursor], eax
    pop eax
    ret

dpmi_stack_depth dd 0
dpmi_mouse_frame db 0
dpmi_stack_cursors times DPMI_LOCK_LEVELS dd 0

dpmi_locked_abort:
    mov word [ebp+mon_status], DPMI_ABORT_STACK
    mov byte [ebp+dpmi_exit_code], 1
    jmp dpmi_finish

dpmi_locked_linear dd 3fe000h,DPMI_LOCK_BASE,3fa000h,3fb000h,DPMI_LOCK_BASE+4096,DPMI_LOCK_BASE+8192,DPMI_LOCK_BASE+12288
    dd DPMI_LOCK_BASE+16384,DPMI_LOCK_BASE+20480,DPMI_LOCK_BASE+24576,DPMI_LOCK_BASE+28672
dpmi_locked_pages times DPMI_LOCK_PAGES dd 0
dpmi_locked_ptes times DPMI_LOCK_PAGES dd 0
dpmi_locked_cursor dd 4096
; Hardware and software deliveries that skipped zero bytes at the handler.
dpmi_entry_skips dd 0
%ifdef RESIDENT_HOST
; The stack depth of the running SB handler. SB IRQs held for it, and
; delivered at its return.
dpmi_sb_level dd 0
dpmi_sb_holds dd 0
dpmi_sb_resumed dd 0
dpmi_sb_next db 0
dpmi_sb_resume db 0
%endif
HOST_REAL
dpmi_locked_depth dd 0
HOST_PROTECTED
dpmi_exception_sp dd 0
dpmi_exception_cursor dd 0
; Outer handlers' cursor and SP by level; one entry more than the levels,
; as the save comes before dpmi_stack_acquire.
dpmi_exception_saved times (DPMI_LOCK_LEVELS+1)*8 db 0
