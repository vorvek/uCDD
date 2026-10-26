; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%ifndef RESIDENT_AUDIO
%include "audio/config.asm"
%endif
%define HOTKEY_NEXT 11
%define HOTKEY_PREVIOUS 12
%define HOTKEY_EJECT 13

mdm_unit dw 0
mdm_count db 0
mdm_current db 0
; 1 to 10 selects a disc. The other values are HOTKEY_* actions.
mdm_pending db 0
mdm_ejected db 0
; Left and right bits for Ctrl, Alt, Shift, and Win.
mdm_modifiers db 0
mdm_prefix db 0
mdm_key_active db 0
mdm_last db 0
; A hotkey keeps an ejected single image open for unit 0.
eject_handle dw 0ffffh
eject_sectors dd 0
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
; Set at the list's mount when any member is bound for CD audio: the list
; counts as an audio disc from then on, so a hotkey never changes whether the
; driver has stepped aside (audio/standby.asm).
mdm_audio db 0
%ifdef RESIDENT_AUDIO
mdm_old_mouse dd 0
%endif

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
    mov byte [mdm_audio], 0
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
%ifdef RESIDENT_AUDIO
    ; mount_image stops after the checks for a list member (control_op 7),
    ; so the candidate fields say whether audio_bind would bind it: a raw
    ; image or more than one track.
    cmp word [candidate_stride], 2352
    je .audio_member
    cmp word [candidate_count], 1
    jbe .audio_counted
.audio_member:
    mov byte [mdm_audio], 1
.audio_counted:
%endif
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
    mov byte [mdm_ejected], 0
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
%ifdef DRIVER_STAGE
    mov byte [cs:stage_valid], 0
%endif
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
    mov byte [mdm_audio], 0
    mov byte [mdm_count], 0
    mov byte [mdm_pending], 0
    mov byte [mdm_ejected], 0
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
%ifdef RESIDENT_AUDIO
    mov ax, 3515h
    int 21h
    mov [mdm_old_mouse], bx
    mov [mdm_old_mouse+2], es
    mov dx, mdm_mouse
    mov ax, 2515h
    int 21h
%endif
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

%ifdef RESIDENT_AUDIO
; The BIOS mouse service (INT 15h AH=C2h) sends a mouse command and takes the
; next byte as the reply. A moving mouse can leave a data byte from the last
; call in the controller when the caller has IF clear, and the setup fails.
; Remove such bytes, and do not trap port 60h during the call.
mdm_mouse:
    cmp ah, 0c2h
    jne .chain
    cmp al, 6
    ja .chain
    push bp
    mov bp, sp
    test byte [bp+7], 2
    pop bp
    jnz .trap
    push ax
    push cx
    mov cx, 400
.drain:
    in al, 64h
    and al, 21h
    cmp al, 21h
    jne .idle
    in al, 60h
    mov cx, 400
.idle:
    loop .drain
    pop cx
    pop ax
.trap:
    cmp byte [cs:callback_set], 0
    je .chain
    push ax
    smsw ax
    test al, 1
    pop ax
    jz .chain
    push ax
    mov ax, 1a0ah
    call .port
    pop ax
    pushf
    call far [cs:mdm_old_mouse]
    push ax
    pushf
    mov ax, 1a09h
    call .port
    popf
    pop ax
    ; Return CF in the caller's flags, so that its IF stays as it was.
    push bp
    mov bp, sp
    jc .carry
    and byte [bp+6], 0feh
    pop bp
    iret
.carry:
    or byte [bp+6], 1
    pop bp
    iret
.chain:
    jmp far [cs:mdm_old_mouse]
.port:
    pushad
    mov dx, 60h
    call far [cs:qpi]
    popad
    ret
%endif

; Observe set-1 bytes without acknowledging the keyboard or PIC.
mdm_scan:
    pushf
    push ax
    push bx
    push cx
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
    mov ah, al
    and al, 7fh
    jz .done
    mov bl, [cs:mdm_prefix]
    mov byte [cs:mdm_prefix], 0
    ; BH is the left bit of the modifier group.
    mov bh, 1
    cmp al, 1dh
    je .side
    mov bh, 4
    cmp al, 38h
    je .side
    test bl, bl
    jnz .extended
    mov bh, 10h
    cmp al, 2ah
    je .modifier
    mov bh, 20h
    cmp al, 36h
    je .modifier
    jmp .key
.extended:
    ; Ignore the shift codes that come with some E0 keys.
    cmp al, 2ah
    je .done
    cmp al, 36h
    je .done
    mov bh, 40h
    cmp al, 5bh
    je .modifier
    mov bh, 80h
    cmp al, 5ch
    je .modifier
    cmp al, 47h
    jb .e0
    cmp al, 53h
    jbe .key
.e0:
    or al, 80h
    jmp .key
.side:
    test bl, bl
    jz .modifier
    shl bh, 1
.modifier:
    test ah, 80h
    jz .pressed
    not bh
    and [cs:mdm_modifiers], bh
    jmp .done
.pressed:
    or [cs:mdm_modifiers], bh
    jmp .done
.key:
    test ah, 80h
    jz .make
    cmp al, [cs:mdm_last]
    jne .done
    mov byte [cs:mdm_last], 0
    jmp .done
.make:
    mov bl, [cs:mdm_modifiers]
    mov bh, [cs:config_modifiers]
    mov cx, 4
.group:
    shr bh, 1
    jnc .next_group
    test bl, 3
    jz .done
.next_group:
    shr bl, 2
    loop .group
    ; CL is 1 for a key that repeats.
    cmp al, [cs:mdm_last]
    sete cl
    mov [cs:mdm_last], al
    mov ah, 1
    cmp byte [cs:config_disc_keys], 1
    je .disc
    mov ah, 3ah
    cmp byte [cs:config_disc_keys], 2
    jne .hotkey
.disc:
    mov bl, al
    sub bl, ah
    jbe .hotkey
    cmp bl, 10
    jbe .action
.hotkey:
    xor bx, bx
.find:
    cmp al, [cs:config_keys+bx]
    je .found
    inc bx
    cmp bx, HOTKEY_COUNT
    jb .find
    jmp .done
.found:
    cmp bl, 3
%ifdef RESIDENT_AUDIO
    jae .volume
%else
    jae .done
%endif
    add bl, HOTKEY_NEXT
.action:
    test cl, cl
    jnz .done
    mov [cs:mdm_pending], bl
    jmp .done
%ifdef RESIDENT_AUDIO
.volume:
    call hotkey_volume
%endif
.done:
    pop cx
    pop bx
    pop ax
    popf
    ret

%ifdef RESIDENT_AUDIO
; BX 3 to 10 selects a volume key. An even key raises a level and an odd key
; lowers it: CD, master, FM, then PCM.
hotkey_volume:
    push ds
    push si
    push di
    push cs
    pop ds
    sub bx, 3
    mov si, bx
    and si, 0eh
    mov di, [volume_levels+si]
    mov al, [di]
    mov ah, [config_volume_step]
    test bl, 1
    jnz .down
    add al, ah
    cmp al, 100
    jbe .store
    mov al, 100
    jmp .store
.down:
    sub al, ah
    jnc .store
    xor al, al
.store:
    mov [di], al
    call [volume_updates+si]
    pop di
    pop si
    pop ds
    ret

volume_levels dw config_cd_volume,config_master_volume,config_fm_volume,config_game_volume
volume_updates dw cd_gain_update,master_update,fm_update,pcm_update
%endif

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
    jnz .unit
    mov si, [units_base]
.unit:
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
    cmp si, [mdm_unit]
    jne .single
    mov bh, [mdm_count]
    mov al, [mdm_current]
    cmp bl, HOTKEY_EJECT
    je .eject
    cmp bl, HOTKEY_NEXT
    jb .disc
    ja .previous
    inc al
    cmp al, bh
    jbe .select
    mov al, 1
    jmp .select
.previous:
    dec al
    jnz .select
    mov al, bh
.select:
    mov bl, al
.disc:
    cmp bl, bh
    ja .done
    cmp bl, [mdm_current]
    jne .load
    cmp byte [mdm_ejected], 0
    je .done
.load:
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
    mov byte [mdm_ejected], 0
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
    jmp .done
.eject:
    cmp byte [mdm_ejected], 0
    jne .done
    mov byte [mdm_ejected], 1
    call clear_unit
    jmp .done
.single:
    cmp bl, HOTKEY_EJECT
    je .single_eject
    ; Disc 1, next, and previous insert the ejected image again.
    cmp bl, 1
    je .insert
    cmp bl, HOTKEY_NEXT
    jb .done
.insert:
    mov ax, 0ffffh
    xchg ax, [eject_handle]
    cmp ax, 0ffffh
    je .done
    mov [si+HANDLE], ax
%ifdef DRIVER_STAGE
    mov byte [cs:stage_valid], 0
%endif
    mov eax, [eject_sectors]
    mov [si+SECTORS], eax
    mov byte [si+CHANGED], 0ffh
%ifdef RESIDENT_AUDIO
    call audio_bind
%endif
    jmp .done
.single_eject:
    mov ax, [si+HANDLE]
    cmp ax, 0ffffh
    je .done
    mov [eject_handle], ax
    mov eax, [si+SECTORS]
    mov [eject_sectors], eax
    call clear_unit
.done:
    pop word [unit_pointer]
    pop es
    popad
    popf
    ret
