; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%define CD_CACHE_ENTRIES 256
%define CD_CACHE_TABLE_BYTES (CD_CACHE_ENTRIES*8)
%define CD_CACHE_KIB ((CD_CACHE_TABLE_BYTES+CD_CACHE_ENTRIES*512)/1024)

; Keep the mounted file's seek metadata in XMS.
cd_cache_open:
    cmp word [cd_xms+2], 0
    je .return
    pushad
    push es
    mov dx, [cc_handle]
    test dx, dx
    jnz .clear_table
    mov ah, 9
    mov dx, CD_CACHE_KIB
    call far [cd_xms]
    cmp ax, 1
    jne .done
    mov [cc_handle], dx
.clear_table:
    mov dword [cc_probe], 0
    mov dword [cc_probe+4], 0
    mov dword [cc_epoch], 1
    mov word [cc_move+4], 0
    mov word [cc_move+6], cc_probe
    mov [cc_move+8], cs
    mov [cc_move+10], dx
    mov dword [cc_move], 8
    mov dword [cc_move+12], 0
    mov cx, CD_CACHE_ENTRIES
.clear:
    push cx
    call cc_copy
    pop cx
    cmp ax, 1
    jne .failed
    add dword [cc_move+12], 8
    loop .clear
    jmp .done
.failed:
    call cd_cache_close
.done:
    pop es
    popad
.return:
    ret
cd_cache_close:
    pushad
    mov dx, [cc_handle]
    test dx, dx
    jz .done
    mov ah, 0ah
    call far [cd_xms]
    mov word [cc_handle], 0
.done:
    popad
    ret
cd_cache_warm:
    cmp word [cc_handle], 0
    je .done
    cmp byte [cd_background_set], 1
    jne .done
    pushad
    call cd_cache_open
    cmp word [cc_handle], 0
    je .warmed
    push ds
    mov byte [cc_warming], 1
    mov bp, 2
.again:
    mov bx, [cd_handle]
    mov cx, -1
    mov dx, -2
    mov ax, 4202h
    int 21h
    jc .restore
    mov bx, [cd_handle]
    mov ds, [cd_work_segment]
    xor dx, dx
    mov cx, 2
    mov ah, 3fh
    int 21h
.restore:
    pop ds
    mov bx, [cd_handle]
    xor cx, cx
    xor dx, dx
    mov ax, 4200h
    int 21h
    dec bp
    jz .warmed
    push ds
    mov bx, [cd_handle]
    mov ds, [cd_work_segment]
    xor dx, dx
    mov cx, 2
    mov ah, 3fh
    int 21h
    pop ds
    push ds
    jmp .again
.warmed:
    mov byte [cc_warming], 0
    popad
.done:
    ret
cd_cache_bios:
    pushf
    cmp word [cs:cc_handle], 0
    je .chain
    cmp dword [cs:cc_epoch], 0
    je .chain
    cmp byte [cs:cd_bios_busy], 1
    jne .invalidate
    cmp ax, 0201h
    jne .other
    test dl, 80h
    jz .chain
    cmp bx, 0fe00h
    ja .chain
    pushad
    push ds
    push es
    push cs
    pop ds
    mov [cc_buffer], bx
    mov [cc_buffer+2], es
    mov byte [cc_fill], 0
    movzx eax, cx
    shl eax, 16
    mov ax, dx
    mov [cc_key], eax
    mov eax, [cc_epoch]
    mov [cc_key+4], eax
    call cc_index
    mov [cc_slot], ax
    shl eax, 3
    mov [cc_move+6], eax
    mov ax, [cc_handle]
    mov [cc_move+4], ax
    mov word [cc_move+10], 0
    mov word [cc_move+12], cc_probe
    mov [cc_move+14], cs
    mov dword [cc_move], 8
    call cc_copy
    cmp ax, 1
    jne .miss
    mov eax, [cc_probe]
    cmp eax, [cc_key]
    je .matched
    test eax, eax
    jnz .miss
    mov al, [cc_warming]
    mov [cc_fill], al
    jmp .miss
.matched:
    mov byte [cc_fill], 1
    mov eax, [cc_probe+4]
    cmp eax, [cc_epoch]
    jne .miss
    movzx eax, word [cc_slot]
    shl eax, 9
    add eax, CD_CACHE_TABLE_BYTES
    mov [cc_move+6], eax
    mov eax, [cc_buffer]
    mov [cc_move+12], eax
    mov dword [cc_move], 512
    call cc_copy
    cmp ax, 1
    jne .miss
    xor ax, ax
    mov es, ax
    mov byte [es:474h], 0
    pop es
    pop ds
    popad
    popf
    mov ah, 0
    clc
    ret
.miss:
    pop es
    pop ds
    popad
    popf
    pushf
    call far [cs:cd_old_bios]
    pushf
    jc .returned
    cmp byte [cs:cc_fill], 1
    jne .returned
    pushad
    push ds
    push es
    push cs
    pop ds
    mov word [cc_move+4], 0
    mov eax, [cc_buffer]
    mov [cc_move+6], eax
    mov ax, [cc_handle]
    mov [cc_move+10], ax
    movzx eax, word [cc_slot]
    shl eax, 9
    add eax, CD_CACHE_TABLE_BYTES
    mov [cc_move+12], eax
    mov dword [cc_move], 512
    call cc_copy
    cmp ax, 1
    jne .failed
    mov word [cc_move+6], cc_key
    mov [cc_move+8], cs
    movzx eax, word [cc_slot]
    shl eax, 3
    mov [cc_move+12], eax
    mov dword [cc_move], 8
    call cc_copy
    cmp ax, 1
    je .stored
.failed:
    inc dword [cc_epoch]
.stored:
    pop es
    pop ds
    popad
.returned:
    popf
    ret
.other:
    cmp ax, 0301h
    je .write_one
    cmp ah, 1
    je .chain
    cmp ah, 4
    je .chain
    cmp ah, 0ch
    je .chain
    cmp ah, 10h
    je .chain
    cmp ah, 11h
    je .chain
    cmp ah, 14h
    je .chain
    cmp ah, 41h
    je .chain
    cmp ah, 44h
    je .chain
    cmp ah, 47h
    je .chain
    cmp ah, 48h
    je .chain
    cmp ah, 2
    je .chain
    cmp ah, 8
    je .chain
    cmp ah, 15h
    je .chain
    cmp ah, 42h
    je .chain
.invalidate:
    inc dword [cs:cc_epoch]
    jmp .chain
.write_one:
    pushad
    push ds
    push es
    push cs
    pop ds
    call cc_index
    shl eax, 3
    add eax, 4
    mov [cc_move+12], eax
    mov ax, [cc_handle]
    mov [cc_move+10], ax
    mov word [cc_move+4], 0
    mov word [cc_move+6], cc_probe
    mov [cc_move+8], cs
    mov dword [cc_probe], 0
    mov dword [cc_move], 4
    call cc_copy
    cmp ax, 1
    je .invalidated
    inc dword [cc_epoch]
.invalidated:
    pop es
    pop ds
    popad
.chain:
    popf
    pushf
    call far [cs:cd_old_bios]
    ret
cc_index:
    movzx eax, dh
    shl eax, 6
    movzx ebx, cl
    and ebx, 63
    add eax, ebx
    movzx ebx, ch
    xor eax, ebx
    and eax, CD_CACHE_ENTRIES-1
    ret
cc_copy:
    mov si, cc_move
    mov ah, 0bh
    call far [cd_xms]
    ret
cc_warming db 0
cc_fill db 0
cc_handle dw 0
cc_epoch dd 1
cc_slot dw 0
cc_buffer dd 0
cc_key dq 0
cc_probe dq 0
cc_move:
    dd 0
    dw 0
    dd 0
    dw 0
    dd 0
