; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%include "audio/diag.inc"
%include "audio/sb_state.inc"

; Configuration selects the physical card resources.
physical_read:
%ifdef DIRECT_OUTPUT
    in al, dx
%else
    push bx
    push cx
    mov ax, 1a00h
    call far [qpi]
    mov al, bl
    pop cx
    pop bx
%endif
    ret
physical_write:
%ifdef DIRECT_OUTPUT
    out dx, al
%else
    push ax
    push bx
    push cx
    mov bl, al
    mov ax, 1a01h
    call far [qpi]
    pop cx
    pop bx
    pop ax
%endif
    ret
dsp_write:
    cmp byte [dsp_failed], 0
    jne .failed
    push ax
    push cx
    mov cx, 65535
    mov dx, [sb_base]
    add dx, 0ch
.wait:
    call physical_read
    test al, 80h
    jz .ready
    loop .wait
%ifdef MOUNTED_AUDIO
    FAULT_SET 6, 4
%else
    mov byte [fault], 1
%endif
    mov byte [dsp_failed], 1
    mov dx, 0d4h
    cmp byte [sound_card], 0
    je .mask
    mov dx, 0ah
.mask:
    mov al, [dma_channel]
    or al, 4
    call physical_write
    pop cx
    pop ax
.failed:
    stc
    ret
.ready:
    pop cx
    pop ax
    call physical_write
    clc
    ret
physical_reset:
    mov al, 1
; AL: the reset value.
.value:
    mov byte [dsp_failed], 0
    mov dx, [sb_base]
    add dx, 6
    call physical_write
    mov cx, 64
.delay:
    call physical_read
    loop .delay
    xor al, al
    call physical_write
    mov cx, 65535
.ready:
    mov dx, [sb_base]
    add dx, 0eh
    call physical_read
    test al, 80h
    jnz .data
    loop .ready
    stc
    ret
.data:
    mov dx, [sb_base]
    add dx, 0ah
    call physical_read
    cmp al, 0aah
    je .success
    loop .ready
    stc
    ret
.success:
    clc
    ret
sb_start:
    cmp byte [sound_card], 2
    je wss_start
    cmp byte [sound_card], 0
%ifdef RESIDENT_AUDIO
    jne pro_start
%elifdef DIRECT_OUTPUT
    jne pro_start
%else
    jne .fail
%endif
    movzx bx, byte [sb_dma16]
    mov al, [dma_pages+bx-5]
    mov [dma_page_port], al
    mov ax, bx
    sub ax, 4
    mov [dma_channel], al
    shl ax, 2
    add ax, 0c0h
    mov [dma_address_port], ax
    add ax, 2
    mov [dma_count_port], ax
    call physical_reset
    jc .fail
    mov si, mixer_registers
    mov di, mixer_saved
    mov cx, 6
.mixer:
    mov dx, [sb_base]
    add dx, 4
    lodsb
    call physical_write
    inc dx
    call physical_read
    mov [di], al
    inc di
    ; Registers 34h and 35h hold the FM level, which fm_init sets below.
    ; Registers 30h and 31h hold the master volume.
    cmp cx, 4
    ja .next
    mov al, 0f8h
    cmp cx, 2
    jbe .level
    mov al, [master_register]
.level:
    call physical_write
.next:
    loop .mixer
    ; Nothing is pending now. A card without 82h (or with bit 2 stuck) must not
    ; show an MPU-401 request.
    call card_irq_status
    mov bl, 0fbh
    cmp al, 0ffh
    je .mpu_off
    test al, 4
    jnz .mpu_off
    mov bl, 0ffh
.mpu_off:
    mov [card_irq_mask], bl
%ifdef RESIDENT_AUDIO
    mov al, [mixer_saved]
    mov ah, [mixer_saved+1]
    call fm_init
%endif
    call output_hook
    cli
    mov al, [dma_channel]
    or al, 4
    mov dx, 0d4h
    call physical_write
    xor al, al
    mov dx, 0d8h
    call physical_write
    movzx eax, word [output_segment]
    shl eax, 4
    mov ebx, eax
    shr eax, 1
    mov dx, [dma_address_port]
    call physical_write
    mov al, ah
    call physical_write
    shr ebx, 16
    mov al, bl
    mov dx, [dma_page_port]
    call physical_write
    mov al, (RING_WORDS-1) & 0ffh
    mov dx, [dma_count_port]
    call physical_write
    mov al, (RING_WORDS-1) >> 8
    call physical_write
    mov al, [dma_channel]
    or al, 58h
    mov dx, 0d6h
    call physical_write
    mov al, [dma_channel]
    mov dx, 0d4h
    call physical_write
    sti
    mov byte [sb_running], 1
    mov al, 41h
    call dsp_write
    mov al, 0ach
    call dsp_write
    mov al, 44h
    call dsp_write
    mov al, 0b6h
    call dsp_write
    mov al, 30h
    call dsp_write
    mov al, (PERIOD_FRAMES*2-1) & 0ffh
    call dsp_write
    mov al, (PERIOD_FRAMES*2-1) >> 8
    call dsp_write
    jc .start_failed
    clc
    ret
.start_failed:
    call sb_stop
.fail:
    stc
    ret
; Select the 8-bit DMA channel, then hook the IRQ.
dma8_output_hook:
    mov al, [sb_dma8]
    mov [dma_channel], al
    movzx bx, al
    shl bx, 1
    mov [dma_address_port], bx
    inc bx
    mov [dma_count_port], bx
    mov word [dma_page_port], 83h
    cmp al, 1
    je output_hook
    mov word [dma_page_port], 82h
; Hook the card IRQ and unmask it.
output_hook:
    mov al, [sb_irq]
    add al, 8
    push ax
    mov ah, 35h
    int 21h
    mov [old_irq], bx
    mov [old_irq+2], es
    mov dx, audio_irq
    pop ax
    mov ah, 25h
    int 21h
    mov dx, 21h
    call physical_read
    mov [saved_pic], al
    mov cl, [sb_irq]
    mov ah, 1
    shl ah, cl
    not ah
    and al, ah
    jmp physical_write
; Mask the IRQ, so that no block end runs the handler during a reset.
output_irq_mask:
    pushf
    cli
    mov dx, 21h
    call physical_read
    mov cl, [sb_irq]
    mov ah, 1
    shl ah, cl
    or al, ah
    call physical_write
    popf
    ret
; Mask the DMA channel and clear a pending request, then unhook.
output_halt:
    mov dx, 0ah
    mov al, [dma_channel]
    or al, 4
    call physical_write
    mov dx, [sb_base]
    add dx, 0eh
    call physical_read
    jmp output_unhook
; Put back the IRQ vector and the PIC mask.
output_unhook:
    mov al, [sb_irq]
    add al, 8
    push ds
    lds dx, [old_irq]
    mov ah, 25h
    int 21h
    pop ds
    mov al, [saved_pic]
    mov dx, 21h
    jmp physical_write
sb_stop:
    cmp byte [sound_card], 2
    je wss_stop
    test byte [sound_card], 1
    jnz pro_stop
    cmp byte [sb_running], 0
    je .done
    mov al, 0d5h
    call dsp_write
    mov al, [dma_channel]
    or al, 4
    mov dx, 0d4h
    call physical_write
    mov dx, [sb_base]
    add dx, 0fh
    call physical_read
    call output_unhook
    mov si, mixer_registers
    mov di, mixer_saved
    mov cx, 6
.mixer:
    mov dx, [sb_base]
    add dx, 4
    lodsb
    call physical_write
    inc dx
    mov al, [di]
    inc di
    call physical_write
    loop .mixer
    mov byte [sb_running], 0
.done:
    ret
audio_irq:
    push ds
    push ax
    mov ax, cs
    mov ds, ax
    cmp byte [audio_irq_busy], 0
    jne .nested
    mov byte [audio_irq_busy], 1
    mov [irq_ss], ss
    mov [irq_sp], sp
    mov ss, ax
    mov sp, irq_stack_top
    pushad
    push es
    push fs
    cld
    call audio_irq_mask
    cmp byte [sound_card], 2
    je .wss
    test byte [sound_card], 1
    jnz .pro
    ; Mixer 82h names the sources on the card's line: bit 1 the 16-bit DMA
    ; that plays the output, bit 2 the MPU-401, bit 0 the 8-bit DMA and
    ; SB-MIDI. A reflected game IRQ shows none and must not advance the
    ; physical output buffer.
    call card_irq_status
    and al, [card_irq_mask]
%ifdef VIRTUAL_IRQ
    test al, 4
    jz .no_mpu
    push ax
    call virtual_mpu_raise
    pop ax
.no_mpu:
%endif
    test al, 2
    jnz .output16
    test al, 5
    jz .unowned
    ; The MPU-401 alone: the game reads its byte at 330h and ends the request.
    test al, 1
    jz .other_owner
    ; A stray 8-bit request: the 2xEh read acknowledges it.
    mov dx, [sb_base]
    add dx, 0eh
    call physical_read
.other_owner:
    ; A handler in RAM may own the interrupt: pass it on. The vector from
    ; before the driver is the BIOS one on most machines, and its handler
    ; masks the IRQ, so the interrupt ends here.
    cmp word [old_irq+2], 0c000h
    jb .unowned
    jmp .eoi
.output16:
    mov dx, [sb_base]
    add dx, 0fh
    call physical_read
.acknowledged:
%ifdef RESIDENT_AUDIO
    call sb_patch
%endif
%ifdef MOUNTED_AUDIO
    ; The DMA position gives the period that plays, also after a late IRQ.
    call output_clock
    shr eax, OUTPUT_SHIFT
    mov [periods], eax
%else
    inc dword [periods]
%endif
    call mix_catch_up
%ifdef VIRTUAL_IRQ
%ifdef RESIDENT_AUDIO
    mov eax, [sb_hold_until]
    test eax, eax
    jz .tick
    ; An interrupt inside the start write, or pending when it returned, comes
    ; before the deadline. A later one can signal.
    cmp eax, 1
    je .ticked
    mov ecx, [periods]
    shl ecx, OUTPUT_SHIFT
    sub eax, ecx
    jg .ticked
    mov dword [sb_hold_until], 0
.tick:
%endif
    call virtual_irq_tick
%ifdef RESIDENT_AUDIO
.ticked:
%endif
%ifdef OWN_HOST
    mov byte [cd_refill_pending], 0
    cmp byte [cd_started], 1
    jne .refill_ready
    cmp byte [cd_error], 0
    jne .refill_ready
    cmp dword [cd_remaining], 0
    je .refill_ready
    mov byte [cd_refill_pending], 1
    mov eax, [cd_produced]
    sub eax, [cd_consumed]
%ifdef UCDD_DIAG
    ; The low-water mark starts when the first data has arrived.
    cmp dword [cd_produced], 0
    je .queue_seen
    mov edx, eax
    not edx
    cmp edx, [diag_queue_low]
    jbe .queue_seen
    mov [diag_queue_low], edx
.queue_seen:
%endif
    cmp eax, CD_REFILL_URGENT
    jae .refill_ready
    mov byte [cd_refill_pending], 2
.refill_ready:
    ; The host refills in protected mode. A live client that stays in real
    ; mode starves it, and this IRQ then refills. Without a client only a
    ; stopped timer starts a refill.
    cmp byte [cd_refill_pending], 0
    je .host_idle
    call cd_client_live
    je .host_wait
.host_idle:
    mov word [cd_host_missed], 0
    ; Without a live client an urgent queue refills from this IRQ.
    cmp byte [cd_refill_pending], 2
    jne .host_checked
    mov byte [cd_irq_refill], 1
    jmp .host_checked
.host_wait:
    cmp word [cd_host_missed], CD_HOST_STARVED
    jae .host_starved
    inc word [cd_host_missed]
    jmp .host_checked
.host_starved:
    mov byte [cd_irq_refill], 1
