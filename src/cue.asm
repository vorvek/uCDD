; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

prepare_image:
    mov si, full_path
.extension:
    lodsb
    test al, al
    jnz .extension
    sub si, 5
    cmp si, full_path
    jb .iso
    mov eax, [si]
    or eax, 20202000h
    cmp eax, '.cue'
    je .cue
    cmp eax, '.bin'
    jne .iso
    mov word [full_path+INFO_STRIDE], 2352
    mov word [full_path+INFO_PAYLOAD], 16
.iso:
    clc
    ret
.cue:
    mov dx, full_path
    mov ax, 3d00h
    int 21h
    jc cue_bad
    mov bx, ax
    mov dx, cue_text
    mov cx, 16385
    mov ah, 3fh
    int 21h
    pushf
    push ax
    mov ah, 3eh
    int 21h
    pop ax
    popf
    jc cue_bad
    cmp ax, 16384
    ja cue_bad
    test ax, ax
    jz cue_bad
    mov si, cue_text
    mov cx, ax
.nul_check:
    cmp byte [si], 0
    je cue_bad
    inc si
    loop .nul_check
    mov byte [si], 0
    mov word [cue_next], cue_text
    mov word [cue_count], 0
    mov dword [cue_gaps], 0
    mov byte [cue_file_seen], 0
    mov byte [cue_have_index], 1
.line:
    mov si, [cue_next]
    cmp byte [si], 0
    je .finish
    mov di, si
.line_end:
    mov al, [di]
    test al, al
    jz .line_ready
    cmp al, 13
    je .terminate
    cmp al, 10
    je .terminate
    inc di
    jmp .line_end
.terminate:
    mov byte [di], 0
    inc di
    cmp byte [di], 10
    jne .line_ready
    inc di
.line_ready:
    mov [cue_next], di
    call token
    jc .line
    mov di, cue_rem
    call option_equal
    je .line
    mov di, cue_title
    call option_equal
    je .line
    mov di, cue_performer
    call option_equal
    je .line
    mov di, cue_songwriter
    call option_equal
    je .line
    mov di, cue_catalog
    call option_equal
    je .line
    mov di, cue_isrc
    call option_equal
    je .line
    mov di, cue_file
    call option_equal
    je .file
    mov di, cue_track
    call option_equal
    je .track
    mov di, cue_pregap
    call option_equal
    je .pregap
    mov di, cue_index
    call option_equal
    je .index
    jmp cue_bad
.file:
    cmp byte [cue_file_seen], 0
    jne cue_bad
    inc byte [cue_file_seen]
    call token
    jc cue_bad
    mov [cue_bin_name], bx
    call token
    jc cue_bad
    mov di, cue_binary
    call option_equal
    jne cue_bad
    call token
    jnc cue_bad
    jmp .line
.track:
    cmp byte [cue_file_seen], 1
    jne cue_bad
    cmp byte [cue_have_index], 1
    jne cue_bad
    cmp word [cue_count], MAX_TRACKS
    jae cue_bad
    call token
    jc cue_bad
    call cue_number
    jc cue_bad
    dec ax
    cmp ax, [cue_count]
    jne cue_bad
    imul di, ax, TRACK_SIZE
    add di, mount_tracks
    mov [cue_current], di
    mov eax, [cue_gaps]
    shl eax, 8
    mov [di+TRACK_CONTROL], eax
    mov byte [cue_gap_seen], 0
    mov dword [di+TRACK_START], 0ffffffffh
    mov dword [di+TRACK_INDEX0], 0ffffffffh
    inc word [cue_count]
    mov byte [cue_have_index], 0
    call token
    jc cue_bad
    mov di, cue_audio
    call option_equal
    je .audio
    cmp word [cue_count], 1
    jne cue_bad
    mov di, cue_mode1
    call option_equal
    jne cue_bad
    mov di, [cue_current]
    mov byte [di+TRACK_CONTROL], 40h
    jmp .mode_done
.audio:
    mov di, [cue_current]
    mov byte [di+TRACK_CONTROL], 0
.mode_done:
    call token
    jnc cue_bad
    jmp .line
.pregap:
    cmp word [cue_count], 0
    je cue_bad
    cmp byte [cue_gap_seen], 0
    jne cue_bad
    cmp byte [cue_have_index], 0
    jne cue_bad
    mov di, [cue_current]
    cmp dword [di+TRACK_INDEX0], 0ffffffffh
    jne cue_bad
    call token
    jc cue_bad
    call cue_time
    jc cue_bad
    add [cue_gaps], eax
    cmp dword [cue_gaps], 7fffffffh/2352
    ja cue_bad
    mov eax, [cue_gaps]
    shl eax, 8
    mov di, [cue_current]
    mov al, [di+TRACK_CONTROL]
    mov [di+TRACK_CONTROL], eax
    inc byte [cue_gap_seen]
    call token
    jnc cue_bad
    jmp .line
.index:
    cmp word [cue_count], 0
    je cue_bad
    call token
    jc cue_bad
    call cue_number
    jc cue_bad
    cmp ax, 1
    ja cue_bad
    mov [cue_index_number], ax
    call token
    jc cue_bad
    call cue_time
    jc cue_bad
    mov di, [cue_current]
    cmp word [cue_index_number], 0
    jne .index_one
    cmp byte [cue_have_index], 0
    jne cue_bad
    cmp dword [di+TRACK_INDEX0], 0ffffffffh
    jne cue_bad
    call .index_zero
    mov [di+TRACK_INDEX0], eax
    jmp .index_done
.index_one:
    cmp byte [cue_have_index], 0
    jne cue_bad
    cmp dword [di+TRACK_INDEX0], 0ffffffffh
    jne .index_zero_set
    push eax
    call .index_zero
    mov [di+TRACK_INDEX0], eax
    pop eax
.index_zero_set:
    add eax, [cue_gaps]
    cmp eax, [di+TRACK_INDEX0]
    jb cue_bad
    mov [di+TRACK_START], eax
    cmp word [cue_count], 1
    je .first
    cmp eax, [di-TRACK_SIZE+TRACK_START]
    jbe cue_bad
    mov edx, [di+TRACK_INDEX0]
    cmp edx, [di-TRACK_SIZE+TRACK_START]
    jbe cue_bad
.first:
    mov byte [cue_have_index], 1
.index_done:
    call token
    jnc cue_bad
    jmp .line
.index_zero:
    cmp word [cue_count], 1
    je .zero_done
    mov edx, [di-TRACK_SIZE+TRACK_CONTROL]
    shr edx, 8
    add eax, edx
.zero_done:
    ret
.finish:
    cmp byte [cue_file_seen], 1
    jne cue_bad
    cmp byte [cue_have_index], 1
    jne cue_bad
    cmp word [cue_count], 0
    je cue_bad
    mov ax, [cue_count]
    mov [full_path+INFO_COUNT], ax
    mov eax, [mount_tracks+TRACK_START]
    mov [full_path+INFO_ORIGIN], eax
    mov word [full_path+INFO_STRIDE], 2352
    mov word [full_path+INFO_PAYLOAD], 16
    mov si, full_path
    mov di, cue_resolved
    mov bx, [cue_bin_name]
    cmp byte [bx+1], ':'
    je .copy_bin
    movsw
    cmp byte [bx], '\'
    je .copy_bin
    mov dx, di
.directory:
    lodsb
    test al, al
    jz .directory_done
    stosb
    cmp al, '\'
    jne .directory
    mov dx, di
    jmp .directory
.directory_done:
    mov di, dx
.copy_bin:
    mov si, bx
.copy_name:
    cmp di, cue_resolved+127
    jae cue_bad
    lodsb
    stosb
    test al, al
    jnz .copy_name
    mov si, cue_resolved
    mov di, full_path
    push ds
    pop es
    mov ax, 6000h
    int 21h
    ret

cue_bad:
    stc
    ret

cue_number:
    push bx
    xor ax, ax
    cmp byte [bx], 0
    je .bad
.digit:
    mov dl, [bx]
    inc bx
    test dl, dl
    jz .done
    sub dl, '0'
    cmp dl, 9
    ja .bad
    cmp ax, 99
    ja .bad
    imul ax, 10
    movzx dx, dl
    add ax, dx
    jmp .digit
.done:
    pop bx
    clc
    ret
.bad:
    pop bx
    stc
    ret

cue_time:
    push si
    mov si, bx
    xor eax, eax
    xor ecx, ecx
.pair:
    movzx edx, byte [si]
    sub dl, '0'
    cmp dl, 9
    ja .bad
    imul edx, 10
    movzx ebx, byte [si+1]
    sub bl, '0'
    cmp bl, 9
    ja .bad
    add edx, ebx
    add si, 2
    cmp cx, 0
    je .minutes
    cmp cx, 1
    je .seconds
    cmp edx, 75
    jae .bad
    add eax, edx
    cmp byte [si], 0
    jne .bad
    pop si
    clc
    ret
.minutes:
    imul eax, edx, 4500
    jmp .separator
.seconds:
    cmp edx, 60
    jae .bad
    imul edx, 75
    add eax, edx
.separator:
    cmp byte [si], ':'
    jne .bad
    inc si
    inc cx
    jmp .pair
.bad:
    pop si
    stc
    ret

cue_gaps dd 0
cue_gap_seen db 0
cue_pregap db 'PREGAP',0
cue_next dw 0
cue_count dw 0
cue_current dw 0
cue_index_number dw 0
cue_bin_name dw 0
cue_file_seen db 0
cue_have_index db 0
cue_rem db 'REM',0
cue_title db 'TITLE',0
cue_performer db 'PERFORMER',0
cue_songwriter db 'SONGWRITER',0
cue_catalog db 'CATALOG',0
cue_isrc db 'ISRC',0
cue_file db 'FILE',0
cue_binary db 'BINARY',0
cue_track db 'TRACK',0
cue_audio db 'AUDIO',0
cue_mode1 db 'MODE1/2352',0
cue_index db 'INDEX',0
cue_resolved times 128 db 0
cue_text times 16385 db 0
