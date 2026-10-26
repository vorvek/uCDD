; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

LOAD_OK equ 0
LOAD_MISSING equ 1
LOAD_OLD equ 2
LOAD_INVALID equ 3
LOAD_UNREADABLE equ 4
; Version 4's record (0.9.4-a1 to a6); version 5 adds three bytes after it.
CONFIG_V4_SIZE equ 42

; Return AL: LOAD_OK, LOAD_MISSING, LOAD_OLD, LOAD_INVALID, or LOAD_UNREADABLE.
; Every result except LOAD_OK leaves settings that the user must examine.
config_load:
    mov dx, config_path
    mov ax, 3d00h
    int 21h
    jnc .read
    cmp ax, 2
    je .missing
    cmp ax, 3
    je .missing
    jmp .unreadable
.read:
    mov bx, ax
    mov dx, file_buffer
    mov cx, CONFIG_SIZE+1
    mov ah, 3fh
    int 21h
    pushf
    push ax
    mov ah, 3eh
    int 21h
    pop ax
    popf
    jc .unreadable
    cmp dword [file_buffer], 'uCDD'
    jne .invalid
    cmp ax, 12
    je .old
    cmp ax, 36
    je .five_keys
    cmp ax, CONFIG_V4_SIZE
    je .version4
    cmp ax, CONFIG_SIZE
    jne .invalid
    cmp byte [file_buffer+4], CONFIG_VERSION
    jne .invalid
.copy:
    mov si, file_buffer
    mov di, config_data
    mov cx, CONFIG_SIZE
    rep movsb
    mov byte [config_ready], 0
    call config_valid
    jc .invalid
    mov al, LOAD_OK
    ret
.old:
    cmp byte [file_buffer+4], 1
    jne .invalid
    cmp byte [file_buffer+11], 0
    jne .invalid
    call config_defaults
    mov si, file_buffer+5
    mov di, sound_card
    mov cx, 6
    rep movsb
    call physical_valid
    jc .invalid
    mov al, LOAD_OLD
    ret
.missing:
    call config_defaults
    mov al, LOAD_MISSING
    ret
.invalid:
    call config_defaults
    mov al, LOAD_INVALID
    ret
.unreadable:
    call config_defaults
    mov al, LOAD_UNREADABLE
    ret
.five_keys:
    ; Version 2 has five keys and no FM level. The volume keys take the
    ; current defaults. The other settings stay.
    cmp byte [file_buffer+4], 2
    jne .invalid
    mov byte [file_buffer+35], 100
    std
    mov si, file_buffer+35
    mov di, file_buffer+CONFIG_V4_SIZE-1
    mov cx, 12
    rep movsb
    cld
    mov si, config_default+22
    mov di, file_buffer+22
    mov cx, 8
    rep movsb
    ; A kept key that equals a default volume key turns that volume key off.
    mov di, file_buffer+22
.conflict:
    mov al, [di]
    cmp al, [file_buffer+19]
    je .off
    cmp al, [file_buffer+20]
    je .off
    cmp al, [file_buffer+21]
    jne .kept
.off:
    mov byte [di], 0
.kept:
    inc di
    cmp di, file_buffer+30
    jb .conflict
    jmp .extend

.version4:
    cmp byte [file_buffer+4], 4
    jne .invalid
; Joined from .version4 and .five_keys with a version 4 record in the buffer:
; version 5's bytes read 0.
.extend:
    mov word [file_buffer+CONFIG_V4_SIZE], 0
    mov byte [file_buffer+CONFIG_V4_SIZE+2], 0
    mov byte [file_buffer+4], CONFIG_VERSION
    jmp .copy

config_defaults:
    mov si, config_default
    mov di, config_data
    mov cx, CONFIG_SIZE
    rep movsb
    ret

; Return CF set if a setting is not valid.
config_valid:
    call physical_valid
    jc .done
    mov ax, [virtual_base]
    mov si, sb_port_values
    call value_listed
    jc .done
    movzx ax, byte [virtual_irq]
    mov si, irq_values
    call value_listed
    jc .done
    movzx ax, byte [virtual_dma8]
    mov si, dma8_values
    call value_listed
    jc .done
    movzx ax, byte [virtual_dma16]
    mov si, dma16_values
    call value_listed
    jc .done
    movzx ax, byte [virtual_model]
    mov si, virtual_model_values
    call value_listed
    jc .done
    mov ax, [virtual_wss_base]
    mov si, wss_port_values
    call value_listed
    jc .done
    movzx ax, byte [virtual_wss_irq]
    mov si, wss_irq_values
    call value_listed
    jc .done
    call hotkeys_valid
    jc .done
    cmp byte [config_cd_volume], 100
    ja .bad
    cmp byte [config_game_volume], 100
    ja .bad
    cmp byte [config_master_volume], 100
    ja .bad
    movzx ax, byte [config_disk_irq]
    mov si, disk_irq_values
    call value_listed
    jc .done
    cmp byte [config_audio_always], 1
    ja .bad
    cmp byte [config_fm_volume], 100
    ja .bad
    movzx ax, byte [config_volume_step]
    mov si, step_values
    call value_listed
.done:
    ret
.bad:
    stc
    ret

; Check the physical card. A card without a high DMA channel keeps H5.
physical_valid:
    cmp byte [sound_card], 5
    ja .bad
    cmp byte [sound_card], 0
    je .port
    movzx ax, byte [sb_dma16]
    mov si, dma16_values
    call value_listed
    jnc .port
    mov byte [sb_dma16], 5
.port:
    call port_list
    mov ax, [sb_base]
    call value_listed
    jc .done
    movzx ax, byte [sb_irq]
    mov si, irq_values
    call value_listed
    jc .done
    movzx ax, byte [sb_dma8]
    mov si, dma8_values
    call value_listed
    jc .done
    movzx ax, byte [sb_dma16]
    mov si, dma16_values
    call value_listed
.done:
    ret
.bad:
    stc
    ret

; AX value, SI list. Return CF set if the list does not include the value.
value_listed:
    push cx
    push si
    movzx cx, byte [si]
    inc si
    jcxz .missing
.value:
    cmp [si], ax
    je .found
    add si, 2
    loop .value
.missing:
    stc
    jmp .done
.found:
    clc
.done:
    pop si
    pop cx
    ret

; Set the physical mixer value for the selected card.
config_derive:
    movzx ax, byte [config_master_volume]
    mov bl, [sound_card]
    cmp bl, 3
    je .none
    cmp bl, 2
    je .wss
    mov cx, 31
    cmp bl, 1
    je .pro_scale
    cmp bl, 4
    jb .scale
.pro_scale:
    mov cx, 15
.scale:
    push cx
    mul cx
    add ax, 50
    mov cl, 100
    div cl
    pop cx
    cmp cx, 15
    je .pro
    shl al, 3
    jmp .store
.pro:
    mov ah, 11h
    mul ah
    jmp .store
.wss:
    test ax, ax
    jz .mute
    mov cx, 63
    mul cx
    add ax, 50
    mov cl, 100
    div cl
    mov ah, al
    mov al, 63
    sub al, ah
    jmp .store
.mute:
    mov al, 80h
    jmp .store
.none:
    xor al, al
.store:
    mov [master_register], al
    movzx bx, byte [virtual_model]
    shl bx, 1
    mov ax, [dsp_versions+bx]
    mov [virtual_dsp_version], ax
    ret

; DSP version replies by model: 4.05, 3.02, unused, 2.01.
dsp_versions dw 0504h,0203h,0,0102h

; Write UCDD.CF$, then replace UCDD.CFG with it. A failed write keeps the
; old file. status_buffer holds the temporary path.
config_save:
    call config_derive
    mov byte [config_ready], 0
    mov si, config_path
    mov di, status_buffer
    call copy_text
    mov byte [di-1], '$'
    mov dx, status_buffer
    xor cx, cx
    mov ah, 3ch
    int 21h
    jc .done
    mov bx, ax
    mov dx, config_data
    mov cx, CONFIG_SIZE
    mov ah, 40h
    int 21h
    pushf
    push ax
    mov ah, 3eh
    int 21h
    pop dx
    pop cx
    jc .remove
    test cl, 1
    jnz .remove
    cmp dx, CONFIG_SIZE
    jne .remove
    mov dx, config_path
    mov ah, 41h
    int 21h
    mov dx, status_buffer
    mov di, config_path
    mov ah, 56h
    int 21h
    ret
.remove:
    mov dx, status_buffer
    mov ah, 41h
    int 21h
    stc
.done:
    ret

; Return SI port list for the physical card.
port_list:
    mov si, sb_port_values
    cmp byte [sound_card], 2
    je .wss
    cmp byte [sound_card], 4
    jb .done
    mov si, ess_port_values
    ret
.wss:
    mov si, wss_port_values
.done:
    ret

sb_port_values db 4
    dw 220h,240h,260h,280h
ess_port_values db 6
    dw 220h,230h,240h,250h,260h,280h
wss_port_values db 4
    dw 530h,604h,0e80h,0f40h
irq_values db 2
    dw 5,7
wss_irq_values db 4
    dw 7,9,10,11
dma8_values db 2
    dw 1,3
dma16_values db 3
    dw 5,6,7
config_default times CONFIG_SIZE db 0
file_buffer times CONFIG_SIZE+1 db 0