.host_checked:
    cmp word [cd_timer_missed], CD_TIMER_STARVED
    jae .timer_starved
    inc word [cd_timer_missed]
    jmp .timer_checked
.timer_starved:
    cmp byte [cd_refill_pending], 2
    jne .timer_checked
    mov byte [cd_irq_refill], 1
.timer_checked:
%endif
%endif
.eoi:
%ifdef VIRTUAL_IRQ
    ; A request that came after the status read shows now.
    cmp byte [sound_card], 0
    jne .eoi_status
    call card_irq_status
    and al, [card_irq_mask]
    test al, 4
    jz .eoi_status
    call virtual_mpu_raise
.eoi_status:
%endif
    mov al, [sb_irq]
    or al, 60h
    mov dx, 20h
    call physical_write
%ifdef OWN_HOST
    call sb_real_irq
    call host_real_pending
%endif
    cli
    call audio_irq_unmask
    mov byte [audio_irq_busy], 0
    pop fs
    pop es
    popad
    mov ss, [irq_ss]
    mov sp, [irq_sp]
    pop ax
    pop ds
%ifdef OWN_HOST
    cmp word [cs:host_pending_irqs], 0
    jne host_pending_tail
.tail:
    cmp byte [cs:sb_real_pending], 0
    jne .real_tail
    cmp byte [cs:cd_irq_refill], 0
    jne .refill_tail
%endif
    iret
%ifdef OWN_HOST
.real_tail:
    mov byte [cs:sb_real_pending], 0
    jmp far [cs:sb_real_vector]
.refill_tail:
    ; This IRQ's return frame becomes the refill's frame.
    mov byte [cs:cd_irq_refill], 0
    mov byte [cs:cd_irq_entry], 1
    jmp cd_timer_refill
%endif
.pro:
    cmp byte [pro_priming], 0
    je .pro_audio
    mov byte [pro_priming], 0
    mov dx, [sb_base]
    add dx, 0eh
    call physical_read
    jmp .eoi
.pro_audio:
    ; The chip sends no more IRQs until 2xEh is read. Read it also when the
    ; clock does not claim the IRQ: one that is late by RING_PERIODS-1 or
    ; more periods finds the DMA in the slot of [periods].
    mov dx, [sb_base]
    add dx, 0eh
    call physical_read
%ifdef MOUNTED_AUDIO
    call output_clock
    shr eax, OUTPUT_SHIFT
    cmp eax, [periods]
    je .unowned
%endif
    cmp byte [sound_card], 3
    jne .acknowledged
    call sb_mono_next
    jmp .acknowledged
.wss:
    cmp byte [ess_native], 0
    jne .ess
    mov dx, [sb_base]
    add dx, 6
    call physical_read
    test al, 1
    jz .unowned
    xor al, al
    call physical_write
    jmp .acknowledged
.ess:
    ; Bit 0 of 2xCh: the DMA counter overflowed. The 2xEh read clears it.
    ; An IRQ that comes before the DMA position passes the period boundary
    ; must still be acknowledged, or the chip sends no more IRQs.
    mov dx, [sb_base]
    add dx, 0ch
    call physical_read
    test al, 1
    jz .pro_audio
    mov dx, [sb_base]
    add dx, 0eh
    call physical_read
    jmp .acknowledged
.unowned:
    DIAG_INC diag_spurious
    cli
    call audio_irq_unmask
    mov byte [audio_irq_busy], 0
    pop fs
    pop es
    popad
    mov ss, [irq_ss]
    mov sp, [irq_sp]
    pop ax
    pop ds
%ifdef VIRTUAL_IRQ
    pushf
    call far [cs:old_irq]
    ; The guest does not see this IRQ in service. End it if its handler did not.
    push ds
    push ax
    push dx
    mov ax, cs
    mov ds, ax
    call physical_pic_isr
    test al, [physical_irq_bit]
    jz .ended
    mov al, [sb_irq]
    or al, 60h
    ; DX=20h after physical_pic_isr.
    call physical_write
.ended:
    pop dx
    pop ax
    pop ds
    iret
%else
    jmp far [cs:old_irq]
%endif

audio_irq.nested:
    pop ax
    pop ds
    jmp far [cs:old_irq]

audio_irq_mask:
    mov dx, 21h
    call physical_read
    mov [audio_irq_old_mask], al
    mov cl, [sb_irq]
    mov ah, 1
    shl ah, cl
    mov [audio_irq_mask_bit], ah
    or al, ah
    call physical_write
    ret

audio_irq_unmask:
    mov dx, 21h
    call physical_read
    mov ah, [audio_irq_mask_bit]
    not ah
    and al, ah
    mov ah, [audio_irq_old_mask]
    and ah, [audio_irq_mask_bit]
    or al, ah
    mov byte [audio_irq_mask_bit], 0
    call physical_write
    ret

; Mix every period from mix_period to the last one the ring holds ahead of
; the period that plays. Periods the DMA passed before their mix are lost.
mix_catch_up:
    mov eax, [periods]
    cmp [mix_period], eax
    ja .ahead
    inc eax
    mov [mix_period], eax
.ahead:
    mov eax, [periods]
    add eax, RING_PERIODS
    cmp [mix_period], eax
    jae .done
    call mix_next
    jmp .ahead
.done:
    ret

; Mix period mix_period into its ring slot.
mix_next:
    mov eax, [mix_period]
    shl eax, OUTPUT_SHIFT
    call ring_offset
    mov di, ax
    mov es, [output_segment]
    call mix_half
    inc dword [mix_period]
    ret

; Mix the whole ring before the output starts.
mix_fill:
    mov dword [periods], 0
    mov dword [mix_period], 0
.next:
    call mix_next
    cmp dword [mix_period], RING_PERIODS
    jb .next
    ret

; EAX: an output frame. Returns AX: its byte offset in the output ring.
ring_offset:
    push edx
    push ecx
    xor edx, edx
    mov ecx, RING_FRAMES
    div ecx
    mov eax, edx
    shl ax, 2
    cmp byte [ess_half], 0
    je .full
    ; Half rate: a stored frame is two mixed frames.
    shr ax, 1
    and ax, 0fffch
    jmp .done
.full:
    test byte [sound_card], 1
    jz .done
    shr ax, 2
    and ax, 0fffeh
    cmp byte [sound_card], 3
    jne .done
    shr ax, 1
.done:
    pop ecx
    pop edx
    ret

; AX: a block of two ring sizes. Returns AX: the ring segment, which does not
; cross a 64 KiB page, and DX: the other ring size.
ring_place:
    mov cx, RING_PARAS
    cmp byte [sound_card], 3
    jne .pro
    shr cx, 1
.pro:
    test byte [sound_card], 1
    jz .half
    shr cx, 2
.half:
    cmp byte [ess_half], 0
    je .size_ready
    shr cx, 1
.size_ready:
    mov dx, ax
    add dx, cx
    mov bx, ax
    and bx, 0fffh
    add bx, cx
    cmp bx, 1000h
    jbe .done
    xchg ax, dx
.done:
    ret

; Mixer 82h: the sources on the SB16 line.
card_irq_status:
    mov dx, [sb_base]
    add dx, 4
    mov al, 82h
    call physical_write
    inc dx
    jmp physical_read

card_irq_mask db 0ffh
audio_irq_old_mask db 0
old_irq dd 0
dma_pages db 8bh,89h,8ah
dma_channel db 1
dma_page_port dw 8bh
dma_address_port dw 0c4h
dma_count_port dw 0c6h
irq_ss dw 0
irq_sp dw 0
mix_period dd 0
periods dd 0
saved_pic db 0
sb_running db 0
dsp_failed db 0
mixer_registers db 34h,35h,30h,31h,32h,33h
mixer_saved times 6 db 0

%include "audio/wss_output.asm"
%include "audio/ess_output.asm"
%ifndef RESIDENT_AUDIO
%include "audio/ess_install.asm"
%endif
%include "audio/pro_output.asm"
; Word pushes on an odd stack are misaligned: keep the IRQ stack aligned.
    align 4
times 1024 db 0
irq_stack_top:
