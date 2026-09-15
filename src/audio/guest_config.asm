; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

guest_configure:
    push es
    mov es, [resident_psp]
    mov ax, [es:2ch]
    test ax, ax
    jz .ready
    mov es, ax
    xor si, si
.variable:
    cmp si, 0fff0h
    jae .bad
    cmp byte [es:si], 0
    je .ready
    cmp dword [es:si], 'BLAS'
    jne .skip
    cmp dword [es:si+4], 'TER='
    je .found
.skip:
    inc si
    jz .bad
    cmp byte [es:si-1], 0
    jne .skip
    jmp .variable
.found:
    add si, 8
    xor bp, bp
.token:
    mov dl, [es:si]
    inc si
    jz .bad
    test dl, dl
    jz .complete
    cmp dl, ' '
    je .token
    cmp dl, 9
    je .token
    and dl, 0dfh
    mov ebx, 10
    mov di, guest_irq
    mov dh, 2
    cmp dl, 'I'
    je .number
    mov di, guest_dma8
    mov dh, 4
    cmp dl, 'D'
    je .number
    mov di, guest_dma16
    mov dh, 8
    cmp dl, 'H'
    je .number
    mov di, guest_base
    mov dh, 1
    cmp dl, 'A'
    jne .ignore
    mov ebx, 16
.number:
    movzx ax, dh
    test bp, ax
    jnz .bad
    or bp, ax
    xor eax, eax
    mov cl, [es:si]
    cmp cl, ' '
    je .bad
    cmp cl, 9
    je .bad
    test cl, cl
    jz .bad
.digit:
    movzx ecx, byte [es:si]
    test cl, cl
    jz .value
    cmp cl, ' '
    je .value
    cmp cl, 9
    je .value
    cmp cl, '0'
    jb .bad
    cmp cl, '9'
    jbe .decimal_digit
    and cl, 0dfh
    cmp cl, 'A'
    jb .bad
    cmp cl, 'F'
    ja .bad
    sub cl, 'A'-10
    jmp .valid_digit
.decimal_digit:
    sub cl, '0'
.valid_digit:
    cmp ecx, ebx
    jae .bad
    imul eax, ebx
    add eax, ecx
    cmp eax, 65535
    ja .bad
    inc si
    jz .bad
    jmp .digit
.value:
    mov [di], ax
    jmp .token
.ignore:
    mov al, [es:si]
    test al, al
    jz .token
    cmp al, ' '
    je .token
    cmp al, 9
    je .token
    inc si
    jz .bad
    jmp .ignore
.complete:
    and bp, 7
    cmp bp, 7
    jne .bad
    mov ax, [guest_base]
    sub ax, 220h
    test ax, 0ff9fh
    jnz .bad
    cmp word [guest_irq], 5
    je .dma
    cmp word [guest_irq], 7
    jne .bad
.dma:
    cmp word [guest_dma8], 1
    je .high
    cmp word [guest_dma8], 3
    jne .bad
.high:
    cmp word [guest_dma16], 5
    jb .bad
    cmp word [guest_dma16], 7
    ja .bad
.ready:
    pop es
    call guest_ports_init
    clc
    ret
.bad:
    pop es
    mov word [audio_error_text], guest_config_message
    stc
    ret

guest_ports_init:
    mov si, guest_dma_ports
    mov cx, 6
.dma_port:
    lodsw
    call guest_port_translate
    mov [si-2], ax
    loop .dma_port
    mov si, trap_ports
.port:
    lodsw
    test ax, ax
    jz .emm
    call guest_port_translate
    mov [si-2], ax
    jmp .port
.emm:
    mov si, host_emm_ports_full
    mov cx, host_emm_full_count+host_emm_high_count
.emm_port:
    mov ax, [si]
    call guest_port_translate
    mov [si], ax
    add si, 4
    loop .emm_port
%ifndef OWN_HOST
    mov si, pm_trap_ports
    mov cx, pm_port_count
.pm_port:
    mov ax, [si]
    call guest_port_translate
    mov [si], ax
    add si, 4
    loop .pm_port
%endif
    mov al, [guest_irq]
    add al, 8
    mov [guest_vector], al
    mov cl, [guest_irq]
    mov al, 1
    shl al, cl
    mov [guest_irq_bit], al
    mov ah, al
    dec ah
    mov [guest_irq_higher], ah
    or ah, al
    mov [guest_irq_priority], ah
    mov al, [guest_irq]
    or al, 60h
    mov [guest_eoi], al
    mov al, 2
    cmp byte [guest_irq], 5
    je .mixer_irq
    mov al, 4
.mixer_irq:
    mov [virtual_mixer+80h], al
    mov cl, [guest_dma8]
    mov al, 1
    shl al, cl
    mov cl, [guest_dma16]
    mov ah, 1
    shl ah, cl
    or al, ah
    mov [virtual_mixer+81h], al
    ret

; AX is a default trap port. Return the selected guest port.
guest_port_translate:
    cmp ax, 224h
    jb .dma
    cmp ax, 22fh
    ja .done
    sub ax, 220h
    add ax, [guest_base]
    ret
.dma:
    cmp ax, 2
    je .low
    cmp ax, 3
    je .low
    cmp ax, 83h
    je .low_page
    cmp ax, 8bh
    je .high_page
    cmp ax, 0c4h
    je .high
    cmp ax, 0c6h
    jne .done
.high:
    mov bx, [guest_dma16]
    sub bx, 5
    shl bx, 2
    add ax, bx
    ret
.high_page:
    mov bx, [guest_dma16]
    mov al, [guest_dma_pages+bx]
    ret
.low_page:
    mov bx, [guest_dma8]
    mov al, [guest_dma_pages+bx]
    ret
.low:
    mov bx, [guest_dma8]
    dec bx
    shl bx, 1
    add ax, bx
.done:
    ret

guest_dma_pages db 87h,83h,81h,82h,8fh,8bh,89h,8ah
guest_config_message db 'BLASTER is not valid. Use A220 to A280 in steps of 20 (hex),',13,10
    db 'I5 or I7, D1 or D3, and H5 to H7. A, I, and D are required.',13,10,'$'
