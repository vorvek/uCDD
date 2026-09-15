; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

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
    mov byte [cd_background_reads], 8
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

cd_bios:
    pushf
    inc byte [cs:cd_bios_busy]
    popf
    pushf
    call far [cs:cd_old_bios]
    pushf
    dec byte [cs:cd_bios_busy]
    popf
    retf 2

cd_background_remove:
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
