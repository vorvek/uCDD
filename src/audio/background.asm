; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%include "audio/diag.inc"
%ifdef OWN_HOST
CD_REFILL_URGENT equ CD_READ_BYTES*2
; About 190 ms of output periods without a timer call.
CD_TIMER_STARVED equ 8192/PERIOD_FRAMES
; About 23 ms of output periods without a host refill. The hold refill
; then keeps the queue near its threshold.
CD_HOST_STARVED equ 8
%endif
CD_TIMER_READS equ 4
CD_TIMER_MAX_READS equ 8
CD_HOLD_READS equ 2
; Hold refills run only below this queue level (0.75 s), or when urgent.
CD_HOLD_LOW equ 131072

; DOS calls INT 28h while it waits for a key, with InDOS 1 (the prompt). Refill
; there after the chain, as the timer does.
cd_idle:
    pushf
    call far [cs:cd_old_idle]
    mov byte [cs:cd_idle_entry], 1
    jmp cd_timer_refill

; Refusals of the INT 28h path are not counted.
%macro DIAG_REF 1
%ifdef UCDD_DIAG
    cmp byte [cd_idle_now], 0
    jne %%skip
    inc word [%1]
%%skip:
%endif
%endmacro

cd_timer:
    mov word [cs:cd_timer_missed], 0
    pushf
    call far [cs:cd_old_timer]
; The audio IRQ enters here when a game timer handler does not chain.
cd_timer_refill:
    pushad
    push ds
    push es
    push fs
    push gs
    push cs
    pop ds
    cli
    mov al, 0
    xchg al, [cd_idle_entry]
    mov [cd_idle_now], al
%ifdef OWN_HOST
    mov al, 0
    xchg al, [cd_irq_entry]
    mov [cd_irq_forced], al
%endif
    cmp byte [cd_started], 1
    jne .done
    cmp byte [cd_error], 0
    jne .done
    cmp dword [cd_remaining], 0
    je .done
    mov eax, [cd_produced]
    sub eax, [cd_consumed]
    cmp eax, CD_QUEUE_BYTES-65536
%ifdef UCDD_DIAG
    ja .queue_full
%else
    ja .done
%endif
    ; Between refills the read limit is the timer budget. Each tick adds a
    ; few reads, and a tick that cannot read keeps its share.
%ifdef OWN_HOST
    cmp byte [cd_irq_forced], 0
    jne .budget
%endif
    cmp byte [cd_idle_now], 0
    jne .budget
    cmp byte [cd_background_reads], CD_TIMER_MAX_READS-CD_TIMER_READS
    ja .budget
    add byte [cd_background_reads], CD_TIMER_READS
.budget:
    call cd_refill_wait
    jc .done
%ifdef OWN_HOST
    call cd_client_live
    je .hold
%endif
    les bx, [cd_indos]
    mov ax, [es:bx-1]
    cmp byte [cd_idle_now], 0
    je .dos_checked
    ; The idle call: DOS waits in one call (InDOS 1) with no critical error.
    sub ax, 100h
.dos_checked:
    test ax, ax
%ifdef UCDD_DIAG
    jne .dos_busy
%else
    jne .done
%endif
%ifdef OWN_HOST
    cmp byte [cd_irq_forced], 0
    je .counted
    mov byte [cd_background_reads], CD_HOLD_READS
.counted:
%endif
    cmp byte [cd_idle_now], 0
    je .counted_idle
    mov byte [cd_background_reads], CD_TIMER_READS
    DIAG_INC diag_run_idle
    jmp .run
.counted_idle:
%ifdef UCDD_DIAG
%ifdef OWN_HOST
    ; The timer tail counts at 0 and the audio IRQ tail at 1.
    movzx bx, byte [cd_irq_forced]
    add bx, bx
    inc word [diag_runs+bx]
%else
    inc word [diag_run_timer]
%endif
%endif
.run:
    call cd_refill_run
.done:
    pop gs
    pop fs
    pop es
    pop ds
    popad
    iret
%ifdef UCDD_DIAG
.queue_full:
    DIAG_REF diag_ref_queue
    jmp .done
.dos_busy:
    DIAG_REF diag_ref_dos
    jmp .done
%endif
%ifdef OWN_HOST
    ; A live client is in a real-mode call. Read only when the interrupted
    ; code belongs to the current program or to the client: a refill in DOS,
    ; a driver or XMS/EMS code breaks JEMMEX nested execution (Earthworm Jim).
.hold:
    cmp byte [cd_idle_now], 0
    jne .done
    mov al, [cd_refill_pending]
    mov ah, al
    cmp al, 1
    adc al, 0
    mov [cd_refill_pending], al
    cmp ah, 2
    je .low
    mov eax, [cd_produced]
    sub eax, [cd_consumed]
    cmp eax, CD_HOLD_LOW
    jb .low
    DIAG_INC diag_hold_idle
    jmp .done
.low:
    mov si, 2
    les di, [cd_indos]
    cmp word [es:di-1], 0
    jne .refuse
    add si, 2
    mov bp, sp
    test byte [ss:bp+45], 2
    jz .refuse
    add si, 2
    ; No real-mode call (0) still runs client code here when the host
    ; reflects a software interrupt (DOS/16M, Judge Dredd briefing). The
    ; block owner test below refuses the host, DOS and driver code.
    les bx, [own_host_active]
    cmp byte [es:bx+10], 2
    je .refuse
    mov di, [es:bx+8]
    test di, di
    jz .refuse
    cmp byte [es:di], 0
    jne .refuse
    add si, 2
    mov dx, [es:bx+12]
    ; At the timer tail the frame is the interrupted code only when INT 8
    ; leads to this routine or to the host stub, which chains with a jump.
    cmp byte [cd_irq_forced], 0
    jne .frame_ready
    xor ax, ax
    mov es, ax
    mov ax, [es:8*4+2]
    mov cx, cs
    cmp ax, cx
    je .frame_ready
%ifdef OWN_HOST
    ; The timer hook of the hotkeys is in the driver part.
    cmp ax, [driver_seg]
    je .frame_ready
%endif
    cmp ax, [own_host_active+2]
    jne .refuse
.frame_ready:
    ; The walk ends at the last conventional block, so code in upper memory
    ; is refused. The owner of the block that holds CS+IP/16 must be the
    ; current PSP, the client PSP or its parent.
%ifdef OWN_HOST
    push ds
    mov ds, [driver_seg]
    les bx, [sda_pointer]
    pop ds
%else
    les bx, [sda_pointer]
%endif
    mov cx, [es:bx+10h]
    mov ax, [ss:bp+40]
    shr ax, 4
    add ax, [ss:bp+42]
    mov bx, [cd_first_mcb]
.walk:
    mov es, bx
    cmp byte [es:0], 'M'
    je .block
    cmp byte [es:0], 'Z'
    jne .refuse_cs
.block:
    mov di, [es:3]
    mov si, ax
    sub si, bx
    dec si
    cmp si, di
    jb .found
    cmp byte [es:0], 'Z'
    je .refuse_cs
    add bx, di
    jc .refuse_cs
    inc bx
    jnz .walk
.refuse_cs:
    mov si, 8
    jmp .refuse
.found:
    mov bx, [es:1]
    test bx, bx
    jz .refuse_cs
    cmp bx, cx
    je .owned
    cmp bx, dx
    je .owned
    mov es, dx
    cmp bx, [es:16h]
    jne .refuse_cs
.owned:
    les bx, [own_host_active]
    mov di, [es:bx+8]
    mov byte [es:di], 1
    cmp byte [cd_irq_forced], 0
    je .budget_kept
    mov byte [cd_background_reads], CD_HOLD_READS
.budget_kept:
    mov word [cd_host_missed], 0
    DIAG_INC diag_hold_run
    call cd_refill_run
    les bx, [own_host_active]
    mov di, [es:bx+8]
    mov byte [es:di], 0
    jmp .done
.refuse:
    DIAG_INC diag_hold_refused+si
    DIAG_INC diag_ref_defer
    jmp .done
%endif

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
    call cd_refill_wait
    jc .done
    cmp byte [cd_started], 1
    jne .cancel
    cmp byte [cd_error], 0
    jne .cancel
    cmp dword [cd_remaining], 0
    je .cancel
    les bx, [cd_indos]
    cmp word [es:bx-1], 0
%ifdef UCDD_DIAG
    jne .dos_busy
%else
    jne .done
%endif
    mov eax, [cd_produced]
    sub eax, [cd_consumed]
    cmp eax, CD_QUEUE_BYTES-65536
%ifdef UCDD_DIAG
    ja .queue_full
%else
    ja .cancel
%endif
    mov byte [cd_refill_pending], 0
    mov word [cd_host_missed], 0
    mov byte [cd_background_reads], 1
    DIAG_INC diag_run_host
    call cd_refill_run
    jmp .done
.cancel:
    mov byte [cd_refill_pending], 0
    mov word [cd_host_missed], 0
.done:
    pop gs
    pop fs
    pop es
    pop ds
    popad
    popf
    retf
%ifdef UCDD_DIAG
.queue_full:
    DIAG_INC diag_ref_queue
    jmp .cancel
.dos_busy:
    DIAG_INC diag_ref_dos
    jmp .done
%endif
cd_refill_pending db 0
cd_first_mcb dw 0

; ZF set: a protected-mode client is live. Keeps all registers.
cd_client_live:
    cmp byte [own_host_refill], 1
    jne .no
    push es
    push bx
    les bx, [own_host_active]
    cmp byte [es:bx], 1
    pop bx
    pop es
.no:
    ret
%endif

; CF set: the refill waits. A gate that refuses counts in the diagnostics.
cd_refill_wait:
%ifdef OWN_HOST
    push es
    mov es, [driver_seg]
    cmp byte [es:busy], 0
    pop es
%else
    cmp byte [busy], 0
%endif
    je .bios
    DIAG_REF diag_ref_busy
    stc
    ret
.bios:
    cmp byte [cd_bios_busy], 0
    je .dsp
    DIAG_REF diag_ref_bios
    stc
    ret
.dsp:
%ifdef RESIDENT_AUDIO
    ; The game is between the bytes of a DSP command (Prototype).
    call cd_dsp_wait
    jnc .pic
    DIAG_REF diag_ref_dsp
    ret
.pic:
%endif
    call physical_pic_isr
    or al, [virtual_pic_service]
    ; A masked IRQ cannot be delivered, so it does not hold the refill.
    mov ah, [virtual_pic_mask]
    not ah
    and ah, [virtual_pic_taken]
    or al, ah
    jz .free
    DIAG_REF diag_ref_pic
    stc
    ret
.free:
    clc
    ret

; Run the refill on the CD stack. Interrupts are off.
cd_refill_run:
%ifdef OWN_HOST
    push es
    mov es, [driver_seg]
    mov byte [es:busy], 1
    pop es
%else
    mov byte [busy], 1
%endif
    mov [cd_call_ss], ss
    mov [cd_call_sp], sp
%ifdef EXTERNAL_CD_BUFFERS
    mov ax, [cd_work_segment]
%else
    mov ax, cs
%endif
    mov ss, ax
    mov sp, cd_stack_top
%ifdef RESIDENT_AUDIO
    call cd_refill_mask
%endif
    sti
    cld
    call cd_foreground
    cli
%ifdef RESIDENT_AUDIO
    call cd_refill_unmask
%endif
    mov byte [cd_background_reads], 0
    mov ss, [cd_call_ss]
    mov sp, [cd_call_sp]
%ifdef OWN_HOST
    push es
    mov es, [driver_seg]
    mov byte [es:busy], 0
    pop es
%else
    mov byte [busy], 0
%endif
    ret

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
    ; The chain ran with IF clear. Return the caller's IF with the result.
    push bp
    mov bp, sp
    and byte [bp+3], 0fdh
    test byte [bp+9], 2
    jz .if_ready
    or byte [bp+3], 2
.if_ready:
    pop bp
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
    push cs
    pop ds
    lds dx, [cd_old_idle]
    mov ax, 2528h
    int 21h
    pop ds
    mov byte [cd_background_set], 0
.done:
    ret

%ifdef RESIDENT_AUDIO
; A refill runs on top of the interrupted game code. A game keyboard handler
; that does not return (Prototype skips its intro so) leaves the refill and
; DOS busy. Hold the keyboard IRQ until the refill ends.
cd_refill_mask:
    mov dx, 21h
    call physical_read
    mov [cd_refill_old_mask], al
    mov byte [cd_refill_masked], 1
    or al, 2
    jmp physical_write

cd_refill_unmask:
    mov byte [cd_refill_masked], 0
    mov dx, 21h
    call physical_read
    mov ah, [cd_refill_old_mask]
    or ah, 0fdh
    and al, ah
    jmp physical_write

; The guest's own keyboard bit while the refill holds the IRQ. A game handler
; that runs during the refill must not save the held bit (TEMIM).
cd_refill_old_mask db 0
cd_refill_masked db 0

; CF set: wait until the game sends the rest of a DSP command, for a few calls.
cd_dsp_wait:
    cmp byte [dsp_arguments], 0
    je .free
    cmp byte [cd_dsp_waits], 8
    jae .free
    inc byte [cd_dsp_waits]
    stc
    ret
.free:
    mov byte [cd_dsp_waits], 0
    clc
    ret

cd_dsp_waits db 0
%endif

cd_old_timer dd 0
cd_old_bios dd 0
cd_old_idle dd 0
cd_idle_entry db 0
cd_idle_now db 0
cd_bios_busy db 0
cd_timer_missed dw 0
cd_irq_refill db 0
cd_irq_entry db 0
cd_irq_forced db 0
cd_host_missed dw 0
cd_background_set db 0
cd_background_reads db 0

%ifdef RESIDENT_AUDIO
%include "audio/disk_cache.asm"
%endif
