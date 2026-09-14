; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%ifdef HOST_DPMI
%define DPMI_LDT_COUNT 512
%define MON_VECTOR_COUNT 256
%define MON_SERVER_SELECTOR 80
%define DPMI_IRQ_SS 37h
%define DPMI_CALLBACK_SS 3fh
%else
%define MON_VECTOR_COUNT 32
%define MON_SERVER_SELECTOR 48
%endif

%macro MON_IRETD 0
%ifdef HOST_DPMI
    jmp mon_iret
%else
    iretd
%endif
%endmacro

bits 16
; DS=CS. Init: AX=client offset, BX=I/O callback offset. Run: AX=status.
monitor_init:
    pushad
    push es
    cld
    cmp byte [mon_running], 0
    jne .bad
    mov byte [mon_ready], 0
    movzx eax, ax
    mov [mon_client], eax
    movzx ebx, bx
    mov [mon_callback], ebx
    push cs
    pop es
    xor eax, eax
    mov di, mon_bitmap
    mov cx, 8192/4
    rep stosd
    mov di, mon_vectors
    mov cx, 256*6/4
    rep stosd
    mov di, mon_rm_regs
    mov cx, 25
    rep stosw
    mov [mon_irq_callback], eax
    mov ax, 3567h
    int 21h
    mov ax, es
    or ax, bx
    jz .bad
    mov ax, 0de00h
    int 67h
    test ah, ah
    jnz .bad
    xor eax, eax
    mov ax, cs
    shl eax, 4
    mov [mon_base], eax
    add [mon_client], eax
    add [mon_callback], eax
    lea edx, [eax+mon_gdt]
    mov [mon_gdtr+2], edx
    lea edx, [eax+mon_idt]
    mov [mon_idtr+2], edx
    lea edx, [eax+mon_tss]
    mov [mon_gdt+24+2], dx
    shr edx, 16
    mov [mon_gdt+24+4], dl
    mov [mon_gdt+24+7], dh
%ifdef HOST_DPMI
    mov [mon_gdt+56+2], ax
    mov edx, eax
    shr edx, 16
    mov [mon_gdt+56+4], dl
    mov [mon_gdt+56+7], dh
    lea edx, [eax+dpmi_ldt]
    mov [mon_gdt+72+2], dx
    shr edx, 16
    mov [mon_gdt+72+4], dl
    mov [mon_gdt+72+7], dh
%endif
    lea edx, [eax+mon_kernel_stack_top]
    mov [mon_tss+4], edx
    lea edx, [eax+mon_gdtr]
    mov [mon_switch+4], edx
    lea edx, [eax+mon_idtr]
    mov [mon_switch+8], edx
    lea edx, [eax+mon_enter]
    mov [mon_switch+16], edx
    lea eax, [eax+mon_pages+4095]
    and eax, 0fffff000h
    mov [mon_page_linear], eax
    mov ecx, eax
    shr ecx, 12
    mov ax, 0de06h
    int 67h
    test ah, ah
    jnz .bad
    mov [mon_switch], edx
    mov ecx, [mon_page_linear]
    shr ecx, 12
    inc cx
    mov ax, 0de06h
    int 67h
    test ah, ah
    jnz .bad
    or edx, 7
    mov eax, [mon_page_linear]
    shr eax, 4
    mov es, ax
    xor di, di
    xor eax, eax
    mov cx, 2048
    rep stosd
    mov [es:0], edx
%ifdef HOST_DPMI
    mov edx, [mon_switch]
    or edx, 3
    mov [es:4092], edx
%endif
    mov ax, es
    add ax, 100h
    mov es, ax
    xor di, di
    mov si, mon_gdt+MON_SERVER_SELECTOR
    mov ax, 0de01h
    int 67h
    test ah, ah
    jnz .bad
    mov [mon_server], ebx
    mov ax, 0de0ah
    int 67h
    test ah, ah
    jnz .bad
    test bx, 7
    jnz .bad
    test cx, 7
    jnz .bad
    cmp bx, 8
    jb .bad
    cmp bx, cx
    je .bad
    cmp bx, 30h
    je .bad
    cmp cx, 30h
    je .bad
    cmp bx, 248
    ja .bad
    cmp cx, 32
    jb .bad
    cmp cx, 248
    ja .bad
%ifdef HOST_DPMI
    cmp bx, 0f0h
    je .bad
    cmp cx, 0f0h
    je .bad
%endif
    mov [mon_master], bl
    mov [mon_slave], cl
    push cs
    pop es
    mov di, mon_idt
    mov si, mon_stubs
%ifdef HOST_DPMI
    mov cx, 256
%else
    mov cx, 32
%endif
.exception:
    lodsw
    movzx eax, ax
    add eax, [mon_base]
%ifdef HOST_DPMI
    mov bl, 0eeh
%else
    mov bl, 8eh
%endif
    call mon_gate
    loop .exception
%ifdef HOST_DPMI
    mov di, mon_idt+21h*8
    mov eax, [mon_base]
    add eax, dpmi_dos
    mov bl, 0eeh
    call mon_gate
%endif
%ifndef HOST_DPMI
    mov di, mon_idt+30h*8
    mov eax, [mon_base]
    add eax, mon_exit
    mov bl, 0eeh
    call mon_gate
%endif
    mov di, mon_idt+31h*8
    mov eax, [mon_base]
    add eax, mon_dpmi
    mov bl, 0eeh
    call mon_gate
%ifdef HOST_DPMI
    mov di, mon_idt+0f0h*8
    mov eax, [mon_base]
    add eax, dpmi_raw
    mov bl, 0eeh
    call mon_gate
    mov di, mon_idt+0f1h*8
    mov eax, [mon_base]
    add eax, dpmi_callback_done
    mov bl, 0eeh
    call mon_gate
    mov di, mon_idt+0f2h*8
    mov eax, [mon_base]
    add eax, dpmi_reflect
    mov bl, 0eeh
    call mon_gate
    mov di, mon_idt+0f3h*8
    mov eax, [mon_base]
    add eax, dpmi_exception_done
    mov bl, 0eeh
    call mon_gate
    mov di, mon_idt+0f4h*8
    mov eax, [mon_base]
    add eax, dpmi_locked_done
    mov bl, 0eeh
    call mon_gate
%endif
    xor bp, bp
.irq:
    movzx ax, byte [mon_master]
    cmp bp, 8
    jb .master
    movzx ax, byte [mon_slave]
    sub ax, 8
.master:
    add ax, bp
    mov di, ax
    shl di, 3
    add di, mon_idt
    mov si, bp
    shl si, 1
    cmp ax, 32
    jae .separate
    shl ax, 1
    mov si, ax
    mov ax, [mon_shared_stubs+si]
    jmp .irq_gate
.separate:
    mov ax, [mon_irq_stubs+si]
.irq_gate:
    movzx eax, ax
    add eax, [mon_base]
    mov bl, 8eh
    call mon_gate
    inc bp
    cmp bp, 16
    jb .irq
%ifdef HOST_DPMI
    mov ax, 20h
    mov cx, 2
    call monitor_trap
    mov ax, 0a0h
    call monitor_trap
%endif
    mov byte [mon_ready], 1
    pop es
    popad
    clc
    ret
.bad:
    pop es
    popad
    stc
    ret

mon_gate:
    stosw
    mov word [es:di], 8
    add di, 2
    mov byte [es:di], 0
    mov [es:di+1], bl
    add di, 2
    shr eax, 16
    stosw
    ret

; AX=first port, CX=count. Only these ports fault at CPL 3.
monitor_trap:
    pushad
    movzx edx, ax
    movzx eax, cx
    add eax, edx
    cmp eax, 10000h
    ja .bad
    jcxz .done
.port:
    bts [mon_bitmap], edx
    inc edx
    loop .port
.done:
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

; AX=ring-0 callback offset. It returns zero or virtual vector plus one.
monitor_irq_callback:
    push eax
    movzx eax, ax
    add eax, [mon_base]
    mov [mon_irq_callback], eax
    pop eax
    ret

monitor_run:
    cmp byte [mon_ready], 1
    jne .unavailable
    cmp byte [mon_running], 0
    jne .unavailable
    mov byte [mon_running], 1
    pushf
    pushad
    push ds
    push es
    push fs
    push gs
    mov [mon_return+12], sp
    mov [mon_return+16], ss
    mov [mon_return+4], cs
    mov [mon_return+20], es
    mov [mon_return+24], ds
    mov [mon_return+28], fs
    mov [mon_return+32], gs
    mov word [mon_status], 0ffffh
    mov dword [mon_error], 0
    mov dword [mon_eip], 0
    mov byte [mon_virtual_active], 0
    and byte [mon_gdt+24+5], 0fdh
    mov esi, [mon_base]
    mov edi, esi
    add esi, mon_switch
    mov ax, 0de0ch
    int 67h
.returned:
    mov byte [cs:mon_running], 0
    pop gs
    pop fs
    pop es
    pop ds
    popad
    popf
    mov ax, [mon_status]
    ret
.unavailable:
    mov ax, 0ffffh
    ret

bits 32
mon_enter:
    mov ax, 10h
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov ebp, edi
    lea esp, [ebp+mon_kernel_stack_top]
    mov word [ebp+mon_status], 0
%ifdef HOST_DPMI
    cmp byte [ebp+dpmi_active], 0
    jne dpmi_enter_client
%endif
    mov ax, 2bh
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    push dword 2bh
    lea eax, [ebp+mon_client_stack_top]
    push eax
    push dword 202h
    push dword 23h
    push dword [ebp+mon_client]
    MON_IRETD

%assign vector 0
%rep MON_VECTOR_COUNT
mon_exception_%+vector:
%if vector != 8 && vector != 10 && vector != 11 && vector != 12 && vector != 13 && vector != 14 && (vector != 17 || MON_VECTOR_COUNT == 256)
    push dword 0
%endif
    push dword vector
    jmp mon_exception
%assign vector vector+1
%endrep

%assign vector 0
%rep 32
mon_shared_%+vector:
    push eax
    mov al, 0bh
    out 20h, al
    in al, 20h
    test al, 1 << (vector & 7)
    pop eax
%if (vector & 7) == 7
    jz mon_spurious_master
%else
    jz mon_exception_%+vector
%endif
    push dword 0
    push dword (vector & 7)
    jmp mon_irq
%assign vector vector+1
%endrep

%assign irq 0
%rep 16
mon_irq_%+irq:
%if irq == 7 || irq == 15
    push eax
    mov al, 0bh
%if irq == 7
    out 20h, al
    in al, 20h
%else
    out 0a0h, al
    in al, 0a0h
%endif
    test al, 80h
    pop eax
%if irq == 7
    jz mon_spurious_master
%else
    jz mon_spurious_slave
%endif
%endif
    push dword 0
    push dword irq
    jmp mon_irq
%assign irq irq+1
%endrep

mon_spurious_slave:
    push eax
    mov al, 20h
    out 20h, al
    pop eax
mon_spurious_master:
    MON_IRETD

mon_irq:
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
    inc dword [ebp+mon_irqs]
%ifdef HOST_DPMI
    lea ebx, [esp+8]
    call dpmi_locked_capture
%endif
    mov ebx, [esp+40]
    movzx eax, byte [ebp+mon_master]
    cmp ebx, 8
    jb .master
    movzx eax, byte [ebp+mon_slave]
    sub eax, 8
.master:
    add eax, ebx
%ifdef HOST_DPMI
    cmp bl, [ebp+dpmi_audio_irq]
    je .real_irq
    imul edx, eax, 6
    cmp word [ebp+mon_vectors+edx+4], 0
    je .real_irq
    call dpmi_pic_queue
    jmp .done
.real_irq:
%endif
    lea edi, [ebp+mon_rm_regs]
    mov dword [edi+32], 2
    mov dword [edi+46], 0
    call mon_real_int
    cmp dword [ebp+mon_irq_callback], 0
    je .done
    call [ebp+mon_irq_callback]
    test ax, ax
    jz .done
    dec ax
    movzx eax, ax
    cmp eax, 256
    jae .done
    imul eax, 6
    lea esi, [ebp+mon_vectors+eax]
%ifdef HOST_DPMI
    cmp word [esi+4], 0
    je .done
    mov ebx, esp
    mov edi, ebx
    add edi, 44
    mov ecx, 10
.compact_frame:
    mov eax, [edi-8]
    mov [edi], eax
    sub edi, 4
    loop .compact_frame
    add esp, 8
    mov ebx, esp
    jmp dpmi_deliver_hardware
