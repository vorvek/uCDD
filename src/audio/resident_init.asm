; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

audio_install:
    mov word [audio_error_text], audio_unit_message
    cmp byte [unit_count], 1
    jne .bad
    call audio_configure
    jc .bad
    cmp byte [sound_card], 3
    jne .pro_rate
    mov dword [output_rate], 44444
    mov dword [cd_step], (44100*65536)/44444
    mov dword [cd_step_remainder], (44100*65536) % 44444
    jmp .format_ready
.pro_rate:
    cmp byte [sound_card], 1
    jne .format_ready
    mov dword [output_rate], 43478
    mov dword [cd_step], (44100*65536)/43478
    mov dword [cd_step_remainder], (44100*65536) % 43478
.format_ready:
%ifndef OWN_HOST
    mov word [audio_error_text], dpmi_host_message
    mov ax, 1687h
    int 2fh
    test ax, ax
    jnz .bad
    test bl, 1
    jz .bad
%endif
    mov word [audio_error_text], port_trap_missing_message
    call host_install
    jc .bad
    mov eax, [host_api_entry]
    mov [qpi], eax
    mov word [audio_error_text], memory_control_message
    call cd_memory_low
    jc .cleanup
    mov word [audio_error_text], xms_memory_message
    call cd_open
    jc .cleanup
    call virtual_irq_init
    mov bx, RING_PARAS*2
    cmp byte [sound_card], 3
    jne .pro_size
    shr bx, 1
.pro_size:
    test byte [sound_card], 1
    jz .allocate_dma
    shr bx, 2
.allocate_dma:
    mov word [audio_error_text], dos_memory_message
    mov ah, 48h
    int 21h
    jc .cleanup
    mov [output_allocation], ax
    cmp byte [sound_card], 3
    jne .pro_align
    add ax, RING_PARAS/8-1
    and ax, ~(RING_PARAS/8-1)
    jmp .dma_ready
.pro_align:
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
    mov word [audio_error_text], port_trap_rejected_message
    call trap_install
    jc .cleanup
    mov word [audio_error_text], sound_card_message
    call sb_start
    jc .cleanup
    call cd_memory_restore
%ifdef OWN_HOST
    mov word [audio_error_text], internal_host_message
    call own_host_install
    jc .cleanup
    cmp byte [sb_irq], 5
    jne .dos_vector_ready
    mov eax, [old_irq]
    mov [sb_game_vector], eax
    mov ax, 3521h
    int 21h
    mov [sb_old_dos], bx
    mov [sb_old_dos+2], es
    mov dx, sb_dos_vector
    mov ax, 2521h
    int 21h
.dos_vector_ready:
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
%include "audio/host_emm_init.asm"
host_install:
    call host_jemm_install
    jnc .done
    call host_emm_install
.done:
    ret
%ifdef OWN_HOST
%include "audio/resident_host_init.asm"
%endif
%include "audio/configure.asm"
%include "config_path.asm"
