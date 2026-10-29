; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; The keyboard and mouse hooks of the hotkeys, and the volume keys. With the
; internal host they are in the audio part (they touch its port-trap state);
; mdm_scan stays in the driver part and is a far call from here.

mdm_key_active db 0
mdm_old_key dd 0
%ifdef RESIDENT_AUDIO
mdm_old_mouse dd 0
%endif

%macro MDM_SCAN 0
%ifdef OWN_HOST
    call far [cs:mdm_scan_far]
%else
    call mdm_scan
%endif
%endmacro

%ifdef OWN_HOST
; The key and mouse hooks. The driver part installs the timer hook.
mdm_key_hooks:
    cmp word [mdm_old_key+2], 0
    jne .done
    mov ax, 3509h
    int 21h
    mov [mdm_old_key], bx
    mov [mdm_old_key+2], es
    mov dx, mdm_key
    mov ax, 2509h
    int 21h
    mov ax, 3515h
    int 21h
    mov [mdm_old_mouse], bx
    mov [mdm_old_mouse+2], es
    mov dx, mdm_mouse
    mov ax, 2515h
    int 21h
.done:
    ret
%endif

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
    MDM_SCAN
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

%ifdef OWN_HOST
; From mdm_scan in the driver part.
hotkey_volume_entry:
    call hotkey_volume
    retf
%endif
