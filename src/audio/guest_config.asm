; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; UCDDSET checked the virtual card and the volumes in config_data.
guest_configure:
    mov ax, [virtual_base]
    mov [guest_base], ax
    movzx ax, byte [virtual_irq]
    mov [guest_irq], ax
    mov al, [virtual_dma8]
    mov [guest_dma8], ax
    mov al, [virtual_dma16]
    mov [guest_dma16], ax
    ; A game can still select another IRQ in the WSS board register.
    mov al, [virtual_wss_irq]
    mov [wss_guest_irq], ax
    call sb_pcm_update
    call cd_gain_update
    call guest_ports_init
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
    jz .ports_done
    call guest_port_translate
    mov [si-2], ax
    jmp .port
.ports_done:
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
    ja .wss
    sub ax, 220h
    add ax, [guest_base]
    ret
.wss:
    cmp ax, 530h
    jb .done
    cmp ax, 537h
    ja .done
    sub ax, 530h
    add ax, [virtual_wss_base]
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