%else
    cmp word [esi+4], 23h
    jne .done
    cmp byte [ebp+mon_virtual_active], 0
    jne .done
    mov eax, [esp+48]
    mov [ebp+mon_virtual_eip], eax
    mov eax, [esp+56]
    mov [ebp+mon_virtual_flags], eax
    mov edi, [esp+60]
    sub edi, 12
    mov dword [edi], mon_virtual_return
    ; An invalid selector makes the client's IRETD return through our fault handler.
    mov dword [edi+4], 0fff8h
    mov [edi+8], eax
    mov [esp+60], edi
    mov eax, [esi]
    mov [esp+48], eax
    and word [esp+56], 0fdffh
    mov byte [ebp+mon_virtual_active], 1
%endif
.done:
    pop es
    pop ds
    popad
    add esp, 8
    MON_IRETD

mon_dpmi:
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
%ifdef HOST_DPMI
    cld
    mov ebx, esp
    call dpmi_locked_capture
    cmp word [ebp+mon_vectors+31h*6+4], 0
    je .host_service
    lea esi, [ebp+mon_vectors+31h*6]
    jmp dpmi_deliver_interrupt
.host_service:
    jmp dpmi_dispatch
%endif
    cmp word [esp+36], 0300h
    je .simulate
    cmp word [esp+36], 0204h
    je .get_vector
    cmp word [esp+36], 0205h
    je .set_vector
    jmp .unsupported
.get_vector:
    movzx eax, byte [esp+24]
    imul eax, 6
    mov edx, [ebp+mon_vectors+eax]
    mov [esp+28], edx
    mov cx, [ebp+mon_vectors+eax+4]
%ifdef HOST_DPMI
    test cx, cx
    jnz .vector_ready
    movzx edx, byte [esp+24]
    imul edx, 11
    add edx, dpmi_default_vectors
    mov [esp+28], edx
    mov cx, 3bh
.vector_ready:
%endif
    mov [esp+32], cx
    jmp .success
.set_vector:
    cmp word [esp+32], 23h
    jne .unsupported
    movzx eax, byte [esp+24]
    imul eax, 6
    mov edx, [esp+28]
    mov [ebp+mon_vectors+eax], edx
    mov word [ebp+mon_vectors+eax+4], 23h
    jmp .success
.simulate:
    cmp word [esp+32], 0
    jne .unsupported
    cmp byte [esp+25], 0
    jne .unsupported
    mov edi, [esp+8]
    cmp dword [edi+46], 0
    jne .unsupported
    movzx eax, byte [esp+24]
    call mon_real_int
.success:
    and byte [esp+48], 0feh
    jmp .done
.unsupported:
%ifdef HOST_DPMI
    mov ax, [esp+36]
    mov [ebp+dpmi_unsupported], ax
    mov esi, esp
    lea edi, [ebp+dpmi_unsupported_frame]
    mov ecx, 15
    cld
    rep movsd
%endif
    mov word [esp+36], 8001h
    or byte [esp+48], 1
.done:
%ifdef HOST_DPMI
    mov ebx, esp
    call dpmi_reflect_flags
%endif
    pop es
    pop ds
    popad
    MON_IRETD

; Ring 0, EBP=module base, EDI=flat register frame, AX=real interrupt.
mon_real_int:
    mov byte [ebp+mon_rm_kind], 0
    mov [ebp+mon_int_opcode+1], al
    jmp mon_real_transfer
mon_real_far:
    mov [ebp+mon_rm_kind], al
mon_real_transfer:
    push fs
    push gs
    push dword [ebp+mon_rm_stack]
%ifdef HOST_DPMI
    push word [ebp+dpmi_vif]
%endif
    pushad
    mov [ebp+mon_resume_sp], esp
    mov [ebp+mon_rm_target], edi
    mov esi, edi
    lea edi, [ebp+mon_rm_regs]
    mov ecx, 50
    cld
    rep movsb
    mov dword [ebp+mon_return], mon_real_callback
    lea eax, [ebp+mon_resume]
    mov [ebp+mon_switch+16], eax
    jmp mon_leave

mon_resume:
    mov ax, 10h
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov ebp, edi
    mov esp, [ebp+mon_resume_sp]
    lea esi, [ebp+mon_rm_regs]
    mov edi, [ebp+mon_rm_target]
    mov ecx, 50
    cld
    rep movsb
    mov dword [ebp+mon_return], monitor_run.returned
    lea eax, [ebp+mon_enter]
    mov [ebp+mon_switch+16], eax
    popad
%ifdef HOST_DPMI
    pop word [ebp+dpmi_vif]
%endif
    pop dword [ebp+mon_rm_stack]
    pop gs
    pop fs
    ret

mon_exception:
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
%ifdef HOST_DPMI
    lea ebx, [esp+8]
    call dpmi_locked_capture
    cmp dword [esp+40], 16
    jb .cpu_exception
    mov ebx, esp
    cmp dword [esp+40], 16
    jne .software
    mov ax, [esp+52]
    mov edx, [esp+48]
    sub edx, 2
    jc .cpu_exception
    mov ecx, 2
    mov edi, 2
    call dpmi_buffer
    jc .cpu_exception
    cmp word [eax], 10cdh
    jne .cpu_exception
.software:
    jmp dpmi_software_interrupt
.cpu_exception:
    cmp dword [esp+40], 1
    jne .ordinary_exception
    cmp byte [ebp+dpmi_step_active], 1
    jne .ordinary_exception
    test byte [esp+52], 3
    jz .ordinary_exception
    mov ebx, esp
    call dpmi_step_check
    xor edi, edi
    jmp .advance
.ordinary_exception:
%endif
    cmp dword [esp+40], 13
    jne .fault
    cmp byte [ebp+mon_virtual_active], 1
    jne .ordinary
    cmp dword [esp+44], 0fff8h
    jne .ordinary
    mov esi, [esp+48]
    cmp byte [esi], 0cfh
    jne .ordinary
    mov esi, [esp+60]
    cmp dword [esi], mon_virtual_return
    jne .ordinary
    cmp dword [esi+4], 0fff8h
    jne .ordinary
    mov eax, [ebp+mon_virtual_eip]
    mov [esp+48], eax
    mov eax, [ebp+mon_virtual_flags]
    mov [esp+56], eax
    add dword [esp+60], 12
    mov byte [ebp+mon_virtual_active], 0
    xor edi, edi
    jmp .advance
.ordinary:
    cmp dword [esp+44], 0
    jne .fault
    mov esi, [esp+48]
    xor edi, edi
    mov ecx, 4
%ifdef HOST_DPMI
    cmp byte [ebp+dpmi_active], 0
    je .fault
    mov ebx, esp
    mov ax, [esp+52]
    cmp ax, 23h
    je .flat_opcode
    call dpmi_descriptor
    jc .fault
    test byte [esi+6], 40h
    jnz .wide_opcode
    mov ecx, 2
.wide_opcode:
    call dpmi_descriptor_base
    add eax, [esp+48]
    mov esi, eax
.flat_opcode:
    call mon_gp_fetch
    jc .fault
    cmp al, 66h
%else
    cmp byte [esi], 66h
%endif
    jne .opcode
    inc edi
    xor cl, 6
.opcode:
%ifdef HOST_DPMI
    call mon_gp_fetch
    jc .fault
%else
    mov al, [esi+edi]
%endif
    inc edi
    cmp al, 0fah
    je .cli
    cmp al, 0fbh
    je .sti
    cmp al, 0ech
    jb .immediate
    cmp al, 0efh
    ja .fault
    movzx edx, word [esp+28]
    jmp .decode
.immediate:
    cmp al, 0e4h
    jb .fault
    cmp al, 0e7h
    ja .fault
%ifdef HOST_DPMI
    push eax
    call mon_gp_fetch
    movzx edx, al
    pop eax
    jc .fault
%else
    movzx edx, byte [esi+edi]
%endif
    inc edi
.decode:
    test al, 1
    jnz .width
    mov cl, 1
.width:
    test al, 2
    setnz ch
    bt [ebp+mon_bitmap], edx
    jnc .fault
    mov eax, [esp+36]
    push ecx
    push edi
%ifdef HOST_DPMI
    call dpmi_pic_io
%else
    call [ebp+mon_callback]
%endif
    pop edi
    pop ecx
    jc .fault
    test ch, ch
    jnz .advance
    cmp cl, 1
    jne .word
    mov [esp+36], al
    jmp .advance
.word:
    cmp cl, 2
    jne .dword
    mov [esp+36], ax
    jmp .advance
.dword:
    mov [esp+36], eax
.advance:
    add [esp+48], edi
    pop es
    pop ds
    popad
    add esp, 8
    MON_IRETD
.cli:
%ifdef HOST_DPMI
    cmp word [ebp+dpmi_vif], 0
    jne .trace_cli
    and word [esp+56], 0feffh
    or word [esp+56], 200h
    jmp .advance
.trace_cli:
    mov byte [ebp+dpmi_vif], 0
    mov byte [ebp+dpmi_step_active], 1
    or word [esp+56], 300h
    add [esp+48], edi
    mov ebx, esp
    call dpmi_step_check
    xor edi, edi
%else
    and word [esp+56], 0fdffh
%endif
    jmp .advance
.sti:
%ifdef HOST_DPMI
    mov byte [ebp+dpmi_vif], 1
    mov byte [ebp+dpmi_step_active], 0
    and word [esp+56], 0feffh
%endif
    or word [esp+56], 200h
    jmp .advance
.fault:
%ifdef HOST_DPMI
    cmp byte [ebp+dpmi_active], 0
    je .unhandled
    test byte [esp+52], 3
    jz .unhandled
    cmp byte [ebp+dpmi_exception_active], 0
    jne .unhandled
    mov eax, [esp+40]
    cmp eax, 32
    jae .unhandled
    imul eax, 6
    lea esi, [ebp+dpmi_exceptions+eax]
    cmp word [esi+4], 0
    jne dpmi_deliver_exception
.unhandled:
%endif
    mov eax, cr2
    mov [ebp+mon_cr2], eax
    mov eax, [esp+52]
    mov [ebp+mon_fault_cs], ax
%ifdef HOST_DPMI
    mov eax, [esp+64]
    mov [ebp+mon_fault_ss], eax
%endif
    mov eax, [esp+44]
    mov [ebp+mon_error], eax
    mov eax, [esp+48]
    sub eax, ebp
    mov [ebp+mon_eip], eax
    mov ax, [esp+40]
    inc ax
    mov [ebp+mon_status], ax
%ifdef HOST_DPMI
    mov esi, esp
    lea edi, [ebp+dpmi_fault_regs]
    mov ecx, 16
    cld
    rep movsd
    mov eax, [esp+48]
    mov [ebp+dpmi_fault_ip], eax
    jmp dpmi_finish
%endif
    jmp mon_leave

%ifdef HOST_DPMI
; EBX=exception frame, EDI=instruction offset. Keep other registers.
mon_gp_fetch:
    pushad
    mov ax, [ebx+52]
    mov edx, [ebx+48]
    add edx, edi
    jc .bad
    mov ecx, 1
    mov edi, 2
    call dpmi_buffer
    jc .bad
    movzx eax, byte [eax]
    mov [esp+28], eax
    popad
    clc
    ret
.bad:
    popad
    stc
    ret
%endif

mon_exit:
    call .base
.base:
    pop ebp
    sub ebp, .base
    push eax
    mov ax, 10h
    mov ds, ax
    pop eax
    mov [ebp+mon_status], ax
mon_leave:
    cli
    mov ax, 10h
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    lea esp, [ebp+mon_return]
    cmp byte [ebp+mon_vcpi_flags_slot], 0
    je .return_stack_ready
    mov word [esp-2], 0
    sub esp, 2
.return_stack_ready:
    clts
    mov ax, 0de0ch
    call far [ebp+mon_server]
    ud2
mon_virtual_return:
    ud2

bits 16
mon_real_callback:
    mov [cs:mon_rm_stack], sp
    mov [cs:mon_rm_stack+2], ss
    cmp word [cs:mon_rm_regs+48], 0
    je .stack_ready
    mov ss, [cs:mon_rm_regs+48]
    mov sp, [cs:mon_rm_regs+46]
.stack_ready:
    mov es, [cs:mon_rm_regs+34]
    mov ds, [cs:mon_rm_regs+36]
    mov fs, [cs:mon_rm_regs+38]
    mov gs, [cs:mon_rm_regs+40]
    mov edi, [cs:mon_rm_regs]
    mov esi, [cs:mon_rm_regs+4]
    mov ebp, [cs:mon_rm_regs+8]
    mov ebx, [cs:mon_rm_regs+16]
    mov edx, [cs:mon_rm_regs+20]
    mov ecx, [cs:mon_rm_regs+24]
    mov eax, [cs:mon_rm_regs+28]
    cmp byte [cs:mon_rm_kind], 0
    jne mon_far_callback
    push word [cs:mon_rm_regs+32]
    popf
mon_int_opcode:
    int 0
    jmp mon_callback_done
mon_far_callback:
    cmp byte [cs:mon_rm_kind], 2
    je .iret
    push word [cs:mon_rm_regs+32]
    popf
    call far [cs:mon_rm_regs+42]
    jmp mon_callback_done
.iret:
    push word [cs:mon_rm_regs+32]
    popf
    pushf
    call far [cs:mon_rm_regs+42]
mon_callback_done:
    pushf
    pop word [cs:mon_rm_regs+32]
    cmp word [cs:mon_rm_regs+48], 0
    je .stack_ready
    mov [cs:mon_rm_regs+46], sp
    mov [cs:mon_rm_regs+48], ss
.stack_ready:
    mov ss, [cs:mon_rm_stack+2]
    mov sp, [cs:mon_rm_stack]
    mov [cs:mon_rm_regs], edi
    mov [cs:mon_rm_regs+4], esi
    mov [cs:mon_rm_regs+8], ebp
    mov [cs:mon_rm_regs+16], ebx
    mov [cs:mon_rm_regs+20], edx
    mov [cs:mon_rm_regs+24], ecx
    mov [cs:mon_rm_regs+28], eax
    mov [cs:mon_rm_regs+34], es
    mov [cs:mon_rm_regs+36], ds
    mov [cs:mon_rm_regs+38], fs
    mov [cs:mon_rm_regs+40], gs
    push cs
    pop ds
    and byte [mon_gdt+24+5], 0fdh
    mov edi, [mon_base]
    lea esi, [edi+mon_switch]
    mov ax, 0de0ch
    int 67h

align 4
mon_base dd 0
mon_page_linear dd 0
mon_client dd 0
mon_callback dd 0
mon_status dw 0
mon_error dd 0
mon_eip dd 0
mon_cr2 dd 0
mon_fault_cs dw 0
%ifdef HOST_DPMI
mon_fault_ss dd 0
%endif
mon_ready db 0
mon_running db 0
mon_master db 0
mon_slave db 0
mon_irqs dd 0
mon_irq_callback dd 0
mon_virtual_active db 0
mon_virtual_eip dd 0
mon_virtual_flags dd 0
mon_vcpi_flags_slot db 0
mon_vectors times 256*6 db 0
mon_resume_sp dd 0
mon_rm_target dd 0
mon_rm_stack dd 0
mon_rm_kind db 0
mon_rm_regs times 50 db 0
mon_server dd 0
    dw MON_SERVER_SELECTOR
mon_switch dd 0,0,0
%ifdef HOST_DPMI
    dw 72,24
%else
    dw 0,24
%endif
    dd 0
    dw 8
    ; Leave stack space for the VCPI host and the far-call return address.
    times 32 db 0
mon_return dd monitor_run.returned,0,23002h,0,0,0,0,0,0
mon_gdtr dw mon_gdt_end-mon_gdt-1
    dd 0
mon_idtr dw 256*8-1
    dd 0
mon_gdt:
    dq 0
    dq 00cf9a000000ffffh
    dq 00cf92000000ffffh
    dw mon_tss_end-mon_tss-1,0
    db 0,89h,0,0
    dq 00cffa000000ffffh
    dq 00cff2000000ffffh
%ifdef HOST_DPMI
    dq 00cf92000000ffffh
    dq 0040fa000000ffffh
    dq 0000f200040002feh
    dw DPMI_LDT_COUNT*8-1,0
    db 0,82h,0,0
%endif
    times 3 dq 0
mon_gdt_end:
mon_stubs:
%assign vector 0
%rep MON_VECTOR_COUNT
    dw mon_exception_%+vector
%assign vector vector+1
%endrep
mon_shared_stubs:
%assign vector 0
%rep 32
    dw mon_shared_%+vector
%assign vector vector+1
%endrep
mon_irq_stubs:
%assign irq 0
%rep 16
    dw mon_irq_%+irq
%assign irq irq+1
%endrep
mon_idt times 256*8 db 0
mon_tss:
    dd 0,0
    dw 10h,0
    times 90 db 0
    dw 104
mon_bitmap times 8192 db 0
    db 0ffh
mon_tss_end:
mon_pages times 12287 db 0
    times 2048 db 0
mon_kernel_stack_top:
%ifndef HOST_DPMI
    times 2048 db 0
%endif
mon_client_stack_top:
%ifdef HOST_DPMI
%include "host/dpmi.asm"
%endif
