; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%define BRIDGE_BOTTOM 3fa000h
%define BRIDGE_TOP 3fc000h
%define BRIDGE_SOFT_COUNT 1
struc bridge_frame
    .previous: resd 1
    .stack: resd 1
    .entry: resd 1
    .tss: resd 1
    .locked_cursor: resd 1
    .locked_depth: resd 1
    .vif: resw 1
    .opcode: resb 1
    .kind: resb 1
    .resume: resd 1
    .target: resd 1
    .rm_stack: resd 1
    .switch: resd 1
    .irq_target: resd 1
    .return: resb 36
    .regs: resb 50
    .reflect: resb 1
    .software: resb 1
    .rmcall: resb 1
    .padding: resb 3
endstruc

HOST_REAL
dpmi_bridge_real_allocate:
%ifdef RESIDENT_HOST
    ; dpmi_nested_save allocates the block of a child.
    mov ax, [dpmi_nested_segment]
    cmp byte [dpmi_nested_depth], 0
    jne .store
%endif
    mov bx, 128+DPMI_XFER_PARAS
    call dpmi_real_allocate
    jc .done
.store:
    mov [dpmi_bridge_real_segment], ax
.done:
    ret

; BX=paragraphs. Try upper memory first and keep the DOS allocation policy.
dpmi_real_allocate:
    push si
    mov si, bx
    mov ax, 5800h
    int 21h
    push ax
    mov ax, 5802h
    int 21h
    xor ah, ah
    push ax
    mov ax, 5803h
    mov bx, 1
    int 21h
    mov ax, 5801h
    mov bx, 80h
    int 21h
    mov ah, 48h
    mov bx, si
    int 21h
    mov si, 0
    jc .restore
    mov si, ax
.restore:
    pop bx
    mov ax, 5803h
    int 21h
    pop bx
    mov ax, 5801h
    int 21h
    mov ax, si
    pop si
    test ax, ax
    jz .bad
    clc
    ret
.bad:
    stc
    ret

dpmi_bridge_real_free:
    push ax
    push es
    mov ax, [dpmi_large_stack_segment]
    test ax, ax
    jz .bridge
    mov es, ax
    mov ah, 49h
    int 21h
    mov word [dpmi_large_stack_segment], 0
.bridge:
    mov byte [dpmi_large_stack_busy], 0
    mov ax, [dpmi_bridge_real_segment]
    test ax, ax
    jz .done
    mov es, ax
    mov ah, 49h
    int 21h
    mov word [dpmi_bridge_real_segment], 0
.done:
    pop es
    pop ax
    ret

HOST_PROTECTED
dpmi_bridge_install:
    pushad
    mov dword [ebp+dpmi_bridge_stack], BRIDGE_TOP
    mov dword [ebp+dpmi_bridge_context], 0
    mov dword [ebp+dpmi_bridge_depth], 0
    mov word [ebp+dpmi_bridge_mask], 0
    mov byte [ebp+dpmi_bridge_soft_active], 0
    popad
dpmi_bridge_install_vectors:
    pushad
    xor ebx, ebx
.irq:
    call dpmi_bridge_vector
    mov ecx, [ebp+mon_real_base]
    shl ecx, 12
    mov cx, [ebp+dpmi_bridge_stubs+ebx*2]
    mov eax, [edx*4]
    ; A stub in the vector means a live bridge. Keep its saved handler.
    cmp eax, ecx
    je .saved
    mov [ebp+dpmi_bridge_vectors+ebx*4], eax
.saved:
    cmp bl, [ebp+dpmi_audio_irq]
    je .next
    mov [edx*4], ecx
.next:
    inc ebx
    cmp ebx, 16
    jb .irq
    xor ebx, ebx
.software:
    movzx edx, byte [ebp+dpmi_bridge_soft_numbers+ebx]
    mov ecx, [ebp+mon_real_base]
    shl ecx, 12
    mov cx, [ebp+dpmi_bridge_soft_stubs+ebx*2]
    mov eax, [edx*4]
    cmp eax, ecx
    je .soft_saved
    mov [ebp+dpmi_bridge_soft_vectors+ebx*4], eax
.soft_saved:
    mov [edx*4], ecx
    inc ebx
    cmp ebx, BRIDGE_SOFT_COUNT
    jb .software
    mov byte [ebp+dpmi_bridge_installed], 1
    popad
    ret

dpmi_bridge_remove:
    pushad
    call dpmi_pic_restore
    mov word [ebp+dpmi_bridge_mask], 0
    cmp byte [ebp+dpmi_bridge_installed], 0
    je .done
    xor ebx, ebx
.irq:
    call dpmi_bridge_vector
    mov eax, [ebp+mon_real_base]
    shl eax, 12
    mov ax, [ebp+dpmi_bridge_stubs+ebx*2]
    cmp [edx*4], eax
    jne .next
    mov eax, [ebp+dpmi_bridge_vectors+ebx*4]
    mov [edx*4], eax
.next:
    inc ebx
    cmp ebx, 16
    jb .irq
    xor ebx, ebx
.software:
    movzx edx, byte [ebp+dpmi_bridge_soft_numbers+ebx]
    mov eax, [ebp+mon_real_base]
    shl eax, 12
    mov ax, [ebp+dpmi_bridge_soft_stubs+ebx*2]
    cmp [edx*4], eax
    jne .soft_next
    mov eax, [ebp+dpmi_bridge_soft_vectors+ebx*4]
    mov [edx*4], eax
.soft_next:
    inc ebx
    cmp ebx, BRIDGE_SOFT_COUNT
    jb .software
    mov byte [ebp+dpmi_bridge_soft_mask], 0
    mov byte [ebp+dpmi_bridge_installed], 0
.done:
    popad
    ret

; EBX=IRQ, EDX=real interrupt number.
dpmi_bridge_vector:
    movzx edx, byte [ebp+mon_master]
    cmp ebx, 8
    jb .master
    movzx edx, byte [ebp+mon_slave]
    sub edx, 8
.master:
    add edx, ebx
    ret

; AL=interrupt number, ESI=the client-visible real vector slot.
dpmi_bridge_real_vector:
    push eax
    push ebx
    push edx
    movzx eax, al
    lea esi, [eax*4]
    cmp byte [ebp+dpmi_bridge_installed], 0
    je .done
    xor ebx, ebx
.software:
    cmp al, [ebp+dpmi_bridge_soft_numbers+ebx]
    je .soft_vector
    inc ebx
    cmp ebx, BRIDGE_SOFT_COUNT
    jb .software
    movzx ebx, byte [ebp+mon_master]
    sub eax, ebx
    cmp eax, 8
    jb .irq
    mov eax, esi
    shr eax, 2
    movzx ebx, byte [ebp+mon_slave]
    sub eax, ebx
    cmp eax, 8
    jae .done
    add eax, 8
.irq:
    mov edx, [ebp+mon_real_base]
    shl edx, 12
    mov dx, [ebp+dpmi_bridge_stubs+eax*2]
    cmp [esi], edx
    jne .done
    lea esi, [ebp+dpmi_bridge_vectors+eax*4]
    jmp .done
.soft_vector:
    mov edx, [ebp+mon_real_base]
    shl edx, 12
    mov dx, [ebp+dpmi_bridge_soft_stubs+ebx*2]
    cmp [esi], edx
    jne .done
    lea esi, [ebp+dpmi_bridge_soft_vectors+ebx*4]
.done:
    pop edx
    pop ebx
    pop eax
    ret

; AL=vector of a reflected IRQ. A real-mode handler that was installed after
; the bridge (Jutland, Aegis) chains to the stub during the reflection. The
; stub must then continue to the saved vector, or the BIOS timer stops.
dpmi_bridge_mark_irq:
    push eax
    call dpmi_vector_irq
    jc .mark
    mov al, -1
.mark:
    inc eax
    mov [ebp+dpmi_bridge_irq_chain], al
    pop eax
    ret

; AL=vector. CF set and AL=IRQ 0-15 for a PIC vector.
dpmi_vector_irq:
    sub al, [ebp+mon_master]
    cmp al, 8
    jb .done
    add al, [ebp+mon_master]
    sub al, [ebp+mon_slave]
    cmp al, 8
    jae .done
    add al, 8
    stc
.done:
    ret

; The reflection starts at the saved vector. Clear the marks of this IRQ, or
; the stub would pass new IRQs of this level to the real chain only.
dpmi_bridge_unmark_irq:
    push eax
    movzx eax, byte [ebp+dpmi_bridge_irq_chain]
    test eax, eax
    jz .done
    dec eax
    btr [ebp+dpmi_irq_reflecting], eax
    mov byte [ebp+dpmi_bridge_irq_chain], 0
.done:
    pop eax
    ret

; A reflected IRQ must finish the real chain that entered this bridge.
dpmi_bridge_chained_vector:
    call dpmi_bridge_real_vector
    push ebx
    push edx
    mov edx, [ebp+dpmi_bridge_context]
    test edx, edx
    jz .done
    cmp byte [edx+bridge_frame.software], 0
    jne .done
    movzx ebx, word [edx+bridge_frame.entry+2]
    shl ebx, 4
    movzx edx, word [edx+bridge_frame.entry]
    add edx, ebx
    movzx ebx, word [edx+44]
    cmp ebx, 16
    jae .done
    call dpmi_bridge_vector
    cmp al, dl
    jne .done
    lea esi, [ebp+dpmi_bridge_vectors+ebx*4]
.done:
    pop edx
    pop ebx
    ret

dpmi_bridge_update:
    pushad
    xor ebx, ebx
    xor ecx, ecx
.irq:
    cmp bl, [ebp+dpmi_audio_irq]
    je .next
    call dpmi_bridge_vector
    imul esi, edx, 6
    lea esi, [ebp+mon_vectors+esi]
    cmp word [esi+4], 0
    je .next
    cmp word [esi+4], 3bh
    je .default
    cmp word [esi+4], DPMI_STUB16
    jne .enable
.default:
    imul eax, edx, 3
    add eax, dpmi_default_vectors
    cmp [esi], eax
    je .next
.enable:
    bts ecx, ebx
.next:
    inc ebx
    cmp ebx, 16
    jb .irq
    mov [ebp+dpmi_bridge_mask], cx
    xor ebx, ebx
    xor ecx, ecx
.software:
    movzx edx, byte [ebp+dpmi_bridge_soft_numbers+ebx]
    imul esi, edx, 6
    lea esi, [ebp+mon_vectors+esi]
    cmp word [esi+4], 0
    je .soft_next
    cmp word [esi+4], 3bh
    je .soft_default
    cmp word [esi+4], DPMI_STUB16
    jne .soft_enable
.soft_default:
    imul eax, edx, 3
    add eax, dpmi_default_vectors
    cmp [esi], eax
    je .soft_next
.soft_enable:
    bts ecx, ebx
.soft_next:
    inc ebx
    cmp ebx, BRIDGE_SOFT_COUNT
    jb .software
    mov [ebp+dpmi_bridge_soft_mask], cl
%ifdef RESIDENT_HOST
    movzx eax, byte [ebp+dpmi_guest_vector]
    imul eax, 6
    cmp word [ebp+mon_vectors+eax+4], 0
    setne byte [ebp+dpmi_audio_pm_handler]
%endif
    popad
    ret

dpmi_bridge_pm:
    mov ax, 10h
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov ebp, edi
    cmp dword [ebp+dpmi_bridge_depth], 4
    jae dpmi_locked_abort
    inc dword [ebp+dpmi_bridge_depth]
    mov esp, [ebp+dpmi_bridge_stack]
    cmp esp, BRIDGE_TOP
    ja dpmi_locked_abort
    cmp esp, BRIDGE_BOTTOM+bridge_frame_size+1024
    jb dpmi_locked_abort
    call dpmi_debug_host_save
    sub esp, bridge_frame_size
    mov edi, esp
    mov eax, [ebp+dpmi_bridge_context]
    mov [edi+bridge_frame.previous], eax
    mov eax, [ebp+dpmi_bridge_stack]
    mov [edi+bridge_frame.stack], eax
    mov eax, [ebp+dpmi_bridge_entry]
    mov [edi+bridge_frame.entry], eax
    mov eax, [ebp+mon_tss+4]
    mov [edi+bridge_frame.tss], eax
    mov eax, [ebp+dpmi_locked_cursor]
    mov [edi+bridge_frame.locked_cursor], eax
    mov eax, [ebp+dpmi_locked_depth]
    mov [edi+bridge_frame.locked_depth], eax
    mov ax, [ebp+dpmi_vif]
    mov [edi+bridge_frame.vif], ax
    mov al, [ebp+dpmi_rm_call]
    mov [edi+bridge_frame.rmcall], al
    cmp al, 1
    jne .rm_kept
    mov byte [ebp+dpmi_rm_call], 2
.rm_kept:
    mov al, [ebp+mon_int_opcode+1]
    mov [edi+bridge_frame.opcode], al
    mov al, [ebp+mon_rm_kind]
    mov [edi+bridge_frame.kind], al
    mov al, [ebp+dpmi_reflect_vector]
    mov [edi+bridge_frame.reflect], al
    mov eax, [ebp+mon_resume_sp]
    mov [edi+bridge_frame.resume], eax
    mov eax, [ebp+mon_rm_target]
    mov [edi+bridge_frame.target], eax
    mov eax, [ebp+mon_rm_stack]
    mov [edi+bridge_frame.rm_stack], eax
    mov eax, [ebp+mon_rm_irq_target]
    mov [edi+bridge_frame.irq_target], eax
    movzx esi, word [edi+bridge_frame.entry+2]
    shl esi, 4
    movzx eax, word [edi+bridge_frame.entry]
    add esi, eax
    mov eax, [esi]
    mov [edi+bridge_frame.switch], eax
    movzx ebx, word [esi+44]
    mov byte [edi+bridge_frame.software], 0
    test bx, 200h
    jz .entry_ready
    mov byte [edi+bridge_frame.software], 1
.entry_ready:
    mov [ebp+dpmi_bridge_context], edi
    mov [ebp+dpmi_bridge_stack], edi
    mov [ebp+mon_tss+4], edi
    lea esi, [ebp+mon_return]
    add edi, bridge_frame.return
    mov ecx, 36
    cld
    rep movsb
    lea esi, [ebp+mon_rm_regs]
    mov ecx, 50
    rep movsb
    mov eax, [ebp+dpmi_bridge_depth]
    shl eax, 9
    mov [ebp+mon_return+12], eax
    movzx eax, word [ebp+dpmi_bridge_real_segment]
    mov [ebp+mon_return+16], eax
    test bh, 2
    jnz dpmi_bridge_soft_enter
    ; The interrupted real-mode code had interrupts enabled.
    mov byte [ebp+dpmi_vif], 1
    mov byte [ebp+dpmi_step_active], 0
    btr ebx, 8
    jnc .queue
    mov byte [ebp+dpmi_sti_sb_held], 1
    jmp .queued
.queue:
    call dpmi_pic_queue
.queued:
    push dword DPMI_IRQ_SS
    push dword [ebp+dpmi_locked_cursor]
    push dword 202h
    push dword 3bh
    push dword dpmi_bridge_return
    ; Handlers may rely on the segments of the client's real-mode call.
    call dpmi_client_segments
    mov es, ax
    mov ds, dx
    MON_IRETD

dpmi_bridge_soft_enter:
    and ebx, 0ffh
    imul ebx, 6
    lea ebx, [ebp+mon_vectors+ebx]
    mov edx, [ebx]
    mov ax, [ebx+4]
    call dpmi_code_target
    jc dpmi_locked_abort
    push ebx
    sub esp, 60
    mov dword [esp+40], dpmi_bridge_return
    mov dword [esp+44], 3bh
    mov eax, 202h
    call dpmi_virtual_flags
    mov [esp+48], eax
    mov eax, [ebp+dpmi_locked_cursor]
    mov [esp+52], eax
    mov dword [esp+56], DPMI_IRQ_SS
    call dpmi_client_segments
    movzx eax, ax
    mov [esp], eax
    movzx edx, dx
    mov [esp+4], edx
    mov ebx, [ebp+dpmi_bridge_context]
    movzx esi, word [ebx+bridge_frame.entry+2]
    shl esi, 4
    movzx eax, word [ebx+bridge_frame.entry]
    add esi, eax
    add esi, 12
    lea edi, [esp+8]
    mov ecx, 8
    cld
    rep movsd
    mov esi, [esp+60]
    mov ebx, esp
    jmp dpmi_deliver_software

dpmi_bridge_return:
    int 0f5h
    ud2

dpmi_bridge_done:
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
    mov ebx, [ebp+dpmi_bridge_context]
    cmp ebx, BRIDGE_BOTTOM
    jb dpmi_locked_abort
    cmp ebx, BRIDGE_TOP-bridge_frame_size
    ja dpmi_locked_abort
    cmp word [esp+44], 3bh
    jne dpmi_locked_abort
    cmp dword [esp+40], dpmi_bridge_return+2
    jne dpmi_locked_abort
    cmp word [esp+56], DPMI_IRQ_SS
    jne dpmi_locked_abort
    cmp byte [ebx+bridge_frame.software], 0
    je .hardware_stack
    movzx edi, word [ebx+bridge_frame.entry+2]
    shl edi, 4
    movzx eax, word [ebx+bridge_frame.entry]
    add edi, eax
    mov byte [ebp+dpmi_bridge_soft_active], 0
%assign soft_reg 0
%rep 8
%if soft_reg != 12
    mov eax, [esp+8+soft_reg]
    mov [edi+12+soft_reg], eax
%endif
%assign soft_reg soft_reg+4
%endrep
.hardware_stack:
    mov eax, [ebx+bridge_frame.locked_cursor]
    cmp [esp+52], eax
    jne dpmi_locked_abort
    mov eax, [ebx+bridge_frame.locked_cursor]
    cmp [ebp+dpmi_locked_cursor], eax
    jne dpmi_locked_abort
    mov eax, [ebx+bridge_frame.locked_depth]
    cmp [ebp+dpmi_locked_depth], eax
    jne dpmi_locked_abort
    lea esi, [ebx+bridge_frame.return]
    lea edi, [ebp+mon_return]
    mov ecx, 36
    cld
    rep movsb
    lea edi, [ebp+mon_rm_regs]
    mov ecx, 50
    rep movsb
    mov eax, [ebx+bridge_frame.resume]
    mov [ebp+mon_resume_sp], eax
    mov eax, [ebx+bridge_frame.target]
    mov [ebp+mon_rm_target], eax
    mov eax, [ebx+bridge_frame.rm_stack]
    mov [ebp+mon_rm_stack], eax
    mov eax, [ebx+bridge_frame.switch]
    mov [ebp+mon_switch+16], eax
    mov eax, [ebx+bridge_frame.irq_target]
    mov [ebp+mon_rm_irq_target], eax
    mov ax, [ebx+bridge_frame.vif]
    mov [ebp+dpmi_vif], ax
    mov al, [ebx+bridge_frame.opcode]
    mov [ebp+mon_int_opcode+1], al
    mov al, [ebx+bridge_frame.kind]
    mov [ebp+mon_rm_kind], al
    mov al, [ebx+bridge_frame.reflect]
    mov [ebp+dpmi_reflect_vector], al
    mov eax, [ebx+bridge_frame.tss]
    mov [ebp+mon_tss+4], eax
    mov eax, [ebx+bridge_frame.previous]
    mov [ebp+dpmi_bridge_context], eax
    mov al, [ebx+bridge_frame.rmcall]
    mov [ebp+dpmi_rm_call], al
    dec dword [ebp+dpmi_bridge_depth]
    mov eax, [ebx+bridge_frame.stack]
    mov [ebp+dpmi_bridge_stack], eax
    lea edi, [ebp+dpmi_bridge_return_frame]
    mov dword [edi], dpmi_bridge_real_return
    mov eax, [ebp+mon_real_base]
    shr eax, 4
    mov [edi+4], eax
    mov dword [edi+8], 23002h
    movzx eax, word [ebx+bridge_frame.entry]
    add ax, 4
    mov [edi+12], eax
    movzx eax, word [ebx+bridge_frame.entry+2]
    mov [edi+16], eax
    cli
    mov ax, 10h
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    call dpmi_debug_host_restore
    lea esp, [ebp+dpmi_bridge_return_frame]
    sub esp, ebp
    add esp, [ebp+mon_real_base]
    clts
    mov ax, 0de0ch
    call far [ebp+mon_server]
    ud2

dpmi_bridge_stack dd BRIDGE_TOP
dpmi_bridge_context dd 0
dpmi_bridge_depth dd 0

HOST_REAL
dpmi_bridge_soft_numbers db 1ch
dpmi_bridge_soft_stubs dw dpmi_bridge_soft_0
dpmi_bridge_soft_vectors times BRIDGE_SOFT_COUNT dd 0
dpmi_bridge_soft_mask db 0
dpmi_bridge_soft_active db 0

%assign soft 0
%rep BRIDGE_SOFT_COUNT
dpmi_bridge_soft_%+soft:
    pushf
    test byte [cs:dpmi_bridge_soft_mask], 1<<soft
    jz .chain
    test byte [cs:dpmi_bridge_soft_active], 1<<soft
    jnz .chain
%if soft = 0
%ifdef RESIDENT_HOST
    cmp byte [cs:resident_refill_busy], 0
    jne .chain
%endif
%endif
    or byte [cs:dpmi_bridge_soft_active], 1<<soft
    popf
    push strict word 21ch
    jmp dpmi_bridge_enter
.chain:
    popf
    jmp far [cs:dpmi_bridge_soft_vectors+soft*4]
%assign soft soft+1
%endrep

dpmi_bridge_stubs:
%assign irq 0
%rep 16
    dw dpmi_bridge_irq_%+irq
%assign irq irq+1
%endrep
%assign irq 0
%rep 16
dpmi_bridge_irq_%+irq:
    pushf
    cmp byte [cs:dpmi_bridge_irq_chain], irq+1
    je .chained
    test byte [cs:dpmi_irq_reflecting+(irq>>3)], 1<<(irq&7)
    jnz .chained
%if irq < 2
    push byte irq
    call dpmi_bridge_owned
    jc .chain
%endif
    call dpmi_bridge_blocked
%if irq = 6 || irq >= 8 && irq <= 11 || irq >= 14
    ; The CD refill can wait for the disk and RTC IRQs.
    jc .chain
%elif irq < 2 || irq = 12
    jc .defer
%else
    jnc .open
    jz .defer
    jmp .chain
.open:
%endif
    test word [cs:dpmi_bridge_mask], 1<<irq
    jz .chain
    cmp byte [cs:dpmi_sti_shadow], 0
    jne .shadow
    popf
    push strict word irq
    jmp dpmi_bridge_enter
.defer:
    test word [cs:dpmi_bridge_mask], 1<<irq
    jz .chain
.shadow:
    popf
    push strict word irq
    jmp dpmi_bridge_defer
.chained:
    ; The hook chains once. A later IRQ at this stub is a new one.
    mov byte [cs:dpmi_bridge_irq_chain], 0
    and byte [cs:dpmi_irq_reflecting+(irq>>3)], 0ffh & ~(1<<(irq&7))
.chain:
    popf
    jmp far [cs:dpmi_bridge_vectors+irq*4]
%assign irq irq+1
%endrep

; Word argument=master IRQ. CF=1 when the protected handler of this level
; calls the real vector (On the Ball chains through a raw switch). The real
; chain then owns the EOI, as with function 0302h.
dpmi_bridge_owned:
    pusha
    mov bp, sp
    mov cx, [bp+18]
    bt [cs:dpmi_pic_service], cx
    jnc .done
    ; A new IRQ of this level is in service in the controller.
    mov al, 0bh
    out 20h, al
    in al, 20h
    xchg ax, bx
    mov al, 0ah
    out 20h, al
    bt bx, cx
    cmc
    jnc .done
    btr [cs:dpmi_pic_service], cx
%ifdef RESIDENT_HOST
    bts word [cs:dpmi_real_eoi], cx
    stc
%endif
.done:
    popa
    ret 2

; A virtual guest IRQ during a real-mode call, entered like an IRQ handler.
dpmi_bridge_virtual:
    pushf
    cmp byte [cs:dpmi_bridge_installed], 0
    je .later
    cmp byte [cs:dpmi_sti_shadow], 0
    jne .later
    call dpmi_bridge_blocked
    jc .later
    popf
    ; Bit 8 marks an SB IRQ that uCDD has already taken.
    push strict word 100h
    jmp dpmi_bridge_enter
.later:
    popf
    mov byte [cs:dpmi_sti_sb_held], 1
    iret

dpmi_bridge_defer:
    push bp
    mov bp, sp
    push ax
    push bx
    movzx bx, byte [bp+2]
    mov al, bl
    cmp al, 8
    jb .master
    sub al, 8
    add al, 60h
    out 0a0h, al
    mov al, 62h
    jmp .eoi
.master:
    add al, 60h
.eoi:
    out 20h, al
    bts word [cs:dpmi_pending_irqs], bx
%ifdef RESIDENT_HOST
    bts word [cs:dpmi_physical_pending], bx
%endif
    pop bx
    pop ax
    pop bp
    add sp, 2
    iret

; CF=1 blocks delivery. Then ZF=1 marks a CD refill and ZF=0 a disabled client.
dpmi_bridge_blocked:
%ifdef RESIDENT_HOST
    ; The CD refill runs inside DOS. The client must not run until it ends.
    cmp byte [cs:resident_refill_busy], 0
    je .client
    cmp al, al
    stc
    ret
.client:
%endif
    cmp byte [cs:dpmi_vif], 0
    jne .enabled
    cmp dword [cs:dpmi_locked_depth], 0
    je .enabled
    stc
    ret
.enabled:
    clc
    ret

dpmi_bridge_enter:
    pushad
    push ds
    push es
    push fs
    push gs
    push dword [cs:mon_switch+16]
    mov [cs:dpmi_bridge_entry], sp
    mov [cs:dpmi_bridge_entry+2], ss
    mov ax, cs
    mov ds, ax
    mov ss, ax
    mov sp, dpmi_bridge_real_top
    and byte [mon_gdt+24+5], 0fdh
    mov edi, [mon_base]
    lea eax, [edi+dpmi_bridge_pm]
    mov [mon_switch+16], eax
    mov esi, [mon_real_base]
    add esi, mon_switch
    mov ax, 0de0ch
    int 67h
    ud2

dpmi_bridge_real_return:
    pop gs
    pop fs
    pop es
    pop ds
    popad
    add sp, 2
    iret

dpmi_bridge_mask dw 0
dpmi_irq_reflecting dd 0
; The real-mode stubs read the virtual in-service levels.
dpmi_pic_service dd 0
dpmi_bridge_installed db 0
dpmi_bridge_irq_chain db 0
dpmi_bridge_vectors times 16 dd 0
dpmi_bridge_entry dd 0
    times 32 db 0
dpmi_bridge_return_frame times 36 db 0
    times 512 db 0
dpmi_bridge_real_top:
dpmi_bridge_real_segment dw 0
HOST_PROTECTED
