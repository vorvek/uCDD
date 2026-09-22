; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%ifdef RESIDENT_HOST
HOST_SCRATCH
%define DPMI_TRACE_COUNT 16
%else
HOST_REAL
%define DPMI_TRACE_COUNT 32
%endif
dpmi_install:
    mov ax, 1687h
    int 2fh
    test ax, ax
    jz .bad
    xor ax, ax
    xor bx, bx
    call monitor_init
    jc .bad
%ifdef RESIDENT_HOST
    mov ax, 352fh
    int 21h
    mov [dpmi_old_mux], bx
    mov [dpmi_old_mux+2], es
    clc
    ret
%endif
    mov ax, 352fh
    int 21h
    mov [dpmi_old_mux], bx
    mov [dpmi_old_mux+2], es
    mov dx, dpmi_mux
    mov ax, 252fh
    int 21h
    clc
    ret
.bad:
    stc
    ret
dpmi_remove:
    push ds
    lds dx, [dpmi_old_mux]
    mov ax, 252fh
    int 21h
    pop ds
    ret
HOST_REAL
dpmi_mux:
    cmp ax, 1687h
    jne .chain
    xor ax, ax
    mov bx, 1
    mov cx, 3
    mov dx, 90
    xor si, si
    push cs
    pop es
    mov di, dpmi_entry
    iret
.chain:
    jmp far [cs:dpmi_old_mux]

dpmi_entry:
    cmp ax, 1
    jne .bad
    cmp byte [cs:dpmi_active], 0
    jne .bad
    pushf
    pushad
    push ds
    push es
    push fs
    push gs
    mov bp, sp
    push cs
    pop ds
    push cs
    pop es
    cld
    mov di, dpmi_client_regs
    lea si, [bp+8]
    mov cx, 8
.copy:
    mov eax, [ss:si]
    stosd
    add si, 4
    loop .copy
    movzx eax, word [ss:bp+42]
    mov [dpmi_client_ip], eax
    mov ax, [ss:bp+40]
    and ax, 0cfeh
    or ax, 202h
    mov [dpmi_client_flags], ax
    lea ax, [bp+46]
    mov [dpmi_client_sp], ax
    mov ax, [ss:bp+44]
    mov [dpmi_client_cs], ax
    mov ax, [ss:bp+6]
    mov [dpmi_client_ds], ax
    mov ax, ss
    mov [dpmi_client_ss], ax
    mov byte [dpmi_callback_active], 0
    mov dword [dpmi_pending_irqs], 0
    call dpmi_ivt_snapshot
    mov ah, 51h
    int 21h
    mov ax, bx
    mov [dpmi_psp], ax
    push es
    mov es, [dpmi_psp]
    mov ax, [es:2ch]
    mov [dpmi_environment], ax
    test ax, ax
    jz .no_environment
    mov word [es:2ch], 2fh
.no_environment:
    pop es
    mov byte [dpmi_exit_code], 1
    call dpmi_bridge_real_allocate
    jc .exit
    mov byte [dpmi_audio_pm_handler], 0
    mov byte [dpmi_active], 1
    mov byte [dpmi_exit_code], 1
    cli
%ifdef RESIDENT_HOST
    mov ax, [host_stack_segment]
    mov ss, ax
    mov sp, HOST_STACK_BYTES
%else
    mov ax, cs
    mov ss, ax
    mov sp, dpmi_entry_stack_top
%endif
    sti
    call monitor_run
    mov byte [dpmi_active], 0
    call dpmi_bridge_real_free
    test ax, ax
    jz .exit
    mov byte [dpmi_exit_code], 1
.exit:
    mov es, [dpmi_psp]
    mov ax, [dpmi_environment]
    mov [es:2ch], ax
    mov al, [dpmi_exit_code]
    mov ah, 4ch
    int 21h
.bad:
    stc
    retf

%ifdef RESIDENT_HOST
dpmi_traps_suspended db 0
%endif

HOST_PROTECTED
; A return to a 16-bit stack must preserve the client's high ESP word.
mon_iret:
    pushad
    push ds
    push es
    mov ax, 10h
    mov ds, ax
    mov es, ax
    call .irq_base
.irq_base:
    pop ebp
    sub ebp, .irq_base
    test byte [esp+44], 3
    jz .no_irq
    cmp byte [ebp+dpmi_step_active], 1
    jne .check_irq
    or word [esp+48], 300h
    DPMI_STEP_NORMAL
.check_irq:
    cmp byte [ebp+dpmi_vif], 1
    jne .no_irq
    test byte [esp+44], 3
    jz .no_irq
    call dpmi_pic_next
    jc .no_irq
    movzx edx, byte [ebp+mon_master]
    cmp eax, 8
    jb .irq_vector
    movzx edx, byte [ebp+mon_slave]
    sub edx, 8
