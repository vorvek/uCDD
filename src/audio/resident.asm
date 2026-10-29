; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%ifndef OUTPUT_SHIFT
%define OUTPUT_SHIFT 5
%endif
%define MOUNTED_AUDIO 1
%define CD_IMAGE_TEST 1
%define VIRTUAL_IRQ 1
%define WSS_INPUT 1
%ifdef RESIDENT_AUDIO
%define UCDD_DIAG 1
%endif
%include "audio/layout.inc"
%include "audio/diag.inc"

qpi dd 0
audio_error_text dw audio_unit_message
output_segment dw 0
output_allocation dw 0
output_spare dw 0
cd_half_allocation dw 0
cd_half_segment dw 0
cd_work_allocation dw 0
cd_work_segment dw 0
%ifdef OWN_HOST
cold_allocation dw 0
cold_paras dw 0
%endif
fault db 0
%ifdef UCDD_DIAG
; UCDD -status reads this block with control 10 and 11 (driver.asm). Counters
; are words that wrap. diag_host and the abort record are the part that the
; protected host writes (CDF5); the host uses the offsets DIAG_HOST_*.
DIAG_BYTES equ 144
DIAG_HOST_DUE_PM equ 82
DIAG_HOST_REFUSED equ 0
DIAG_HOST_ABORT equ 20
DIAG_HOST_GATES equ 40
diag_block:
dw 1
dw DIAG_BYTES
; [periods] at the last reset. The copy holds the periods since.
diag_periods dd 0
; The complement of the smallest queue level since the last PLAY. 0: none.
diag_queue_low dd 0
diag_irq:
diag_raised dw 0
diag_taken dw 0
diag_ended dw 0
diag_overrun dw 0
diag_spurious dw 0
; Refill runs: timer tail, audio IRQ tail, host, and request.
diag_runs:
diag_run_timer dw 0
diag_run_irq dw 0
diag_run_host dw 0
diag_run_request dw 0
; Refusals: queue full, driver busy, BIOS busy, DSP split, PIC in service,
; InDOS or critical, deferred to a protected-mode client.
diag_refused:
diag_ref_queue dw 0
diag_ref_busy dw 0
diag_ref_bios dw 0
diag_ref_dsp dw 0
diag_ref_pic dw 0
diag_ref_dos dw 0
diag_ref_defer dw 0
diag_busy dw 0
diag_nested dw 0
diag_busy_command dw 0
diag_fault_site db 0
diag_fault_value db 0
diag_fault_port dw 0
diag_fault_dsp db 0
diag_fault_dma db 0
diag_host:
; Host refusals: STI shadow, inactive, VIF, busy, callback, exception, locked
; stack depth, retrace wait, clock, queue wait.
times 10 dw 0
; The abort record: mon_status, mon_error, mon_eip, mon_cr2, mon_fault_cs
; (copied as one run of the host's variables), exit code, count.
diag_abort_status dw 0
diag_abort_error dd 0
diag_abort_eip dd 0
diag_abort_cr2 dd 0
diag_abort_cs dw 0
diag_abort_exit db 0, 0
diag_abort_count dw 0
; Host gates at the IRQ path: hardware room refused (refill busy, stack depth),
; SB IRQ blocked (in service, higher request), take refused (undelivered, no
; request), stale delivery, room refused at the IRQ callback.
diag_gates times 8 dw 0
; Client refills: run, then refused for these causes: not in a real-mode call,
; DOS busy, interrupts off, host depth or busy, interrupted code area. Then
; the count of checks that found the queue full enough, and a spare word.
diag_hold_run dw 0
diag_hold_refused times 5 dw 0
diag_hold_idle dw 0
; Refills run from the INT 28h idle call.
diag_run_idle dw 0
; Delayed interrupts (F2h and short blocks) by the site that fired them:
; next access, guest steps, output tick, mask write. Then the arms: JEMMEX
; V86 and protected host (the host writes the last word).
diag_due_access dw 0
diag_due_step dw 0
diag_due_tick dw 0
diag_due_mask dw 0
diag_due_arm_v86 dw 0
diag_due_arm_pm dw 0
; The copy gets audio_engaged here (driver.asm).
diag_state dd 0
diag_end:
%if diag_due_arm_pm-diag_host != DIAG_HOST_DUE_PM
%error The host counter offset is wrong.
%endif
%if diag_end-diag_block != DIAG_BYTES || diag_abort_status-diag_host != DIAG_HOST_ABORT || diag_gates-diag_host != DIAG_HOST_GATES
%error The diagnostic block layout is wrong.
%endif

; AL: site, AH: fault value. The first fault since the reset keeps a record. The port and the
; value are those of the last trapped access.
fault_set:
    cmp byte [diag_fault_site], 0
    jne .set
    push bx
    mov [diag_fault_site], al
    mov bx, [callback_port]
    mov [diag_fault_port], bx
    mov bl, [callback_value]
    mov [diag_fault_value], bl
    mov bl, [dsp_command]
    mov [diag_fault_dsp], bl
    mov bx, [game_dma]
    mov bl, [bx+DMA_MODE]
    mov [diag_fault_dma], bl
    pop bx
.set:
    mov [fault], ah
    ret
%endif
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
%include "audio/config.asm"
%include "audio/mounted.asm"
%include "audio/background.asm"
%include "audio/irq.asm"
%include "audio/sb_patch.asm"
%include "audio/standby.asm"
%include "audio/host_jemm.asm"
%ifdef OWN_HOST
%include "audio/resident_host.asm"
%else
%include "audio/resident_pm.asm"
%endif

audio_bind:
    cmp word [si+STRIDE], 2352
    je .bind
    cmp word [si+TRACK_COUNT], 1
    jbe .done
.bind:
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

%ifndef OWN_HOST
%include "audio/resident_install.asm"
%endif
