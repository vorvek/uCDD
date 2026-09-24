; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 0

    jmp start

%define CONFIG_EXE_PATH 1
%include "audio/config.asm"

start:
    mov [cs:psp], ds
    mov si, 81h
    movzx cx, byte [80h]
.help_leading:
    jcxz .normal
    lodsb
    dec cx
    cmp al, ' '
    je .help_leading
    cmp al, 9
    je .help_leading
    cmp al, '/'
    jne .normal
    jcxz .normal
    lodsb
    dec cx
    cmp al, '?'
    jne .normal
.help_tail:
    jcxz .show_help
    lodsb
    dec cx
    cmp al, ' '
    je .help_tail
    cmp al, 9
    je .help_tail
    jmp .normal
.show_help:
    jmp show_command_help
.normal:
    push cs
    pop ds
    push cs
    pop es
    cld
    call config_path_init
    jnc .path_ready
    mov dx, path_message
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
.path_ready:
    mov ax, 3
    int 10h
    mov ah, 1
    mov cx, 2000h
    int 10h
    call suggest_blaster
    call config_load
    jnc .loaded
    mov word [status], invalid_message
.loaded:
    call draw
.key:
    xor ah, ah
    int 16h
    cmp al, 27
    je exit
    cmp ah, 44h
    je save
    cmp ah, 3ch
    je test_sound
    cmp ah, 48h
    je .up
    cmp ah, 50h
    je .down
    cmp ah, 4bh
    je .change
    cmp ah, 4dh
    je .change
    cmp al, 13
    jne .key
.change:
    mov cx, 1
    cmp ah, 4bh
    jne .step
    movzx bx, byte [selected]
    movzx cx, byte [choice_counts+bx]
    dec cx
.step:
    movzx bx, byte [selected]
    shl bx, 1
.cycle:
    call [changes+bx]
    loop .cycle
    mov word [status], changed_message
    jmp .loaded
.up:
    cmp byte [selected], 0
    je .key
    dec byte [selected]
    jmp .loaded
.down:
    cmp byte [selected], 4
    je .key
    inc byte [selected]
    jmp .loaded

save:
    call config_save
    jc save_error
    jmp exit
save_error:
    mov word [status], save_message
    jmp start.loaded
test_sound:
    call resident_audio_present
    jc .resident
    call config_save
    jc save_error
    mov word [status], listen_message
    call draw
    mov bx, (setup_end-$$+15)/16+64+16
    mov es, [psp]
    mov ah, 4ah
    int 21h
    jc .failed
    push cs
    pop es
    call speaker_test
    jc .failed
    mov word [status], test_message
    mov byte [result], 0
    jmp start.loaded
.failed:
    mov byte [result], 1
    mov word [status], test_error
    jmp start.loaded
.resident:
    mov word [status], resident_message
    jmp start.loaded

resident_audio_present:
    pushad
    push es
    mov ah, 52h
    int 21h
    add bx, 22h
.scan:
    cmp dword [es:bx+10], 'UCDD'
    jne .next
    cmp dword [es:bx+14], '0001'
    jne .next
    cmp dword [es:bx+22], 'uCDD'
    jne .next
    cmp word [es:bx+26], 2
    jne .next
    mov eax, [es:bx+28]
    mov [resident_entry], eax
    xor bx, bx
    mov ax, 6
    mov dx, resident_report
    call far [resident_entry]
    cmp ax, 1
    jmp .done
.next:
    cmp word [es:bx], 0ffffh
    je .absent
    les bx, [es:bx]
    jmp .scan
.absent:
    clc
.done:
    pop es
    popad
    ret

show_command_help:
    push cs
    pop ds
    mov dx, setup_usage_message
    mov ah, 9
    int 21h
    mov dx, license_notice
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h

exit:
    mov ax, 3
    int 10h
    mov ax, 4c00h
    mov al, [result]
    int 21h

change_card:
    inc byte [sound_card]
    cmp byte [sound_card], 2
    je .wss
    jb .done
    cmp byte [sound_card], 3
    je .sb
    mov byte [sound_card], 0
.sb:
    mov word [sb_base], 220h
.done:
    ret
.wss:
    mov word [sb_base], 530h
    mov byte [sb_irq], 7
    ret
change_port:
    cmp byte [sound_card], 2
    je .wss
    add word [sb_base], 20h
    cmp word [sb_base], 280h
    jbe .done
    mov word [sb_base], 220h
.done:
    ret
.wss:
    cmp word [sb_base], 530h
    je .p604
    cmp word [sb_base], 604h
    je .pe80
    cmp word [sb_base], 0e80h
    je .pf40
    mov word [sb_base], 530h
    ret
.p604:
    mov word [sb_base], 604h
    ret
.pe80:
    mov word [sb_base], 0e80h
    ret
.pf40:
    mov word [sb_base], 0f40h
    ret
change_irq:
    xor byte [sb_irq], 2
    ret
change_dma8:
    xor byte [sb_dma8], 2
    ret
change_dma16:
    cmp byte [sound_card], 0
    jne .done
    inc byte [sb_dma16]
    cmp byte [sb_dma16], 7
    jbe .done
    mov byte [sb_dma16], 5
.done:
    ret

draw:
    push es
    mov ax, 0b800h
    mov es, ax
    xor di, di
    mov ax, 1720h
    mov cx, 2000
    rep stosw
    pop es
    mov dx, 0205h
    mov si, title
    call put
    mov dx, 0405h
    mov si, subtitle
    call put
    mov dx, 0607h
    mov si, labels
    call put
    mov dx, 0627h
    mov si, sb16_name
    cmp byte [sound_card], 0
    je .card
    mov si, sb_name
    cmp byte [sound_card], 3
    je .card
    mov si, pro_name
    cmp byte [sound_card], 2
    jne .card
    mov si, wss_name
.card:
    call put
    mov ax, [sb_base]
    mov di, port_text+2
    mov cx, 3
.hex:
    mov bx, ax
    and bx, 15
    mov bl, [hex_digits+bx]
    mov [di], bl
    dec di
    shr ax, 4
    loop .hex
    mov dx, 0827h
    mov si, port_text
    call put
    mov al, [sb_irq]
    add al, '0'
    mov [number_text], al
    mov dx, 0a27h
    mov si, number_text
    call put
    mov al, [sb_dma8]
    add al, '0'
    mov [number_text], al
    mov dx, 0c27h
    mov si, number_text
    call put
    mov al, [sb_dma16]
    add al, '0'
    mov [number_text], al
    mov dx, 0e27h
    mov si, number_text
    cmp byte [sound_card], 0
    je .high_dma
    mov si, unused_text
.high_dma:
    call put
    mov dx, 1007h
    mov si, output_sb
    cmp byte [sound_card], 3
    je .output
    mov si, output_16
    cmp byte [sound_card], 1
    jne .output
    mov si, output_pro
.output:
    call put
    mov dh, [selected]
    shl dh, 1
    add dh, 6
    mov dl, 4
    mov si, arrow
    call put
    mov dx, 1205h
    mov si, [status]
    call put
    mov dx, 1505h
    mov si, help
    call put
%ifdef SETUP_SNAPSHOT
    push ds
    mov ax, 40h
    mov ds, ax
    mov bx, [6ch]
.frame:
    mov ax, [6ch]
    sub ax, bx
    cmp ax, 2
    jb .frame
    pop ds
    mov al, 2
    out 0e6h, al
%endif
    ret

put:
    push ax
    push bx
    push cx
    push di
    push es
    mov ax, 0b800h
    mov es, ax
    movzx ax, dh
    imul ax, 160
    movzx di, dl
    shl di, 1
    add di, ax
.next:
    lodsb
    test al, al
    jz .done
    cmp al, 13
    je .cr
    cmp al, 10
    je .lf
    mov ah, 1fh
    stosw
    jmp .next
.cr:
    mov ax, di
    mov bl, 160
    div bl
    mul bl
    mov di, ax
    jmp .next
.lf:
    add di, 160
    jmp .next
.done:
    pop es
    pop di
    pop cx
    pop bx
    pop ax
    ret

suggest_blaster:
    push es
    mov es, [psp]
    mov ax, [es:2ch]
    test ax, ax
    jz .done
    mov es, ax
    xor si, si
.variable:
    cmp si, 0fff0h
    jae .done
    cmp byte [es:si], 0
    je .done
    cmp dword [es:si], 'BLAS'
    jne .skip
    cmp dword [es:si+4], 'TER='
    je .found
.skip:
    inc si
    cmp byte [es:si-1], 0
    jne .skip
    jmp .variable
.found:
    add si, 8
.token:
    mov dl, [es:si]
    inc si
    test dl, dl
    jz .done
    cmp dl, ' '
    je .token
    and dl, 0dfh
    mov bx, 10
    cmp dl, 'A'
    jne .number
    mov bx, 16
.number:
    xor ax, ax
.digit:
    movzx cx, byte [es:si]
    cmp cl, ' '
    je .value
    test cl, cl
    jz .value
    sub cl, '0'
    cmp cl, 9
    jbe .valid_digit
    and cl, 0dfh
    sub cl, 7
.valid_digit:
    cmp cx, bx
    jae .done
    imul ax, bx
    jo .done
    add ax, cx
    inc si
    jmp .digit
.value:
    cmp dl, 'A'
    jne .irq
    mov cx, ax
    sub cx, 220h
    test cx, 0ff9fh
    jnz .token
    mov [sb_base], ax
    jmp .token
.irq:
    cmp dl, 'I'
    jne .dma
    cmp ax, 5
    je .set_irq
    cmp ax, 7
    jne .token
.set_irq:
    mov [sb_irq], al
    jmp .token
.dma:
    cmp dl, 'D'
    jne .high
    cmp ax, 1
    je .set_dma
    cmp ax, 3
    jne .token
.set_dma:
    mov [sb_dma8], al
    jmp .token
.high:
    cmp dl, 'H'
    jne .type
    cmp ax, 5
    jb .token
    cmp ax, 7
    ja .token
    mov [sb_dma16], al
    jmp .token
.type:
    cmp dl, 'T'
    jne .token
    cmp ax, 6
    je .sb16
    cmp ax, 1
    je .sb
    cmp ax, 3
    je .sb
    cmp ax, 2
    je .pro
    cmp ax, 4
    jne .token
.pro:
    mov byte [sound_card], 1
    jmp .token
.sb:
    mov byte [sound_card], 3
    jmp .token
.sb16:
    mov byte [sound_card], 0
    jmp .token
.done:
    pop es
    ret

psp dw 0
resident_entry dd 0
resident_report times 26 db 0
selected db 0
result db 0
status dw initial_message
changes dw change_card,change_port,change_irq,change_dma8,change_dma16
choice_counts db 4,4,2,2,3
title db 'uCDD Sound Setup',0
sb_name db 'Sound Blaster / 1.5 / 2',0
output_sb db 'Output: 22.22 kHz, 8-bit mono.',0
subtitle db 'Select the settings for the physical sound card.',0
labels db 'Card',13,10,13,10,'       I/O address',13,10,13,10
    db '       IRQ',13,10,13,10,'       8-bit DMA',13,10,13,10,'       16-bit DMA',0
sb16_name db 'Sound Blaster 16',0
pro_name db 'Sound Blaster Pro',0
wss_name db 'Windows Sound System',0
port_text db '220h',0
number_text db '5',0
unused_text db 'Not used',0
hex_digits db '0123456789ABCDEF'
arrow db '>',0
output_16 db 'Output: 44.1 kHz, 16-bit stereo.',0
output_pro db 'Output: 8-bit stereo. Nominal rate: 22.05 kHz.',0
initial_message db '',0
changed_message db '',0
invalid_message db 'UCDD.CFG is not valid. Check all settings before you save.',0
save_message db 'The settings cannot be saved.',0
listen_message db 'Listen for a tone from each speaker.',0
test_message db 'The test has stopped. Check that both speakers made a sound.',0
test_error db 'The test failed. Check the sound card and its settings.',0
resident_message db 'Restart DOS before you run the sound test.',0
help db 'Up/Down: Select   Left/Right/Enter: Change',13,10
    db '     F2: Save and test   F10: Save and exit   Esc: Exit',0

setup_usage_message db 'Use UCDDSET to select the physical sound card settings.',13,10
    db 'Use the arrow keys to select and change a setting.',13,10
    db 'Use F2 to save the settings and test the sound.',13,10
    db 'Use F10 to save the settings and exit.',13,10
    db 'Use Esc to exit without saving.',13,10
    db 'Use UCDDSET /? to show this information.',13,10,'$'
%include "notice.inc"

%include "audio/speaker.asm"
%include "config_path.asm"
path_message db 'The program directory cannot be read.',13,10,'$'
setup_end:
