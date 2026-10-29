; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; Install-only code. With the internal host, the driver puts it after the
; resident part and gives the memory back when the activation ends.

audio_cleanup:
    mov byte [audio_detach_failed], 0
    call cd_background_remove
%ifdef OWN_HOST
    cmp word [sb_old_dos+2], 0
    je .dos_restored
    push ds
    lds dx, [sb_old_dos]
    mov ax, 2521h
    int 21h
    pop ds
    mov dword [sb_old_dos], 0
.dos_restored:
%endif
    call sb_stop
    call fast_dma_clear
    call trap_remove
    jnc .trap_removed
    mov byte [audio_detach_failed], 1
.trap_removed:
    call host_remove
    jnc .host_removed
    mov byte [audio_detach_failed], 1
.host_removed:
    cmp byte [audio_detach_failed], 0
    jne .memory
    cmp word [output_allocation], 0
    je .xms
    mov es, [output_allocation]
    mov ah, 49h
    int 21h
    mov word [output_allocation], 0
    mov word [sb_record_segment], 0
.xms:
    call cd_close
    cmp word [cd_half_allocation], 0
    je .work_memory
    mov es, [cd_half_allocation]
    mov ah, 49h
    int 21h
    mov word [cd_half_allocation], 0
.work_memory:
    cmp word [cd_work_allocation], 0
    je .memory
    mov es, [cd_work_allocation]
    mov ah, 49h
    int 21h
    mov word [cd_work_allocation], 0
.memory:
    call cd_memory_restore
    cmp byte [audio_detach_failed], 0
    je .ok
    stc
    ret
.ok:
    clc
    ret

%ifndef OWN_HOST
audio_abort:
    push cs
    pop ds
    call audio_cleanup
    jc .failed
    cmp byte [audio_linked], 0
    je .done
    mov ah, 52h
    int 21h
    mov eax, [header]
    mov [es:bx+22h], eax
    mov byte [audio_linked], 0
.done:
    clc
    retf
.failed:
    stc
    retf

%endif

audio_detach_failed db 0

%include "audio/resident_init.asm"
