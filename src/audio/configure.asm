; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

audio_configure:
    call config_path_init
    mov dx, config_path_message
    jc .error
    call config_load
    jnc .done
    cmp ax, 2
    mov dx, config_read_message
    jne .error
    mov dx, setup_start_message
    mov ah, 9
    int 21h
    mov bx, [config_directory_end]
    mov dword [bx+4], 'SET.'
    mov dword [bx+8], 'EXE'
    call config_run_setup
    jc .error
    call config_path_init
    mov dx, config_path_message
    jc .error
    call config_load
    mov dx, config_unsaved_message
    jc .error
.done:
    clc
    ret
.error:
    mov [audio_error_text], dx
    stc
    ret

config_run_setup:
    mov ax, 5800h
    int 21h
    jc .failed
    mov [setup_strategy], ax
    mov ax, 5802h
    int 21h
    jc .failed
    mov [setup_umb], al
    xor bx, bx
    mov ax, 5801h
    int 21h
    jc .restore_failed
    xor bx, bx
    mov ax, 5803h
    int 21h
    jc .restore_failed
    mov [setup_exec+4], cs
    mov [setup_exec+8], cs
    mov [setup_exec+12], cs
    push cs
    pop es
    mov bx, setup_exec
    mov dx, config_path
    mov [setup_sp], sp
    mov ax, 4b00h
    int 21h
    cli
    mov dx, cs
    mov ss, dx
    mov sp, [cs:setup_sp]
    sti
    push cs
    pop ds
    cld
    jc .restore_failed
    mov ah, 4dh
    int 21h
    push ax
    call .restore
    pop ax
    test ax, ax
    mov dx, setup_exit_message
    jnz .bad
    clc
    ret
.restore_failed:
    call .restore
.failed:
    mov dx, setup_exec_message
.bad:
    stc
    ret
.restore:
    mov bx, [setup_strategy]
    mov ax, 5801h
    int 21h
    movzx bx, byte [setup_umb]
    mov ax, 5803h
    int 21h
    ret

setup_exec dw 0, setup_tail, 0, setup_fcb, 0, setup_fcb, 0
setup_tail db 0,13
setup_fcb times 37 db 0
setup_sp dw 0
setup_strategy dw 0
setup_umb db 0
config_path_message db 'The program directory cannot be read.',13,10,'$'
config_read_message db 'UCDD.CFG cannot be read. Run UCDDSET and save the settings.',13,10,'$'
config_unsaved_message db 'UCDD.CFG was not saved. The audio driver is not installed.',13,10,'$'
setup_start_message db 'UCDD.CFG was not found. Sound setup will start.',13,10,'$'
setup_exec_message db 'UCDDSET.EXE cannot be started.',13,10,'$'
setup_exit_message db 'Sound setup did not complete. The audio driver is not installed.',13,10,'$'
