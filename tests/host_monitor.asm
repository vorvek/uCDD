; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h
    jmp start
%include "host/monitor.asm"

start:
%ifdef HIGH_HOST
    mov ax, cs
    cmp ax, 0a000h
    jb fail
%endif
    mov sp, program_end+512
    mov bx, (program_end-$$+100h+512+15)/16
    mov ah, 4ah
    int 21h
    jc fail
    mov ax, client
    mov bx, io
    call monitor_init
%ifdef NO_VCPI
    jnc fail
    jmp passed
%else
    jc fail
%endif
    mov [real_segment], cs
    mov ax, 220h
    mov cx, 2
    call monitor_trap
    jc fail
    mov ax, 84h
    mov cx, 1
    call monitor_trap
    jc fail
    mov ax, 0ffffh
    mov cx, 2
    call monitor_trap
    jnc fail
    xor cx, cx
    call monitor_trap
    jc fail
    mov cx, 16
.again:
    call monitor_run
    test ax, ax
    jnz fail
    loop .again
    cmp dword [mon_irqs], 0
    je fail
    mov byte [mode], 1
    call monitor_run
    cmp ax, 14
    jne fail
    mov byte [mode], 2
    call monitor_run
    cmp ax, 14
    jne fail
    mov byte [mode], 0
    call monitor_run
    test ax, ax
    jnz fail
passed:
    mov dx, message
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
fail:
    mov bx, ax
    call print_hex
    mov bx, [mon_error]
    call print_hex
    mov bx, [mon_eip]
    call print_hex
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

bits 32
client:
    call .base
.base:
    pop ebp
    sub ebp, .base
    cmp byte [ebp+mode], 1
    je .halt
    cmp byte [ebp+mode], 2
    je .rejected
    mov ax, cs
    and ax, 3
    cmp ax, 3
    jne .bad
    pushfd
    pop eax
    test eax, 3000h
    jnz .bad
    cli
    pushfd
    pop eax
    test eax, 200h
    jnz .bad
    sti
    mov dx, 220h
    mov eax, 12345678h
    out dx, al
    in al, dx
    cmp eax, 123456a5h
    jne .bad
    out dx, ax
    in ax, dx
    cmp eax, 1234c3a5h
    jne .bad
    out dx, eax
    in eax, dx
    cmp eax, 9876c3a5h
    jne .bad
    mov dx, 80h
    out dx, al
    mov word [ebp+test_stage], 101h
    mov eax, 12345678h
    out 84h, al
    in al, 84h
    cmp eax, 123456a5h
    jne .bad
    mov word [ebp+test_stage], 102h
    out 84h, ax
    in ax, 84h
    cmp eax, 1234c3a5h
    jne .bad
    mov word [ebp+test_stage], 103h
    out 84h, eax
    in eax, 84h
    cmp eax, 9876c3a5h
    jne .bad
    mov word [ebp+test_stage], 104h
    mov ax, 0ffffh
    int 31h
    jnc .bad
    cmp ax, 8001h
    jne .bad
    mov word [ebp+test_stage], 105h
    lea edi, [ebp+registers]
    mov ax, [ebp+real_segment]
    mov [edi+36], ax
    mov word [edi+28], 3000h
    mov ax, 0300h
    mov bx, 21h
    xor ecx, ecx
    int 31h
    jc .bad
    cmp byte [edi+28], 7
    jne .bad
    mov ecx, [ebp+mon_irqs]
.wait:
    cmp [ebp+mon_irqs], ecx
    je .wait
    xor eax, eax
    int 30h
.halt:
    hlt
    jmp .bad
.rejected:
    mov dx, 221h
    in al, dx
    jmp .bad
.bad:
    mov ax, [ebp+test_stage]
    int 30h
io:
    cmp dx, 220h
    je .accepted
    cmp dx, 84h
    jne .bad
.accepted:
    test ch, ch
    jnz .write
    mov eax, 9876c3a5h
    clc
    ret
.write:
    cmp cl, 1
    jne .word
    cmp al, 78h
    jne .bad
    jmp .done
.word:
    cmp cl, 2
    jne .dword
    cmp ax, 56a5h
    jne .bad
    jmp .done
.dword:
    cmp cl, 4
    jne .bad
    cmp eax, 1234c3a5h
    jne .bad
.done:
    clc
    ret
.bad:
    stc
    ret
bits 16
mode db 0
test_stage dw 100h
real_segment dw 0
registers times 50 db 0
message db 'The protected-mode test passed.',13,10,'$'
program_end:
