; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%define SPLIT_HOST 1
%macro HOST_REAL 0
    section .gateway
    bits 16
%endmacro
%macro HOST_PROTECTED 0
    section .protected
    bits 32
%endmacro
%macro HOST_SCRATCH 0
    section .scratch
    bits 16
%endmacro

section .gateway start=0
section .protected follows=.gateway align=16
section .scratch follows=.protected align=16
HOST_REAL
cpu 386
org 0
%define HOST_DPMI 1
%define VIRTUAL_IRQ 1
%define WSS_INPUT 1
%define RESIDENT_HOST 1
%define MDM_SUPPORT 1
host_gateway_start:
    jmp resident_host_init
    db 'uCDH'
HOST_SCRATCH
resident_host_init:
    push ds
    push es
    pushad
    mov [cs:dpmi_audio_irq], al
    push ax
    push si
    push di
    push cx
    mov si, [ds:bp+4]
    mov al, [si]
    mov [cs:dpmi_guest_irq], al
    add al, 8
    mov [cs:dpmi_guest_vector], al
    mov si, [ds:bp+6]
    push cs
    pop es
    mov di, resident_ports
    mov cx, resident_port_count-2
    rep movsw
    pop cx
    pop di
    pop si
    pop ax
    mov [cs:mon_vcpi_flags_slot], ah
    mov [cs:resident_traps], cx
    mov [cs:resident_traps+2], ds
    movzx eax, bp
    xor ecx, ecx
    mov cx, ds
    shl ecx, 4
    add eax, ecx
    mov [cs:resident_game_vector], eax
    push edx
    cmp dword [ds:bp+8], 31464443h
    jne .no_refill
    movzx edx, word [ds:bp+14]
    add edx, ecx
    mov [cs:resident_refill_pending], edx
    mov dx, [ds:bp+12]
    mov [cs:resident_refill], dx
    mov [cs:resident_refill+2], ds
.no_refill:
    pop edx
    mov [cs:resident_port], bx
    mov [cs:resident_port+2], ds
    mov [cs:resident_take], dx
    mov [cs:resident_take+2], ds
    movzx eax, si
    movzx ecx, word [cs:resident_take+2]
    shl ecx, 4
    add eax, ecx
    mov [cs:resident_wss_event], eax
    push cs
    pop ds
    call host_storage_allocate
    jc .bad
    call dpmi_install
    jc .release_bad
    mov eax, [mon_base]
    add eax, resident_io
    mov [mon_callback], eax
    mov ax, resident_pending
    call monitor_irq_callback
    mov si, resident_ports
    mov di, resident_port_count
.port:
    lodsw
    mov dx, ax
    mov cx, 1
    call monitor_trap
    dec di
    jnz .port
    call host_storage_commit
    jc .release_bad
    push ds
    mov ds, [host_gateway_segment]
    mov dx, dpmi_mux
    mov ax, 252fh
    int 21h
    pop ds
    popad
    pop es
    pop ds
    mov word [ds:di], dpmi_active
    mov ax, [cs:host_gateway_segment]
    mov [ds:di+2], ax
    mov ax, [cs:host_stack_segment]
    mov [ds:di+4], ax
    cmp word [cs:resident_refill+2], 0
    je .refill_ready
    mov byte [ds:di+6], 1
.refill_ready:
    clc
    retf
.release_bad:
    call host_storage_release
.bad:
    popad
    pop es
    pop ds
    stc
    retf

HOST_REAL
resident_refill dd 0
resident_refill_pending dd 0
resident_refill_busy db 0
resident_port dd 0
resident_take dd 0
resident_wss_event dd 0
resident_traps dd 0
resident_game_vector dd 0
resident_ports:
%include "audio/ports.inc"
    dw 0a0h,0a1h
resident_port_count equ ($-resident_ports)/2

HOST_SCRATCH
HOST_LINEAR_PAGE equ 0e0000000h
HOST_LINEAR_PDE equ (HOST_LINEAR_PAGE >> 22)
HOST_XMS_KIB equ ((host_protected_end-host_protected_start+21501)/1024)
HOST_STACK_BYTES equ 2048
HOST_STACK_PARAS equ (HOST_STACK_BYTES/16)
HOST_GATEWAY_MIN_PARAS equ ((host_gateway_end-host_gateway_start+15)/16)
HOST_GATEWAY_MAX_PARAS equ ((host_gateway_end-host_gateway_start+4095+15)/16)

host_storage_allocate:
    mov word [host_gateway_segment], 0
    mov word [host_stack_segment], 0
    mov word [host_xms_handle], 0
    mov byte [host_xms_locked], 0
    call host_dos_save
    jc .plain
    mov ax, 5803h
    mov bx, 1
    int 21h
    jc .plain
    mov ax, 5801h
    mov bx, 40h
    int 21h
    jc .restore_plain
    call host_pair_allocate
    pushf
    call host_dos_restore
    popf
    jnc .gateway_ready
    mov ax, 5803h
    xor bx, bx
    int 21h
    jc .plain
    mov ax, 5801h
    xor bx, bx
    int 21h
    jc .restore_plain
    call host_pair_allocate
    pushf
    call host_dos_restore
    popf
    jc .bad
    jmp .gateway_ready
.restore_plain:
    call host_dos_restore
.plain:
    call host_pair_allocate
    jc .bad
.gateway_ready:
    mov ax, 4300h
    int 2fh
    cmp al, 80h
    jne .release_bad
    mov ax, 4310h
    int 2fh
    mov [host_xms], bx
    mov [host_xms+2], es
    mov ah, 9
    mov dx, HOST_XMS_KIB
    call far [host_xms]
    cmp ax, 1
    jne .release_bad
    mov [host_xms_handle], dx
    mov ah, 0ch
    call far [host_xms]
    cmp ax, 1
    jne .release_bad
    mov byte [host_xms_locked], 1
    mov [host_xms_physical], bx
    mov [host_xms_physical+2], dx
    mov eax, [host_xms_physical]
    neg eax
    and eax, 4095
    mov [host_xms_pages_offset], eax
    add eax, [host_xms_physical]
    mov [host_xms_pages_physical], eax
    mov eax, [host_xms_pages_offset]
    add eax, 12288
    mov [host_xms_tail_offset], eax
    movzx edx, word [host_prefix_bytes]
    mov eax, host_protected_end
    sub eax, edx
    jbe .release_bad
    mov [host_xms_tail_bytes], eax
    clc
    ret
.release_bad:
    call host_storage_release
.bad:
    stc
    ret

host_pair_allocate:
    call host_stack_allocate
    jc .bad
    call host_gateway_allocate
    jnc .done
    call host_stack_release
.bad:
    stc
.done:
    ret

host_stack_allocate:
    mov bx, HOST_STACK_PARAS
    mov ah, 48h
    int 21h
    jc .bad
    mov [host_stack_segment], ax
    clc
.bad:
    ret

host_stack_release:
    mov ax, [host_stack_segment]
    test ax, ax
    jz .done
    mov es, ax
    mov ah, 49h
    int 21h
    mov word [host_stack_segment], 0
.done:
    ret

host_dos_save:
    mov ax, 5800h
    int 21h
    jc .bad
    mov [host_dos_strategy], ax
    mov ax, 5802h
    int 21h
    jc .bad
    mov [host_dos_umb], al
    clc
    ret
.bad:
    stc
    ret

host_dos_restore:
    mov bx, [host_dos_strategy]
    mov ax, 5801h
    int 21h
    movzx bx, byte [host_dos_umb]
    mov ax, 5803h
    int 21h
    ret

host_gateway_allocate:
    mov bx, HOST_GATEWAY_MIN_PARAS
    mov ah, 48h
    int 21h
    jc .bad
    mov [host_gateway_segment], ax
    call host_gateway_measure
    mov es, [host_gateway_segment]
    mov bx, [host_prefix_bytes]
    shr bx, 4
    mov ah, 4ah
    int 21h
    jnc .done
    mov es, [host_gateway_segment]
    mov ah, 49h
    int 21h
    mov word [host_gateway_segment], 0
    mov bx, HOST_GATEWAY_MAX_PARAS
    mov ah, 48h
    int 21h
    jc .bad
    mov [host_gateway_segment], ax
    call host_gateway_measure
    mov es, [host_gateway_segment]
    mov bx, [host_prefix_bytes]
    shr bx, 4
    mov ah, 4ah
    int 21h
    jc .free_bad
