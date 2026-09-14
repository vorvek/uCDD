; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h

    mov sp, program_end+512
    mov bx, (program_end-$$+100h+512+15)/16
    mov ah, 4ah
    int 21h
    jc fail
%ifdef PRO_TEST
    mov dx, config_name
    mov ax, 3d00h
    int 21h
    jc fail
    mov bx, ax
    mov dx, config_data
    mov cx, 12
    mov ah, 3fh
    int 21h
    jc fail
    mov ah, 3eh
    int 21h
    mov dx, 224h
    mov al, 80h
    out dx, al
    inc dx
    mov al, 2
    cmp byte [config_data+8], 5
    je .irq_set
    mov al, 4
.irq_set:
    out dx, al
    dec dx
    mov al, 81h
    out dx, al
    inc dx
    mov cl, [config_data+9]
    mov al, 1
    shl al, cl
    or al, 20h
    out dx, al
%endif
%ifdef HIGH_SETUP
    mov ax, 5800h
    int 21h
    mov [old_strategy], ax
    mov ax, 5802h
    int 21h
    mov [old_umb], al
    mov byte [policy_saved], 1
    mov bx, 1
    mov ax, 5803h
    int 21h
    jc fail
    mov bx, 80h
    mov ax, 5801h
    int 21h
    jc fail
%endif
    mov di, before
    call snapshot
%ifndef INSTALL_TEST
%ifndef CHILD_NAME
    mov ax, 40h
    mov es, ax
    cli
    mov word [es:1ah], 1eh
    mov word [es:1ch], 1eh+key_end-keys
    mov si, keys
    mov di, 1eh
    mov cx, (key_end-keys)/2
    cld
    rep movsw
    sti
%endif
%endif
    mov [exec_block+4], cs
    mov [exec_block+8], cs
    mov [exec_block+12], cs
    mov [saved_sp], sp
    push ds
    pop es
    mov dx, setup_name
    mov bx, exec_block
    mov ax, 4b00h
    int 21h
    cli
    mov ax, cs
    mov ss, ax
    mov sp, [cs:saved_sp]
    sti
    push cs
    pop ds
    jc fail
    mov ah, 4dh
    int 21h
%ifdef EXPECT_FAILURE
    cmp ax, 1
%else
    test ax, ax
%endif
    jne fail
    mov di, after
    call snapshot
    push ds
    pop es
    mov si, before
    mov di, after
    mov cx, after-before
    cld
    repe cmpsb
    jne fail
%ifdef INSTALL_TEST
    xor ax, ax
    mov es, ax
    xor di, di
    mov ax, 1684h
    mov bx, 4354h
    int 2fh
    mov ax, es
    or ax, di
    jnz fail
    mov ah, 52h
    int 21h
    add bx, 22h
.driver:
    cmp dword [es:bx+10], 'UCDD'
    jne .next
    cmp dword [es:bx+14], '0001'
    je fail
.next:
    cmp word [es:bx], 0ffffh
    je .absent
    les bx, [es:bx]
    jmp .driver
.absent:
%endif
    xor al, al
    jmp finish
fail:
    mov al, 1
finish:
%ifdef HIGH_SETUP
    push ax
    cmp byte [policy_saved], 0
    je .restored
    mov bx, [old_strategy]
    mov ax, 5801h
    int 21h
    movzx bx, byte [old_umb]
    mov ax, 5803h
    int 21h
.restored:
    pop ax
%endif
    mov ah, 4ch
    int 21h

snapshot:
    push ds
    pop es
    cld
    mov ax, 5800h
    int 21h
    stosw
    mov ax, 5802h
    int 21h
    stosb
    mov dx, 21h
    in al, dx
    stosb
    push es
    mov ax, 350dh
    int 21h
    mov [di], bx
    mov [di+2], es
    mov ax, 350fh
    int 21h
    mov [di+4], bx
    mov [di+6], es
    pop es
    add di, 8
    mov bx, 0ffffh
    mov ah, 48h
    int 21h
    jnc fail
    mov ax, bx
    stosw
    mov si, mixer_registers
%ifdef WSS_TEST
    mov cx, 7
%else
    mov cx, 6
%endif
.mixer:
%ifdef WSS_TEST
    mov dx, 534h
%else
    mov dx, 224h
%endif
    lodsb
    out dx, al
    inc dx
    in al, dx
    stosb
    loop .mixer
    ret

%ifdef WSS_TEST
mixer_registers db 6,7,8,9,10,14,15
before times 21 db 0
after times 21 db 0
%else
%ifdef PRO_TEST
mixer_registers db 04h,22h,0eh,0ch,80h,81h
config_name db 'UCDD.CFG',0
config_data times 12 db 0
%else
mixer_registers db 30h,31h,32h,33h,80h,81h
%endif
before times 20 db 0
after times 20 db 0
%endif
saved_sp dw 0
%ifdef HIGH_SETUP
policy_saved db 0
old_strategy dw 0
old_umb db 0
%endif
exec_block dw 0,command_tail,0,5ch,0,6ch,0
%ifdef INSTALL_TEST
command_tail db 9,' -install',13
setup_name db 'UCDD.EXE',0
%elifdef CHILD_NAME
command_tail db 0,13
setup_name db CHILD_NAME,0
%else
command_tail db 0,13
setup_name db 'UCDDSET.EXE',0
%endif
keys:
%ifdef RECOVER
    dw 3c00h,5000h,4b00h
%endif
    dw 3c00h,3c00h,4400h
key_end:
program_end:
