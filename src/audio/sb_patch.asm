; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

sb_patch_initial:
    cmp byte [sb_patch_available], 0
    jne .done
    cmp dword [periods], 0
    je .done
    mov byte [sb_patch_available], 2
.done:
    ret

sb_patch:
    cmp byte [sb_patch_available], 0
    je .done
    cmp byte [sb_single], 0
    je .clear
    pushad
    push es
    pushf
    cli
    call output_clock
    add eax, 32
    cmp byte [sb_patch_available], 2
    je .initial
    mov byte [sb_patch_available], 0
    cmp eax, [sb_patch_clock]
    jae .restore
    mov eax, [sb_patch_clock]
    jmp .scheduled
.initial:
    mov byte [sb_patch_available], 0
    inc eax
    and al, 0feh
    mov edx, [mix_period]
    shl edx, OUTPUT_SHIFT
    cmp eax, edx
    jae .restore
    mov [sb_patch_clock], eax
    mov [sb_patch_limit], edx
.scheduled:
    mov [game_started], eax
    mov byte [game_start_pending], 2
    cmp eax, [sb_patch_limit]
    jae .restore
    call sb_remix
    cmp dword [sb_hold_until], 0
    jne .restore
    call virtual_irq_tick
.restore:
    popf
    pop es
    popad
    ret
.clear:
    mov byte [sb_patch_available], 0
.done:
    ret

; Mix [sb_patch_clock, sb_patch_limit) again. A frame f is at ring frame
; f mod RING_FRAMES. The new game part replaces the stored one.
sb_remix:
    mov eax, [sb_patch_limit]
    mov [sb_remix_end], eax
    call sb_filter_seed
.part:
    ; Each part ends at the ring wrap.
    mov eax, [sb_patch_clock]
    xor edx, edx
    mov ecx, RING_FRAMES
    div ecx
    sub ecx, edx
    add ecx, [sb_patch_clock]
    mov eax, ecx
    cmp eax, [sb_remix_end]
    jb .split
    mov eax, [sb_remix_end]
.split:
    mov [sb_patch_limit], eax
    mov eax, [sb_patch_clock]
    call ring_offset
    mov di, ax
    mov es, [output_segment]
    mov byte [sb_patch_active], 1
    call mix_half
    mov byte [sb_patch_active], 0
    mov eax, [sb_patch_limit]
    mov [sb_patch_clock], eax
    cmp eax, [sb_remix_end]
    jb .part
    ret

; The legacy filter of a remix starts at the stored output before it.
sb_filter_seed:
    cmp byte [sb_filter_legacy], 0
    je .done
    cmp word [sb_record_segment], 0
    je .done
    push es
    mov eax, [sb_patch_clock]
    dec eax
    call ring_offset
    mov si, ax
    mov es, [sb_record_segment]
%macro seed_channel 1
    movsx eax, word [es:si+%1/4]
    shl eax, 15
    cdq
    mov ecx, [mix_gain+%1/2]
    test ecx, ecx
    jz %%zero
    idiv ecx
    cmp eax, 32767
    jle %%low
    mov eax, 32767
%%low:
    cmp eax, -32767
    jge %%ready
    mov eax, -32767
    jmp %%ready
%%zero:
    xor eax, eax
%%ready:
    imul edx, eax, -7966
    mov [sb_filter_state+%1+4], edx
    imul eax, 15746
    mov [sb_filter_state+%1], eax
%endmacro
    seed_channel 0
    seed_channel 8
%unmacro seed_channel 1
    pop es
.done:
    ret

; ES:DI: start of an output period. Its stored game part becomes zero.
sb_record_clear:
    cmp word [sb_record_segment], 0
    je .done
    pushad
    push es
    call sb_record_bit
    or [sb_record_halves], al
    mov es, [sb_record_segment]
    mov cx, PERIOD_BYTES/2
    xor ax, ax
    rep stosw
    pop es
    popad
.done:
    ret

; ES:DI: an output period mixed without stored game parts.
sb_record_lost:
    push ax
    call sb_record_bit
    not al
    and [sb_record_halves], al
    pop ax
    ret

; DI: the ring offset of an output period. Returns AL: its bit.
sb_record_bit:
    push cx
    mov cx, di
    shr cx, OUTPUT_SHIFT+2
    mov al, 1
    shl al, cl
    pop cx
    ret

; EAX: game part of the word at ES:DI. Returns EAX minus the stored part
; and stores EAX.
sb_record_word:
    cmp word [sb_record_segment], 0
    je .done
    push es
    push si
    push edx
    mov si, di
    mov es, [sb_record_segment]
    movsx edx, word [es:si]
    mov [es:si], ax
    sub eax, edx
    pop edx
    pop si
    pop es
.done:
    ret

; SI: DMA channel whose address changed. AL: 1 if the frames already mixed can
; be mixed again. A game that moves the address of a running auto-init
; transfer at each block end (Savage Warriors) plays its next block from the
; new buffer.
sb_dma_switch:
    cmp si, [game_dma]
    jne .done
    cmp byte [game_active], 0
    je .done
    cmp byte [game_start_pending], 0
    jne .done
    cmp byte [sb_single], 0
    jne .done
    cmp byte [game_source], 0
    jne .done
    cmp byte [sb_input], 0
    jne .done
    cmp byte [game_adpcm], 0
    jne .done
    cmp dword [game_limit], 0
    je .done
%ifdef OWN_HOST
    cmp dword [game_physical], 0
    jne .done
%endif
    pushad
    push es
    pushf
    cli
    mov [sb_switch_remix], al
    ; The new buffer has the same size and is below 1 MiB.
    movzx ebx, word [si+DMA_COUNT]
    inc ebx
    movzx eax, word [si+DMA_ADDRESS]
    movzx ecx, byte [si+DMA_PAGE]
    cmp si, dma16
    jne .units
    shl ebx, 1
    shl eax, 1
    and cl, 0feh
.units:
    shl ecx, 16
    add ecx, eax
    mov eax, [game_limit]
    shr eax, 16
    mov dl, cl
    mov cl, [game_frame_shift]
    shl eax, cl
    mov cl, dl
    cmp eax, ebx
    jne .restore
    lea eax, [ebx+ecx]
    cmp eax, 100000h
    ja .restore
    call dma_source_split
    cmp cx, [game_segment]
    jne .moved
    cmp bx, [game_offset]
    je .restore
.moved:
    ; With the old block end in the tail copy, the ring wrap reads the new buffer.
    cmp byte [sb_tail_valid], 0
    je .wrap
    call .switch
    jmp .restore
.wrap:
    ; Else the ring wrap must be in the frames mixed ahead.
    mov edi, [mix_period]
    shl edi, OUTPUT_SHIFT
    lea eax, [edi-1]
    sub eax, [game_started]
    mul dword [game_step]
    add eax, [game_origin]
    adc edx, 0
    div dword [game_limit]
    mov eax, edx
    xor edx, edx
    div dword [game_step]
    cmp eax, RING_FRAMES
    jae .restore
    call .switch
    cmp byte [sb_switch_remix], 0
    je .restore
    cmp word [sb_record_segment], 0
    je .restore
    neg eax
    lea eax, [edi+eax-1]
    mov [sb_patch_clock], eax
    mov [sb_patch_limit], edi
    call output_clock
    add eax, 32
    cmp eax, [sb_patch_clock]
    jae .start
    mov eax, [sb_patch_clock]
.start:
    cmp eax, edi
    jae .restore
    mov [sb_patch_clock], eax
    ; Every period of the frames needs stored game parts.
    mov ecx, eax
    shr ecx, OUTPUT_SHIFT
    mov ebx, edi
    dec ebx
    shr ebx, OUTPUT_SHIFT
.recorded:
    mov eax, ecx
    shl eax, OUTPUT_SHIFT
    push di
    call ring_offset
    mov di, ax
    call sb_record_bit
    pop di
    test [sb_record_halves], al
    jz .restore
    inc ecx
    cmp ecx, ebx
    jbe .recorded
    call sb_remix
.restore:
    popf
    pop es
    popad
.done:
    ret
.switch:
    mov [game_segment], cx
    mov [game_offset], bx
    ret
sb_switch_remix db 0

%ifdef OWN_HOST
sb_real_irq:
    cmp word [own_host_active+2], 0
    je .done
    les di, [own_host_active]
    cmp byte [es:di], 2
    je .done
    cmp byte [es:di], 0
    je .take
    cmp byte [es:di+1], 0
    jne .protected
.take:
    push cs
    call virtual_irq_take
    test ax, ax
    jz .done
    call virtual_irq_deliver
    xor ax, ax
    mov es, ax
    movzx bx, byte [guest_vector]
    shl bx, 2
    mov eax, [es:bx]
    mov bl, [guest_irq]
    cmp [sb_irq], bl
    jne .vector
    cmp ax, audio_irq
    jne .direct_vector
    mov edx, eax
    shr edx, 16
    mov bx, cs
    cmp dx, bx
    je .saved_vector
.direct_vector:
    cmp dword [host_irq_slot], 0
    jne .vector
.saved_vector:
    mov eax, [sb_game_vector]
.vector:
    mov [sb_real_vector], eax
    mov byte [sb_real_pending], 1
.done:
    ret
; A client's real-mode call was interrupted. Its protected-mode handler gets
; the IRQ through the host bridge. The host delivers the IRQs it reflects.
.protected:
    push ds
    mov bx, [irq_sp]
    mov ds, [irq_ss]
    mov ax, es
    cmp [bx+6], ax
    pop ds
    je .done
    ; Without the JEMMEX IRQ slot, host calls show the mixer in the vector. A
    ; real-mode handler written directly to the vector then gets the IRQ there.
    cmp dword [host_irq_slot], 0
    jne .bridge
    push es
    xor ax, ax
    mov es, ax
    movzx bx, byte [guest_vector]
    shl bx, 2
    mov ax, [es:bx+2]
    pop es
    mov bx, cs
    cmp ax, bx
    je .bridge
    mov bx, es
    cmp ax, bx
    jne .take
.bridge:
    push cs
    call virtual_irq_take
    test ax, ax
    jz .done
    mov ax, [es:di+2]
    mov [sb_real_vector], ax
    mov [sb_real_vector+2], es
    mov byte [sb_real_pending], 1
    ret
sb_real_vector dd 0
sb_real_pending db 0

; Physical IRQs that arrived in protected mode and have no protected-mode
; handler. The real chain gets them when this IRQ ends.
host_real_pending:
    cmp word [own_host_active+2], 0
    je .done
    les di, [own_host_active]
    cmp byte [es:di], 1
    jne .done
    ; The interrupted code must accept IRQs.
    push ds
    mov bx, [irq_sp]
    mov ds, [irq_ss]
    test byte [bx+9], 2
    pop ds
    jz .done
    mov ax, [es:di+6]
    test ax, ax
    jz .done
    mov [host_pending_entry], ax
    mov [host_pending_entry+2], es
    call physical_pic_isr
    call far [host_pending_entry]
    or [host_pending_irqs], ax
.done:
    ret

; IF is clear. Stack: the interrupted IRQ frame.
host_pending_tail:
    push ax
    push bx
    push ds
    xor ax, ax
    xchg ax, [cs:host_pending_irqs]
.next:
    bsf bx, ax
    jz .done
    btr ax, bx
    push ax
    add bx, 8
    cmp bx, 16
    jb .vector
    add bx, 70h-16
.vector:
    shl bx, 2
    xor ax, ax
    mov ds, ax
    pushf
    call far [bx]
    cli
    pop ax
    jmp .next
.done:
    pop ds
    pop bx
    pop ax
    jmp audio_irq.tail
host_pending_entry dd 0
host_pending_irqs dw 0

sb_dos_vector:
    cmp al, [cs:guest_vector]
    jne .chain
    ; While the driver has stepped aside the vector is DOS's to give and
    ; take: audio_release and audio_engage move it through INT 21h with this
    ; byte clear, and a game on the real card installs its own handler.
    cmp byte [cs:audio_engaged], 0
    je .chain
    cmp dword [cs:host_irq_slot], 0
    je .saved
    push ax
    push bx
    push es
    xor bx, bx
    mov es, bx
    mov bl, al
    shl bx, 2
    mov ax, cs
    cmp word [es:bx], audio_irq
    jne .direct
    cmp [es:bx+2], ax
    jne .direct
    pop es
    pop bx
    pop ax
.saved:
    cmp ah, 35h
    je .get
    cmp ah, 25h
    jne .chain
    mov [cs:sb_game_vector], dx
    mov [cs:sb_game_vector+2], ds
    iret
.get:
    les bx, [cs:sb_game_vector]
    iret
.chain:
    jmp far [cs:sb_old_dos]
.direct:
    pop es
    pop bx
    pop ax
    jmp .chain

sb_game_vector dd 0
sb_host_guest_irq dw guest_irq
sb_host_ports dw trap_ports
%ifdef UCDD_DIAG
    dd 35464443h
%else
    dd 34464443h
%endif
    dw cd_deferred_refill, cd_refill_pending, virtual_pic_request, last_clock
    dw host_info, host_jemm_version
%ifdef UCDD_DIAG
    dw diag_host, cd_bios_busy
%else
    dw 0, 0
%endif
%ifdef OWN_HOST
    dw virtual_irq_due_far
    ; The disk IRQs that go straight to the real-mode handler.
    dw config_disk_mask
%endif
sb_old_dos dd 0
%endif
