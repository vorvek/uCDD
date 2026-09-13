; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

virtual_client_install:
    mov byte [stage], 'G'
    mov bl, 0dh
    mov ax, 0204h
    int 31h
    jc failed
    mov [old_game_vector], edx
    mov [old_game_vector+4], cx
    mov cx, cs
    mov edx, game_irq
    mov ax, 0205h
    int 31h
    jc failed
    mov byte [virtual_vector_set], 1
    in al, 21h
    mov [client_pic_mask], al
    and al, 0dfh
    out 21h, al
    in al, 21h
    test al, 20h
    jnz failed
    ret

virtual_client_remove:
    cmp byte [virtual_vector_set], 0
    je .done
    mov al, [client_pic_mask]
    out 21h, al
    mov bl, 0dh
    mov cx, [old_game_vector+4]
    mov edx, [old_game_vector]
    mov ax, 0205h
    int 31h
    jnc .restored
    mov byte [cleanup_fault], 1
.restored:
    mov byte [virtual_vector_set], 0
.done:
    ret

virtual_client_wait:
    mov ebp, [game_interrupts]
    mov cx, 19
    call wait_ticks
    mov eax, [game_interrupts]
    sub eax, ebp
    cmp byte [event_fault], 0
    jne failed
    cmp byte [playing], 0
    je .idle
%ifdef NO_DELIVERY
    test eax, eax
    jnz failed
    cmp dword [owned_irqs], 8
    jb failed
    mov edx, missing_irq
    mov ah, 9
    int 21h
    jmp failed
%endif
    cmp word [client_rate], 11025
    je .slow
    cmp eax, 4
    jb failed
    cmp eax, 6
    ja failed
    ret
.slow:
    cmp eax, 1
    jb failed
    cmp eax, 3
    ja failed
    ret
.idle:
    test eax, eax
    jnz failed
    ret

wait_ticks:
    mov fs, [ticks_selector]
    mov si, [fs:6ch]
.wait:
%ifdef CD_IMAGE_TEST
%ifndef CD_STARVE
    call cd_poll
%else
    cmp byte [cd_polled], 0
    jne .no_poll
    call cd_poll
    mov byte [cd_polled], 1
.no_poll:
%endif
%endif
    mov ax, [fs:6ch]
    sub ax, si
    cmp ax, cx
    jb .wait
    ret

%ifdef CD_STARVE
cd_polled db 0
%endif

read_dsp_irq:
    mov dx, 224h
    mov al, 82h
    out dx, al
    inc dx
    in al, dx
%ifdef CLIENT_STEREO
    and al, 2
    shr al, 1
%else
    and al, 1
%endif
    ret

read_irr:
    mov al, 0ah
    out 20h, al
    in al, 20h
    and al, 20h
    ret

read_isr:
    mov al, 0bh
    out 20h, al
    in al, 20h
    and al, 20h
    ret

virtual_client_checks:
    mov byte [stage], 'H'
    in al, 21h
    or al, 20h
    out 21h, al
    in al, 21h
    test al, 20h
    jz failed
    mov ebp, [game_interrupts]
    mov cx, 6
    call wait_ticks
    cmp ebp, [game_interrupts]
    jne failed
    call read_dsp_irq
    cmp al, 1
    jne failed
    call read_irr
    cmp al, 20h
    jne failed
    call read_isr
    test al, al
    jnz failed

    mov byte [stage], 'I'
    in al, 21h
    and al, 0dfh
    out 21h, al
    mov cx, 6
    call wait_ticks
    cmp [game_interrupts], ebp
    jbe failed

    mov byte [stage], 'J'
    mov byte [hold_eoi], 1
    mov ebp, [game_interrupts]
    mov cx, 10
    call wait_ticks
    inc ebp
    cmp ebp, [game_interrupts]
    jne failed
    call read_isr
    cmp al, 20h
    jne failed
    call read_irr
    cmp al, 20h
    jne failed
    call read_dsp_irq
    cmp al, 1
    jne failed
    mov byte [hold_eoi], 0
    mov al, 65h
    out 20h, al
    mov cx, 6
    call wait_ticks
    cmp [game_interrupts], ebp
    jbe failed

    mov byte [stage], 'K'
    mov byte [hold_ack], 1
    mov ebp, [game_interrupts]
    mov cx, 10
    call wait_ticks
    inc ebp
    cmp ebp, [game_interrupts]
    jne failed
    call read_dsp_irq
    cmp al, 1
    jne failed
    call read_irr
    test al, al
    jnz failed
    call read_isr
    test al, al
    jnz failed
    mov dx, 22eh
    in al, dx
    mov byte [hold_ack], 0
    mov cx, 6
    call wait_ticks
    cmp [game_interrupts], ebp
    jbe failed

    mov byte [stage], 'L'
    in al, 21h
    or al, 20h
    out 21h, al
    mov ebp, [game_interrupts]
    mov cx, 6
    call wait_ticks
    call read_irr
    cmp al, 20h
    jne failed
    call reset
    call read_dsp_irq
    test al, al
    jnz failed
    call read_irr
    test al, al
    jnz failed
    in al, 21h
    and al, 0dfh
    out 21h, al
    mov cx, 6
    call wait_ticks
    cmp ebp, [game_interrupts]
    jne failed
    mov byte [stage], 'M'
    mov byte [hold_eoi], 1
    mov ax, 22050
    call play
    mov cx, 6
    call wait_ticks
    inc ebp
    cmp ebp, [game_interrupts]
    jne failed
    call reset
    call read_dsp_irq
    test al, al
    jnz failed
    call read_isr
    cmp al, 20h
    jne failed
    mov byte [hold_eoi], 0
    mov al, 65h
    out 20h, al
    call read_isr
    test al, al
    jnz failed
    mov cx, 6
    call wait_ticks
    cmp ebp, [game_interrupts]
    jne failed
    cmp byte [event_fault], 0
    jne failed
    ret

game_irq:
    pushad
    push ds
    mov ds, [cs:data_selector]
    inc dword [game_interrupts]
    call read_isr
    cmp al, 20h
    jne .error
    call read_dsp_irq
    cmp al, 1
    jne .error
    cmp byte [hold_ack], 0
    jne .eoi
%ifdef CLIENT_STEREO
    mov dx, 22eh
    in al, dx
    call read_dsp_irq
    cmp al, 1
    jne .error
%endif
    mov dx, CLIENT_DSP_ACK
    in al, dx
    call read_dsp_irq
    test al, al
    jnz .error
    call read_isr
    cmp al, 20h
    jne .error
.eoi:
    cmp byte [hold_eoi], 0
    jne .done
    mov al, 20h
    test byte [game_interrupts], 1
    jz .send_eoi
    mov al, 65h
.send_eoi:
    out 20h, al
    call read_isr
    test al, al
    jnz .error
.done:
%ifdef STREAM_TEST
    call stream_refill
%endif
    pop ds
    popad
    iretd
.error:
    mov byte [event_fault], 1
    mov dx, CLIENT_DSP_ACK
    in al, dx
    mov al, 65h
    out 20h, al
    jmp .done

old_game_vector dd 0
    dw 0
game_vector dd 0
    dw 0
virtual_vector_set db 0
client_pic_mask db 0
client_rate dw 0
game_interrupts dd 0
event_fault db 0
hold_eoi db 0
hold_ack db 0
%ifdef NO_DELIVERY
missing_irq db 'No virtual sound interrupt was received.',13,10,'$'
%endif
