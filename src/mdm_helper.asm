; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

is_mdm:
    mov si, full_path
.end:
    lodsb
    test al, al
    jnz .end
    sub si, 5
    cmp si, full_path
    jb .done
    mov eax, [si]
    or eax, 20202000h
    cmp eax, '.mdm'
.done:
    ret

prepare_mdm:
    mov bx, (MDM_INPUT_SIZE+15)/16
    mov ah, 48h
    int 21h
    jc .bad
    mov [mdm_segment], ax
    mov es, ax
    xor di, di
    mov si, full_path
    mov cx, 128/2
    rep movsw
    mov word [es:128], 0
    mov dx, full_path
    mov ax, 3d00h
    int 21h
    jc .free_bad
    mov [mdm_file], ax
.line:
    mov word [mdm_length], 0
.byte:
    mov bx, [mdm_file]
    mov dx, mdm_character
    mov cx, 1
    mov ah, 3fh
    int 21h
    jc .close_bad
    test ax, ax
    jz .eof
    mov al, [mdm_character]
    cmp al, 10
    je .line_end
    cmp al, 13
    je .line_end
    test al, al
    jz .close_bad
    mov bx, [mdm_length]
    cmp bx, 127
    jae .close_bad
    mov [mdm_line+bx], al
    inc word [mdm_length]
    jmp .byte
.eof:
    mov byte [mdm_eof], 1
.line_end:
    mov bx, [mdm_length]
.trim:
    test bx, bx
    jz .empty_line
    mov al, [mdm_line+bx-1]
    cmp al, ' '
    je .trim_one
    cmp al, 9
    jne .ready
.trim_one:
    dec bx
    jmp .trim
.ready:
    mov byte [mdm_line+bx], 0
    mov bx, mdm_line
.leading:
    cmp byte [bx], ' '
    je .skip
    cmp byte [bx], 9
    jne .resolve
.skip:
    inc bx
    jmp .leading
.resolve:
    push ds
    mov ds, [mdm_segment]
    xor si, si
    push cs
    pop es
    mov di, cue_resolved
    mov cx, 128
    rep movsb
    pop ds
    mov di, cue_resolved
    cmp byte [bx+1], ':'
    je .copy
    add di, 2
    cmp byte [bx], '\'
    je .copy
    mov si, di
.directory:
    lodsb
    test al, al
    jz .copy
    cmp al, '\'
    jne .directory
    mov di, si
    jmp .directory
.copy:
    mov si, bx
.name:
    cmp di, cue_resolved+127
    jae .close_bad
    lodsb
    stosb
    test al, al
    jnz .name
    mov si, cue_resolved
    mov di, full_path
    mov ax, 6000h
    int 21h
    jc .close_bad
    call mdm_local_path
    jc .close_bad
    call is_mdm
    je .close_bad
    push ds
    pop es
    mov di, full_path+128
    xor ax, ax
    mov cx, (INFO_SIZE-128)/2
    rep stosw
    mov word [full_path+INFO_STRIDE], 2048
    mov word [full_path+INFO_COUNT], 1
    mov byte [mount_tracks+TRACK_CONTROL], 40h
    call prepare_image
    jc .close_bad
    call mdm_local_path
    jc .close_bad
    mov es, [mdm_segment]
    mov di, [es:128]
    imul di, INFO_SIZE
    add di, MDM_INFO
    mov si, full_path
    mov cx, INFO_SIZE/2
    rep movsw
    inc word [es:128]
    cmp word [es:128], MDM_MAX
    je .finish
.empty_line:
    cmp byte [mdm_eof], 0
    je .line
.finish:
    mov bx, [mdm_file]
    mov ah, 3eh
    int 21h
    mov es, [mdm_segment]
    cmp word [es:128], 0
    je .free_bad
    clc
    ret
.close_bad:
    mov bx, [mdm_file]
    mov ah, 3eh
    int 21h
.free_bad:
    mov es, [mdm_segment]
    mov ah, 49h
    int 21h
.bad:
    stc
    ret

mdm_local_path:
    mov al, [full_path]
    and al, 0dfh
    sub al, 'A'
    cmp al, 2
    jb .bad
    cmp al, 25
    ja .bad
    cmp word [full_path+1], 5c3ah
    jne .bad
    xor si, si
.cd:
    cmp si, [drive_count]
    jae .local
    cmp al, [drive_list+si]
    je .bad
    inc si
    jmp .cd
.local:
    mov bl, al
    inc bl
    mov ax, 4409h
    int 21h
    jc .bad
    test dx, 1000h
    jnz .bad
    clc
    ret
.bad:
    stc
    ret

mdm_segment dw 0
mdm_file dw 0
mdm_length dw 0
mdm_eof db 0
mdm_character db 0
mdm_line times 128 db 0
named_path times 128 db 0
