; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%include "audio/diag.inc"

bits 16
host_old_mux dd 0
host_api_entry dd 0
host_services dd 0
host_old_gate dd 0
host_old_io dd 0
host_io_bitmap dd 0
host_callback dd 0
host_installed db 0
host_backend db 0
host_port_count dw 0
host_ports times 64 dw 0
host_port_old times 64 db 0
host_irq_slot dd 0
host_irq_previous dd 0
host_irq_root dd 0
host_irq_dispatch_previous dd 0
host_irq_table times 256 dd 0

host_mux:
    cmp ax, 1684h
    jne .chain
    cmp bx, 4354h
    jne .chain
    les di, [cs:host_api_entry]
    xor al, al
    iret
.chain:
    jmp far [cs:host_old_mux]

bits 32
host_gate:
    push ebx
    call .base
.base:
    pop ebx
    sub ebx, .base
    mov eax, [ebp+28]
    cmp ah, 1ah
    jne .chain
    movzx edx, word [ebp+20]
    and byte [ebp+48], 0feh
    cmp al, 0
    je .input
    cmp al, 1
    je .output
    cmp al, 6
    je .get
    cmp al, 7
    je .set
    cmp al, 9
    je .trap
    cmp al, 10
    je .untrap
    cmp al, 11
    je .remove_host
.error:
    or byte [ebp+48], 1
.done:
    mov eax, [ebx+host_services]
    pop ebx
    jmp dword [eax+12]
.chain:
    mov eax, [ebx+host_old_gate]
    pop ebx
    jmp eax
.input:
    in al, dx
    mov [ebp+16], al
    jmp .done
.remove_host:
    cmp word [ebx+host_port_count], 0
    jne .error
    cmp dword [ebx+host_callback], 0
    jne .error
    call host_irq_remove
    jc .error
    mov esi, [ebx+host_services]
    mov esi, [esi+48]
    mov eax, [ebx+host_old_io]
    mov [esi], eax
    mov esi, [ebx+host_gate_slot]
    mov eax, [ebx+host_old_gate]
    mov [esi], eax
    jmp .done
.output:
    mov al, [ebp+16]
    out dx, al
    jmp .done
.get:
    mov eax, [ebx+host_callback]
    mov [ebp], ax
    shr eax, 16
    mov [ebp+60], ax
    jmp .done
.set:
    movzx eax, word [ebp+60]
    shl eax, 16
    mov ax, [ebp]
    mov [ebx+host_callback], eax
    jmp .done
.trap:
    movzx ecx, word [ebx+host_port_count]
    cmp ecx, 64
    jae .error
    xor esi, esi
.find:
    cmp esi, ecx
    jae .add
    cmp dx, [ebx+host_ports+esi*2]
    je .error
    inc esi
    jmp .find
.add:
    mov [ebx+host_ports+ecx*2], dx
    mov esi, [ebx+host_io_bitmap]
    bts [esi], edx
    setc byte [ebx+host_port_old+ecx]
    inc word [ebx+host_port_count]
    jmp .done
.untrap:
    movzx ecx, word [ebx+host_port_count]
    xor esi, esi
.search:
    cmp esi, ecx
    jae .error
    cmp dx, [ebx+host_ports+esi*2]
    je .remove
    inc esi
    jmp .search
.remove:
    cmp byte [ebx+host_port_old+esi], 0
    jne .compact
    mov edi, [ebx+host_io_bitmap]
    btr [edi], edx
.compact:
    dec ecx
    mov ax, [ebx+host_ports+ecx*2]
    mov [ebx+host_ports+esi*2], ax
    mov al, [ebx+host_port_old+ecx]
    mov [ebx+host_port_old+esi], al
    mov [ebx+host_port_count], cx
    jmp .done

host_io:
    push ebx
    push esi
    call .base
.base:
    pop ebx
    sub ebx, .base
    movzx esi, word [ebx+host_port_count]
.find:
    test esi, esi
    jz .chain
    dec esi
    cmp dx, [ebx+host_ports+esi*2]
    jne .find
    cmp dword [ebx+host_callback], 0
    je .chain
    ; Stepping ends without its last INT 1 when the guest loads flags without
    ; TF (POPF, IRET). Put the guest INT 1 vector back. An interrupt handler
    ; also runs without TF, so not while the event is still due.
    lea esi, [ebx+virtual_pic_request]
    cmp byte [esi+16], 0
    je .unstepped
    cmp byte [esi+14], 0
    jne .unstepped
    test byte [ebp+49], 1
    jnz .unstepped
    mov byte [esi+16], 0
    cmp byte [esi+17], 0
    je .unstepped
    mov byte [esi+17], 0
    call host_step_ours
    cmp [4], eax
    jne .unstepped
    mov eax, [esi+18]
    mov [4], eax
.unstepped:
    push ecx
    push edx
    push dword [ebp+48]
    push dword [ebp+24]
    push dword [ebp+20]
    mov ch, [ebp+49]
    and ch, 2
    mov [ebp+24], cx
    mov [ebp+20], dx
    and byte [ebp+49], 0fch
    mov esi, [ebx+host_services]
    call dword [esi+16]
    movzx ecx, word [ebx+host_callback+2]
    movzx edx, word [ebx+host_callback]
    call dword [esi+8]
    call dword [esi+24]
    call dword [esi+28]
    mov eax, [ebp+28]
    pop dword [ebp+20]
    pop dword [ebp+24]
    pop dword [ebp+48]
    pop edx
    pop ecx
    ; Step the guest after a command that left an interrupt due: the INT 1
    ; handler counts the instructions. Not when the guest traces. A guest
    ; INT 1 vector is replaced while the steps run and put back at the end.
    push eax
    lea esi, [ebx+virtual_pic_request]
    cmp byte [esi+15], 0
    je .armed
    cmp byte [esi+14], 0
    je .armed
    test byte [ebp+49], 1
    jnz .armed
    call host_step_ours
    cmp [4], eax
    je .vector_ready
    push dword [4]
    pop dword [esi+18]
    mov [4], eax
    mov byte [esi+17], 1
.vector_ready:
    mov al, [esi+15]
    mov [esi+16], al
    mov byte [esi+15], 0
    or byte [ebp+49], 1
%ifdef UCDD_DIAG
    inc word [ebx+diag_due_arm_v86]
%endif
.armed:
    pop eax
    call host_io_irq
    pop esi
    pop ebx
    ret
.chain:
    pop esi
    push dword [ebx+host_old_io]
    mov ebx, [esp+4]
    ret 4

host_step_ours:
    mov eax, ebx
    shr eax, 4
    shl eax, 16
    mov ax, irq_step
    ret

host_io_irq:
    pushad
    test byte [ebp+49], 2
    jz .done
    cmp byte [ebx+virtual_pic_request], 0
    je .done
    cmp byte [ebx+virtual_pic_service], 0
    jne .done
    cmp byte [ebx+virtual_pic_taken], 0
    jne .done
    mov al, [ebx+guest_irq_bit]
    test [ebx+virtual_pic_mask], al
    jnz .done
    movzx esi, word [ebx+own_host_active+2]
    test esi, esi
    jz .done
    shl esi, 4
    movzx eax, word [ebx+own_host_active]
    add esi, eax
    cmp byte [esi], 0
    je .priority
    cmp byte [esi+1], 0
    jne .done
    mov al, [esi+4]
    test al, [ebx+guest_irq_priority]
    jnz .done
.priority:
    mov al, 0bh
    out 20h, al
    in al, 20h
    mov ah, al
    mov al, [ebx+physical_pic_read]
    out 20h, al
    test ah, [ebx+guest_irq_priority]
    jnz .done
    movzx esi, byte [ebx+guest_vector]
    mov esi, [esi*4]
    mov al, [ebx+guest_irq]
    cmp al, [ebx+sb_irq]
    jne .vector
    mov eax, ebx
    shr eax, 4
    shl eax, 16
    mov ax, audio_irq
    cmp esi, eax
    jne .vector
    mov esi, [ebx+sb_game_vector]
.vector:
    mov byte [ebx+virtual_pic_request], 0
    mov al, [ebx+guest_irq_bit]
    mov [ebx+virtual_pic_service], al
    mov al, [ebx+pic_mask_late]
    or [ebx+virtual_pic_mask], al
    mov byte [ebx+pic_mask_late], 0
%ifdef UCDD_DIAG
    inc word [ebx+diag_taken]
%endif
    movzx ecx, word [ebp+56]
    shl ecx, 4
    movzx edx, word [ebp+52]
    mov eax, [ebp+48]
    sub dx, 2
    mov [ecx+edx], ax
    and ah, 0fch
    mov [ebp+48], eax
    mov ax, [ebp+44]
    sub dx, 2
    mov [ecx+edx], ax
    mov ax, [ebp+40]
    sub dx, 2
    mov [ecx+edx], ax
    mov [ebp+52], dx
    movzx eax, si
    mov [ebp+40], eax
    shr esi, 16
    mov [ebp+44], esi
.done:
    popad
    ret

; Jemm calls this before it reflects a hardware interrupt through the IVT.
    dd host_irq_previous
host_irq_dispatch:
    pushad
    call .base
.base:
    pop ebx
    sub ebx, .base
    cmp byte [ebx+sb_running], 1
    jne .chain
    mov cl, [ebx+sb_irq]
    mov al, 0bh
    out 20h, al
    in al, 20h
    mov ah, al
    mov al, [ebx+physical_pic_read]
    out 20h, al
    mov al, 1
    shl al, cl
    test ah, al
    jz .chain
    movzx ecx, word [ebp+56]
    shl ecx, 4
    movzx edx, word [ebp+52]
    mov eax, [ebp+48]
    sub dx, 2
    mov [ecx+edx], ax
    and ah, 0fch
    mov [ebp+48], eax
    mov ax, [ebp+44]
    sub dx, 2
    mov [ecx+edx], ax
    mov ax, [ebp+40]
    sub dx, 2
    mov [ecx+edx], ax
    mov [ebp+52], dx
    mov dword [ebp+40], audio_irq
    mov eax, ebx
    shr eax, 4
    mov [ebp+44], eax
    popad
    clc
    ret
