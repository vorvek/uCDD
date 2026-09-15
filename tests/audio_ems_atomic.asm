; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h
    jmp start
%include "ems.inc"
start:
    mov ax, 3567h
    int 21h
    mov [old_ems], bx
    mov [old_ems+2], es
    mov dx, fake_ems
    mov ax, 2567h
    int 21h
    mov [cd_work_segment], cs
    mov [cd_half_segment], cs
    mov ax, cs
    add ax, (frame-$$+100h)/16
    mov [cd_ems_frame], ax
    sti
    call cd_ems_write
    pushf
    pop dx
    test dh, 2
    jz fail
    cmp byte [probe_seen], 0
    je fail
%ifdef EMS_ERROR_TEST
    test ax, ax
    jnz fail
%else
    cmp ax, 1
    jne fail
    push cs
    pop es
    mov si, stage
    mov di, frame
    mov cx, 64
    repe cmpsb
    jne fail
%endif
    cli
    call cd_ems_write
    pushf
    pop dx
    test dh, 2
    jnz fail
    xor bl, bl
    jmp finish
fail:
    mov bl, 1
finish:
    sti
    push bx
    lds dx, [old_ems]
    mov ax, 2567h
    int 21h
    pop bx
    mov al, bl
    mov ah, 4ch
    int 21h

irq_probe:
    pushf
    pushad
    mov byte [cs:probe_seen], 1
    cmp byte [cs:in_irq], 0
    jne .done
    pushf
    pop ax
    test ah, 2
    jz .done
    cli
    mov byte [cs:in_irq], 1
    call cd_ems_read
    mov byte [cs:in_irq], 0
.done:
    popad
    popf
    ret
fake_ems:
%ifdef EMS_ERROR_TEST
    cmp byte [cs:in_irq], 0
    jne .ok
    mov ah, 80h
    iret
.ok:
%endif
    xor ah, ah
    iret

old_ems dd 0
probe_seen db 0
in_irq db 0
cd_write_offset dd 0
cd_write_move dd 64
cd_write_address dw stage,0
cd_read_offset dd 8192
cd_read_move dd 16
cd_read_address dw half,0
cd_work_segment dw 0
cd_half_segment dw 0
cd_ems_handle dw 1
cd_ems_frame dw 0
cd_ems_offset dd 0
cd_ems_remaining dw 0
cd_ems_buffer dw 0
cd_ems_direction db 0
cd_ems_saved db 0
cd_ems_error db 0
stage times 64 db 5ah
half times 64 db 0
align 16
frame times 16384 db 77h
