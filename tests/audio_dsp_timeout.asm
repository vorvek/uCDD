; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h
%include "audio/layout.inc"
%ifndef DSP_FAIL_AFTER
%define DSP_FAIL_AFTER 0
%endif
    jmp start
%include "audio/sb16.asm"

start:
    mov [qpi+2], cs
    mov ax, 350fh
    int 21h
    mov [expected_irq], bx
    mov [expected_irq+2], es
    call sb_start
    jnc failed
    cmp byte [sb_running], 0
    jne failed
    cmp word [dsp_writes], DSP_FAIL_AFTER
    jne failed
    mov ax, 350fh
    int 21h
    cmp bx, [expected_irq]
    jne failed
    mov ax, es
    cmp ax, [expected_irq+2]
    jne failed
    mov byte [busy_dsp], 0
    mov al, 0d1h
    call dsp_write
    jnc failed
    cmp word [dsp_writes], DSP_FAIL_AFTER
    jne failed
    call sb_start
    jc failed
    cmp byte [sb_running], 1
    jne failed
    call sb_stop
    cmp byte [sb_running], 0
    jne failed
    mov ax, 4c00h
    int 21h
failed:
    mov ax, 4c01h
    int 21h

port_api:
    cmp ax, 1a00h
    jne .write
    mov bl, 0
    cmp dx, 22ch
    jne .reset_status
    cmp byte [busy_dsp], 0
    je .done
    cmp word [dsp_writes], DSP_FAIL_AFTER
    jb .done
    mov bl, 80h
    retf
.reset_status:
    cmp dx, 22eh
    jne .reset_byte
    mov bl, 80h
    retf
.reset_byte:
    cmp dx, 22ah
    jne .done
    mov bl, 0aah
    retf
.write:
    cmp dx, 22ch
    jne .done
    inc word [dsp_writes]
.done:
    retf

mix_half:
    ret
sound_card db 0
sb_base dw 220h
sb_irq db 7
sb_dma8 db 1
sb_dma16 db 5
fault db 0
qpi dw port_api,0
output_segment dw 6000h
busy_dsp db 1
dsp_writes dw 0
expected_irq dd 0