.chain:
    popad
    stc
    ret

host_irq_call:
    jmp ecx

host_irq_remove:
    mov edx, [ebx+host_irq_slot]
    test edx, edx
    jz .ok
    lea eax, [ebx+host_irq_dispatch]
    cmp [edx], eax
    jne .bad
    mov esi, [ebx+host_irq_root]
    movzx ecx, byte [ebx+sb_irq]
    mov eax, [esi]
    lea ecx, [eax+ecx*4+8*4]
    cmp ecx, edx
    jne .bad
    lea eax, [ebx+host_irq_table]
    cmp [esi], eax
    jne .restore
    lea ecx, [ebx+host_irq_call]
    cmp [esi+4], ecx
    jne .bad
    xor ecx, ecx
.check:
    lea edi, [eax+ecx*4]
    cmp edi, edx
    je .next
    cmp dword [edi], 0
    jne .bad
.next:
    inc ecx
    cmp ecx, 256
    jb .check
    mov dword [esi], 0
    mov eax, [ebx+host_irq_dispatch_previous]
    mov [esi+4], eax
.restore:
    mov eax, [ebx+host_irq_previous]
    mov [edx], eax
    mov dword [ebx+host_irq_slot], 0
.ok:
    clc
    ret
.bad:
    stc
    ret

bits 16
host_gate_slot dd 0
irq_step_old dd 0

; INT 1 while the guest runs the instructions of a due interrupt.
irq_step:
    cmp byte [cs:irq_step_left], 0
    jne .counting
.foreign:
    ; Steps that ended early with the guest vector still replaced.
    cmp byte [cs:irq_step_swapped], 0
    je .foreign_old
    push bp
    mov bp, sp
    and byte [bp+7], 0feh
    call irq_step_restore
    pop bp
    iret
.foreign_old:
    ; A TF image that the guest saved while we stepped: no one owns it now.
    push ax
    mov ax, [cs:irq_step_old+2]
    cmp ax, 100h
    jbe .stale
    cmp ax, 0f000h
    jb .chain
.stale:
    push bp
    mov bp, sp
    and byte [bp+9], 0feh
    pop bp
    pop ax
    iret
.chain:
    pop ax
    jmp far [cs:irq_step_old]
.counting:
    push bp
    mov bp, sp
    cmp byte [cs:irq_due], 0
    je .stop
    dec byte [cs:irq_step_left]
    jz .due
    pop bp
    iret
.stop:
    mov byte [cs:irq_step_left], 0
    and byte [bp+7], 0feh
    call irq_step_restore
    pop bp
    iret
.due:
    and byte [bp+7], 0feh
    call irq_step_restore
    cmp byte [cs:audio_irq_busy], 0
    jne .leave
    cmp byte [cs:callback_depth], 0
    jne .leave
    push ds
    push es
    pushad
    mov bl, [bp+7]
    push cs
    pop ds
    cld
    mov [callback_ss], ss
    mov [callback_sp], sp
    mov ax, cs
    mov ss, ax
    mov sp, callback_stack_top
    inc byte [callback_depth]
    DIAG_INC diag_due_step
    call virtual_irq_due_fire
%ifdef OWN_HOST
    test bl, 2
    jz .fired
    cmp word [own_host_active+2], 0
    je .fired
    les di, [own_host_active]
    cmp byte [es:di], 0
    je .deliver
    cmp byte [es:di+1], 0
    jne .fired
.deliver:
    call sb_real_irq
%endif
.fired:
    dec byte [callback_depth]
    mov ss, [callback_ss]
    mov sp, [callback_sp]
    popad
    pop es
    pop ds
    cmp byte [cs:sb_real_pending], 0
    je .leave
    mov byte [cs:sb_real_pending], 0
    pop bp
    jmp far [cs:sb_real_vector]
.leave:
    pop bp
    iret

; Put back the guest INT 1 vector that the steps replaced. All registers stay.
irq_step_restore:
    cmp byte [cs:irq_step_swapped], 0
    je .done
    mov byte [cs:irq_step_swapped], 0
    push ds
    push ax
    xor ax, ax
    mov ds, ax
    cmp word [4], irq_step
    jne .kept
    mov ax, cs
    cmp [6], ax
    jne .kept
    push word [cs:irq_step_guest]
    pop word [4]
    push word [cs:irq_step_guest+2]
    pop word [6]
.kept:
    pop ax
    pop ds
.done:
    ret

host_remove:
    cmp byte [host_installed], 0
    je .ok
    mov ax, 1a0bh
    call far [host_api_entry]
    jc .failed
    call irq_step_restore
    xor ax, ax
    mov es, ax
    cmp word [es:4], irq_step
    jne .step_kept
    mov ax, cs
    cmp [es:6], ax
    jne .step_kept
    mov eax, [irq_step_old]
    mov [es:4], eax
.step_kept:
    push ds
    lds dx, [host_old_mux]
    mov ax, 252fh
    int 21h
    pop ds
    mov byte [host_installed], 0
    mov byte [host_backend], 0
.ok:
    clc
    ret
.failed:
    stc
    ret