.done:
    clc
    ret
.free_bad:
    mov es, [host_gateway_segment]
    mov ah, 49h
    int 21h
    mov word [host_gateway_segment], 0
.bad:
    stc
    ret

host_gateway_measure:
    mov ax, [host_gateway_segment]
    movzx eax, ax
    shl eax, 4
    mov [host_gateway_physical], eax
    mov [mon_real_base], eax
    and eax, 4095
    add eax, HOST_LINEAR_PAGE
    mov [mon_base], eax
    mov edx, eax
    add edx, host_gateway_end+4095
    and edx, 0fffff000h
    sub edx, eax
    mov [host_prefix_bytes], dx
    ret

host_storage_commit:
    mov eax, [mon_page_linear]
    shr eax, 4
    mov es, ax
    mov edx, [host_xms_pages_physical]
    mov [mon_switch], edx
    mov eax, edx
    add eax, 4096
    or eax, 7
    mov [es:0], eax
    add eax, 4096
    mov [es:HOST_LINEAR_PDE*4], eax
    or edx, 3
    mov [es:4092], edx
    xor si, si
    mov eax, 8192
    mov edi, [host_xms_pages_offset]
    call host_xms_copy
    jc .bad
    mov eax, [mon_page_linear]
    shr eax, 4
    mov es, ax
    xor di, di
    xor eax, eax
    mov cx, 1024
    rep stosd
    mov eax, [mon_base]
    mov edx, eax
    shr eax, 12
    and eax, 3ffh
    shl ax, 2
    mov di, ax
    and edx, 4095
    movzx eax, word [host_prefix_bytes]
    add eax, edx
    shr eax, 12
    mov bp, ax
    mov ebx, [host_gateway_physical]
    and ebx, 0fffff000h
.gateway_map:
    mov ecx, ebx
    shr ecx, 12
    push ebx
    push di
    push bp
    push es
    mov ax, 0de06h
    int 67h
    pop es
    pop bp
    pop di
    pop ebx
    test ah, ah
    jnz .bad
    or edx, 7
    mov [es:di], edx
    add ebx, 4096
    add di, 4
    dec bp
    jnz .gateway_map
    mov eax, [mon_base]
    movzx ebx, word [host_prefix_bytes]
    add eax, ebx
    shr eax, 12
    and eax, 3ffh
    shl ax, 2
    mov di, ax
    mov edx, [host_xms_physical]
    add edx, [host_xms_tail_offset]
    mov eax, [host_xms_tail_bytes]
    add eax, 4095
    shr eax, 12
    mov cx, ax
.map:
    mov eax, edx
    or eax, 7
    mov [es:di], eax
    add edx, 4096
    add di, 4
    loop .map
    push cs
    pop es
    mov si, [host_prefix_bytes]
    mov eax, [host_xms_tail_bytes]
    mov edi, [host_xms_tail_offset]
    call host_xms_copy
    jc .bad
    mov eax, [mon_page_linear]
    shr eax, 4
    mov es, ax
    xor si, si
    mov eax, 4096
    mov edi, [host_xms_pages_offset]
    add edi, 8192
    call host_xms_copy
    jc .bad
    push ds
    push cs
    pop ds
    mov es, [host_gateway_segment]
    xor si, si
    xor di, di
    mov cx, [host_prefix_bytes]
    shr cx, 1
    rep movsw
    pop ds
    clc
    ret
.bad:
    stc
    ret

; ES:SI is the conventional source. EAX is the length. EDI is the XMS offset.
host_xms_copy:
    mov [host_xms_move], eax
    mov word [host_xms_move+4], 0
    mov [host_xms_move+6], si
    mov ax, es
    mov [host_xms_move+8], ax
    mov ax, [host_xms_handle]
    mov [host_xms_move+10], ax
    mov [host_xms_move+12], edi
    push si
    mov si, host_xms_move
    mov ah, 0bh
    call far [host_xms]
    pop si
    cmp ax, 1
    jne .bad
    clc
    ret
.bad:
    stc
    ret

host_storage_release:
    cmp byte [host_xms_locked], 0
    je .free_xms
    mov dx, [host_xms_handle]
    mov ah, 0dh
    call far [host_xms]
    mov byte [host_xms_locked], 0
.free_xms:
    mov dx, [host_xms_handle]
    test dx, dx
    jz .free_gateway
    mov ah, 0ah
    call far [host_xms]
    mov word [host_xms_handle], 0
.free_gateway:
    mov ax, [host_gateway_segment]
    test ax, ax
    jz .done
    mov es, ax
    mov ah, 49h
    int 21h
    mov word [host_gateway_segment], 0
.done:
    call host_stack_release
    ret

host_gateway_segment dw 0
host_prefix_bytes dw 0
host_gateway_physical dd 0
host_dos_strategy dw 0
host_dos_umb db 0
host_xms dd 0
host_xms_handle dw 0
host_xms_locked db 0
align 4
host_xms_physical dd 0
host_xms_tail_offset dd 0
host_xms_tail_bytes dd 0
host_xms_pages_offset dd 0
host_xms_pages_physical dd 0
host_xms_move times 16 db 0

HOST_REAL
host_stack_segment dw 0

HOST_PROTECTED
host_protected_start:
resident_refill_schedule:
    pushad
    cmp byte [ebp+dpmi_active], 1
    jne .done
    cmp byte [ebp+dpmi_vif], 1
    jne .done
    cmp byte [ebp+resident_refill_busy], 0
    jne .done
    cmp byte [ebp+dpmi_callback_active], 0
    jne .done
    cmp byte [ebp+dpmi_exception_active], 0
    jne .done
    cmp dword [ebp+dpmi_locked_depth], 0
    jne .done
    cmp dword [ebp+dpmi_stack_depth], 0
    jne .done
    cmp dword [ebp+dpmi_bridge_depth], 0
    jne .done
    test byte [esp+32+4+44], 3
    jz .done
    test dword [esp+32+4+48], 20000h
    jnz .done
    mov esi, [ebp+resident_refill_pending]
    test esi, esi
    jz .done
    cmp byte [esi], 1
    jne .done
    mov byte [ebp+resident_refill_busy], 1
    sub esp, 52
    mov edi, esp
    xor eax, eax
    mov ecx, 13
    cld
    rep stosd
    mov edi, esp
    mov word [edi+32], 202h
    mov eax, [ebp+resident_refill]
    mov [edi+42], eax
    mov al, 1
    call mon_real_far
    add esp, 52
    mov byte [ebp+resident_refill_busy], 0
.done:
    popad
    ret

resident_refill_reset:
    mov byte [ebp+resident_refill_busy], 0
    mov eax, [ebp+resident_refill_pending]
    test eax, eax
    jz .done
    mov byte [eax], 0
.done:
    ret

resident_pending:
    call dpmi_hardware_room
    jc .none
    mov esi, [ebp+resident_wss_event]
    movzx eax, word [esi]
    cmp eax, 16
    jae .sb
    mov word [esi], 0ffffh
    bts [ebp+dpmi_pending_irqs], eax
.sb:
    call dpmi_pic_audio_allowed
    jc .none
    cmp byte [ebp+dpmi_vif], 1
    jne .none
    test byte [esp+4+52], 3
    jz .none
    lea edi, [ebp+mon_rm_regs]
    mov dword [edi+46], 0
    mov word [edi+32], 2
    mov eax, [ebp+resident_take]
    mov [edi+42], eax
    mov al, 1
    call mon_real_far
    cmp word [edi+28], 1
    jne .none
    movzx eax, byte [ebp+dpmi_guest_vector]
    inc eax
    ret
.none:
    xor eax, eax
    ret
resident_io:
    cmp cl, 1
    jne .bad
    lea edi, [ebp+mon_rm_regs]
    mov [edi+28], eax
    mov [edi+20], edx
    movzx ecx, ch
    shl ecx, 2
    mov [edi+24], ecx
    mov dword [edi+46], 0
    mov word [edi+32], 2
    mov eax, [ebp+resident_port]
    mov [edi+42], eax
    mov al, 1
    call mon_real_far
    mov eax, [edi+28]
    clc
    ret
.bad:
    stc
    ret

%include "host/monitor.asm"

HOST_REAL
align 16
host_gateway_end:
HOST_PROTECTED
align 16
host_protected_end:
HOST_SCRATCH
host_image_end:
