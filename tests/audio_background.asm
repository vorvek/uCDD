; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h
%define CD_QUEUE_BYTES 524288
    jmp start
%include "audio/background.asm"
start:
    mov [bios_entry+2], cs
    mov [cd_old_timer+2], cs
    mov word [cd_old_timer], old_timer
    mov [cd_old_bios+2], cs
    mov word [cd_old_bios], old_bios
    mov word [cd_indos], indos
    mov [cd_indos+2], cs
    mov byte [busy], 1
    call tick
    mov byte [busy], 0
    mov byte [cd_bios_busy], 1
    call tick
    mov byte [cd_bios_busy], 0
    mov byte [indos], 1
    call tick
    mov byte [indos], 0
    mov byte [critical], 1
    call tick
    mov byte [critical], 0
    mov byte [cd_started], 0
    call tick
    mov byte [cd_started], 1
    mov byte [cd_error], 2
    call tick
    mov byte [cd_error], 0
    mov dword [cd_produced], CD_QUEUE_BYTES
    call tick
    mov dword [cd_produced], 0
    cmp word [refills], 0
    jne failed
    mov [saved_sp], sp
    call tick
    cmp [saved_sp], sp
    jne failed
    cmp word [refills], 1
    jne failed
    cmp byte [busy], 0
    jne failed
    cmp byte [cd_background_reads], 0
    jne failed
    pushf
    call far [bios_entry]
    jnc failed
    cmp ax, 1234h
    jne failed
    cmp byte [cd_bios_busy], 0
    jne failed
    mov dx, success
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
tick:
    pushf
    push cs
    call cd_timer
    ret
old_timer:
    iret
old_bios:
    cmp byte [cs:cd_bios_busy], 1
    jne failed
    mov ax, 1234h
    stc
    retf 2
cd_foreground:
    cmp byte [busy], 1
    jne failed
    cmp byte [cd_background_reads], 8
    jne failed
    inc word [refills]
    call tick
    ret
failed:
    mov dx, failure
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
busy db 0
cd_started db 1
cd_error db 0
cd_remaining dd 4096
cd_produced dd 0
cd_consumed dd 0
cd_indos dd 0
critical db 0
indos db 0
cd_call_ss dw 0
cd_call_sp dw 0
refills dw 0
saved_sp dw 0
bios_entry dw cd_bios
    dw 0
success db 'The background audio test passed.',13,10,'$'
failure db 'The background audio test failed.',13,10,'$'
    times 2048 db 0
cd_stack_top:
