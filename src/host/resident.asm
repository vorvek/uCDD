; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%include "host/profile.inc"

; Offsets in the driver's diagnostic block part that this host writes.
DIAG_HOST_REFUSED equ 0
DIAG_HOST_ABORT equ 20
; The word index of the arm counter for the audio steps.
DIAG_INDEX_ARM_PM equ 41
; The IRQ gate counters follow the abort record: counter indices 20 to 27.

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
section .pages follows=.scratch nobits align=16
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
    ; The IVT holds the mixer's handler for the physical IRQ now.
    push bx
    push edx
    push es
    movzx bx, al
    add bx, 8
    cmp al, 8
    jb .mixer_vector
    add bx, 70h-10h
.mixer_vector:
    shl bx, 2
    xor dx, dx
    mov es, dx
    mov edx, [es:bx]
    mov [cs:resident_mixer_vector], edx
    pop es
    pop edx
    pop bx
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
    mov cx, resident_port_count-5
    rep movsw
    pop cx
    pop di
    pop si
    pop ax
    test ah, 2
    jz .vcpi_hidden
    mov byte [cs:dpmi_hide_vcpi], 0
.vcpi_hidden:
    test ah, 4
    jz .slot_ready
    mov byte [cs:resident_irq_slot], 1
.slot_ready:
    call host_v86_prepare
    movzx eax, bp
    xor ecx, ecx
    mov cx, ds
    shl ecx, 4
    add eax, ecx
    mov [cs:resident_game_vector], eax
    push edx
    cmp dword [ds:bp+8], 35464443h
    jne .version4
    movzx edx, word [ds:bp+24]
    add edx, ecx
    mov [cs:resident_counters], edx
    movzx edx, word [ds:bp+26]
    add edx, ecx
    mov [cs:resident_bios_busy], edx
    mov dx, [ds:bp+28]
    mov [cs:resident_due], dx
    mov [cs:resident_due+2], ds
    ; The disk IRQ mask at +30. Never the timer, keyboard, cascade, RTC,
    ; coprocessor, or the sound card's own IRQ.
    push bx
    push cx
    mov bx, [ds:bp+30]
    mov dx, [ds:bx]
    and dx, 0def8h
    movzx cx, byte [cs:dpmi_audio_irq]
    cmp cx, 15
    ja .disk_mask
    btr dx, cx
.disk_mask:
    mov [cs:dpmi_disk_mask], dx
    pop cx
    pop bx
    jmp .version3
.version4:
    cmp dword [ds:bp+8], 34464443h
    je .version3
    cmp dword [ds:bp+8], 33464443h
    jne .version2
.version3:
    movzx edx, word [ds:bp+18]
    add edx, ecx
    mov [cs:resident_refill_clock], edx
    jmp .audio_request
.version2:
    cmp dword [ds:bp+8], 32464443h
    jne .version1
.audio_request:
    movzx edx, word [ds:bp+16]
    add edx, ecx
    mov [cs:resident_audio_request], edx
    jmp .refill
.version1:
    cmp dword [ds:bp+8], 31464443h
    jne .no_refill
.refill:
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
    cmp byte [cs:dpmi_hide_vcpi], 0
    je .vcpi_ready
    mov [dpmi_ems_gateway], ds
    push ds
    pop es
    mov di, dpmi_ems_name
    push ds
    mov ds, [dpmi_old_ems+2]
    mov si, 0ah
    mov cx, 8
    cld
    rep movsb
    pop ds
    push ds
    mov ax, ds
    add ax, (dpmi_ems_base-host_gateway_start)/16
    mov ds, ax
    mov dx, dpmi_ems-dpmi_ems_base
    mov ax, 2567h
    int 21h
    pop ds
.vcpi_ready:
    pop ds
    call host_v86_install
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
resident_irq_slot db 0
resident_mixer_vector dd 0
resident_port dd 0
resident_take dd 0
resident_due dd 0
resident_wss_event dd 0
resident_game_vector dd 0
; The driver's diagnostic block that the host writes (CDF5).
resident_counters dd 0
; The driver's cd_bios_busy byte: 1 while it reads the disc image through INT 13h.
resident_bios_busy dd 0
resident_ports:
%define PORT_MIXER_LABEL resident_mixer_ports
%include "audio/ports.inc"
%undef PORT_MIXER_LABEL
    dw 0a0h,0a1h,03dah,40h,43h
resident_port_count equ ($-resident_ports)/2

HOST_SCRATCH
HOST_LINEAR_PAGE equ 0e0000000h
HOST_LINEAR_PDE equ (HOST_LINEAR_PAGE >> 22)
HOST_XMS_KIB equ ((host_ldt_end-host_protected_start+21501)/1024)
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
    jc .conventional
    mov ax, 5801h
    mov bx, 40h
    int 21h
    jc .conventional
    call host_gateway_allocate
    pushf
    call host_dos_restore
    popf
    jnc .gateway_ready
.conventional:
    ; Without UMB support 5803h fails; the last-fit strategy still applies.
    mov ax, 5803h
    xor bx, bx
    int 21h
    mov ax, 5801h
    mov bx, 2
    int 21h
    jc .restore_plain
    call host_gateway_allocate
    pushf
    call host_dos_restore
    popf
    jc .bad
    jmp .gateway_ready
.restore_plain:
    call host_dos_restore
.plain:
    call host_gateway_allocate
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

host_dos_save:
    mov ax, 5800h
    int 21h
    jc .bad
    mov [host_dos_strategy], ax
    mov ax, 5802h
    int 21h
    jnc .link
    xor ax, ax
.link:
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

; One block holds the gateway and, in its last 128 paragraphs, the host stack.
host_gateway_allocate:
    mov bx, HOST_GATEWAY_MAX_PARAS+HOST_STACK_PARAS
.try:
    mov si, bx
    mov ah, 48h
    int 21h
    jnc .got
    ; Take the largest block when it still holds the gateway.
    cmp si, HOST_GATEWAY_MAX_PARAS+HOST_STACK_PARAS
    jne .bad
    cmp bx, HOST_GATEWAY_MIN_PARAS+HOST_STACK_PARAS
    jae .try
.bad:
    stc
    ret
.got:
    mov [host_gateway_segment], ax
    call host_gateway_measure
    mov dx, [host_prefix_bytes]
    shr dx, 4
    add dx, HOST_STACK_PARAS
    cmp si, dx
    jb .free_bad
    mov ax, [host_gateway_segment]
    add ax, si
    sub ax, HOST_STACK_PARAS
    mov [host_stack_segment], ax
    clc
    ret
.free_bad:
    mov es, [host_gateway_segment]
    mov ah, 49h
    int 21h
    mov word [host_gateway_segment], 0
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
    add eax, host_ldt_end-host_protected_end+4095
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
    mov word [host_stack_segment], 0
.done:
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
    test byte [esp+32+4+44], 3
    jz resident_refill_check.done
    test dword [esp+32+4+48], 20000h
    jnz resident_refill_check.done
    jmp resident_refill_check
; A real-mode call returned to the host. A client that stays in real-mode
; calls gets no IRQ in protected mode, so the refill runs here.
resident_refill_callback:
    pushad
resident_refill_check:
    xor ecx, ecx
    cmp byte [ebp+dpmi_sti_shadow], 0
    jne .refuse0
    cmp byte [ebp+dpmi_active], 1
    jne .refuse1
    cmp byte [ebp+dpmi_vif], 1
    jne .refuse2
    cmp byte [ebp+resident_refill_busy], 0
    jne .refuse3
    cmp byte [ebp+dpmi_callback_active], 0
    jne .refuse4
    cmp byte [ebp+dpmi_exception_active], 0
    jne .refuse5
    cmp dword [ebp+dpmi_locked_depth], 0
    jne .refuse6
    cmp dword [ebp+dpmi_stack_depth], 0
    jne .refuse6
    cmp dword [ebp+dpmi_bridge_depth], 0
    jne .refuse6
    jmp .clock
; ECX counts one INC for each label from the entry to .refuse0. The count
; is the gate in the host area of the diagnostic block. Only a pending refill
; counts.
.refuse9:
    inc ecx
.refuse8:
    inc ecx
.refuse7:
    inc ecx
.refuse6:
    inc ecx
.refuse5:
    inc ecx
.refuse4:
    inc ecx
.refuse3:
    inc ecx
.refuse2:
    inc ecx
.refuse1:
    inc ecx
.refuse0:
    mov esi, [ebp+resident_refill_pending]
    test esi, esi
    jz .done
    cmp byte [esi], 0
    je .done
    mov edi, [ebp+resident_counters]
    test edi, edi
    jz .done
    inc word [edi+ecx*2+DIAG_HOST_REFUSED]
    jmp .done
.clock:
    ; Give the foreground mixer time after a retrace.
    movzx edx, byte [ebp+resident_vga_ready]
    mov edi, [ebp+resident_refill_clock]
    test edi, edi
    jz .hint_ready
    cmp edx, 1
    jne .hint_waiting
    mov eax, [edi]
    mov [ebp+resident_vga_clock], eax
    mov byte [ebp+resident_vga_ready], 2
    jmp .refuse7
.hint_waiting:
    cmp edx, 2
    jne .hint_ready
    mov eax, [edi]
    sub eax, [ebp+resident_vga_clock]
    cmp eax, 128
    jb .refuse7
    ; The checks come once per output period. With 256-frame periods a
    ; window that ends at 192 frames is missed (Earthworm Jim title).
    xor edx, edx
    cmp eax, 384
    seta dl
    xor dl, 1
.hint_ready:
    mov byte [ebp+resident_vga_ready], 0
    mov esi, [ebp+resident_refill_pending]
    test esi, esi
    jz .done
    cmp byte [esi], 0
    je .done
    mov edi, [ebp+resident_refill_clock]
    test edi, edi
    jz .refill_due
    mov eax, [edi]
    sub eax, [ebp+resident_refill_last]
    cmp eax, 128
    jb .refuse8
.refill_due:
    cmp edx, 1
    je .window
    ; The client can stop the BIOS timer.
    test edi, edi
    jz .bios_wait
    cmp byte [esi], 2
    jne .queue_wait
    mov eax, [edi]
    sub eax, [ebp+resident_refill_last]
    cmp eax, 512
    jae .window
.queue_wait:
    mov eax, [edi]
    sub eax, [ebp+resident_vga_clock]
    cmp eax, 4096
    jb .refuse9
    jmp .window
.bios_wait:
    mov eax, [46ch]
    sub eax, [ebp+resident_vga_tick]
    cmp eax, 2
    jb .refuse9
.window:
    mov byte [ebp+resident_refill_busy], 1
    HOST_COUNT refill, 0
    ; From mon_resume this call nests in a finished real-mode call whose
    ; caller still reads its registers (resident_audio_take). Keep them.
    sub esp, 52
    lea esi, [ebp+mon_rm_regs]
    mov edi, esp
    mov ecx, 50
    cld
    rep movsb
    sub esp, 52
    mov edi, esp
    xor eax, eax
    mov ecx, 13
    rep stosd
    mov edi, esp
    mov word [edi+32], 202h
    mov eax, [ebp+resident_refill]
    mov [edi+42], eax
    mov al, 1
    call mon_real_far
    add esp, 52
    mov esi, esp
    lea edi, [ebp+mon_rm_regs]
    mov ecx, 50
    rep movsb
    add esp, 52
    mov esi, [ebp+resident_refill_clock]
    test esi, esi
    jz .refill_finished
    mov eax, [esi]
    mov [ebp+resident_refill_last], eax
.refill_finished:
    mov byte [ebp+resident_refill_busy], 0
.done:
    popad
    ret

resident_refill_reset:
    mov eax, [ebp+resident_refill_clock]
    test eax, eax
    jz .clock_reset
    mov eax, [eax]
.clock_reset:
    sub eax, 128
    mov [ebp+resident_refill_last], eax
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
    cmp byte [ebp+dpmi_sti_shadow], 0
    je .sb_now
    cmp byte [ebp+dpmi_sti_sb_held], 0
    jne .none
    call resident_audio_take
    cmp ax, 1
    jne .none
    mov byte [ebp+dpmi_sti_sb_held], 1
    jmp .none
.sb_now:
    call dpmi_pic_audio_allowed
    jc .none
    cmp byte [ebp+dpmi_vif], 1
    jne .none
    test byte [esp+4+52], 3
    jz .none
    call resident_audio_take
    cmp ax, 1
    jne .none
    movzx eax, byte [ebp+dpmi_guest_vector]
    inc eax
    ret
.none:
    xor eax, eax
    ret
resident_audio_request dd 0
; The taken SB IRQ is delivered: it moves from request to in-service.
; CF=1: nothing was taken, a reset ended it.
resident_audio_deliver:
    push eax
    mov esi, [ebp+resident_audio_request]
    test esi, esi
    jz .done
    mov al, [esi+11]
    test al, al
    jz .none
    mov byte [esi+11], 0
    mov byte [esi], 0
    mov [esi+1], al
.done:
    clc
    pop eax
    ret
.none:
    HOST_DIAG 25
    stc
    pop eax
    ret

; A held take goes back to a request when its client ends.
resident_audio_release:
    cmp byte [ebp+dpmi_sti_sb_held], 0
    je .done
    mov esi, [ebp+resident_audio_request]
    test esi, esi
    jz .done
    mov byte [esi+11], 0
.done:
    ret
resident_refill_clock dd 0
resident_refill_last dd 0
; CL=index of the counter in the host area of the diagnostic block.
resident_diag:
    pushfd
    push edi
    mov edi, [ebp+resident_counters]
    test edi, edi
    jz .done
    movzx ecx, cl
    inc word [edi+ecx*2+DIAG_HOST_REFUSED]
.done:
    pop edi
    popfd
    ret
resident_audio_take:
    mov esi, [ebp+resident_audio_request]
    test esi, esi
    jz .take
    cmp byte [esi], 0
    je .none
    cmp byte [esi+11], 0
    jne .held
.take:
    call dpmi_hardware_room
    jnc .room
    cmp byte [ebp+resident_refill_busy], 0
    jne .refill
    HOST_DIAG 21
    jmp .none
.refill:
    HOST_DIAG 20
    jmp .none
.room:
    mov eax, [ebp+resident_take]
    call resident_audio_far
    movzx eax, word [edi+28]
    ret
.held:
    HOST_DIAG 24
.none:
    xor eax, eax
    ret
; The driver fires its due IRQ event after the client ran enough steps.
; CF=1: the real-mode call has no room, the event stays due.
resident_audio_due:
    cmp dword [ebp+resident_due], 0
    je .none
    call dpmi_hardware_room
    jc .none
    mov eax, [ebp+resident_due]
    call resident_audio_far
    clc
    ret
.none:
    stc
    ret
; EAX=far address in the driver. EDI points to the real-mode registers.
resident_audio_far:
    lea edi, [ebp+mon_rm_regs]
    mov dword [edi+46], 0
    mov word [edi+32], 2
    mov [edi+42], eax
    mov al, 1
    jmp mon_real_far
resident_vga_pending db 0
resident_pit_reads db 0
resident_vga_previous db 0
resident_vga_ready db 0
resident_vga_tick dd 0
resident_vga_clock dd 0
resident_io:
    cmp cl, 1
    je .narrow
    cmp dx, 43h
    ja .wide_vga
    cmp dx, 40h
    jae .wide_pit
    cmp dx, 3dh
    jb .regular
    push edx
    movzx edi, cl
    add edx, edi
    cmp edx, 40h
    pop edx
    jbe .regular
.wide_pit:
    test ch, ch
    jz .physical_read
    mov byte [ebp+resident_pit_reads], 0
    jmp .vga_write
.wide_vga:
    cmp dx, 3dah
    je .vga
    ja .regular
    cmp dx, 3d7h
    jb .regular
    push edx
    movzx edi, cl
    add edx, edi
    cmp edx, 3dah
    pop edx
    jbe .regular
    test ch, ch
    jnz .vga_write
.physical_read:
    cmp cl, 2
    je .physical_word
    in eax, dx
    clc
    ret
.physical_word:
    in ax, dx
    clc
    ret
.narrow:
    cmp dx, 40h
    je .pit
    cmp dx, 43h
    je .pit
    jmp .vga
.pit:
    cmp cl, 1
    jne .regular
    test ch, ch
    jz .pit_read
    out dx, al
    mov byte [ebp+resident_pit_reads], 0
    cmp dx, 43h
    jne .pit_done
    test al, al
    jnz .pit_done
    mov byte [ebp+resident_pit_reads], 2
.pit_done:
    clc
    ret
.pit_read:
    in al, dx
    cmp dx, 40h
    jne .pit_done
    cmp byte [ebp+resident_pit_reads], 0
    je .pit_done
    dec byte [ebp+resident_pit_reads]
    jnz .pit_done
    cmp byte [ebp+resident_vga_pending], 0
    je .pit_done
    mov byte [ebp+resident_vga_pending], 0
    mov byte [ebp+resident_vga_ready], 1
    push eax
    mov eax, [46ch]
    mov [ebp+resident_vga_tick], eax
    pop eax
    jmp .pit_done
.vga:
    cmp dx, 03dah
    jne .regular
    test ch, ch
    jnz .vga_write
    cmp cl, 1
    je .vga_read_byte
    cmp cl, 2
    je .vga_read_word
    in eax, dx
    jmp .vga_sample
.vga_read_word:
    in ax, dx
    jmp .vga_sample
.vga_read_byte:
    in al, dx
.vga_sample:
    push eax
    push edx
    and al, 8
    cmp al, [ebp+resident_vga_previous]
    je .vga_return
    mov [ebp+resident_vga_previous], al
    test al, al
    jz .vga_return
    mov byte [ebp+resident_vga_pending], 1
.vga_return:
    pop edx
    pop eax
    clc
    ret
.vga_write:
    cmp cl, 1
    je .vga_write_byte
    cmp cl, 2
    je .vga_write_word
    out dx, eax
    clc
    ret
.vga_write_word:
    out dx, ax
    clc
    ret
.vga_write_byte:
    out dx, al
    clc
    ret
.regular:
    cmp cl, 1
    je .callback
    ; Word input and output at the mixer ports go to the audio callback.
    cmp cl, 2
    jne .split
    cmp dx, [ebp+resident_mixer_ports]
    je .callback
.split:
    ; Other wide access: one byte at a time, as on the ISA bus.
    push ebx
    push edx
    push esi
    push eax
    mov bl, ch
    mov bh, cl
    movzx esi, cl
.split_byte:
    bt [ebp+mon_bitmap], edx
    jc .split_trapped
    mov al, [esp]
    test bl, bl
    jz .split_input
    out dx, al
    jmp .split_next
.split_input:
    in al, dx
    jmp .split_store
.split_trapped:
    push edx
    push esi
    mov al, [esp+8]
    mov cl, 1
    mov ch, bl
    call resident_io
    pop esi
    pop edx
    jc .split_bad
.split_store:
    test bl, bl
    jnz .split_next
    mov [esp], al
.split_next:
    ror dword [esp], 8
    inc edx
    dec esi
    jnz .split_byte
    cmp bh, 4
    je .split_done
    ror dword [esp], 16
.split_done:
    clc
    ; CF is set on the jump from a trapped byte.
.split_bad:
    pop eax
    pop esi
    pop edx
    pop ebx
    ret
.callback:
    lea edi, [ebp+mon_rm_regs]
    mov [edi+28], eax
    mov [edi+20], edx
    movzx eax, cl
    dec eax
    shl eax, 3
    movzx ecx, ch
    shl ecx, 2
    or ecx, eax
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

%include "host/v86.asm"
%include "host/monitor.asm"
%include "host/handoff.asm"

HOST_REAL
dpmi_sti_shadow db 0
dpmi_sti_tf db 0
dpmi_sti_cs dw 0
dpmi_sti_ip dd 0
align 16
host_gateway_end:
HOST_PROTECTED
align 16
host_protected_end:
; The LDT pages follow the image in XMS. Each client start clears them.
dpmi_ldt equ host_protected_end
dpmi_used equ dpmi_ldt+DPMI_LDT_COUNT*8
; The host stacks follow the LDT and need no image bytes.
dpmi_parent_map equ dpmi_used+DPMI_LDT_COUNT
mon_kernel_stack_top equ dpmi_parent_map+DPMI_LDT_COUNT/8+2048
dpmi_callback_kernel_top equ mon_kernel_stack_top+1920
host_ldt_end equ dpmi_callback_kernel_top
HOST_SCRATCH
host_image_end:
