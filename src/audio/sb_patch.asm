; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

sb_patch:
    cmp byte [sb_patch_available], 0
    je .done
    mov byte [sb_patch_available], 0
    cmp byte [sb_single], 0
    je .done
    pushad
    push es
    pushf
    cli
    call output_clock
    add eax, 32
    cmp eax, [sb_patch_clock]
    jae .restore
    mov eax, [sb_patch_clock]
    mov [game_started], eax
    mov byte [game_start_pending], 2
    cmp eax, [sb_patch_limit]
    jae .restore
    and ax, PERIOD_FRAMES-1
    shl ax, 2
    test byte [sound_card], 1
    jz .offset
    shr ax, 2
    and ax, 0fffeh
    cmp byte [sound_card], 3
    jne .offset
    shr ax, 1
.offset:
    add ax, [sb_patch_base]
    mov di, ax
    mov es, [output_segment]
    mov byte [sb_patch_active], 1
    call mix_half
    mov byte [sb_patch_active], 0
    call virtual_irq_tick
.restore:
    popf
    pop es
    popad
.done:
    ret

%ifdef OWN_HOST
sb_real_irq:
    cmp word [own_host_active+2], 0
    je .done
    les di, [own_host_active]
    cmp byte [es:di], 0
    je .take
    cmp byte [es:di+1], 0
    jne .done
.take:
    push cs
    call virtual_irq_take
    test ax, ax
    jz .done
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
sb_real_vector dd 0
sb_real_pending db 0

sb_dos_vector:
    cmp al, [cs:guest_vector]
    jne .chain
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
    dd 33464443h
    dw cd_deferred_refill, cd_refill_pending, virtual_pic_request, last_clock
sb_old_dos dd 0
%endif
