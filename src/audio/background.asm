; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%ifdef OWN_HOST
CD_REFILL_URGENT equ CD_READ_BYTES*2
%endif

cd_timer:
    pushf
    call far [cs:cd_old_timer]
    pushad
    push ds
    push es
    push fs
    push gs
    push cs
    pop ds
    cli
    cmp byte [busy], 0
    jne .done
    cmp byte [cd_bios_busy], 0
    jne .done
    cmp byte [cd_started], 1
    jne .done
    cmp byte [cd_error], 0
    jne .done
    cmp dword [cd_remaining], 0
    je .done
    les bx, [cd_indos]
    cmp word [es:bx-1], 0
    jne .done
    mov eax, [cd_produced]
    sub eax, [cd_consumed]
    cmp eax, CD_QUEUE_BYTES-65536
    ja .done
%ifdef OWN_HOST
    cmp byte [own_host_refill], 1
    jne .synchronous
    les bx, [own_host_active]
    cmp byte [es:bx], 1
    jne .synchronous
    mov byte [cd_refill_pending], 1
    jmp .done
.synchronous:
%endif
    mov byte [busy], 1
    mov [cd_call_ss], ss
    mov [cd_call_sp], sp
%ifdef EXTERNAL_CD_BUFFERS
    mov ax, [cd_work_segment]
%else
    mov ax, cs
%endif
    mov ss, ax
    mov sp, cd_stack_top
    mov byte [cd_background_reads], 32
    sti
    cld
    call cd_foreground
    cli
    mov byte [cd_background_reads], 0
    mov ss, [cd_call_ss]
    mov sp, [cd_call_sp]
    mov byte [busy], 0
.done:
    pop gs
    pop fs
    pop es
    pop ds
    popad
    iret

%ifdef OWN_HOST
cd_deferred_refill:
    pushf
    pushad
    push ds
    push es
    push fs
    push gs
    push cs
    pop ds
    cli
    cmp byte [cd_refill_pending], 0
    je .done
    cmp byte [busy], 0
    jne .done
    cmp byte [cd_bios_busy], 0
    jne .done
    cmp byte [cd_started], 1
    jne .cancel
    cmp byte [cd_error], 0
    jne .cancel
    cmp dword [cd_remaining], 0
    je .cancel
    les bx, [cd_indos]
    cmp word [es:bx-1], 0
    jne .done
    mov eax, [cd_produced]
    sub eax, [cd_consumed]
    cmp eax, CD_QUEUE_BYTES-65536
    ja .cancel
    mov byte [cd_refill_pending], 0
    mov byte [busy], 1
    mov [cd_call_ss], ss
    mov [cd_call_sp], sp
%ifdef EXTERNAL_CD_BUFFERS
    mov ax, [cd_work_segment]
%else
    mov ax, cs
%endif
    mov ss, ax
    mov sp, cd_stack_top
    mov byte [cd_background_reads], 1
    sti
    cld
    call cd_foreground
    cli
    mov byte [cd_background_reads], 0
    mov ss, [cd_call_ss]
    mov sp, [cd_call_sp]
    mov byte [busy], 0
    jmp .done
.cancel:
    mov byte [cd_refill_pending], 0
.done:
    pop gs
    pop fs
    pop es
    pop ds
    popad
    popf
    retf
cd_refill_pending db 0
%endif

cd_bios:
    pushf
    inc byte [cs:cd_bios_busy]
    popf
%ifdef RESIDENT_AUDIO
    call cd_cache_bios
%else
    pushf
    call far [cs:cd_old_bios]
%endif
    pushf
    dec byte [cs:cd_bios_busy]
    popf
    retf 2

cd_background_remove:
%ifdef OWN_HOST
    mov byte [cd_refill_pending], 0
%endif
    cmp byte [cd_background_set], 0
    je .done
    push ds
    lds dx, [cd_old_timer]
    mov ax, 2508h
    int 21h
    push cs
    pop ds
    lds dx, [cd_old_bios]
    mov ax, 2513h
    int 21h
    pop ds
    mov byte [cd_background_set], 0
.done:
    ret

cd_old_timer dd 0
cd_old_bios dd 0
cd_bios_busy db 0
cd_background_set db 0
cd_background_reads db 0

%ifdef RESIDENT_AUDIO
%include "audio/disk_cache.asm"
%endif
