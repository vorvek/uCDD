; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%define OUTPUT_SHIFT 5
%define MOUNTED_AUDIO 1
%define CD_IMAGE_TEST 1
%define VIRTUAL_IRQ 1
%define WSS_INPUT 1
%include "audio/layout.inc"

qpi dd 0
output_segment dw 0
output_allocation dw 0
cd_half_allocation dw 0
cd_half_segment dw 0
cd_work_allocation dw 0
cd_work_segment dw 0
fault db 0
cd_position dw 0
game_phase dd 0
game_step dd 32768
game_limit dd 4096*65536
game_rate dw 22050
game_segment dw 0
game_offset dw 0
game_started dd 0
game_active db 0
output_rate dd 44100
cd_step dd 65536
cd_step_remainder dd 0
cd_step_error dd 0
cd_fraction dd 0
cd_take_bytes dd PERIOD_BYTES
pro_pair_left dd 0
pro_pair_right dd 0
resident_paragraphs dw 0
audio_linked db 0

%include "audio/mix.asm"
%include "audio/sb16.asm"
%define arguments dsp_arguments
%include "audio/trap.asm"
%undef arguments
%define CONFIG_EXE_PATH 1
%include "audio/config.asm"
%include "audio/mounted.asm"
%include "audio/background.asm"
%include "audio/irq.asm"
%include "audio/sb_patch.asm"
%include "audio/host_jemm.asm"
%include "audio/host_emm.asm"
%ifdef OWN_HOST
%include "audio/resident_host.asm"
%else
%include "audio/resident_pm.asm"
%endif

audio_bind:
    cmp word [si+STRIDE], 2352
    jne .done
    pushad
    push es
    mov ax, [si+HANDLE]
    mov [cd_handle], ax
    mov di, cd_info+INFO_STRIDE
    push ds
    pop es
    push si
    add si, STRIDE
    mov cx, 4
    rep movsw
    pop si
    mov ax, [si+TRACK_COUNT]
    stosw
    push si
    add si, TRACKS
    mov cx, MAX_TRACKS*TRACK_SIZE/2
    rep movsw
    pop si
    mov eax, [si+DISC_SECTORS]
    stosd
    mov word [si+AUDIO_ENTRY], cd_request
    mov [si+AUDIO_ENTRY+2], cs
    mov byte [cd_error], 0
    mov eax, [si+ORIGIN]
    mov [cd_head_lba], eax
    call cd_cache_warm
    pop es
    popad
.done:
    ret

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

audio_detach_failed db 0

%include "audio/resident_init.asm"
