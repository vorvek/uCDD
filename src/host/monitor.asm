; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%include "host/profile.inc"

%ifndef SPLIT_HOST
%macro HOST_REAL 0
    bits 16
%endmacro
%macro HOST_PROTECTED 0
    bits 32
%endmacro
%macro HOST_SCRATCH 0
    bits 16
%endmacro
%endif

%ifdef HOST_DPMI
%ifdef RESIDENT_HOST
%define DPMI_LDT_COUNT 8192
%else
%define DPMI_LDT_COUNT 512
%endif
%define MON_VECTOR_COUNT 256
%define MON_SERVER_SELECTOR 80
%define DPMI_IRQ_SS 37h
%define DPMI_CALLBACK_SS 3fh
%define DPMI_STUB16 6bh
%define DPMI_LOCK_PAGES 11
%define DPMI_XFER_BYTES 4096
%define DPMI_XFER_DTA 4096
%define DPMI_XFER_PARAS (DPMI_XFER_BYTES+128)/16
%else
%define MON_VECTOR_COUNT 32
%define MON_SERVER_SELECTOR 48
%endif

; Add exception slots without shifting the saved register fields.
%macro DPMI_STEP_NORMAL 0
    sub esp, 8
    lea esi, [esp+8]
    mov edi, esp
    mov ecx, 10
    cld
    rep movsd
    mov ebx, esp
    call dpmi_step_check
    mov ecx, 10
%%restore:
    mov eax, [esp+ecx*4-4]
    mov [esp+ecx*4+4], eax
    loop %%restore
    add esp, 8
    mov ebx, esp
%endmacro

; A 16-bit client passes a 16-bit offset. Ignore the high word.
%macro DPMI_OFFSET16 2
    cmp byte [ebp+dpmi_client16], 0
    je %%wide
    movzx %1, %2
%%wide:
%endmacro

%macro MON_IRETD 0
%ifdef HOST_DPMI
    jmp mon_iret
%else
    iretd
%endif
%endmacro

%macro DPMI_DEBUG_STOP 0
%ifdef HOST_DPMI
    push eax
    mov eax, 400h
    mov dr7, eax
    pop eax
%endif
%endmacro

%ifdef RESIDENT_HOST
HOST_SCRATCH
%else
HOST_REAL
%endif
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
.vcpi_query_return:
    test ah, ah
    jnz .bad
%ifndef RESIDENT_HOST
    xor eax, eax
    mov ax, cs
    shl eax, 4
    mov [mon_base], eax
    mov [mon_real_base], eax
%else
    mov eax, [mon_base]
%endif
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
    mov [mon_gdt+DPMI_STUB16-3+2], ax
    mov edx, eax
    shr edx, 16
    mov [mon_gdt+56+4], dl
    mov [mon_gdt+56+7], dh
    mov [mon_gdt+DPMI_STUB16-3+4], dl
    mov [mon_gdt+DPMI_STUB16-3+7], dh
    lea edx, [eax+dpmi_ldt]
    mov [mon_gdt+72+2], dx
    shr edx, 16
    mov [mon_gdt+72+4], dl
    mov [mon_gdt+72+7], dh
%endif
    lea edx, [eax+mon_kernel_stack_top]
    mov [mon_tss+4], edx
    mov edx, [mon_real_base]
    add edx, mon_gdtr
    mov [mon_switch+4], edx
    mov edx, [mon_real_base]
    add edx, mon_idtr
    mov [mon_switch+8], edx
    lea edx, [eax+mon_enter]
    mov [mon_switch+16], edx
%ifdef RESIDENT_HOST
    xor eax, eax
    mov ax, cs
    shl eax, 4
%else
    mov eax, [mon_base]
%endif
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
    ; A ring-3 INT 0-2 or INT 5-7 is a software interrupt, not an exception:
    ; DPL 0 makes it fault into the INT n path. INT 3 and INTO stay DPL 3.
%assign vector 0
%rep 8
%if vector != 3 && vector != 4
    and byte [es:mon_idt+vector*8+5], 9fh
%endif
%assign vector vector+1
%endrep
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
    mov di, mon_idt+0f5h*8
    mov eax, [mon_base]
    add eax, dpmi_bridge_done
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

HOST_REAL
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
    mov edi, [mon_base]
    mov esi, [mon_real_base]
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

HOST_PROTECTED
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
    call dpmi_debug_host_save
    cmp byte [ebp+dpmi_active], 0
    jne dpmi_client_init
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

%assign vector 8
%rep 24
mon_shared_%+vector:
    push eax
%if vector == 13 || vector == 10
    ; A ring-3 #GP or #TS has one more stack dword than the IRQ.
    call .base
.base:
    pop eax
    sub eax, .base
    mov eax, [cs:eax+mon_tss+4]
    sub eax, 28
    cmp esp, eax
    je .exception
%endif
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
%if vector == 13 || vector == 10
.exception:
    pop eax
    jmp mon_exception_%+vector
%endif
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
    DPMI_DEBUG_STOP
    MON_IRETD

mon_irq:
    DPMI_DEBUG_STOP
    pushad
    push ds
    push es
    mov ax, 10h
    mov ds, ax
    mov es, ax
    cld
    call .base
.base:
    pop ebp
    sub ebp, .base
    inc dword [ebp+mon_irqs]
    HOST_COUNT irqentry, 0
%ifdef RESIDENT_HOST
    call dpmi_pic_sync
%endif
%ifdef HOST_DPMI
    lea ebx, [esp+8]
    call dpmi_locked_capture
    call dpmi_quiet_entry
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
%ifdef RESIDENT_HOST
    cmp byte [ebp+resident_refill_busy], 0
    je .queue
    ; The CD refill can wait for a disk or RTC IRQ, and the client cannot run now.
    cmp bl, 6
    je .disk_irq
    cmp bl, 8
    jb .queue
    cmp bl, 11
    jbe .disk_irq
    cmp bl, 14
    jae .disk_irq
.queue:
%endif
    call dpmi_pic_queue
    jmp .done
%ifdef RESIDENT_HOST
.disk_irq:
    lea edi, [ebp+mon_rm_regs]
    mov dword [edi+32], 2
    mov dword [edi+46], 0
    call mon_real_int
    jmp .done
%endif
.real_irq:
%endif
    lea edi, [ebp+mon_rm_regs]
    mov dword [edi+32], 2
    mov dword [edi+46], 0
%ifdef RESIDENT_HOST
    cmp byte [ebp+resident_irq_slot], 0
    je .audio_int
    ; The IVT can hold the game's handler. Call the mixer's handler.
    mov ecx, [ebp+resident_mixer_vector]
    mov [ebp+mon_rm_irq_target], ecx
    mov al, 3
    call mon_real_far
    jmp .audio_done
.audio_int:
%endif
    call mon_real_int
.audio_done:
%ifdef HOST_DPMI
    call dpmi_hardware_room
    jnc .callback_room
    HOST_DIAG 26
    jmp .done
.callback_room:
%endif
    cmp dword [ebp+mon_irq_callback], 0
    je .done
    call [ebp+mon_irq_callback]
    test ax, ax
    jz .done
    dec ax
    movzx eax, ax
    cmp eax, 256
    jae .done
%ifdef RESIDENT_HOST
    call resident_audio_deliver
%endif
    mov edx, eax
    imul eax, 6
    lea esi, [ebp+mon_vectors+eax]
%ifdef HOST_DPMI
    cmp word [esi+4], 0
    jne .virtual_protected
    mov eax, edx
    lea edi, [ebp+mon_rm_regs]
    mov dword [edi+32], 2
    mov dword [edi+46], 0
    call mon_real_int
    jmp .done
.virtual_protected:
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
%ifdef HOST_DPMI
    cld
    mov ebx, esp
    call dpmi_record_segments
    call dpmi_sti_arrival
    call dpmi_locked_capture
    call dpmi_quiet_entry
    call dpmi_tf_entry
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
    imul edx, 3
    add edx, dpmi_default_vectors
    mov [esp+28], edx
    call dpmi_stub_selector
    mov cx, ax
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
%ifdef HOST_DPMI
mon_real_irq:
    push dword 0
    jmp mon_real_irq_start
; As mon_real_irq with the register copy count in ECX.
mon_real_irq_copy:
    push ecx
mon_real_irq_start:
    mov byte [ebp+mon_rm_kind], 0
    mov [ebp+mon_int_opcode+1], al
    call dpmi_bridge_mark_irq
    push esi
    call dpmi_bridge_chained_vector
    ; Only a real-mode hook in front of the stub can chain back to it.
    cmp esi, 1024
    jb mon_real_int_vector
    call dpmi_bridge_unmark_irq
    jmp mon_real_int_vector
%endif
mon_real_int:
    push dword 0
    jmp mon_real_int_start
mon_real_int_copy:
    push ecx
mon_real_int_start:
    mov byte [ebp+mon_rm_kind], 0
    mov [ebp+mon_int_opcode+1], al
%ifdef HOST_DPMI
    mov byte [ebp+dpmi_bridge_irq_chain], 0
    push esi
    call dpmi_bridge_real_vector
mon_real_int_vector:
    cmp esi, 1024
    jb .ordinary
    push eax
    mov eax, [esi]
    mov [ebp+mon_rm_irq_target], eax
    pop eax
    mov byte [ebp+mon_rm_kind], 3
.ordinary:
    pop esi
%endif
    jmp mon_real_transfer
mon_real_far:
    push dword 0
    jmp mon_real_far_start
mon_real_far_copy:
    push ecx
mon_real_far_start:
    mov [ebp+mon_rm_kind], al
%ifdef HOST_DPMI
    mov byte [ebp+dpmi_bridge_irq_chain], 0
%endif
mon_real_transfer:
    HOST_COUNT bridge, 0
    ; A raw switch can run client code inside this call. Keep the outer state.
    sub esp, 36
    push esi
    push edi
    push ecx
    lea esi, [ebp+mon_return]
    lea edi, [esp+12]
    mov ecx, 9
    cld
    rep movsd
    pop ecx
    pop edi
    pop esi
    push dword [ebp+mon_switch+16]
    push dword [ebp+mon_resume_sp]
    push dword [ebp+mon_tss+4]
    push dword [ebp+mon_rm_regs+46]
    push fs
    push gs
    push dword [ebp+mon_rm_stack]
%ifdef HOST_DPMI
    push word [ebp+dpmi_vif]
    push dword [ebp+dpmi_bridge_stack]
    cmp dword [ebp+dpmi_bridge_context], 0
    je .stack_ready
    cmp esp, 3fa000h
    jb .stack_ready
    cmp esp, 3fc000h
    ja .stack_ready
    push eax
    lea eax, [esp-28]
    mov [ebp+dpmi_bridge_stack], eax
    pop eax
.stack_ready:
%endif
    pushad
%ifdef RESIDENT_HOST
    mov al, [ebp+dpmi_audio_irq]
    cmp al, [ebp+dpmi_guest_irq]
    jne .irq_ready
    ; With the JEMMEX IRQ slot, the mixer gets the IRQ without the IVT.
    cmp byte [ebp+resident_irq_slot], 0
    jne .irq_ready
    movzx ebx, al
    movzx eax, byte [ebp+mon_master]
    add eax, ebx
    shl eax, 2
    ; Keep the mixer on the real IVT. POPAD ignores its saved ESP slot.
    mov ecx, [eax]
    mov [esp+12], ecx
    mov ecx, [ebp+dpmi_bridge_vectors+ebx*4]
    mov [eax], ecx
