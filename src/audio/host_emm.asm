; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

host_emm_ports_full:
    dw 002h, emm_port_callback
    dw 003h, emm_port_callback
    dw 00ah, emm_port_callback
    dw 00bh, emm_port_callback
    dw 00ch, emm_port_callback
    dw 00eh, emm_port_callback
    dw 020h, emm_port_callback
    dw 021h, emm_port_callback
    dw 083h, emm_port_callback
    dw 08bh, emm_port_callback
    dw 0c4h, emm_port_callback
    dw 0c6h, emm_port_callback
    dw 0d4h, emm_port_callback
    dw 0d6h, emm_port_callback
    dw 0d8h, emm_port_callback
    dw 0dch, emm_port_callback
    dw 224h, emm_port_callback
    dw 225h, emm_port_callback
    dw 226h, emm_port_callback
    dw 22ah, emm_port_callback
    dw 22ch, emm_port_callback
    dw 22eh, emm_port_callback
    dw 22fh, emm_port_callback
    dw 530h, emm_port_callback
    dw 531h, emm_port_callback
    dw 532h, emm_port_callback
    dw 533h, emm_port_callback
    dw 534h, emm_port_callback
    dw 535h, emm_port_callback
    dw 536h, emm_port_callback
    dw 537h, emm_port_callback
host_emm_full_count equ ($-host_emm_ports_full)/4

host_emm_ports_high:
    dw 224h, emm_port_callback
    dw 225h, emm_port_callback
    dw 226h, emm_port_callback
    dw 22ah, emm_port_callback
    dw 22ch, emm_port_callback
    dw 22eh, emm_port_callback
    dw 22fh, emm_port_callback
    dw 530h, emm_port_callback
    dw 531h, emm_port_callback
    dw 532h, emm_port_callback
    dw 533h, emm_port_callback
    dw 534h, emm_port_callback
    dw 535h, emm_port_callback
    dw 536h, emm_port_callback
    dw 537h, emm_port_callback
host_emm_high_count equ ($-host_emm_ports_high)/4

emm_port_callback:
    cmp byte [cs:emm_bypass], 0
    jne .physical
    cmp byte [cs:callback_set], 0
    je .physical
    test byte [cs:host_emm_caps], 2
    jz .dispatch
    test cl, 3
    jz .dispatch
    or cl, 8
.dispatch:
    jmp port_callback
.physical:
    stc
    retf

emm_qpi:
    cmp ax, 1a00h
    je .read
    cmp ax, 1a01h
    je .write
    cmp ax, 1a06h
    je .get
    cmp ax, 1a07h
    je .set
    cmp ax, 1a09h
    je .ok
    cmp ax, 1a0ah
    je .ok
    cmp ax, 1a0bh
    je .ok
    stc
    retf
.read:
    inc byte [emm_bypass]
    in al, dx
    dec byte [emm_bypass]
    mov bl, al
    jmp .ok
.write:
    inc byte [emm_bypass]
    mov al, bl
    out dx, al
    dec byte [emm_bypass]
    jmp .ok
.get:
    xor di, di
    mov es, di
    cmp byte [callback_set], 0
    je .ok
    mov di, port_callback
    push cs
    pop es
    jmp .ok
.set:
    mov ax, es
    or ax, di
    setnz byte [callback_set]
.ok:
    clc
    retf

host_emm_register:
    cmp byte [host_emm_active], 0
    jne .ok
    mov byte [host_emm_seen], 0
    mov word [host_emm_version], 0
    mov word [host_emm_min_port], 100h
    mov byte [host_emm_caps], 0
    mov ax, 4a15h
    mov bx, 3
    stc
    int 2fh
    jc .ports_ready
    mov byte [host_emm_seen], 1
    cmp ah, 1
    jb .ports_ready
    mov [host_emm_version], ax
    mov [host_emm_min_port], dx
    mov [host_emm_caps], bl
.ports_ready:
    mov ax, 4a15h
    xor bx, bx
    mov cx, host_emm_high_count
    mov si, host_emm_ports_high
    mov edx, 05370224h
    cmp word [host_emm_min_port], 2
    ja .install
    mov cx, host_emm_full_count
    mov si, host_emm_ports_full
    mov edx, 05370002h
.install:
    mov di, [units_base]
    add di, UNIT_SIZE
    stc
    int 2fh
    jc .failed
    mov [host_emm_handle], ax
    mov byte [host_emm_active], 1
.ok:
    clc
.done:
    ret
.failed:
    pushf
    cmp ax, 8000h
    jb .classified
    cmp ax, 800ch
    ja .classified
    mov byte [host_emm_seen], 1
.classified:
    popf
    ret

host_emm_unregister:
    cmp byte [host_emm_active], 0
    je .ok
    mov ax, 4a15h
    mov bx, 1
    mov si, [host_emm_handle]
    stc
    int 2fh
    jc .done
    mov byte [host_emm_active], 0
.ok:
    clc
.done:
    ret

host_client_traps:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push cs
    pop ds
    cmp byte [host_backend], 2
    jne .ok
    test al, al
    jnz .enable
    call host_emm_unregister
    jmp .done
.enable:
    call host_emm_register
    jnc .done
    mov byte [fault], 3
    stc
    jmp .done
.ok:
    clc
.done:
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    retf

host_emm_remove:
    call host_emm_unregister
    jc .done
    mov byte [host_installed], 0
    mov byte [host_backend], 0
.done:
    ret

host_emm_handle dw 0ffffh
host_emm_active db 0
host_emm_version dw 0
host_emm_min_port dw 100h
host_emm_caps db 0
host_emm_seen db 0
emm_bypass db 0
emm_in_callback db 0
