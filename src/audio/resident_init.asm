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
    call environment_detach
    mov word [audio_error_text], irq_table_memory_message
    call irq_table_allocate
    jc .bad
    mov word [audio_error_text], port_trap_missing_message
    call host_install
    pushf
    call irq_table_settle
    popf
    jc .bad
    mov eax, [host_api_entry]
    mov [qpi], eax
    mov word [audio_error_text], memory_control_message
    call cd_memory_low
    jc .cleanup
    mov bx, RING_PARAS*2
    cmp byte [sound_card], 3
    jne .pro_size
    shr bx, 1
.pro_size:
    test byte [sound_card], 1
    jz .half_size
    shr bx, 2
.half_size:
    cmp byte [ess_half], 0
    je .allocate_dma
    shr bx, 1
.allocate_dma:
    mov word [audio_error_text], dma_memory_message
    mov ah, 48h
    int 21h
    jc .cleanup
    mov [output_allocation], ax
    call ring_place
    mov [output_segment], ax
    mov [output_spare], dx
    test byte [sound_card], 1
    jnz .dma_ready
    cmp byte [ess_half], 0
    jne .dma_ready
    ; The spare ring keeps the game part of each output word.
    mov [sb_record_segment], dx
.dma_ready:
    mov word [audio_error_text], cd_half_memory_message
    call cd_half_allocate
    jc .cleanup
    mov word [audio_error_text], cd_work_memory_message
    call cd_work_allocate
    jc .cleanup
%ifdef OWN_HOST
    mov word [audio_error_text], cold_memory_message
    call cold_allocate
    jc .cleanup
%endif
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
    call mix_fill
    mov word [audio_error_text], port_trap_rejected_message
    call trap_install
    jc .cleanup
    mov word [audio_error_text], sound_card_message
    call sb_start
    jc .cleanup
    call fast_dma_set
    call cd_memory_restore
%ifdef OWN_HOST
    mov word [audio_error_text], internal_host_message
    call own_host_install
    jc .cleanup
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
    mov ax, 3528h
    int 21h
    mov [cd_old_idle], bx
    mov [cd_old_idle+2], es
    mov dx, cd_bios
    mov ax, 2513h
    int 21h
    mov dx, cd_idle
    mov ax, 2528h
    int 21h
    mov dx, cd_timer
    mov ax, 2508h
    int 21h
    mov byte [cd_background_set], 1
    ; The hotkeys work without an MDM list.
%ifdef OWN_HOST
    call mdm_key_hooks
    call far [cs:mdm_hooks_far]
%else
    call mdm_hooks
%endif
    ; Nothing is mounted at install: step aside when the pairing allows it.
    call audio_reconsider
    clc
    ret
.cleanup:
    call audio_cleanup
.bad:
    stc
    ret

; JEMMEX may keep a pointer to the IRQ table (host_irq_table_linear), so the
; block must not move afterwards: upper memory if it is free, else the top of
; conventional memory (or any block when the image is loaded high).
irq_table_allocate:
    mov ax, 5800h
    int 21h
    jc .none
    mov [cd_buffer_strategy], ax
    mov ax, 5802h
    int 21h
    jc .none
    mov [cd_buffer_umb], al
    mov ax, 5803h
    mov bx, 1
    int 21h
    jc .low
    mov ax, 5801h
    mov bx, 40h
    int 21h
    jc .low
    mov bx, 1024/16
    mov ah, 48h
    int 21h
    jnc .got
.low:
    mov ax, 5803h
    xor bx, bx
    int 21h
    mov ax, 5801h
    xor bx, bx
    cmp word [RESIDENT_PSP], 0a000h
    jae .strategy
    mov bl, 2
.strategy:
    int 21h
    mov bx, 1024/16
    mov ah, 48h
    int 21h
    jnc .got
    call .restore
    stc
    ret
.got:
    mov [host_irq_table_block], ax
    ; JEMMEX takes the table as it is: it must be empty.
    mov es, ax
    xor di, di
    mov cx, 1024/2
    xor ax, ax
    cld
    rep stosw
    movzx eax, word [host_irq_table_block]
    shl eax, 4
    mov [host_irq_table_linear], eax
    call .restore
    clc
    ret
.none:
    stc
    ret
.restore:
    mov bx, [cd_buffer_strategy]
    mov ax, 5801h
    int 21h
    movzx bx, byte [cd_buffer_umb]
    mov ax, 5803h
    int 21h
    ret

; Free the table block unless the host keeps the table.
irq_table_settle:
    cmp byte [host_table_used], 0
    jne .keep
    call irq_table_free
.keep:
    ret

irq_table_free:
    cmp word [host_irq_table_block], 0
    je .done
    mov es, [host_irq_table_block]
    mov ah, 49h
    int 21h
    mov word [host_irq_table_block], 0
    mov dword [host_irq_table_linear], 0
.done:
    ret

audio_activate_far:
    call audio_activate
    retf

; BX: paragraphs. Return AX: the block, or CF set. Upper memory first, so that
; a buffer that fits there never takes conventional memory and leaves a gap
; when it would move later. The caller's strategy holds for the fallback.
high_first_allocate:
    mov [high_first_paras], bx
    mov ax, 5800h
    int 21h
    jc .plain
    mov [cd_buffer_strategy], ax
    mov ax, 5802h
    int 21h
    jc .plain
    mov [cd_buffer_umb], al
    mov ax, 5803h
    mov bx, 1
    int 21h
    jc .plain
    mov ax, 5801h
    mov bx, 40h
    int 21h
    jc .restore_plain
    mov bx, [high_first_paras]
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
    jnc .done
    jmp .plain
.restore_plain:
    movzx bx, byte [cd_buffer_umb]
    mov ax, 5803h
    int 21h
.plain:
    mov bx, [high_first_paras]
    mov ah, 48h
    int 21h
.done:
    ret
high_first_paras dw 0

cd_half_allocate:
    mov bx, CD_HALF_PARAS
    call high_first_allocate
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
    call high_first_allocate
    jc .bad
    mov [cd_work_allocation], ax
    mov [cd_work_segment], ax
    clc
    ret
.bad:
    stc
    ret

; LH can put the environment in a UMB that a buffer needs. Copy the program
; path to the command tail of the PSP (the host reads it from there) and free
; the environment before the first buffer goes to upper memory.
environment_detach:
    push ds
    push es
    mov es, [RESIDENT_PSP]
    mov ax, [es:2ch]
    test ax, ax
    jz .done
    mov es, ax
    xor di, di
    xor al, al
    mov cx, 32767
.scan:
    repne scasb
    jne .done
    cmp byte [es:di], 0
    jne .scan
    add di, 3
    push es
    pop ds
    mov si, di
    mov es, [cs:RESIDENT_PSP]
    mov di, 80h
    mov cx, 126
.copy:
    lodsb
    stosb
    test al, al
    jz .copied
    loop .copy
    mov byte [es:di], 0
.copied:
    push cs
    pop ds
    call environment_free
.done:
    pop es
    pop ds
    ret

environment_free:
    push es
    mov es, [RESIDENT_PSP]
    xor ax, ax
    xchg ax, [es:2ch]
    test ax, ax
    jz .done
    mov es, ax
    mov ah, 49h
    int 21h
.done:
    pop es
    ret

%ifdef OWN_HOST
cold_allocate:
    mov bx, [cold_paras]
    call high_first_allocate
    jc .bad
    mov [cold_allocation], ax
    mov [cold_segment], ax
    push es
    mov es, [driver_seg]
    mov [es:cold_stack], ax
    pop es
    clc
    ret
.bad:
    stc
    ret
%endif

cd_buffer_strategy dw 0
cd_buffer_umb db 0

%include "audio/host_jemm_init.asm"
host_install:
    jmp host_jemm_install
%ifdef OWN_HOST
%include "audio/resident_host_init.asm"
%endif
