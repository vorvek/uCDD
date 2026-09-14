; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

audio_install:
    cmp byte [unit_count], 1
    jne .bad
    call config_load
    jc .bad
    cmp byte [sound_card], 1
    jne .format_ready
    mov dword [output_rate], 43478
    mov dword [cd_step], (44100*65536)/43478
    mov dword [cd_step_remainder], (44100*65536) % 43478
.format_ready:
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
    cmp byte [sound_card], 1
    jne .allocate_dma
    shr bx, 2
.allocate_dma:
    mov ah, 48h
    int 21h
    jc .cleanup
    mov [output_allocation], ax
    cmp byte [sound_card], 1
    jne .align_dma
    add ax, RING_PARAS/4-1
    and ax, ~(RING_PARAS/4-1)
    jmp .dma_ready
.align_dma:
    add ax, RING_PARAS-1
    and ax, ~(RING_PARAS-1)
.dma_ready:
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
    mov ax, 3508h
    int 21h
    mov [cd_old_timer], bx
    mov [cd_old_timer+2], es
    mov ax, 3513h
    int 21h
    mov [cd_old_bios], bx
    mov [cd_old_bios+2], es
    mov dx, cd_bios
    mov ax, 2513h
    int 21h
    mov dx, cd_timer
    mov ax, 2508h
    int 21h
    mov byte [cd_background_set], 1
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
