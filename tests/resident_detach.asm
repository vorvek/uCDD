; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h
%include "resident_offsets.inc"
    mov sp, program_end+512
    mov bx, (program_end-$$+100h+512+15)/16
    mov ah, 4ah
    int 21h
    jc fail
    mov ax, 350fh
    int 21h
    mov [old_irq], bx
    mov [old_irq+2], es
    mov [exec_block+4], cs
    mov [exec_block+8], cs
    mov [exec_block+12], cs
    mov [saved_sp], sp
    push ds
    pop es
    mov dx, child
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
    cmp ax, 0301h
    jne fail
    mov byte [stage], 2
    mov ax, 350fh
    int 21h
    cmp bx, [old_irq]
    jne fail
    mov ax, es
    cmp ax, [old_irq+2]
    jne fail
    mov ax, 352fh
    int 21h
    cmp bx, audit_host_mux
    jne fail
    mov [resident], es
    mov ax, [es:audit_resident_psp]
    mov [owner], ax
    mov byte [stage], 3
    mov dx, es
%if EXPECT_HIGH
    cmp dx, 0a000h
    jb fail
    mov ax, [resident]
    call allocated
    mov ax, [owner]
    call allocated
    cmp word [fs:3], 16
    jne fail
    mov ax, [resident]
%else
    cmp dx, 0a000h
    jae fail
    add ax, 16
    cmp ax, dx
    jne fail
    mov ax, [owner]
%endif
    call allocated
    cmp byte [es:audit_audio_detach_failed], 1
    jne fail
    cmp byte [es:audit_sb_running], 0
    jne fail
    mov byte [stage], 4
    mov ax, [es:audit_output_allocation]
    call allocated
    mov ax, [es:audit_cd_half_allocation]
    call allocated
    mov ax, [es:audit_cd_work_allocation]
    call allocated
    mov dx, [es:audit_cd_xms_handle]
    mov [queue_handle], dx
    mov byte [stage], 5
    mov ax, 4310h
    int 2fh
    mov [xms], bx
    mov [xms+2], es
    mov dx, [queue_handle]
    mov ah, 0eh
    call far [xms]
    cmp ax, 1
    jne fail
    cmp dx, 512
    jne fail
    mov byte [stage], 6
    mov ax, 1684h
    mov bx, 4354h
    int 2fh
    mov [qpi], di
    mov [qpi+2], es
    mov ax, 1a06h
    call far [qpi]
    jc fail
    mov ax, es
    cmp ax, [resident]
    jne fail
    mov dx, 226h
    mov al, 1
    out dx, al
    xor al, al
    out dx, al
    mov dx, 22ah
    in al, dx
    cmp al, 0aah
    jne fail
    mov dx, success
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
allocated:
    test ax, ax
    jz fail
    dec ax
    mov fs, ax
    cmp byte [fs:0], 'M'
    je .owner
    cmp byte [fs:0], 'Z'
    jne fail
.owner:
    mov ax, [owner]
    cmp [fs:1], ax
    jne fail
    cmp word [fs:3], 0
    je fail
    ret
fail:
    mov dl, [stage]
    add dl, '0'
    mov ah, 2
    int 21h
    mov ax, 4c01h
    int 21h
stage db 1
saved_sp dw 0
old_irq dd 0
resident dw 0
owner dw 0
queue_handle dw 0
xms dd 0
qpi dd 0
exec_block dw 0,tail,0,5ch,0,6ch,0
tail db 8,'-install',13
child db 'UCDD.EXE',0
success db 'The retained driver and buffer tests passed.',13,10,'$'
program_end:
