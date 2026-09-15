; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

mdm_unit dw 0
mdm_count db 0
mdm_current db 0
mdm_pending db 0
mdm_modifiers db 0
mdm_prefix db 0
mdm_key_active db 0
mdm_down dw 0
mdm_handles times MDM_MAX dw 0ffffh
mdm_xms dd 0
mdm_handle dw 0
mdm_input dd 0
mdm_move:
    dd 0
    dw 0
    dd 0
    dw 0
    dd 0
mdm_old_key dd 0
mdm_old_timer dd 0

; DS:DX contains the list name, count, image records and transient scratch.
mdm_mount:
    cmp word [mdm_handle], 0
    je .input
    cmp word [mdm_unit], 0
    jne .bad
    call mdm_release
    jc .bad
.input:
    cmp word [path_pointer], 10000h-MDM_INPUT_SIZE
    ja .bad
    les di, [path_pointer]
    mov ax, [es:di+128]
    dec ax
    cmp ax, MDM_MAX-1
    ja .bad
    mov eax, [path_pointer]
    mov [mdm_input], eax
    mov ax, 4300h
    int 2fh
    cmp al, 80h
    jne .bad
    mov ax, 4310h
    int 2fh
    mov [mdm_xms], bx
    mov [mdm_xms+2], es
    mov dx, (MDM_BACKUP+UNIT_SIZE+1023)/1024
    mov ah, 9
    call far [mdm_xms]
    cmp ax, 1
    jne .bad
    mov [mdm_handle], dx
    mov eax, [mdm_input]
    xor edx, edx
    mov ecx, 128
    call mdm_write
    jc .rollback
    add word [path_pointer], MDM_INFO
.next:
    call mount_image
    cmp word [control_result], 0
    jne .rollback
    movzx bx, byte [mdm_count]
    shl bx, 1
    mov ax, [candidate]
    mov [mdm_handles+bx], ax
    inc byte [mdm_count]
    call mdm_record
    movzx edx, byte [mdm_count]
    dec edx
    imul edx, UNIT_SIZE
    add edx, 128
    mov eax, [mdm_input]
    add ax, MDM_SCRATCH
    mov ecx, UNIT_SIZE
    call mdm_write
    jc .rollback
    add word [path_pointer], INFO_SIZE
    les di, [mdm_input]
    mov al, [mdm_count]
    cmp al, [es:di+128]
    jb .next
    mov eax, [mdm_input]
    add ax, MDM_SCRATCH
    mov edx, 128
    mov ecx, UNIT_SIZE
    call mdm_read
    jc .rollback
    mov si, [unit_pointer]
    call eject_unit
    jc .rollback
    mov di, si
    push ds
    pop es
    lds si, [mdm_input]
    add si, MDM_SCRATCH
    mov cx, UNIT_SIZE/2
    rep movsw
    push cs
    pop ds
    mov si, [unit_pointer]
    mov [mdm_unit], si
    mov byte [mdm_current], 1
    mov byte [mdm_pending], 0
%ifdef RESIDENT_AUDIO
    call audio_bind
%endif
    call mdm_hooks
    mov word [control_result], 0
    ret
.rollback:
    call mdm_release
.bad:
    mov word [control_result], 8007h
    ret

mdm_record:
    les di, [mdm_input]
    add di, MDM_SCRATCH
    push di
    xor ax, ax
    mov cx, UNIT_SIZE/2
    rep stosw
    pop di
    mov ax, [candidate]
    mov [es:di+HANDLE], ax
    mov eax, [candidate_sectors]
    mov [es:di+SECTORS], eax
    mov byte [es:di+CHANGED], 0ffh
    mov ax, [candidate_stride]
    mov [es:di+STRIDE], ax
    mov ax, [candidate_payload]
    mov [es:di+PAYLOAD], ax
    mov eax, [candidate_origin]
    mov [es:di+ORIGIN], eax
    mov eax, [candidate_total]
    mov [es:di+DISC_SECTORS], eax
    mov ax, [candidate_count]
    mov [es:di+TRACK_COUNT], ax
    add di, IMAGE_PATH
    lds si, [path_pointer]
    mov cx, 128
    rep movsb
    add si, INFO_TRACKS-128
    mov cx, MAX_TRACKS*TRACK_SIZE/2
    rep movsw
    push cs
    pop ds
    ret

; EAX is a conventional far pointer, EDX an XMS byte offset, ECX a size.
mdm_write:
    mov [mdm_move], ecx
    mov word [mdm_move+4], 0
    mov [mdm_move+6], eax
    mov ax, [mdm_handle]
    mov [mdm_move+10], ax
    mov [mdm_move+12], edx
    jmp mdm_transfer
mdm_read:
    mov [mdm_move], ecx
    mov word [mdm_move+10], 0
    mov [mdm_move+12], eax
    mov ax, [mdm_handle]
    mov [mdm_move+4], ax
    mov [mdm_move+6], edx
mdm_transfer:
    push si
    mov si, mdm_move
    mov ah, 0bh
    call far [mdm_xms]
    pop si
    cmp ax, 1
    je .ok
    stc
    ret
.ok:
    clc
    ret

mdm_name:
    cmp si, [mdm_unit]
    jne .done
    cmp word [path_pointer], 10000h-128
    ja .done
    mov eax, [path_pointer]
    xor edx, edx
    mov ecx, 128
    call mdm_read
    jc .done
    mov word [control_result], 0
.done:
    ret

mdm_release:
    push bp
    push si
    xor bp, bp
    mov word [mdm_unit], 0
    mov byte [mdm_count], 0
    mov byte [mdm_pending], 0
    xor si, si
.close:
    mov bx, [mdm_handles+si]
    cmp bx, 0ffffh
    je .next
    mov ah, 3eh
    int 21h
    jnc .closed
    mov bp, 1
    jmp .next
.closed:
    mov word [mdm_handles+si], 0ffffh
.next:
    add si, 2
    cmp si, MDM_MAX*2
    jb .close
    test bp, bp
    jnz .failed
    mov dx, [mdm_handle]
    test dx, dx
    jz .done
    mov ah, 0ah
    call far [mdm_xms]
    cmp ax, 1
    jne .failed
    mov word [mdm_handle], 0
.done:
    pop si
    pop bp
    clc
    ret
.failed:
    pop si
    pop bp
    stc
    ret

mdm_hooks:
    cmp word [mdm_old_key+2], 0
    jne .done
    mov ax, 3509h
    int 21h
    mov [mdm_old_key], bx
    mov [mdm_old_key+2], es
    mov dx, mdm_key
    mov ax, 2509h
    int 21h
    mov ax, 3508h
    int 21h
    mov [mdm_old_timer], bx
    mov [mdm_old_timer+2], es
    mov dx, mdm_timer
    mov ax, 2508h
    int 21h
.done:
    ret

mdm_key:
    push ax
    in al, 64h
    and al, 21h
    cmp al, 1
    jne .chain
%ifdef RESIDENT_AUDIO
    push dx
    push ds
    push cs
    pop ds
    mov dx, 60h
    call physical_read
    pop ds
    pop dx
%else
    in al, 60h
%endif
    call mdm_scan
.chain:
    pop ax
    mov byte [cs:mdm_key_active], 1
    pushf
    call far [cs:mdm_old_key]
    mov byte [cs:mdm_key_active], 0
    iret

; Observe set-1 bytes without acknowledging the keyboard or PIC.
mdm_scan:
    pushf
    push ax
    push bx
    cmp byte [cs:mdm_prefix], 1
    jbe .prefix
    dec byte [cs:mdm_prefix]
    cmp byte [cs:mdm_prefix], 1
    jne .done
    mov byte [cs:mdm_prefix], 0
    jmp .done
.prefix:
    cmp al, 0e0h
    jne .pause
    mov byte [cs:mdm_prefix], 1
    jmp .done
.pause:
    cmp al, 0e1h
    jne .scan
    mov byte [cs:mdm_prefix], 6
    jmp .done
.scan:
.modifier:
    mov ah, al
    and al, 7fh
    mov bl, 1
    cmp al, 1dh
    je .set_modifier
    mov bl, 2
    cmp al, 38h
    je .set_modifier
    cmp byte [cs:mdm_prefix], 0
    jne .clear_prefix
    sub al, 2
    cmp al, 9
    ja .done
    mov bl, al
    xor bh, bh
    test ah, 80h
    jz .make
    btr word [cs:mdm_down], bx
    jmp .done
.make:
    bts word [cs:mdm_down], bx
    jc .done
    cmp word [cs:mdm_unit], 0
    je .done
    mov al, [cs:mdm_modifiers]
    mov ah, al
    and al, 5
    jz .done
    and ah, 10
    jz .done
    inc bl
    cmp bl, [cs:mdm_count]
    ja .done
    mov [cs:mdm_pending], bl
    jmp .done
.set_modifier:
    cmp byte [cs:mdm_prefix], 1
    jne .side
    shl bl, 2
.side:
    test ah, 80h
    jz .pressed
    not bl
    and [cs:mdm_modifiers], bl
    jmp .clear_prefix
.pressed:
    or [cs:mdm_modifiers], bl
.clear_prefix:
    mov byte [cs:mdm_prefix], 0
.done:
    pop bx
    pop ax
    popf
    ret

mdm_timer:
    pushf
    call far [cs:mdm_old_timer]
    pushad
    push ds
    push es
    push fs
    push gs
    push cs
    pop ds
    cli
    cmp byte [busy], 0
    jne .done
    cmp byte [mdm_pending], 0
    je .done
    les bx, [indos_pointer]
    cmp word [es:bx-1], 0
    jne .done
    mov byte [busy], 1
    mov [old_ss], ss
    mov [old_sp], sp
    mov ax, cs
    mov ss, ax
    mov sp, stack_top
    cld
    call mdm_switch
    cli
    mov ss, [old_ss]
    mov sp, [old_sp]
    mov byte [busy], 0
.done:
    pop gs
    pop fs
    pop es
    pop ds
    popad
    iret

; Called with the driver lock and stack. No DOS or image I/O is required.
mdm_switch:
    pushf
    cli
    pushad
    push es
    push word [unit_pointer]
    cmp byte [mdm_pending], 0
    je .done
    mov si, [mdm_unit]
    test si, si
    jz .done
    cmp byte [si+LOCKED], 0
    jne .done
    cmp dword [si+AUDIO_ENTRY], 0
    je .ready
%ifdef RESIDENT_AUDIO
    cmp word [si+AUDIO_ENTRY], cd_request
    jne .done
    mov ax, cs
    cmp [si+AUDIO_ENTRY+2], ax
    jne .done
%else
    jmp .done
%endif
.ready:
    mov [unit_pointer], si
    mov bl, [mdm_pending]
    mov byte [mdm_pending], 0
    cmp bl, [mdm_current]
    je .done
    push bx
    mov ax, cs
    shl eax, 16
    mov ax, si
    mov edx, MDM_BACKUP
    mov ecx, UNIT_SIZE
    call mdm_write
    pop bx
    jc .done
    push bx
    movzx edx, bl
    dec edx
    imul edx, UNIT_SIZE
    add edx, 128
    mov ax, cs
    shl eax, 16
    mov ax, [unit_pointer]
    mov ecx, UNIT_SIZE
    call mdm_read
    pop bx
    jc .rollback
    mov [mdm_current], bl
%ifdef RESIDENT_AUDIO
    call cd_clear_state
    mov word [cd_handle], 0ffffh
%endif
    mov si, [unit_pointer]
    mov byte [si+CHANGED], 0ffh
%ifdef RESIDENT_AUDIO
    call audio_bind
%endif
    jmp .done
.rollback:
    mov ax, cs
    shl eax, 16
    mov ax, [unit_pointer]
    mov edx, MDM_BACKUP
    mov ecx, UNIT_SIZE
    call mdm_read
    jnc .done
    mov si, [unit_pointer]
    call clear_unit
.done:
    pop word [unit_pointer]
    pop es
    popad
    popf
    ret