.irq_ready:
%endif
    mov [ebp+mon_resume_sp], esp
    mov [ebp+mon_rm_target], edi
    mov esi, edi
    lea edi, [ebp+mon_rm_regs]
    mov ecx, 50
    cld
    rep movsb
    ; A client flags image can carry TF or the NT of dpmi_quiet_exit.
    and byte [ebp+mon_rm_regs+33], 0beh
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
%ifdef HOST_DPMI
    call dpmi_debug_host_save
    ; The reflected IRQ has ended. A later IRQ at the stub is a new one.
    mov byte [ebp+dpmi_bridge_irq_chain], 0
%endif
%ifdef HOST_DPMI
    lea esi, [esp+66]
%else
    lea esi, [esp+60]
%endif
    lea edi, [ebp+mon_return]
    mov ecx, 9
    cld
    rep movsd
    movzx eax, word [esi]
    test eax, eax
    jz .stack_ready
    cmp word [ebp+mon_rm_regs+48], 0
    je .host_stack
    add [ebp+mon_rm_regs+46], ax
    jmp .stack_ready
.host_stack:
    add [ebp+mon_return+12], ax
.stack_ready:
    lea esi, [ebp+mon_rm_regs]
    mov edi, [esp]
    mov ecx, 50
    rep movsb
%ifdef RESIDENT_HOST
    mov al, [ebp+dpmi_audio_irq]
    cmp al, [ebp+dpmi_guest_irq]
    jne .irq_restored
    cmp byte [ebp+resident_irq_slot], 0
    jne .irq_restored
    movzx ebx, al
    movzx eax, byte [ebp+mon_master]
    add eax, ebx
    shl eax, 2
    ; Keep a vector that the real-mode code installed during the call.
    mov ecx, [ebp+dpmi_bridge_vectors+ebx*4]
    cmp [eax], ecx
    jne .irq_restored
    mov ecx, [esp+12]
    mov [eax], ecx
.irq_restored:
%endif
    popad
%ifdef HOST_DPMI
    pop dword [ebp+dpmi_bridge_stack]
    pop word [ebp+dpmi_vif]
%endif
    pop dword [ebp+mon_rm_stack]
    pop gs
    pop fs
    pop dword [ebp+mon_rm_regs+46]
    pop dword [ebp+mon_tss+4]
    pop dword [ebp+mon_resume_sp]
    pop dword [ebp+mon_switch+16]
    add esp, 40
%ifdef RESIDENT_HOST
    call resident_refill_callback
%endif
    ret

mon_exception:
    DPMI_DEBUG_STOP
    pushad
    push ds
    push es
    mov ax, 10h
    mov ds, ax
    mov es, ax
    cld
    call .base
.base:
    pop ebp
    sub ebp, .base
%ifdef HOST_DPMI
    lea ebx, [esp+8]
    call dpmi_locked_capture
    call dpmi_quiet_entry
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
    jne .debug_ready
    test byte [esp+52], 3
    jz .debug_ready
    call dpmi_debug_breakpoint
    jc .fault
.debug_ready:
    cmp byte [ebp+dpmi_sti_shadow], 0
    je .shadow_arrival
    cmp dword [esp+40], 1
    jne .shadow_arrival
    test byte [esp+52], 3
    jz .shadow_arrival
    mov eax, dr6
    test eax, 0a00fh
    jnz .shadow_arrival
    test eax, 4000h
    jnz .shadow_debug
    test word [esp+56], 100h
    jnz .shadow_debug
    ; Without BS, a POPF or IRET in the shadow clears the saved TF.
    call dpmi_sti_loads_flags
    jc .shadow_arrival
.shadow_debug:
    lea ebx, [esp+8]
    call dpmi_sti_retire
    cmp byte [ebp+dpmi_sti_tf], 0
    jne .ordinary_exception
    xor edi, edi
    jmp .advance
.shadow_arrival:
    lea ebx, [esp+8]
    call dpmi_sti_arrival
    cmp dword [esp+40], 1
    jne .ordinary_exception
%ifdef RESIDENT_HOST
    cmp byte [ebp+dpmi_audio_steps], 0
    je .audio_done
    test byte [esp+52], 3
    jz .audio_done
    mov esi, [ebp+resident_audio_request]
    test esi, esi
    jz .audio_stop
    cmp byte [esi+14], 0
    je .audio_stop
    dec byte [ebp+dpmi_audio_steps]
    jz .audio_due
    cmp byte [ebp+dpmi_step_active], 1
    je .audio_done
    xor edi, edi
    jmp .advance
.audio_stop:
    mov byte [ebp+dpmi_audio_steps], 0
    cmp byte [ebp+dpmi_step_active], 1
    je .audio_done
    and word [esp+56], 0feffh
    xor edi, edi
    jmp .advance
.audio_due:
    cmp byte [ebp+dpmi_step_active], 1
    je .audio_fire
    and word [esp+56], 0feffh
.audio_fire:
    call resident_audio_due
    cmp byte [ebp+dpmi_step_active], 1
    je .audio_done
    xor edi, edi
    jmp .advance
.audio_done:
%endif
    cmp byte [ebp+dpmi_step_active], 1
    jne .tf_image
    test byte [esp+52], 3
    jz .ordinary_exception
    mov ebx, esp
    cld
    HOST_SAMPLE_STEP
    call dpmi_step_check
    cmp byte [ebp+dpmi_step_active], 0
    je .budget_ready
    dec byte [ebp+dpmi_step_budget]
    jnz .budget_ready
    ; A long CLI section (a blit with ESP as the pointer) runs at full speed.
    mov byte [ebp+dpmi_step_active], 0
%ifdef RESIDENT_HOST
    cmp byte [ebp+dpmi_audio_steps], 0
    jne .budget_audio
%endif
    and word [esp+56], 0feffh
.budget_audio:
    mov byte [ebp+dpmi_step_holdoff], DPMI_STEP_HOLDOFF
.budget_ready:
    ; VIF stays clear: skip IRQ/refill checks, but retain stack repair.
    cmp word [ebp+dpmi_vif], 0100h
    jne .step_full
    mov ax, [esp+52]
    call dpmi_debug_arm
    pop es
    pop ds
    popad
    add esp, 8
    jmp mon_iret.restore_stack
.step_full:
    xor edi, edi
    jmp .advance
.tf_image:
    mov ebx, esp
    call dpmi_tf_loaded
    jnc .ordinary_exception
    call dpmi_tf_fired
    xor edi, edi
    jmp .advance
.ordinary_exception:
    mov ebx, esp
    call dpmi_task_return
    jc .not_task_return
    xor edi, edi
    jmp .advance
.not_task_return:
%endif
    cmp dword [esp+40], 13
    jne .fault
    HOST_COUNT gp, 0
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
%ifdef HOST_DPMI
    ; A ring-3 INT n to an IRQ gate faults with the IDT bit. Run it as INT n.
    mov eax, [esp+44]
    test eax, eax
    jz .no_gate
    and al, 3
    cmp al, 2
    jne .fault
    test byte [esp+52], 3
    jz .fault
    cmp byte [ebp+dpmi_active], 0
    je .fault
    mov ebx, esp
    xor edi, edi
    call mon_gp_fetch
    jc .fault
    cmp al, 0cdh
    jne .fault
    inc edi
    call mon_gp_fetch
    jc .fault
    movzx eax, al
    mov edx, [esp+44]
    shr edx, 3
    cmp eax, edx
    jne .fault
    mov [esp+40], eax
    mov dword [esp+44], 0
    add dword [esp+48], 2
    jmp dpmi_software_interrupt
.no_gate:
%endif
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
.flat_opcode:
    call mon_gp_fetch
    jc .fault
    cmp al, 66h
%else
    cmp byte [esi], 66h
%endif
%ifdef HOST_DPMI
    jne .opcode_ready
%else
    jne .opcode
%endif
    inc edi
    xor cl, 6
.opcode:
%ifdef HOST_DPMI
    call mon_gp_fetch
    jc .fault
%else
    mov al, [esi+edi]
%endif
.opcode_ready:
    inc edi
%ifdef HOST_DPMI
    cmp al, 0fh
    je .debug_instruction
%endif
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
    jc .trapped
    cmp cl, 1
    je .fault
    push edx
    push ecx
    movzx ecx, cl
.more_ports:
    dec ecx
    jz .untrapped
    inc edx
    cmp edx, 10000h
    jae .untrapped
    bt [ebp+mon_bitmap], edx
    jnc .more_ports
    pop ecx
    pop edx
    jmp .trapped
.untrapped:
    pop ecx
    pop edx
    jmp .fault
.trapped:
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
%ifdef HOST_DPMI
.debug_instruction:
    call mon_gp_fetch
    jc .fault
    cmp al, 20h
    je .control_read
    cmp al, 22h
    je .control_write
    call dpmi_debug_move
    jc .fault
    cmp byte [ebp+dpmi_debug_pending], 0
    je .advance
    mov dword [esp+40], 1
    or dword [esp+56], 10000h
    jmp .fault
.control_read:
    call dpmi_cr0_read
    jc .fault
    jmp .advance
.control_write:
    call dpmi_cr0_write
    jc .fault
    jmp .advance
%endif
.cli:
%ifdef HOST_DPMI
    ; A frame with a stale TF turns the virtual IF on first; the CLI faults
    ; again.
    mov ebx, esp
    call dpmi_tf_loaded
    jnc .cli_state
    call dpmi_tf_fired
    xor edi, edi
    jmp .advance
.cli_state:
    cmp word [ebp+dpmi_vif], 0
    jne .trace_cli
    mov ebx, esp
    mov ecx, 0fdffh
    call dpmi_quiet_image
    jmp .cli_quiet
.trace_cli:
    HOST_COUNT cli, 0
    cmp byte [ebp+dpmi_vif], 0
    je .cli_stepping
    call dpmi_clear_vif
    cmp byte [ebp+dpmi_quiet_leak], 0
    je .cli_quiet
    mov ebx, esp
    mov ecx, 0bfffh
    call dpmi_quiet_image
    mov byte [ebp+dpmi_quiet_leak], 0
.cli_quiet:
    and word [esp+56], 0feffh
    or word [esp+56], 200h
    jmp .advance
.cli_stepping:
    call dpmi_clear_vif
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
    mov ebx, esp
    call dpmi_tf_loaded
    jnc .sti_state
    call dpmi_tf_fired
.sti_state:
    call dpmi_sti_begin
    xor edi, edi
%endif
    or word [esp+56], 200h
    jmp .advance
.fault:
%ifdef HOST_DPMI
    cmp byte [ebp+dpmi_active], 0
    je .unhandled
    test byte [esp+52], 3
    jz .unhandled
    mov ebx, esp
    call dpmi_tf_loaded
    jnc .fault_frame
    call dpmi_tf_fired
.fault_frame:
    mov eax, [esp+40]
    cmp eax, 32
    jae .unhandled
    imul eax, 6
    lea esi, [ebp+dpmi_exceptions+eax]
    cmp word [esi+4], 0
    jne dpmi_deliver_exception
    mov ecx, [esp+40]
    mov edx, 0bfh
    bt edx, ecx
    jnc .unhandled
    lea esi, [ebp+mon_vectors+eax]
    cmp word [esi+4], 0
    je .unhandled
    mov edi, esp
    add edi, 44
    mov ecx, 10
.debug_frame:
    mov eax, [edi-8]
    mov [edi], eax
    sub edi, 4
    loop .debug_frame
    add esp, 8
    mov ebx, esp
    jmp dpmi_deliver_interrupt
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
; Permit CR0 reads and unchanged writes from client runtimes.
dpmi_cr0_write:
    pushad
    inc edi
    call mon_gp_fetch
    jc .bad
    cmp al, 0c0h
    jb .bad
    cmp al, 0c7h
    ja .bad
    inc edi
    and eax, 7
    movzx esi, byte [ebp+dpmi_full_registers+eax]
    mov eax, cr0
    cmp [ebx+esi], eax
    jne .bad
    mov [esp], edi
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

dpmi_cr0_read:
    pushad
    inc edi
    call mon_gp_fetch
    jc .bad
    cmp al, 0c0h
    jb .bad
    cmp al, 0c7h
    ja .bad
    inc edi
    and eax, 7
    movzx esi, byte [ebp+dpmi_full_registers+eax]
    mov eax, cr0
    mov [ebx+esi], eax
    mov [esp], edi
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

; EBX=exception frame, EDI=instruction offset. Keep other registers.
mon_gp_fetch:
    pushad
    mov ax, [ebx+52]
    mov edx, [ebx+48]
    add edx, edi
    jc .bad
    mov ecx, 1
    mov edi, 2
    call dpmi_code_buffer
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
%ifdef HOST_DPMI
    call dpmi_debug_host_restore
%endif
    lea esp, [ebp+mon_return]
    sub esp, ebp
    add esp, [ebp+mon_real_base]
    clts
    mov ax, 0de0ch
    call far [ebp+mon_server]
    ud2
mon_virtual_return:
    ud2

HOST_REAL
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
%ifdef HOST_DPMI
    cmp byte [cs:mon_rm_kind], 3
    je .host_irq
%endif
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
    jmp mon_callback_done
%ifdef HOST_DPMI
.host_irq:
    push word [cs:mon_rm_regs+32]
    cli
    call far [cs:mon_rm_irq_target]
%endif
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
    mov esi, [mon_real_base]
    add esi, mon_switch
    mov ax, 0de0ch
    int 67h

%ifdef RESIDENT_HOST
%include "host/nested.asm"
%endif
HOST_REAL
align 4
mon_base dd 0
mon_real_base dd 0
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
HOST_PROTECTED
mon_vectors times 256*6 db 0
HOST_REAL
mon_resume_sp dd 0
mon_rm_target dd 0
mon_rm_stack dd 0
mon_rm_kind db 0
mon_rm_regs times 50 db 0
%ifdef HOST_DPMI
mon_rm_irq_target dd 0
%endif
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
%ifdef HOST_DPMI
    dq 0000fa000000ffffh
%endif
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
%if vector < 8
    dw mon_exception_%+vector
%else
    dw mon_shared_%+vector
%endif
%assign vector vector+1
%endrep
mon_irq_stubs:
%assign irq 0
%rep 16
    dw mon_irq_%+irq
%assign irq irq+1
%endrep
HOST_PROTECTED
mon_idt times 256*8 db 0
mon_tss:
    dd 0,0
    dw 10h,0
    times 90 db 0
    dw 104
mon_bitmap times 8192 db 0
    db 0ffh
mon_tss_end:
%ifdef RESIDENT_HOST
section .pages
mon_pages resb 12287
%elifdef TAIL_NOBITS
; The page area and the stacks follow the image, so the image fits a COM file.
section .pages nobits align=16
mon_pages resb 12287
    resb 2048
mon_kernel_stack_top:
%ifndef HOST_DPMI
    resb 2048
%endif
mon_client_stack_top:
section .text
HOST_PROTECTED
%else
HOST_SCRATCH
mon_pages times 12287 db 0
%endif
%ifndef TAIL_NOBITS
HOST_PROTECTED
%ifdef RESIDENT_HOST
mon_client_stack_top equ mon_kernel_stack_top
%else
    times 2048 db 0
mon_kernel_stack_top:
%ifndef HOST_DPMI
    times 2048 db 0
%endif
mon_client_stack_top:
%endif
%endif
%ifdef HOST_DPMI
%include "host/dpmi.asm"
%endif
%ifndef RESIDENT_HOST
HOST_REAL
%endif
