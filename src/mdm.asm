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
mdm_old_timer dd 0
; Set at the list's mount when any member is bound for CD audio: the list
; counts as an audio disc from then on, so a hotkey never changes whether the
; driver has stepped aside (audio/standby.asm).
mdm_audio db 0
%ifdef OWN_HOST
; The hotkey settings that mdm_scan reads, copied from UCDD.CFG's record at
; install (the record is in the audio part).
hot_modifiers db 0
hot_disc_keys db 0
hot_keys times 11 db 0
%define HOT_MODIFIERS hot_modifiers
%define HOT_DISC_KEYS hot_disc_keys
%define HOT_KEYS hot_keys
%else
%define HOT_MODIFIERS config_modifiers
%define HOT_DISC_KEYS config_disc_keys
%define HOT_KEYS config_keys
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
    AUDIO_BIND
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

%ifdef OWN_HOST
mdm_hooks:
    cmp word [mdm_old_timer+2], 0
    jne .done
    mov ax, 3508h
    int 21h
    mov [mdm_old_timer], bx
    mov [mdm_old_timer+2], es
    mov dx, mdm_timer
    mov ax, 2508h
    int 21h
.done:
    ret
mdm_hooks_entry:
    push ds
    push cs
    pop ds
    call mdm_hooks
    pop ds
    retf
%else
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

%endif

%ifndef OWN_HOST
%include "mdm_keys.asm"
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
    mov bh, [cs:HOT_MODIFIERS]
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
    cmp byte [cs:HOT_DISC_KEYS], 1
    je .disc
    mov ah, 3ah
    cmp byte [cs:HOT_DISC_KEYS], 2
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
    cmp al, [cs:HOT_KEYS+bx]
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
%ifdef OWN_HOST
    call far [cs:volume_far]
%else
    call hotkey_volume
%endif
%endif
.done:
    pop cx
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
    AUDIO_LOAD_GS
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
%ifdef OWN_HOST
    mov ss, [cold_stack]
    mov sp, COLD_STACK_TOP
%else
    mov ax, cs
    mov ss, ax
    mov sp, stack_top
%endif
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

%ifdef OWN_HOST
mdm_scan_entry:
    call mdm_scan
    retf
%endif

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
%ifdef OWN_HOST
    mov ax, [audio_seg]
%else
    mov ax, cs
%endif
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
    AUDIO_CALL clear_state_far, cd_clear_state
    mov word [AUDSEG cd_handle], 0ffffh
%endif
    mov si, [unit_pointer]
    mov byte [si+CHANGED], 0ffh
%ifdef RESIDENT_AUDIO
    AUDIO_BIND
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
    AUDIO_BIND
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
