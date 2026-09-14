; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h
%define HOST_DPMI 1
%ifndef CHILD_RUNS
%define CHILD_RUNS 1
%endif
%ifndef CHILD_EXIT_CODE
%define CHILD_EXIT_CODE 0
%endif
    jmp start
%include "host/monitor.asm"
start:
    mov sp, program_end+512
    mov bx, (program_end-$$+100h+512+15)/16
    mov ah, 4ah
    int 21h
    jc fail
    call dpmi_install
    jc fail
    mov ax, 0de03h
    int 67h
    mov [free_pages], edx
    mov [exec_block+4], cs
    mov [exec_block+8], cs
    mov [exec_block+12], cs
    mov [saved_sp], sp
.run:
    push ds
    pop es
    mov bx, exec_block
    mov dx, child
    mov ax, 4b00h
    int 21h
    cli
    mov ax, cs
    mov ss, ax
    mov sp, [cs:saved_sp]
    sti
    push cs
    pop ds
    jc .failed
    mov ah, 4dh
    int 21h
    mov [exit_code], ax
    cmp word [exit_code], CHILD_EXIT_CODE
    jne .failed
    mov ax, 0de03h
    int 67h
    cmp edx, [free_pages]
    jne .failed
    dec byte [runs_left]
    jnz .run
    call dpmi_remove
    mov ax, 4c00h
    int 21h
.failed:
    call dpmi_remove
fail:
    mov dx, trace_name
    xor cx, cx
    mov ah, 3ch
    int 21h
    jc .no_file
    mov bx, ax
    mov dx, dpmi_trace_pos
    mov cx, dpmi_trace_end-dpmi_trace_pos
    mov ah, 40h
    int 21h
    mov dx, dpmi_ldt
    mov cx, DPMI_LDT_COUNT*8
    mov ah, 40h
    int 21h
    mov dx, dpmi_fault_stack
    mov cx, 64
    mov ah, 40h
    int 21h
    mov dx, dpmi_debug_code
    mov cx, 80
    mov ah, 40h
    int 21h
    mov dx, dpmi_error_frame
    mov cx, 120
    mov ah, 40h
    int 21h
    mov ah, 3eh
    int 21h
.no_file:
    mov bx, [exit_code]
    call print_hex
    mov bx, [dpmi_last_dos]
    call print_hex
    mov bx, [dpmi_unsupported]
    call print_hex
    mov bx, [dpmi_error_call]
    call print_hex
    mov bx, [dpmi_last_error]
    call print_hex
    mov bx, [dpmi_error_cx]
    call print_hex
    mov bx, [dpmi_last_call]
    call print_hex
    mov bx, [mon_status]
    call print_hex
    mov bx, [mon_fault_cs]
    call print_hex
    mov bx, [mon_eip+2]
    call print_hex
    mov bx, [mon_eip]
    call print_hex
    mov bx, [mon_error]
    call print_hex
    mov bx, [mon_cr2+2]
    call print_hex
    mov bx, [mon_cr2]
    call print_hex
    mov bx, [dpmi_fault_ip+2]
    call print_hex
    mov bx, [dpmi_fault_ip]
    call print_hex
    mov si, dpmi_fault_bytes
    mov di, 4
.bytes:
    lodsw
    mov bx, ax
    call print_hex
    dec di
    jnz .bytes
    mov si, dpmi_trace
    mov di, 32
.trace:
    lodsw
    mov bx, ax
    call print_hex
    dec di
    jnz .trace
    mov si, dpmi_fault_regs
    mov di, 32
.regs:
    lodsw
    mov bx, ax
    call print_hex
    dec di
    jnz .regs
    mov ax, 4c01h
    int 21h
print_hex:
    mov cx, 4
.digit:
    rol bx, 4
    mov dl, bl
    and dl, 15
    add dl, '0'
    cmp dl, '9'
    jbe .print
    add dl, 7
.print:
    mov ah, 2
    int 21h
    loop .digit
    mov dl, ' '
    mov ah, 2
    int 21h
    ret
saved_sp dw 0
free_pages dd 0
runs_left db CHILD_RUNS
trace_name db 'HOSTDPMI.DAT',0
exit_code dw 1
exec_block dw 0,tail,0,5ch,0,6ch,0
%ifndef CHILD_TAIL
%define CHILD_TAIL ""
%endif
tail db tail_end-tail-2,CHILD_TAIL,13
tail_end:
%ifndef CHILD_NAME
%define CHILD_NAME "DCLIENT.COM"
%endif
child db CHILD_NAME,0
program_end:
