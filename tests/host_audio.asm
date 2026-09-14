; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h
%define OUTPUT_SHIFT 9
%define DIRECT_OUTPUT 1
%define VIRTUAL_IRQ 1
%include "audio/layout.inc"
    jmp start
qpi dd 0
output_segment dw 0
output_allocation dw 0
fault db 0
cd_position dw 0
game_phase dd 0
game_step dd 32768
game_limit dd 4096*65536
game_rate dw 22050
game_segment dw 0
game_offset dw 0
game_started dd 0
game_active db 0
source_allocation dw 0
source_segment dw 0
test_result dw 1
real_segment dw 0
%include "audio/mix.asm"
%include "audio/sb16.asm"
%include "audio/trap.asm"
%include "audio/config.asm"
%include "audio/irq.asm"
%include "host/monitor.asm"

start:
    mov sp, program_end+512
    mov bx, (program_end-$$+100h+512+15)/16
    mov ah, 4ah
    int 21h
    jc fail
    cld
    mov [real_segment], cs
    call config_load
    jc fail
    mov ax, client
    mov bx, client_io
    call monitor_init
    jc fail
    mov ax, client_irq_pending
    call monitor_irq_callback
    mov si, ranges
.trap:
    lodsw
    mov cx, [si]
    add si, 2
    test cx, cx
    jz .allocate
    call monitor_trap
    jmp .trap
.allocate:
    mov bx, 512
    mov ah, 48h
    int 21h
    jc fail
    mov [source_allocation], ax
    add ax, 255
    and ax, 0ff00h
    mov [source_segment], ax
    mov es, ax
    xor di, di
    mov cx, 4096
.fill:
    mov bx, di
    and bx, 63
    mov al, [waveform+bx]
    stosb
    loop .fill
    mov bx, RING_PARAS*2
    mov ah, 48h
    int 21h
    jc cleanup
    mov [output_allocation], ax
    add ax, RING_PARAS-1
    and ax, ~(RING_PARAS-1)
    mov [output_segment], ax
    mov es, ax
    xor di, di
    call mix_half
    call mix_half
    call virtual_irq_init
    call sb_start
    jc cleanup
    call monitor_run
    mov [test_result], ax
cleanup:
    call sb_stop
    cmp word [output_allocation], 0
    je .source
    mov es, [output_allocation]
    mov ah, 49h
    int 21h
.source:
    cmp word [source_allocation], 0
    je .result
    mov es, [source_allocation]
    mov ah, 49h
    int 21h
.result:
    mov dx, report_name
    xor cx, cx
    mov ah, 3ch
    int 21h
    jc fail
    mov bx, ax
    mov eax, [periods]
    mov [report], eax
    mov eax, [client_irqs]
    mov [report+4], eax
    mov eax, [port_calls]
    mov [report+8], eax
    mov eax, [mon_irqs]
    mov [report+12], eax
    mov dx, report
    mov cx, 16
    mov ah, 40h
    int 21h
    jc fail
    cmp ax, 16
    jne fail
    mov ah, 3eh
    int 21h
    jc fail
    cmp word [test_result], 0
    jne fail
    cmp byte [fault], 0
    jne fail
    cmp dword [periods], 340
    jb fail
    cmp dword [port_calls], 50
    jb fail
    cmp dword [client_irqs], 40
    jb fail
    mov dx, success
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
fail:
    mov bx, [mon_status]
    call hex
    mov bx, [mon_error]
    call hex
    mov bx, [mon_eip]
    call hex
    mov bx, [client_irqs]
    call hex
    mov bx, [periods]
    call hex
    movzx bx, byte [fault]
    call hex
    mov ebx, [mon_virtual_eip]
    sub ebx, [mon_base]
    call hex
    mov bx, [mon_fault_cs]
    call hex
    mov bx, [mon_cr2]
    call hex
    mov dx, failure
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

hex:
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

bits 32
client_irq_pending:
%ifdef NO_DELIVERY
    xor eax, eax
    ret
%endif
    lea edi, [ebp+mon_rm_regs]
    mov word [edi+32], 2
    mov word [edi+42], virtual_irq_take
    mov ax, [ebp+real_segment]
    mov [edi+44], ax
    mov al, 1
    call mon_real_far
    xor eax, eax
    cmp word [edi+28], 1
    jne .done
    mov al, 0eh
.done:
    ret
client_io:
    cmp cl, 1
    jne .bad
    lea edi, [ebp+mon_rm_regs]
    mov [edi+28], eax
    mov [edi+20], edx
    movzx ecx, ch
    shl ecx, 2
    mov [edi+24], ecx
    mov word [edi+32], 2
    mov word [edi+42], port_callback
    mov ax, [ebp+real_segment]
    mov [edi+44], ax
    mov al, 1
    call mon_real_far
    mov eax, [edi+28]
    clc
    ret
.bad:
    stc
    ret
client:
    call .base
.base:
    pop ebp
    sub ebp, .base
    mov ax, 0205h
    mov bx, 0dh
    mov cx, cs
    lea edx, [ebp+client_irq]
    int 31h
    jc client_bad
    call reset
    mov ax, 22050
    call play
    call wait_second
    call reset
    call wait_second
    mov ax, 11025
    call play
    call wait_second
    call reset
    mov ax, 22050
    call play
    call wait_second
    call reset
    xor eax, eax
    int 30h
reset:
    mov dx, 226h
    mov al, 1
    out dx, al
    xor al, al
    out dx, al
    mov dx, 22eh
    in al, dx
    test al, 80h
    jz client_bad
    mov dx, 22ah
    in al, dx
    cmp al, 0aah
    jne client_bad
    ret
play:
    push eax
    mov al, 5
    out 0ah, al
    xor al, al
    out 0ch, al
    movzx eax, word [ebp+source_segment]
    shl eax, 4
    mov ebx, eax
    out 2, al
    mov al, ah
    out 2, al
    shr ebx, 16
    mov al, bl
    out 83h, al
    mov al, 0ffh
    out 3, al
    mov al, 0fh
    out 3, al
    mov al, 59h
    out 0bh, al
    mov al, 1
    out 0ah, al
    pop ebx
    mov dx, 22ch
    mov al, 41h
    out dx, al
    mov al, bh
    out dx, al
    mov al, bl
    out dx, al
    mov al, 0c6h
    out dx, al
    xor al, al
    out dx, al
    mov al, 0ffh
    out dx, al
    mov al, 03h
    out dx, al
    ret
client_irq:
    pushad
    mov dx, 22eh
    in al, dx
    mov al, 20h
    out 20h, al
    inc dword [ebp+client_irqs]
    popad
    iretd
wait_second:
    mov ebx, [46ch]
.wait:
    mov eax, [46ch]
    sub eax, ebx
    cmp eax, 19
    jb .wait
    ret
client_bad:
    mov ax, 100h
    int 30h

bits 16
client_irqs dd 0
report times 16 db 0
report_name db 'HOSTSTAT.DAT',0
ranges:
%define PORT_RANGES 1
%include "audio/ports.inc"
%undef PORT_RANGES
    dw 0,0
waveform incbin "../build/GAMETEST.PCM"
cd_samples incbin "../build/CDTEST.PCM"
success db 'The shared audio test passed.',13,10,'$'
failure db 'The shared audio test failed.',13,10,'$'
program_end:
