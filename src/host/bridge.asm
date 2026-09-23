; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%define BRIDGE_BOTTOM 3fa000h
%define BRIDGE_TOP 3fc000h
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
    .padding: resb 5
endstruc

HOST_REAL
dpmi_bridge_real_allocate:
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
    mov bx, 128
    int 21h
    jc .restore
    mov [dpmi_bridge_real_segment], ax
.restore:
    pop bx
    mov ax, 5803h
    int 21h
    pop bx
    mov ax, 5801h
    int 21h
    cmp word [dpmi_bridge_real_segment], 0
    je .bad
    clc
    ret
.bad:
    stc
    ret

dpmi_bridge_real_free:
    push ax
    push es
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
    xor ebx, ebx
.irq:
    call dpmi_bridge_vector
    mov eax, [edx*4]
    mov [ebp+dpmi_bridge_vectors+ebx*4], eax
    cmp bl, [ebp+dpmi_audio_irq]
    je .next
    mov eax, [ebp+mon_real_base]
    shl eax, 12
    mov ax, [ebp+dpmi_bridge_stubs+ebx*2]
    mov [edx*4], eax
.next:
    inc ebx
    cmp ebx, 16
    jb .irq
    mov byte [ebp+dpmi_bridge_installed], 1
    popad
    ret

dpmi_bridge_remove:
    pushad
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
.done:
    pop edx
    pop ebx
    pop eax
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
    jne .enable
    imul eax, edx, 11
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
    ; The interrupted real-mode code had interrupts enabled.
    mov byte [ebp+dpmi_vif], 1
    mov byte [ebp+dpmi_step_active], 0
    call dpmi_pic_queue
    push dword DPMI_IRQ_SS
    push dword [ebp+dpmi_locked_cursor]
    push dword 202h
    push dword 3bh
    push dword dpmi_bridge_return
    mov ax, 2bh
    mov ds, ax
    mov es, ax
    xor eax, eax
    mov fs, ax
    mov gs, ax
    MON_IRETD

dpmi_bridge_return:
    int 0f5h
    ud2

dpmi_bridge_done:
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
    mov eax, [ebx+bridge_frame.locked_cursor]
    cmp [esp+52], eax
    jne dpmi_locked_abort
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
    lea esp, [ebp+dpmi_bridge_return_frame]
    cmp byte [ebp+mon_vcpi_flags_slot], 0
    je .stack_ready
    mov word [esp-2], 0
    sub esp, 2
.stack_ready:
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
    cmp byte [cs:dpmi_sti_shadow], 0
    je .open
    test word [cs:dpmi_bridge_mask], 1<<irq
    jz .chain
    popf
    push strict word irq
    jmp dpmi_bridge_defer
.open:
    call dpmi_bridge_blocked
    jc .chain
    test word [cs:dpmi_bridge_mask], 1<<irq
    jz .chain
    popf
    push strict word irq
    jmp dpmi_bridge_enter
.chain:
    popf
    jmp far [cs:dpmi_bridge_vectors+irq*4]
%assign irq irq+1
%endrep

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
    pop bx
    pop ax
    pop bp
    add sp, 2
    iret

dpmi_bridge_blocked:
    cmp byte [cs:dpmi_vif], 0
    jne .enabled
    cmp dword [cs:dpmi_locked_depth], 0
    je .enabled
.blocked:
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
dpmi_bridge_installed db 0
dpmi_bridge_vectors times 16 dd 0
dpmi_bridge_entry dd 0
    times 32 db 0
dpmi_bridge_return_frame times 36 db 0
    times 512 db 0
dpmi_bridge_real_top:
dpmi_bridge_real_segment dw 0
HOST_PROTECTED