.irq_vector:
    add eax, edx
    imul eax, 6
    lea esi, [ebp+mon_vectors+eax]
    mov ebx, esp
    jmp dpmi_deliver_hardware
.no_irq:
%ifdef RESIDENT_HOST
    call resident_refill_schedule
%endif
    pop es
    pop ds
    popad
    push eax
    push ecx
    push edx
    test byte [ss:esp+16], 3
    jz .plain
    test dword [ss:esp+20], 20000h
    jnz .plain
    mov eax, [ss:esp+24]
    and eax, 0ffff0000h
    mov edx, esp
    and edx, 0ffff0000h
    sub edx, eax
    jz .plain
    call .base
.base:
    pop ecx
    sub ecx, .base
    mov [ss:ecx+mon_gdt+48+2], dx
    shr edx, 16
    mov [ss:ecx+mon_gdt+48+4], dl
    mov [ss:ecx+mon_gdt+48+7], dh
    mov edx, esp
    and edx, 0ffffh
    or edx, eax
    mov ax, 30h
    mov ss, ax
    mov esp, edx
.plain:
    pop edx
    pop ecx
    pop eax
    iretd

dpmi_client_init:
%ifdef RESIDENT_HOST
    call resident_refill_reset
%endif
    xor eax, eax
    lea edi, [ebp+dpmi_ldt]
    mov ecx, DPMI_LDT_COUNT*8/4
    rep stosd
    lea edi, [ebp+dpmi_used]
    mov ecx, DPMI_LDT_COUNT/4
    rep stosd
    lea edi, [ebp+mon_vectors]
    mov ecx, 256*6/4
    rep stosd
    lea edi, [ebp+dpmi_exceptions]
    mov ecx, 32*6/4
    rep stosd
    mov byte [ebp+dpmi_exception_active], 0
    lea edi, [ebp+dpmi_callbacks]
    mov ecx, 16*20/4
    rep stosd
    mov byte [ebp+dpmi_vif], 1
    mov byte [ebp+dpmi_step_active], 0
    mov byte [ebp+dpmi_first_exception], 0ffh
    call dpmi_ivt_snapshot_protected
    call dpmi_pic_reset
    mov dword [ebp+dpmi_used+1], 01010101h
    lea edi, [ebp+dpmi_ldt+8]
    movzx eax, word [ebp+dpmi_client_cs]
    mov bl, 0fah
    call dpmi_initial_descriptor
    movzx eax, word [ebp+dpmi_client_ds]
    mov bl, 0f2h
    call dpmi_initial_descriptor
    movzx eax, word [ebp+dpmi_client_ss]
    call dpmi_initial_descriptor
    mov byte [ebp+dpmi_ldt+2*8+6], 40h
    mov byte [ebp+dpmi_ldt+3*8+6], 40h
    movzx eax, word [ebp+dpmi_psp]
    call dpmi_initial_descriptor
    mov word [ebp+dpmi_ldt+4*8], 0ffh
    movzx eax, word [ebp+dpmi_environment]
    test eax, eax
    jz .environment_ready
    mov byte [ebp+dpmi_used+5], 1
    call dpmi_initial_descriptor
.environment_ready:
    jmp dpmi_enter_client

dpmi_initial_descriptor:
    shl eax, 4
    mov word [edi], 0ffffh
    mov [edi+2], ax
    shr eax, 16
    mov [edi+4], al
    mov [edi+5], bl
    add edi, 8
    ret

dpmi_enter_client:
    lea esi, [ebp+mon_return]
    lea edi, [ebp+dpmi_exit_frame]
    mov ecx, 9
    rep movsd
    mov byte [ebp+dpmi_release_failed], 0
    call dpmi_locked_init
    jc dpmi_locked_abort
    call dpmi_memory_init
    jc dpmi_locked_abort
    call dpmi_bridge_install
    push dword 1fh
    movzx eax, word [ebp+dpmi_client_sp]
    push eax
    movzx eax, word [ebp+dpmi_client_flags]
    push eax
    push dword 0fh
    push dword [ebp+dpmi_client_ip]
    mov ax, 17h
    mov ds, ax
    mov ax, 27h
    mov es, ax
    xor eax, eax
    mov fs, ax
    mov gs, ax
    mov edi, [ss:ebp+dpmi_client_regs]
    mov esi, [ss:ebp+dpmi_client_regs+4]
    mov ebx, [ss:ebp+dpmi_client_regs+16]
    mov edx, [ss:ebp+dpmi_client_regs+20]
    mov ecx, [ss:ebp+dpmi_client_regs+24]
    mov eax, [ss:ebp+dpmi_client_regs+28]
    mov ebp, [ss:ebp+dpmi_client_regs+8]
    MON_IRETD

dpmi_dispatch:
    mov byte [ebp+dpmi_dos_via21], 0
    movzx eax, word [ebx+36]
    mov [ebp+dpmi_last_call], ax
    movzx edx, byte [ebp+dpmi_trace_pos]
    mov [ebp+dpmi_trace+edx*2], ax
    push eax
    push edx
    imul edx, 24
    mov eax, [ebx+24]
    mov [ebp+dpmi_trace_args+edx], ax
    mov ax, [ebx+32]
    mov [ebp+dpmi_trace_args+edx+2], ax
    mov ax, [ebx+28]
    mov [ebp+dpmi_trace_args+edx+4], ax
    mov ax, [ebx]
    mov [ebp+dpmi_trace_args+edx+6], ax
    mov ax, [ebx+4]
    mov [ebp+dpmi_trace_args+edx+8], ax
    mov eax, [ebx+40]
    mov [ebp+dpmi_trace_args+edx+10], eax
    mov ax, [ebx+44]
    mov [ebp+dpmi_trace_args+edx+14], ax
    mov eax, [ebx+8]
    mov [ebp+dpmi_trace_args+edx+16], eax
    mov eax, [ebx+52]
    mov [ebp+dpmi_trace_args+edx+20], eax
    pop edx
    pop eax
    inc dl
    and dl, DPMI_TRACE_COUNT-1
    mov [ebp+dpmi_trace_pos], dl
    cmp eax, 0ch
    jbe dpmi_descriptors
    cmp eax, 0100h
    je dpmi_dos_allocate
    cmp eax, 0101h
    je dpmi_dos_free
    cmp eax, 0102h
    je dpmi_dos_resize
    cmp eax, 0204h
    je mon_dpmi.get_vector
    cmp eax, 0200h
    je dpmi_get_real_vector
    cmp eax, 0201h
    je dpmi_set_real_vector
    cmp eax, 0202h
    je dpmi_get_exception
    cmp eax, 0203h
    je dpmi_set_exception
    cmp eax, 0205h
    je dpmi_set_vector
    cmp eax, 0300h
    je .simulate
    cmp eax, 0301h
    je .simulate
    cmp eax, 0302h
    je .simulate
    cmp eax, 0303h
    je dpmi_callback_allocate
    cmp eax, 0304h
    je dpmi_callback_free
    cmp eax, 0305h
    je dpmi_state_addresses
    cmp eax, 0306h
    je dpmi_raw_addresses
    cmp eax, 0400h
    je .version
    cmp eax, 0501h
    je dpmi_allocate
    cmp eax, 0500h
    je dpmi_memory_info
    cmp eax, 0502h
    je dpmi_free
    cmp eax, 0503h
    je dpmi_resize
    cmp eax, 0604h
    je .page_size
    cmp eax, 0600h
    je mon_dpmi.success
    cmp eax, 0601h
    je mon_dpmi.success
    cmp eax, 0702h
    je mon_dpmi.success
    cmp eax, 0800h
    je dpmi_physical_map
    cmp eax, 0801h
    je dpmi_physical_unmap
    cmp eax, 0900h
    je .disable
    cmp eax, 0901h
    je .enable
    cmp eax, 0902h
    je .interrupt_state
    jmp mon_dpmi.unsupported
.disable:
    call .interrupt_state_value
    mov byte [ebp+dpmi_vif], 0
    cmp byte [ebp+dpmi_step_active], 1
    je .disable_traced
    and word [ebx+48], 0feffh
    or word [ebx+48], 200h
    jmp mon_dpmi.success
.disable_traced:
    or word [ebx+48], 300h
    DPMI_STEP_NORMAL
    jmp mon_dpmi.success
.enable:
    call .interrupt_state_value
    mov byte [ebp+dpmi_vif], 1
    mov byte [ebp+dpmi_step_active], 0
    and word [ebx+48], 0feffh
    or word [ebx+48], 200h
    jmp mon_dpmi.success
.interrupt_state:
    call .interrupt_state_value
    jmp mon_dpmi.success
.interrupt_state_value:
    mov al, [ebp+dpmi_vif]
    mov [ebx+36], ax
    ret
.version:
    mov word [ebx+36], 90
    mov word [ebx+24], 1
    mov byte [ebx+32], 3
    mov al, [ebp+mon_master]
    mov [ebx+29], al
    mov al, [ebp+mon_slave]
    mov [ebx+28], al
    jmp mon_dpmi.success
.page_size:
    mov word [ebx+24], 0
    mov word [ebx+32], 4096
    jmp mon_dpmi.success
.simulate:
    cmp word [ebx+32], 0
    jne mon_dpmi.unsupported
    mov ax, [ebx]
    mov edx, [ebx+8]
    mov ecx, 50
    mov edi, 1
    call dpmi_buffer
    jc dpmi_error
    mov edi, eax
    mov ax, [ebx+36]
    cmp al, 0
    jne .far_call
    cmp byte [ebx+24], 21h
    jne .interrupt
    cmp byte [edi+29], 4ch
    je dpmi_bad_value
.interrupt:
    movzx eax, byte [ebx+24]
    call mon_real_int
    jmp mon_dpmi.success
.far_call:
    call mon_real_far
    jmp mon_dpmi.success

dpmi_bad_selector:
    mov ax, 8022h
    jmp dpmi_error
dpmi_bad_value:
    mov ax, 8021h
dpmi_error:
    push eax
    push esi
    push edi
    push ecx
    mov esi, ebx
    lea edi, [ebp+dpmi_error_frame]
    mov ecx, 15
    cld
    rep movsd
    pop ecx
    pop edi
    pop esi
    pop eax
    mov [ebp+dpmi_last_error], ax
    mov dx, [ebx+36]
    mov [ebp+dpmi_error_call], dx
    mov dx, [ebx+32]
    mov [ebp+dpmi_error_cx], dx
    mov [ebx+36], ax
    or byte [ebx+48], 1
    jmp mon_dpmi.done

dpmi_dos:
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
    cld
    mov ebx, esp
    call dpmi_locked_capture
    cmp word [ebp+mon_vectors+21h*6+4], 0
    je .host
    lea esi, [ebp+mon_vectors+21h*6]
    jmp dpmi_deliver_interrupt
.host:
    mov byte [ebp+dpmi_reflect_vector], 21h
    mov ax, [ebx+36]
    mov [ebp+dpmi_last_dos], ax
    cmp byte [esp+37], 4ch
    jne dpmi_dos_translate
    mov al, [esp+36]
    mov [ebp+dpmi_exit_code], al
    mov word [ebp+mon_status], 0
    jmp dpmi_finish
.unsupported:
    mov word [esp+36], 1
    or byte [esp+48], 1
    pop es
    pop ds
    popad
    MON_IRETD

dpmi_finish:
%ifdef RESIDENT_HOST
    call resident_refill_reset
%endif
    mov byte [ebp+dpmi_callback_active], 0
    mov byte [ebp+dpmi_exception_active], 0
    lea esi, [ebp+dpmi_exit_frame]
    lea edi, [ebp+mon_return]
    mov ecx, 9
    cld
    rep movsd
    lea eax, [ebp+mon_kernel_stack_top]
    mov [ebp+mon_tss+4], eax
    mov esp, eax
    lea eax, [ebp+mon_enter]
    mov [ebp+mon_switch+16], eax
    call dpmi_memory_cleanup
    cmp byte [ebp+dpmi_release_failed], 0
    je .cleanup_ready
    mov byte [ebp+dpmi_exit_code], 1
.cleanup_ready:
    jmp mon_leave

%include "host/descriptors.asm"
%include "host/memory.asm"
%include "host/dos.asm"
%include "host/vectors.asm"
%include "host/switch.asm"
%include "host/callback.asm"
%include "host/bridge.asm"
%include "host/interrupts.asm"
%include "host/locked.asm"
%include "host/pic.asm"
%include "host/cleanup.asm"

HOST_REAL
dpmi_old_mux dd 0
dpmi_audio_irq db 0ffh
dpmi_guest_irq db 5
dpmi_guest_vector db 0dh
dpmi_pending_irqs dd 0
dpmi_active db 0
dpmi_audio_pm_handler db 0
%if dpmi_audio_pm_handler-dpmi_active != 1
    %error Invalid resident IRQ state layout
%endif
dpmi_psp dw 0
dpmi_environment dw 0
dpmi_exit_code db 1
dpmi_last_call dw 0
dpmi_last_dos dw 0
dpmi_unsupported dw 0
dpmi_last_error dw 0
dpmi_error_call dw 0
dpmi_error_cx dw 0
dpmi_client_regs times 32 db 0
dpmi_client_ip dd 0
dpmi_client_sp dw 0
dpmi_client_flags dw 0
dpmi_client_cs dw 0
dpmi_client_ds dw 0
dpmi_client_ss dw 0

HOST_PROTECTED
dpmi_error_frame times 60 db 0
dpmi_unsupported_frame times 60 db 0
dpmi_trace_pos db 0
dpmi_trace times DPMI_TRACE_COUNT dw 0
dpmi_trace_args times DPMI_TRACE_COUNT*24 db 0
dpmi_trace_end:
dpmi_fault_ip dd 0
dpmi_fault_regs times 16 dd 0
dpmi_fault_bytes times 8 db 0
dpmi_fault_stack times 64 db 0
dpmi_ldt times DPMI_LDT_COUNT*8 db 0
dpmi_used times DPMI_LDT_COUNT db 0
%ifndef RESIDENT_HOST
    times 2048 db 0
dpmi_entry_stack_top:
%endif
