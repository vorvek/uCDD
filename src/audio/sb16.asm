; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%include "audio/sb_state.inc"

; Configuration selects the physical card resources.
physical_read:
%ifdef DIRECT_OUTPUT
    in al, dx
%else
%ifdef RESIDENT_AUDIO
    cmp byte [host_backend], 2
    jne .api
    cmp byte [emm_in_callback], 0
    je .api
    inc byte [emm_bypass]
    in al, dx
    dec byte [emm_bypass]
    ret
.api:
%endif
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
%ifdef RESIDENT_AUDIO
    cmp byte [host_backend], 2
    jne .api
    cmp byte [emm_in_callback], 0
    je .api
    inc byte [emm_bypass]
    out dx, al
    dec byte [emm_bypass]
    ret
.api:
%endif
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
    mov byte [fault], 4
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
    mov byte [dsp_failed], 0
    mov dx, [sb_base]
    add dx, 6
    mov al, 1
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
    mov dx, [sb_base]
    add dx, 4
    mov al, 80h
    call physical_write
    inc dx
    call physical_read
    mov [saved_irq], al
    mov al, 2
    cmp byte [sb_irq], 5
    je .irq_value
    mov al, 4
.irq_value:
    call physical_write
    dec dx
    mov al, 81h
    call physical_write
    inc dx
    call physical_read
    mov [saved_dma], al
    mov cl, [sb_dma8]
    mov al, 1
    shl al, cl
    mov ah, al
    mov cl, [sb_dma16]
    mov al, 1
    shl al, cl
    or al, ah
    call physical_write
    mov si, mixer_registers
    mov di, mixer_saved
    mov cx, 4
.mixer:
    mov dx, [sb_base]
    add dx, 4
    lodsb
    call physical_write
    inc dx
    call physical_read
    mov [di], al
    inc di
    mov al, 0f8h
    call physical_write
    loop .mixer
    mov al, [sb_irq]
    add al, 8
    mov ah, 35h
    int 21h
    mov [old_irq], bx
    mov [old_irq+2], es
    mov dx, audio_irq
    mov al, [sb_irq]
    add al, 8
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
    call physical_write
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
    mov al, [saved_pic]
    mov dx, 21h
    call physical_write
    push ds
    mov al, [sb_irq]
    add al, 8
    lds dx, [old_irq]
    mov ah, 25h
    int 21h
    pop ds
    mov si, mixer_registers
    mov di, mixer_saved
    mov cx, 4
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
    mov dx, [sb_base]
    add dx, 4
    mov al, 80h
    call physical_write
    inc dx
    mov al, [saved_irq]
    call physical_write
    dec dx
    mov al, 81h
    call physical_write
    inc dx
    mov al, [saved_dma]
    call physical_write
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
    ; A reflected game IRQ must not advance the physical output buffer.
    mov dx, [sb_base]
    add dx, 4
    mov al, 82h
    call physical_write
    inc dx
    call physical_read
    test al, 2
    jz .unowned
    mov dx, [sb_base]
    add dx, 0fh
    call physical_read
.acknowledged:
%ifdef RESIDENT_AUDIO
    call sb_patch
%endif
    inc dword [periods]
%ifdef MOUNTED_AUDIO
    call output_clock
    shr eax, OUTPUT_SHIFT
    mov [periods], eax
    and ax, 1
    xor ax, 1
    shl ax, OUTPUT_SHIFT+2
    test byte [sound_card], 1
    jz .half_ready
    shr ax, 2
    cmp byte [sound_card], 3
    jne .half_ready
    shr ax, 1
.half_ready:
    mov [next_half], ax
%endif
    mov es, [output_segment]
    mov di, [next_half]
%ifdef RESIDENT_AUDIO
    mov [sb_patch_base], di
%endif
    mov ax, PERIOD_BYTES
    test byte [sound_card], 1
    jz .half_size
    shr ax, 2
    cmp byte [sound_card], 3
    jne .half_size
    shr ax, 1
.half_size:
    xor [next_half], ax
    call mix_half
%ifdef VIRTUAL_IRQ
    call virtual_irq_tick
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
    cmp eax, CD_REFILL_URGENT
    jae .refill_ready
    mov byte [cd_refill_pending], 2
.refill_ready:
%endif
%endif
.eoi:
    mov al, 20h
    mov dx, 20h
    call physical_write
%ifdef OWN_HOST
    call sb_real_irq
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
    cmp byte [cs:sb_real_pending], 0
    jne .real_tail
%endif
    iret
%ifdef OWN_HOST
.real_tail:
    mov byte [cs:sb_real_pending], 0
    jmp far [cs:sb_real_vector]
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
%ifdef MOUNTED_AUDIO
    call output_clock
    shr eax, OUTPUT_SHIFT
    cmp eax, [periods]
    je .unowned
%endif
    mov dx, [sb_base]
    add dx, 0eh
    call physical_read
    cmp byte [sound_card], 3
    jne .acknowledged
    call sb_mono_next
    jmp .acknowledged
.wss:
    mov dx, [sb_base]
    add dx, 6
    call physical_read
    test al, 1
    jz .unowned
    xor al, al
    call physical_write
    jmp .acknowledged
.unowned:
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
    jmp far [cs:old_irq]

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

audio_irq_old_mask db 0
old_irq dd 0
dma_pages db 8bh,89h,8ah
dma_channel db 1
dma_page_port dw 8bh
dma_address_port dw 0c4h
dma_count_port dw 0c6h
irq_ss dw 0
irq_sp dw 0
next_half dw 0
periods dd 0
saved_pic db 0
saved_irq db 0
saved_dma db 0
sb_running db 0
dsp_failed db 0
mixer_registers db 30h,31h,32h,33h
mixer_saved times 4 db 0

%include "audio/wss_output.asm"
%include "audio/pro_output.asm"
times 1024 db 0
irq_stack_top:
