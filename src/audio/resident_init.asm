; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

audio_activate:
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
    mov word [audio_error_text], cd_half_memory_message
    call cd_half_allocate
    jc .cleanup
    mov word [audio_error_text], cd_work_memory_message
    call cd_work_allocate
    jc .cleanup
    mov word [audio_error_text], xms_memory_message
%ifdef EMS_QUEUE
    cmp byte [memory_mode], 0
    je .queue_message_ready
    mov word [audio_error_text], ems_memory_message
.queue_message_ready:
%endif
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
    mov word [audio_error_text], dma_memory_message
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
    call cd_half_promote
    call cd_work_promote
    mov al, [guest_irq]
    cmp [sb_irq], al
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

audio_activate_far:
    call audio_activate
    retf

cd_half_allocate:
    mov bx, CD_HALF_PARAS
    mov ah, 48h
    int 21h
    jc .bad
    mov [cd_half_allocation], ax
    mov [cd_half_segment], ax
    clc
    ret
.bad:
    stc
    ret

cd_work_allocate:
    mov bx, CD_WORK_PARAS
    mov ah, 48h
    int 21h
    jc .bad
    mov [cd_work_allocation], ax
    mov [cd_work_segment], ax
    clc
    ret
.bad:
    stc
    ret

cd_half_promote:
    mov bx, CD_HALF_PARAS
    mov si, cd_half_allocation
    mov di, cd_half_segment
    mov bp, cd_read_address+2
    jmp cd_buffer_promote

cd_work_promote:
    mov bx, CD_WORK_PARAS
    mov si, cd_work_allocation
    mov di, cd_work_segment
    mov bp, cd_write_address+2

cd_buffer_promote:
    push bx
    mov ax, 5800h
    int 21h
    jc .discard
    mov [cd_buffer_strategy], ax
    mov ax, 5802h
    int 21h
    jc .discard
    mov [cd_buffer_umb], al
    mov ax, 5803h
    mov bx, 1
    int 21h
    jc .discard
    mov ax, 5801h
    mov bx, 40h
    int 21h
    jc .restore_umb_discard
    pop bx
    mov ah, 48h
    int 21h
    pushf
    push ax
    mov bx, [cd_buffer_strategy]
    mov ax, 5801h
    int 21h
    movzx bx, byte [cd_buffer_umb]
    mov ax, 5803h
    int 21h
    pop ax
    popf
    jc .done
    mov es, [si]
    push ax
    mov ah, 49h
    int 21h
    pop ax
    mov [si], ax
    mov [di], ax
    mov [ds:bp], ax
.done:
    ret
.restore_umb_discard:
    movzx bx, byte [cd_buffer_umb]
    mov ax, 5803h
    int 21h
.discard:
    pop bx
    ret

cd_buffer_strategy dw 0
cd_buffer_umb db 0

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
