; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%ifdef RESIDENT_HOST
HOST_SCRATCH
%define DPMI_TRACE_COUNT 4
%else
HOST_REAL
%define DPMI_TRACE_COUNT 32
%endif
dpmi_install:
    mov ax, 1687h
    int 2fh
    test ax, ax
    jz .bad
    call dpmi_cpu_detect
    xor ax, ax
    xor bx, bx
    call monitor_init
    jc .bad
%ifndef RESIDENT_HOST
    mov bx, 80h
    mov ah, 48h
    int 21h
    jc .bad
    mov [dpmi_entry_segment], ax
%endif
%ifdef RESIDENT_HOST
    mov ax, 352fh
    int 21h
    mov [dpmi_old_mux], bx
    mov [dpmi_old_mux+2], es
    mov ax, 3567h
    int 21h
    mov [dpmi_old_ems], bx
    mov [dpmi_old_ems+2], es
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

; Some clients refuse the default 386 processor type.
dpmi_cpu_detect:
    pushad
    pushfd
    pop ecx
    mov edx, 40000h
    call .flag
    jz .done
    mov byte [dpmi_cpu], 4
    mov edx, 200000h
    call .flag
    jz .done
    xor eax, eax
    db 0fh, 0a2h
    test eax, eax
    jz .done
    mov eax, 1
    db 0fh, 0a2h
    mov al, ah
    and al, 0fh
    cmp al, 4
    jbe .done
    mov [dpmi_cpu], al
.done:
    popad
    ret
; ECX=original EFLAGS, EDX=bit. ZF=1 when the bit does not change.
.flag:
    mov eax, ecx
    xor eax, edx
    push eax
    popfd
    pushfd
    pop eax
    push ecx
    popfd
    xor eax, ecx
    test eax, edx
    ret
dpmi_remove:
    push ds
%ifndef RESIDENT_HOST
    xor ax, ax
    xchg ax, [dpmi_entry_segment]
    test ax, ax
    jz .stack_free
    mov es, ax
    mov ah, 49h
    int 21h
.stack_free:
%endif
    lds dx, [dpmi_old_mux]
    mov ax, 252fh
    int 21h
    pop ds
    ret
HOST_REAL
%ifdef RESIDENT_HOST
; EMS detection reads the device name at offset 0Ah of the INT 67h segment.
    align 16
dpmi_ems_base:
dpmi_old_ems dd 0
dpmi_ems_gateway dw 0
dpmi_hide_vcpi db 1
    times 0ah-($-dpmi_ems_base) db 0
dpmi_ems_name times 8 db 0
; The driver lists the mappable EMS pages over its own memory. A map call into
; one of them would page out uCDD's code, so it fails with error 8Bh.
EMS_GUARD_MAX equ 12
dpmi_ems_guard_count dw 0
dpmi_ems_guard_max dw EMS_GUARD_MAX
; Physical page number and segment of each page.
dpmi_ems_guard times EMS_GUARD_MAX*2 dw 0
dpmi_ems:
    cmp ah, 44h
    je .map_page
    cmp ah, 50h
    je .map_pages
    cmp ah, 55h
    je .map_call
    cmp ah, 56h
    je .map_call
    cmp ax, 0de00h
    jne .chain
    ; An extender in its own VCPI mode bypasses the port traps. Offer DPMI instead.
    cmp byte [cs:dpmi_hide_vcpi-dpmi_ems_base], 0
    je .chain
    ; Stepped aside, the driver offers no DPMI: VCPI stays visible.
    push ds
    mov ds, [cs:dpmi_ems_gateway-dpmi_ems_base]
    cmp byte [dpmi_dormant], 0
    pop ds
    jne .chain
    push bp
    mov bp, sp
    push bx
    mov bx, [cs:dpmi_ems_gateway-dpmi_ems_base]
    ; Keep VCPI available to the host gateway, including nested clients.
    cmp [ss:bp+4], bx
    jne .checked
    cmp word [ss:bp+2], monitor_init.vcpi_query_return
.checked:
    pop bx
    pop bp
    je .chain
    mov ah, 84h
    iret
.chain:
    jmp far [cs:dpmi_old_ems-dpmi_ems_base]
; AL: physical page number.
.map_page:
    push bx
    push dx
    movzx bx, al
    xor dl, dl
    call .guarded
    pop dx
    pop bx
    jc .refuse
    jmp .chain
; AL: 0 for page numbers, 1 for segments. DS:SI: CX pairs.
.map_pages:
    cmp al, 1
    ja .chain
    push dx
    mov dl, al
    call .list_guarded
    pop dx
    jc .refuse
    jmp .chain
; DS:SI: target address, pair count byte, pointer to the pairs.
.map_call:
    cmp al, 1
    ja .chain
    push cx
    push dx
    push si
    push ds
    mov dl, al
    movzx cx, byte [si+4]
    lds si, [si+5]
    call .list_guarded
    pop ds
    pop si
    pop dx
    pop cx
    jc .refuse
    jmp .chain
.refuse:
    mov ah, 8bh
    iret
; DS:SI: CX pairs of logical page and physical page. DL: mode. CF=1 for a guarded page.
.list_guarded:
    push bx
    push cx
    push si
    jcxz .list_free
.list_next:
    mov bx, [si+2]
    call .guarded
    jc .list_done
    add si, 4
    loop .list_next
.list_free:
    clc
.list_done:
    pop si
    pop cx
    pop bx
    ret
; BX: page number (DL=0) or segment (DL=1). CF=1 for a guarded page.
.guarded:
    push cx
    push si
    mov cx, [cs:dpmi_ems_guard_count-dpmi_ems_base]
    mov si, dpmi_ems_guard-dpmi_ems_base
    test dl, dl
    jz .guard_first
    add si, 2
.guard_first:
    jcxz .guard_free
.guard_next:
    cmp bx, [cs:si]
    je .guard_hit
    add si, 4
    loop .guard_next
.guard_free:
    clc
    jmp .guard_done
.guard_hit:
    stc
.guard_done:
    pop si
    pop cx
    ret
%endif
dpmi_mux:
    cmp ax, 1687h
    jne .chain
    cmp byte [cs:dpmi_dormant], 0
    jne .chain
    xor ax, ax
    mov bx, 1
    movzx cx, byte [cs:dpmi_cpu]
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
    ja .bad
%ifndef RESIDENT_HOST
    cmp byte [cs:dpmi_active], 0
    jne .bad
%endif
    pushf
    pushad
    push ds
    push es
    push fs
    push gs
%ifdef RESIDENT_HOST
    push ax
    mov ah, 51h
    int 21h
    mov [cs:dpmi_nested_psp], bx
    pop ax
    cmp byte [cs:dpmi_active], 0
    je .saved
    call dpmi_nested_save
    jnc .saved
    pop gs
    pop fs
    pop es
    pop ds
    popad
    popf
    jmp .bad
.saved:
%endif
    ; AX=0 starts a 16-bit client.
    mov byte [cs:dpmi_client16], 0
    test ax, ax
    jnz .bits_ready
    mov byte [cs:dpmi_client16], 1
.bits_ready:
    mov al, [cs:dpmi_client16]
    mov [cs:dpmi_own16], al
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
%ifdef RESIDENT_HOST
    mov dword [dpmi_physical_pending], 0
%endif
    call dpmi_ivt_snapshot
%ifdef RESIDENT_HOST
    mov ax, [dpmi_nested_psp]
%else
    mov ah, 51h
    int 21h
    mov ax, bx
%endif
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
    mov byte [dpmi_rm_call], 0
    mov byte [dpmi_raw_rm], 0
    mov byte [dpmi_active], 1
    mov byte [dpmi_exit_code], 1
    cli
%ifdef RESIDENT_HOST
    mov ax, [host_stack_segment]
    cmp byte [dpmi_nested_depth], 0
    je .stack_ready
    mov ax, [dpmi_bridge_real_segment]
    add ax, 128
    add ax, DPMI_XFER_PARAS
.stack_ready:
    mov ss, ax
    mov sp, HOST_STACK_BYTES
%else
    mov ax, [cs:dpmi_entry_segment]
    mov ss, ax
    mov sp, 2048
%endif
    sti
%ifdef RESIDENT_HOST
    pushf
    cli
%endif
    call monitor_run
%ifdef RESIDENT_HOST
    call dpmi_physical_handoff
    cmp byte [dpmi_nested_depth], 0
    je .complete_ready
%endif
    mov byte [dpmi_active], 0
%ifdef RESIDENT_HOST
.complete_ready:
    popf
    cmp byte [dpmi_nested_depth], 0
    je .free_stack
    cli
    mov dx, cs
    mov ss, dx
    mov sp, dpmi_nested_real_top
    sti
.free_stack:
    ; A child frees its blocks when the parent is back: DOS can call
    ; the parent's DOS/4GW INT 2Ah hook.
    cmp byte [dpmi_nested_depth], 0
    jne .exit
%endif
    call dpmi_bridge_real_free
    test ax, ax
    jz .exit
    mov byte [dpmi_exit_code], 1
.exit:
    mov es, [dpmi_psp]
    mov ax, [dpmi_environment]
    mov [es:2ch], ax
    mov al, [dpmi_exit_code]
%ifdef RESIDENT_HOST
    cmp byte [dpmi_nested_depth], 0
    je .terminate
    push word [dpmi_large_stack_segment]
    push word [dpmi_bridge_real_segment]
    call dpmi_nested_restore
    pop bx
    call .free_block
    pop bx
    call .free_block
.terminate:
    call dpmi_physical_complete
%endif
    mov ah, 4ch
    int 21h
%ifdef RESIDENT_HOST
; BX=a DOS block or 0. AX stays.
.free_block:
    test bx, bx
    jz .freed
    push ax
    mov es, bx
    mov ah, 49h
    int 21h
    pop ax
.freed:
    ret
%endif
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
%ifdef RESIDENT_HOST
    ; A command left an IRQ due: step the client so that the driver fires it
    ; some instructions later. Not with the virtual IF off or a TF in use.
    ; Steps that ended without the last INT 1 (the client loaded flags
    ; without TF) leave no count behind.
    cmp byte [ebp+dpmi_audio_steps], 0
    je .audio_idle
    cmp byte [ebp+dpmi_step_active], 0
    jne .audio_idle
    test word [esp+48], 100h
    jnz .audio_idle
    mov byte [ebp+dpmi_audio_steps], 0
.audio_idle:
    mov esi, [ebp+resident_audio_request]
    test esi, esi
    jz .audio_armed
    cmp dword [ebp+resident_due], 0
    je .audio_armed
    cmp byte [esi+15], 0
    je .audio_armed
    cmp byte [esi+14], 0
    je .audio_armed
    cmp byte [ebp+dpmi_audio_steps], 0
    jne .audio_armed
    cmp byte [ebp+dpmi_vif], 1
    jne .audio_armed
    cmp byte [ebp+dpmi_step_active], 0
    jne .audio_armed
    cmp byte [ebp+dpmi_sti_shadow], 0
    jne .audio_armed
    test dword [esp+48], 20100h
    jnz .audio_armed
    mov al, [esi+15]
    mov [ebp+dpmi_audio_steps], al
    mov byte [esi+15], 0
    or word [esp+48], 100h
    HOST_DIAG DIAG_INDEX_ARM_PM
.audio_armed:
%endif
    cmp byte [ebp+dpmi_step_active], 1
    jne .check_irq
    or word [esp+48], 300h
    DPMI_STEP_NORMAL
.check_irq:
    cmp byte [ebp+dpmi_sti_shadow], 0
    jne .shadow_arrival_now
    cmp byte [ebp+dpmi_callback_sti], 0
    je .shadow_arrival_now
    mov eax, [esp+40]
    cmp eax, [ebp+dpmi_callback_sti+4]
    jne .shadow_arrival_now
    mov ax, [esp+44]
    cmp ax, [ebp+dpmi_callback_sti+2]
    jne .shadow_arrival_now
    mov eax, [ebp+dpmi_callback_sti]
    mov [ebp+dpmi_sti_shadow], eax
    mov eax, [ebp+dpmi_callback_sti+4]
    mov [ebp+dpmi_sti_ip], eax
    mov byte [ebp+dpmi_callback_sti], 0
.shadow_arrival_now:
    mov ebx, esp
    call dpmi_sti_arrival
    cmp byte [ebp+dpmi_sti_shadow], 0
    je .shadow_done
    DPMI_STEP_NORMAL
    mov ebx, esp
    call dpmi_sti_arrival
    cmp byte [ebp+dpmi_sti_shadow], 0
    je .shadow_done
    or word [esp+48], 100h
    jmp .no_irq
.shadow_done:
    cmp byte [ebp+dpmi_vif], 1
    jne .armed_wait
    mov byte [ebp+dpmi_step_holdoff], 0
    test byte [esp+44], 3
    jz .no_irq
    call dpmi_hardware_room
    jc .no_irq
    cmp byte [ebp+dpmi_mouse_pending], 0
    je .irq_check
    call dpmi_top_level
    jc .irq_check
    mov ebx, esp
    jmp dpmi_mouse_deliver
.irq_check:
    call dpmi_pic_audio_allowed
    jc .pic_only
    cmp byte [ebp+dpmi_sti_sb_held], 0
    jne .audio_ready
%ifdef RESIDENT_HOST
    call resident_audio_take
    cmp ax, 1
    jne .pic_only
%else
    jmp .pic_only
%endif
.audio_ready:
%ifdef RESIDENT_HOST
    call resident_audio_deliver
    jnc .delivered
    ; A reset ended the held request: the handler must not run.
    mov byte [ebp+dpmi_sti_sb_held], 0
    jmp .pic_only
.delivered:
%endif
    movzx eax, byte [ebp+dpmi_guest_vector]
    mov edx, eax
    imul eax, 6
    lea esi, [ebp+mon_vectors+eax]
    cmp word [esi+4], 0
    jne .sb_inject
    mov byte [ebp+dpmi_sti_sb_held], 0
.real_irq:
    mov eax, edx
    lea edi, [ebp+mon_rm_regs]
    mov dword [edi+32], 2
    mov dword [edi+46], 0
    call mon_real_int
    jmp .shadow_done
.sb_inject:
    mov byte [ebp+dpmi_sti_sb_held], 0
%ifdef RESIDENT_HOST
    mov byte [ebp+dpmi_sb_next], 1
%endif
    mov ebx, esp
    jmp dpmi_deliver_hardware
.pic_only:
    call dpmi_pic_next
    jc .no_irq
    mov ecx, eax
    movzx edx, byte [ebp+mon_master]
    cmp eax, 8
    jb .irq_vector
    movzx edx, byte [ebp+mon_slave]
    sub edx, 8
.irq_vector:
    add eax, edx
    mov edx, eax
    imul eax, 6
    lea esi, [ebp+mon_vectors+eax]
    cmp word [esi+4], 0
    je .pic_reflect
%ifdef RESIDENT_HOST
    ; A disk IRQ during an INT 13h call goes to the BIOS, not to the client.
    mov ebx, 0c040h
    bt ebx, ecx
    jnc .pic_protected
    call dpmi_pic_disk_busy
    jz .pic_protected
%else
    jmp .pic_protected
%endif
.pic_reflect:
    mov [ebp+dpmi_reflect_vector], dl
    call dpmi_pic_reflect
    jmp .real_irq
.pic_protected:
    mov ebx, esp
    jmp dpmi_deliver_hardware
; The client runs with the virtual IF off and NT (dpmi_quiet_exit). A pending
; IRQ must not wait for a POPF: step to find where the client sets IF again.
.armed_wait:
    cmp byte [ebp+dpmi_step_active], 0
    jne .no_irq
    test byte [esp+44], 3
    jz .no_irq
    test byte [esp+50], 2
    jnz .no_irq
    call dpmi_top_level
    jc .no_irq
.armed_pending:
    movzx eax, word [ebp+dpmi_pic_mask]
    not eax
    and ax, [ebp+dpmi_pending_irqs]
    jnz .armed_step
    cmp byte [ebp+dpmi_sti_sb_held], 0
    jne .armed_step
%ifdef RESIDENT_HOST
    mov esi, [ebp+resident_audio_request]
    test esi, esi
    jz .no_irq
    cmp byte [esi], 0
    je .no_irq
%else
    jmp .no_irq
%endif
.armed_step:
    call dpmi_hardware_room
    jc .no_irq
    ; A POPF without stepping turns the virtual IF on at the next host entry
    ; (NT, see dpmi_quiet_entry). Stepping only shortens that wait.
    cmp byte [ebp+dpmi_step_holdoff], 0
    je .arm
    dec byte [ebp+dpmi_step_holdoff]
    jmp .no_irq
.arm:
    mov byte [ebp+dpmi_step_budget], DPMI_STEP_BUDGET
    mov byte [ebp+dpmi_step_active], 1
    ; Decode the instruction at the resume point: it can be the POPF.
    or word [esp+48], 300h
    DPMI_STEP_NORMAL
    cmp byte [ebp+dpmi_sti_shadow], 0
    jne .no_irq
    cmp byte [ebp+dpmi_vif], 1
    je .shadow_done
.no_irq:
%ifdef RESIDENT_HOST
    call resident_refill_schedule
%endif
    mov ebx, esp
    call dpmi_quiet_exit
    mov ax, [esp+44]
    call dpmi_debug_arm
    pop es
    pop ds
    popad
.restore_stack:
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
    call dpmi_debug_reset
    mov byte [ebp+dpmi_sti_shadow], 0
    mov byte [ebp+dpmi_callback_sti], 0
%ifdef RESIDENT_HOST
    call resident_audio_release
%endif
    mov byte [ebp+dpmi_sti_sb_held], 0
%ifdef RESIDENT_HOST
    mov byte [ebp+dpmi_sb_handler], 0
    mov byte [ebp+dpmi_sb_next], 0
    mov byte [ebp+dpmi_sb_resume], 0
    call resident_refill_reset
%endif
    xor eax, eax
    lea edi, [ebp+mon_vectors]
    mov ecx, 256*6/4
    rep stosd
    lea edi, [ebp+dpmi_exceptions]
    mov ecx, 32*6/4
    rep stosd
    mov byte [ebp+dpmi_exception_active], 0
%ifdef RESIDENT_HOST
    call dpmi_nested_inherit
    jc .descriptors_ready
%endif
    lea edi, [ebp+dpmi_callbacks]
    mov ecx, 16*20/4
    rep stosd
    lea edi, [ebp+dpmi_ldt]
    mov ecx, DPMI_LDT_COUNT*8/4
    rep stosd
    lea edi, [ebp+dpmi_used]
    mov ecx, DPMI_LDT_COUNT/4
    rep stosd
.descriptors_ready:
    mov byte [ebp+dpmi_vif], 1
    mov byte [ebp+dpmi_step_active], 0
    mov byte [ebp+dpmi_audio_steps], 0
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
    cmp byte [ebp+dpmi_client16], 0
    jne .stack_ready
    mov byte [ebp+dpmi_ldt+2*8+6], 40h
    mov byte [ebp+dpmi_ldt+3*8+6], 40h
.stack_ready:
    movzx eax, word [ebp+dpmi_psp]
    call dpmi_initial_descriptor
    mov word [ebp+dpmi_ldt+4*8], 0ffh
    movzx eax, word [ebp+dpmi_environment]
    test eax, eax
    jz .environment_ready
    mov byte [ebp+dpmi_used+5], 1
    call dpmi_initial_descriptor
.environment_ready:
    mov dword [ebp+dpmi_dos16_dta], 00800027h
    mov word [ebp+dpmi_dll_vector+4], 0
    jmp dpmi_enter_client

; Return AX=the ring-3 stub selector for the client's code size.
dpmi_stub_selector:
    mov ax, 3bh
    cmp byte [ebp+dpmi_client16], 0
    je .done
    mov ax, DPMI_STUB16
.done:
    ret

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
    call dpmi_bridge_update
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
    cld
    mov byte [ebp+dpmi_dos_via21], 0
    movzx eax, word [ebx+36]
    mov [ebp+dpmi_last_call], ax
%ifdef HOST_PROFILE
    HOST_COUNT dpmi, 0
%else
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
%endif
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
    cmp eax, 0ff00h
    je dpmi_vendor_ldt
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
    ; The host never pages memory out. Lock and discard calls have no effect.
    cmp eax, 0600h
    jb .paging_ready
    cmp eax, 0603h
    jbe mon_dpmi.success
    cmp eax, 0702h
    je mon_dpmi.success
    cmp eax, 0703h
    je mon_dpmi.success
.paging_ready:
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
    mov al, [ebp+dpmi_cpu]
    mov [ebx+32], al
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
    mov ax, [ebx]
    mov edx, [ebx+8]
    DPMI_OFFSET16 edx, dx
    mov ecx, 50
    mov edi, 1
    call dpmi_buffer
    jc dpmi_error
    mov edi, eax
    movzx ecx, word [ebx+32]
    cmp ecx, 2048
    ja dpmi_bad_value
    call dpmi_mouse_wide_regs
    mov ax, [ebx+36]
    cmp al, 0
    jne .copy_stack
    cmp byte [ebx+24], 21h
    jne .copy_stack
    cmp byte [edi+29], 4ch
    je dpmi_bad_value
.copy_stack:
    push dword [edi+46]
    call dpmi_large_stack_prepare
    jc .prepare_error
    push eax
    call dpmi_stack_copy
    jc .stack_error
    ; The resident reads this: 1 in a real-mode call with no host depth, 2 with depth or
    ; with a bridged IRQ, callback, exception or raw switch on top.
    movzx eax, byte [ebp+dpmi_rm_call]
    push eax
    mov al, 2
    cmp byte [ebp+dpmi_callback_active], 0
    jne .rm_mark
    cmp dword [ebp+dpmi_locked_depth], 0
    jne .rm_mark
    cmp dword [ebp+dpmi_stack_depth], 0
    jne .rm_mark
    cmp dword [ebp+dpmi_bridge_depth], 0
    jne .rm_mark
    dec al
.rm_mark:
    mov [ebp+dpmi_rm_call], al
    mov ax, [ebx+36]
    cmp al, 0
    jne .far_call
.interrupt:
    movzx eax, byte [ebx+24]
    call dpmi_pic_simulated
    jc .irq_call
    call mon_real_int_copy
    jmp .stack_done
.irq_call:
    call mon_real_irq_copy
    jmp .stack_done
.far_call:
    call dpmi_pic_real_chain
    call mon_real_far_copy
.stack_done:
    pop eax
    mov [ebp+dpmi_rm_call], al
    call dpmi_large_stack_restore
    jmp mon_dpmi.success
.stack_error:
    call dpmi_large_stack_restore
    jmp dpmi_error
.prepare_error:
    add esp, 4
    jmp dpmi_error

; DOS/4GW passes INT 33h to real mode with 16-bit BX. The SVGA mouse driver
; of Big Red Adventure takes the cursor segment from the upper half of EBX.
; EBX=client frame, EDI=real-mode register structure.
dpmi_mouse_wide_regs:
    cmp byte [ebp+dpmi_mouse_wide], 0
    je .done
    mov byte [ebp+dpmi_mouse_wide], 0
    cmp byte [ebx+36], 0
    jne .far
    cmp byte [ebx+24], 33h
    je .target
    ret
.far:
    mov eax, [33h*4]
    cmp eax, [edi+42]
    jne .done
.target:
    mov ax, [edi+28]
    cmp ax, [ebp+dpmi_mouse_ax]
    jne .done
    mov eax, [edi+16]
    cmp eax, 0ffffh
    ja .done
    cmp ax, [ebp+dpmi_mouse_ebx]
    jne .done
    mov eax, [ebp+dpmi_mouse_ebx]
    mov [edi+16], eax
.done:
    ret

; EBX=client frame, EDI=real-mode register structure, ECX=word count.
dpmi_stack_copy:
    shl ecx, 1
    jz .done
    push edi
    push ecx
    mov ax, [ebx+56]
    call dpmi_descriptor
    jc .selector
    mov edx, [ebx+52]
    test byte [esi+6], 40h
    jnz .wide_stack
    movzx edx, dx
.wide_stack:
    mov ax, [ebx+56]
    xor edi, edi
    call dpmi_buffer
    jc .error
    mov esi, eax
    mov edi, [esp+4]
    movzx eax, word [edi+48]
    test eax, eax
    jz .host_stack
    shl eax, 4
    movzx edx, word [edi+46]
    cmp edx, ecx
    jae .custom_ready
    test edx, edx
    jnz .value
    mov edx, 10000h
.custom_ready:
    sub edx, ecx
    mov [edi+46], dx
    jmp .copy
.host_stack:
    movzx eax, word [ebp+mon_return+16]
    shl eax, 4
    movzx edx, word [ebp+mon_return+12]
    cmp edx, ecx
    jb .value
    sub edx, ecx
    mov [ebp+mon_return+12], dx
.copy:
    mov edi, eax
    add edi, edx
    rep movsb
    mov ecx, [esp]
    mov edi, [esp+4]
    add esp, 8
.done:
    clc
    ret
.error:
    mov edi, [esp+4]
    add esp, 8
    stc
    ret
.selector:
    mov eax, 8022h
    jmp .error
.value:
    mov eax, 8021h
    jmp .error

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
    cld
    mov ebx, esp
    call dpmi_record_segments
    call dpmi_locked_capture
    call dpmi_quiet_entry
    call dpmi_sti_arrival
    call dpmi_tf_entry
    ; Watcom DLL loaders keep the PSP selector and GS in vector E9h for the
    ; DLL start code. Under a DPMI host, DOS/4GW replaces that vector.
    cmp byte [ebp+dpmi_client16], 0
    jne .vector_ready
    mov ax, [ebx+36]
    cmp ax, 25e9h
    je .dll_set
    cmp ax, 35e9h
    jne .vector_ready
    cmp word [ebp+dpmi_dll_vector+4], 0
    jne .dll_get
.vector_ready:
    cmp word [ebp+mon_vectors+21h*6+4], 0
    je .host
    lea esi, [ebp+mon_vectors+21h*6]
    jmp dpmi_deliver_interrupt
.dll_set:
    mov ax, [ebx+4]
    mov [ebp+dpmi_dll_vector+4], ax
    mov eax, [ebx+28]
    mov [ebp+dpmi_dll_vector], eax
    jmp mon_dpmi.done
.dll_get:
    mov ax, [ebp+dpmi_dll_vector+4]
    mov [ebx], ax
    mov eax, [ebp+dpmi_dll_vector]
    mov [ebx+24], eax
    jmp mon_dpmi.done
.host:
    mov byte [ebp+dpmi_reflect_vector], 21h
    mov ax, [ebx+36]
    mov [ebp+dpmi_last_dos], ax
    HOST_COUNT dos, 0
    cmp byte [esp+37], 4ch
    jne dpmi_dos_translate
    mov al, [esp+36]
    mov [ebp+dpmi_exit_code], al
    mov word [ebp+mon_status], 0
%ifdef RESIDENT_HOST
    jmp dpmi_finish.clean
%else
    jmp dpmi_finish
%endif
.unsupported:
    mov word [esp+36], 1
    or byte [esp+48], 1
    pop es
    pop ds
    popad
    MON_IRETD

; mon_status is 0 after INT 21h 4Ch, the exception number plus 1 after an
; unhandled exception, or one of these after an abort.
DPMI_ABORT_CALLBACK equ 0f1h
DPMI_ABORT_STACK equ 0f2h
DPMI_ABORT_RETURN equ 0f3h
%ifdef RESIDENT_HOST
%if mon_fault_cs-mon_status != 14
%error The abort record copy needs the mon_status to mon_fault_cs layout.
%endif
%endif

dpmi_finish:
%ifdef RESIDENT_HOST
    ; Keep the abort for UCDD -status (diagnostic block, driver side). An
    ; INT 21h 4Ch exit enters at .clean.
    mov edi, [ebp+resident_counters]
    test edi, edi
    jz .clean
    lea esi, [ebp+mon_status]
    add edi, DIAG_HOST_ABORT
    push 4
    pop ecx
    cld
    rep movsd
    ; mon_eip is relative to the host. The client's EIP is the raw one. An
    ; abort has no exception, so those fields are zero.
    mov eax, [ebp+dpmi_fault_ip]
    cmp word [edi-16], 0f0h
    jb .fields_valid
    xor eax, eax
    mov [edi-14], eax
    mov [edi-6], eax
    mov [edi-2], ax
.fields_valid:
    mov [edi-10], eax
    mov al, [ebp+dpmi_exit_code]
    stosb
    inc word [edi+1]
.clean:
%endif
    mov byte [ebp+dpmi_sti_shadow], 0
    mov byte [ebp+dpmi_callback_sti], 0
%ifdef RESIDENT_HOST
    call resident_audio_release
    ; Give the disk IRQ bits of the real mask back to the game.
    mov byte [ebp+dpmi_pic_open], 1
    call dpmi_pic_sync
    mov byte [ebp+dpmi_pic_open], 0
%endif
    mov byte [ebp+dpmi_sti_sb_held], 0
%ifdef RESIDENT_HOST
    mov byte [ebp+dpmi_sb_handler], 0
    mov byte [ebp+dpmi_sb_next], 0
    mov byte [ebp+dpmi_sb_resume], 0
    call resident_refill_reset
%endif
    mov byte [ebp+dpmi_callback_active], 0
    mov byte [ebp+dpmi_exception_active], 0
%ifdef RESIDENT_HOST
    mov al, [ebp+dpmi_nested_depth]
    cmp [ebp+dpmi_mouse_depth], al
    jb .mouse_kept
%endif
    mov word [ebp+dpmi_mouse_vector+4], 0
    mov byte [ebp+dpmi_mouse_pending], 0
.mouse_kept:
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
%include "host/dos16.asm"
%include "host/vectors.asm"
%include "host/switch.asm"
%include "host/callback.asm"
%include "host/bridge.asm"
%include "host/realstack.asm"
%include "host/interrupts.asm"
%include "host/debug.asm"
%include "host/locked.asm"
%include "host/pic.asm"
%include "host/cleanup.asm"

HOST_REAL
dpmi_old_mux dd 0
%ifndef RESIDENT_HOST
dpmi_entry_segment dw 0
%endif
dpmi_audio_irq db 0ffh
dpmi_guest_irq db 5
dpmi_guest_vector db 0dh
dpmi_pending_irqs dd 0
%ifdef RESIDENT_HOST
dpmi_physical_pending dd 0
%endif
dpmi_sti_sb_held db 0
dpmi_active db 0
dpmi_audio_pm_handler db 0
dpmi_virtual_entry dw dpmi_bridge_virtual
dpmi_real_eoi db 0
dpmi_real_priority db 0ffh
%ifdef RESIDENT_HOST
dpmi_pending_entry dw dpmi_real_pending
dpmi_refill_flag dw resident_refill_busy
%else
dpmi_pending_entry dw 0
dpmi_refill_flag dw 0
%endif
dpmi_rm_call db 0
%if dpmi_rm_call-dpmi_active != 10 || dpmi_audio_pm_handler-dpmi_active != 1 || dpmi_virtual_entry-dpmi_active != 2 || dpmi_real_eoi-dpmi_active != 4 || dpmi_real_priority-dpmi_active != 5 || dpmi_pending_entry-dpmi_active != 6 || dpmi_refill_flag-dpmi_active != 8
    %error Invalid resident IRQ state layout
%endif
dpmi_cpu db 3
dpmi_psp dw 0
; The driver sets this byte while it has stepped aside (audio/standby.asm):
; no DPMI is offered and VCPI stays visible, so a protected-mode game runs
; under its own extender.
dpmi_dormant db 0
; 1 while the client's SB IRQ handler runs: a new SB IRQ stays a request
; (World Rally Fever's mixer is not reentrant).
dpmi_sb_handler db 0
%if dpmi_psp-dpmi_active != 12 || dpmi_dormant-dpmi_active != 14 || dpmi_sb_handler-dpmi_active != 15
    %error Invalid resident IRQ state layout
%endif
; The saved dpmi_rm_call of a callback, an exception and a raw switch.
dpmi_cb_rm db 0
dpmi_exc_rm db 0
dpmi_raw_rm db 0
dpmi_environment dw 0
dpmi_client16 db 0
; The code size of the current client. dpmi_client16 has the size of the
; client whose code runs: a parent's handler can run while its child is current.
dpmi_own16 db 0
dpmi_callback_flip db 0
dpmi_raw_flip db 0
dpmi_parent_mode db 0
dpmi_nested_entered db 0
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
%ifdef HOST_PROFILE
align 4
host_profile:
    db 'uCDprof',1
    dw host_profile_end-host_profile,12,4,8
host_profile_step dd 0
host_profile_decode dd 0
host_profile_gp dd 0
host_profile_cli dd 0
host_profile_dpmi dd 0
host_profile_dos dd 0
host_profile_bridge dd 0
host_profile_allocate dd 0
host_profile_page dd 0
host_profile_flush dd 0
host_profile_irqentry dd 0
host_profile_refill dd 0
host_profile_samples times 4*2 dd 0
host_profile_end:
%else
dpmi_trace_pos db 0
dpmi_trace times DPMI_TRACE_COUNT dw 0
dpmi_trace_args times DPMI_TRACE_COUNT*24 db 0
dpmi_trace_end:
%endif
dpmi_dll_vector times 6 db 0
dpmi_fault_ip dd 0
dpmi_fault_regs times 16 dd 0
%ifndef RESIDENT_HOST
dpmi_ldt times DPMI_LDT_COUNT*8 db 0
dpmi_used times DPMI_LDT_COUNT db 0
%endif
