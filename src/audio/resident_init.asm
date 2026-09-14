; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

audio_install:
    cmp byte [unit_count], 1
    jne .bad
    call config_load
    jc .bad
%ifndef OWN_HOST
    mov ax, 1687h
    int 2fh
    test ax, ax
    jnz .bad
    test bl, 1
    jz .bad
%endif
    call host_install
    jc .bad
    mov eax, [host_api_entry]
    mov [qpi], eax
    call cd_memory_low
    jc .cleanup
    call cd_open
    jc .cleanup
    call virtual_irq_init
    mov bx, RING_PARAS*2
    mov ah, 48h
    int 21h
    jc .cleanup
    mov [output_allocation], ax
    add ax, RING_PARAS-1
    and ax, ~(RING_PARAS-1)
    mov [output_segment], ax
    mov es, ax
    xor di, di
    call mix_half
    call mix_half
    call trap_install
    jc .cleanup
    call sb_start
    jc .cleanup
    call cd_memory_restore
%ifdef OWN_HOST
    call own_host_install
    jc .cleanup
%endif
    clc
    ret
.cleanup:
    call audio_cleanup
.bad:
    stc
    ret

%include "audio/host_jemm_init.asm"
%ifdef OWN_HOST
%include "audio/resident_host_init.asm"
%endif
