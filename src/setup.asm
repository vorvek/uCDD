; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 0

    jmp start

%include "audio/config.asm"
%include "setup/screen.asm"

start:
    mov [cs:psp], ds
    push cs
    pop ds
    push cs
    pop es
    cld
    ; Ctrl+Break must not end the program while a vector is hooked. DOS
    ; restores INT 23h at exit.
    mov dx, break_ignore
    mov ax, 2523h
    int 21h
    call command_line
    call config_path_init
    jnc .path_ready
    mov dx, path_message
    jmp exit_error
.path_ready:
    mov si, config_data
    mov di, config_default
    mov cx, CONFIG_SIZE
    rep movsb
    cmp byte [handoff], 0
    je .load
    call handoff_check
    jnc .load
    mov dx, handoff_message
    jmp exit_error
.load:
    call config_load
    mov [load_status], al
    cmp byte [handoff], 0
    je .menu
    cmp al, LOAD_OK
    je install_settings
.menu:
    ; The Disk row shows what the PCI scan finds (disk_scan.asm). The driver
    ; scans for itself at install.
    call disk_scan
    ; The chipset for fast DMA, from the same scan (platform.asm).
    call platform_describe
    call main_menu
    jc .cancel
    cmp byte [handoff], 0
    jne install_settings
    mov dx, saved_message
    mov ah, 9
    int 21h
    mov dx, crlf
    call resident_audio_present
    jnc .print
    mov dx, restart_message
.print:
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
.cancel:
    mov ax, 4c01h
    int 21h

exit_error:
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

; Copy the checked settings into the driver and set BLASTER for games.
install_settings:
    call config_derive
    mov byte [config_ready], 1
    les di, [handoff_pointer]
    mov si, config_data
    mov cx, CONFIG_SIZE
    rep movsb
    push cs
    pop es
    call blaster_update
    push cs
    pop es
    jc .failed
    mov si, blaster_set_message
    call print_text
    mov si, blaster_value
    call print_text
    mov si, period_line
    call print_text
    mov ax, 4c00h
    int 21h
.failed:
    xor si, si
    mov di, blaster_value
    call blaster_build
    mov si, blaster_failed_message
    call print_text
    mov si, blaster_value
    call print_text
    mov si, blaster_failed_end
    call print_text
    mov ax, 4c00h
    int 21h

; SI zero-terminated text for standard output.
print_text:
    mov dx, si
    call text_length
    mov bx, 1
    mov ah, 40h
    int 21h
    ret

; Read /? or the internal -INSTALL segment:offset option from UCDD.
command_line:
    mov es, [psp]
    mov si, 81h
    movzx cx, byte [es:80h]
    call skip_blanks
    jcxz .done
    cmp byte [es:si], '/'
    jne .option
    cmp cx, 2
    jb .done
    cmp byte [es:si+1], '?'
    jne .done
    add si, 2
    sub cx, 2
    call skip_blanks
    test cx, cx
    jz show_command_help
    jmp .done
.option:
    mov di, install_option
    mov bx, 8
    cmp cx, 9
    jb .done
.compare:
    mov al, [es:si]
    cmp al, 'a'
    jb .upper
    sub al, 20h
.upper:
    cmp al, [di]
    jne .done
    inc si
    inc di
    dec cx
    dec bx
    jnz .compare
    mov byte [handoff], 1
    call skip_blanks
    call parse_hex4
    jc .done
    mov dx, ax
    jcxz .done
    cmp byte [es:si], ':'
    jne .done
    inc si
    dec cx
    call parse_hex4
    jc .done
    mov [handoff_pointer], ax
    mov [handoff_pointer+2], dx
.done:
    push cs
    pop es
    ret

; ES:SI text, CX remaining length.
skip_blanks:
    jcxz .done
    cmp byte [es:si], ' '
    je .skip
    cmp byte [es:si], 9
    jne .done
.skip:
    inc si
    dec cx
    jmp skip_blanks
.done:
    ret

; ES:SI text, CX remaining length. Return AX from four hexadecimal digits.
parse_hex4:
    push bx
    push dx
    xor ax, ax
    mov bx, 4
.digit:
    jcxz .bad
    mov dl, [es:si]
    cmp dl, 'a'
    jb .upper
    sub dl, 20h
.upper:
    sub dl, '0'
    cmp dl, 9
    jbe .value
    sub dl, 7
    cmp dl, 0ah
    jb .bad
    cmp dl, 0fh
    ja .bad
.value:
    shl ax, 4
    or al, dl
    inc si
    dec cx
    dec bx
    jnz .digit
    clc
    jmp .done
.bad:
    stc
.done:
    pop dx
    pop bx
    ret

; The pointer must be in the memory block of UCDD, the parent program.
handoff_check:
    push es
    mov es, [psp]
    movzx ebx, word [es:16h]
    lea ax, [bx-1]
    mov es, ax
    cmp byte [es:0], 'M'
    je .size
    cmp byte [es:0], 'Z'
    jne .bad
.size:
    movzx ecx, word [es:3]
    shl ebx, 4
    shl ecx, 4
    add ecx, ebx
    movzx eax, word [handoff_pointer+2]
    shl eax, 4
    movzx edx, word [handoff_pointer]
    add eax, edx
    cmp eax, ebx
    jb .bad
    add eax, CONFIG_SIZE
    cmp eax, ecx
    ja .bad
    les di, [handoff_pointer]
    cmp dword [es:di], 'uCDD'
    jne .bad
    cmp byte [es:di+4], CONFIG_VERSION
    jne .bad
    pop es
    clc
    ret
.bad:
    pop es
    stc
    ret

show_command_help:
    mov dx, setup_usage_message
    mov ah, 9
    int 21h
    mov dx, license_notice
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h

; Return CF set if the user exits without saving.
main_menu:
    movzx bx, byte [load_status]
    shl bx, 1
    mov ax, [load_messages+bx]
    mov [status], ax
    cmp byte [load_status], LOAD_OK
    je .resident
    mov byte [changed], 1
    jmp .start
.resident:
    call resident_audio_present
    jnc .start
    mov word [status], installed_message
.start:
    call screen_start
    mov word [form_title], main_title
    mov word [form_items], main_items
    mov word [form_count], MAIN_ITEMS
    mov word [form_selected], 0
    mov word [form_draw], main_draw
    mov word [form_keys], main_keys
    mov word [form_notes], main_notes
    mov word [form_status_row], 0310h
    mov byte [menu_result], 1
    call form_run
    call screen_stop
    cmp byte [menu_result], 0
    je .saved
    stc
    ret
.saved:
    clc
    ret

main_draw:
    mov dx, 0404h
    mov si, table_header
    mov bl, A_TITLE
    call put_text
    mov dx, 0504h
    mov cx, 69
    mov al, 0c4h
    mov bl, A_BOX
    call put_repeat
    mov dx, 0604h
    mov si, physical_label
    call put_text
    mov dx, 0804h
    mov cx, 69
    mov al, 0fah
    call put_repeat
    mov dx, 0a04h
    mov si, virtual_label
    call put_text
    mov dx, 0b11h
    mov si, wss_name
    call put_text
    ; The virtual WSS codec uses the DMA Low channel of the virtual SB.
    mov dx, 0b3bh
    mov al, [virtual_dma8]
    add al, '0'
    mov cx, 1
    call put_repeat
    mov dl, 45h
    mov al, '*'
    call put_repeat
    mov dx, 0e04h
    mov si, output_label
    call put_text
    mov dx, 0e11h
    movzx bx, byte [sound_card]
    shl bx, 1
    mov si, [output_texts+bx]
    mov bl, A_BOX
    call put_text
    mov dx, 0f04h
    mov si, applications_text
    call put_text
    mov si, virtual_cards_text
    mov bl, A_TITLE
    call put_text
    mov al, '.'
    mov cx, 1
    mov bl, A_BOX
    call put_repeat
    ; The Chipset row: what the PCI scan found and the fast DMA switch,
    ; greyed with its label when the chipset has no fast timing known.
    mov dx, 0704h
    mov si, chipset_label
    mov bl, A_BOX
    call put_text
    mov dx, 0711h
    mov si, platform_text
    call put_text
    call fastdma_available
    jnc .fastdma_label
    mov bl, A_GREY
.fastdma_label:
    mov dx, 0735h
    mov si, fastdma_label
    call put_text
    mov word [main_notes+20*2], fastdma_help
    call fastdma_available
    jnc .fastdma_help_ready
    mov word [main_notes+20*2], fastdma_grey
.fastdma_help_ready:
    ; The Disk row: what the PCI scan found and an IRQ set by hand. A
    ; warning shows in the status area when a disk IRQ is a sound card's.
    mov dx, 0d04h
    mov si, disk_label
    mov bl, A_BOX
    call put_text
    mov dx, 0d11h
    mov si, pci_irq_label
    call put_text
    mov dx, 0d31h
    mov si, other_irq_label
    call put_text
    call disk_draw
    ; The step-aside switch's label, beside its box.
    mov dx, 0e35h
    mov si, always_label
    mov bl, A_BOX
    call put_text
    ret

main_keys:
    cmp ah, 44h
    jne .escape
    call save_action
    stc
    ret
.escape:
    cmp al, 27
    jne .done
    call cancel_action
    stc
    ret
.done:
    clc
    ret

save_action:
    call config_valid
    jnc .valid
    mov word [status], invalid_values_message
    ret
.valid:
    call config_save
    jnc .saved
    mov word [status], save_message
    ret
.saved:
    mov byte [menu_result], 0
    mov byte [form_done], 1
    ret

cancel_action:
    cmp byte [changed], 0
    je .exit
    mov si, confirm_message
    call status_now
    xor ah, ah
    int 16h
    or al, 20h
    cmp al, 'y'
    je .exit
    mov word [status], empty_text
    ret
.exit:
    mov byte [menu_result], 1
    mov byte [form_done], 1
    ret

; A page keeps a copy of the settings. Cancel puts the copy back.
page_begin:
    mov si, config_data
    mov di, page_saved
    mov cx, CONFIG_SIZE
    rep movsb
    mov al, [changed]
    mov [page_changed], al
    ret

page_ok:
    mov byte [form_done], 1
    ret

page_cancel:
    mov si, page_saved
    mov di, config_data
    mov cx, CONFIG_SIZE
    rep movsb
    mov al, [page_changed]
    mov [changed], al
    mov byte [form_done], 1
    ret

test_action:
    call resident_audio_present
    jnc .free
    mov word [status], resident_test_message
    ret
.free:
    call config_derive
    mov si, listen_message
    call status_now
    mov bx, (setup_end-$$+15)/16+64+16
    mov es, [psp]
    mov ah, 4ah
    int 21h
    push cs
    pop es
    jc .failed
    call speaker_test
    jc .failed
    mov word [status], test_message
    ret
.failed:
    mov word [status], test_error
    ret

break_ignore:
    iret

; Return CF set if the uCDD audio driver is resident.
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

; List and text routines for the main screen choices.
model_list:
    mov si, model_values
    ret
irq_list:
    mov si, irq_values
    ret
dma8_list:
    mov si, dma8_values
    ret
sb_port_list:
    mov si, sb_port_values
    ret
virtual_model_list:
    mov si, virtual_model_values
    ret
wss_port_list:
    mov si, wss_port_values
    ret
wss_irq_list:
    mov si, wss_irq_values
    ret
; Only an SB16 has a high DMA channel.
virtual_dma16_list:
    mov si, dma16_values
    cmp byte [virtual_model], 0
    je .done
    mov si, no_values
.done:
    ret
physical_dma16_list:
    mov si, dma16_values
    cmp byte [sound_card], 0
    je .done
    mov si, no_values
.done:
    ret

text_model:
    push bx
    mov bx, ax
    shl bx, 1
    mov si, [model_names+bx]
    pop bx
    jmp copy_text

; Keep the port valid for the new card.
model_changed:
    call port_list
    mov ax, [sb_base]
    call value_listed
    jnc .done
    mov ax, [si+1]
    mov [sb_base], ax
.done:
    clc
    ret

MAIN_ITEMS equ 21
main_items:
    item 6,16,21,0, NONE,5,NONE,1, format_choice,choice_popup,choice_cycle,model_choice
    item 6,41,3,0, NONE,6,0,2, format_choice,choice_popup,choice_cycle,port_choice
    item 6,49,3,0, NONE,20,1,3, format_choice,choice_popup,choice_cycle,irq_choice
    item 6,57,3,0, NONE,20,2,4, format_choice,choice_popup,choice_cycle,dma8_choice
    item 6,67,3,0, NONE,9,3,NONE, format_choice,choice_popup,choice_cycle,dma16_choice
    item 10,16,21,0, 0,10,NONE,6, format_choice,choice_popup,choice_cycle,virtual_model_choice
    item 10,41,3,0, 1,10,5,7, format_choice,choice_popup,choice_cycle,virtual_port_choice
    item 10,49,3,0, 20,11,6,8, format_choice,choice_popup,choice_cycle,virtual_irq_choice
    item 10,57,3,0, 20,11,7,9, format_choice,choice_popup,choice_cycle,virtual_dma8_choice
    item 10,67,3,0, 4,11,8,NONE, format_choice,choice_popup,choice_cycle,virtual_dma16_choice
    item 11,41,3,0, 6,18,NONE,11, format_choice,choice_popup,choice_cycle,wss_port_choice
    item 11,49,3,0, 7,18,10,NONE, format_choice,choice_popup,choice_cycle,wss_irq_choice
    item 20,5,9,0, 19,NONE,NONE,13, format_button,hotkeys_screen,0,hotkeys_label
    item 20,18,7,0, 19,NONE,12,14, format_button,mixer_screen,0,mixer_label
    item 20,31,8,0, 19,NONE,13,15, format_button,detect_action,0,detect_label
    item 20,43,6,0, 19,NONE,14,16, format_button,test_action,0,test_label
    item 20,55,6,0, 19,NONE,15,17, format_button,save_action,0,save_label
    item 20,65,8,0, 19,NONE,16,NONE, format_button,cancel_action,0,cancel_label
    ; The Disk row: an IRQ set by hand for a disk card the PCI scan misses.
    item 13,69,4,0, 10,19,NONE,NONE, format_choice,choice_popup,choice_cycle,disk_irq_choice
    ; The step-aside switch: ticked, the driver stays on without a CD audio disc.
    item 14,48,3,0, 18,12,NONE,NONE, format_tick,toggle_tick,0,always_tick
    ; The fast DMA switch, greyed on a chipset with no fast timing known.
    item 7,48,3,0, 2,7,NONE,NONE, format_tick,toggle_tick,0,fastdma_tick
main_notes dw 0,0,0,0,0
    dw virtual_note,virtual_note,virtual_note,virtual_note,virtual_note,wss_note,wss_note
    dw 0,0,0,0,0,0
    dw disk_note
    dw always_help
    dw fastdma_help
fastdma_tick:
    tick config_fast_dma,fastdma_available
; CF set when the platform offers no fast DMA, or its BIOS has it off.
fastdma_available:
    cmp byte [platform_usable], 1
    ret

; The Detected column's platform line (platform_text) and platform_usable:
; "<chipset>: <timing>", or why there is none.
platform_describe:
    pusha
    push es
    push ds
    pop es
    mov di, platform_text
    mov byte [platform_usable], 0
    movzx bx, byte [platform_row]
    cmp bl, 0ffh
    je .unknown
    shl bx, 1
    mov si, [platform_names+bx]
    call .copy
    mov si, platform_separator
    call .copy
    movzx bx, byte [platform_method]
    shl bx, 1
    mov si, [platform_timings+bx-2]
    ; SiS: Type-F only while the BIOS has 70h bit 7 set (fast_dma_sis71).
    cmp byte [platform_method], PLATFORM_SIS71
    jne .usable
    mov bx, [platform_bridge]
    push di
    mov di, 70h
    call pci_read_byte
    pop di
    jc .off
    test cl, 80h
    jnz .usable
.off:
    mov si, platform_off_text
    jmp .last
.usable:
    mov byte [platform_usable], 1
    jmp .last
.unknown:
    ; A PCI-to-ISA bridge the table lacks, named by its IDs.
    mov si, platform_none_text
    cmp word [platform_bridge_vendor], 0
    je .last
    mov si, platform_bridge_text
    call .copy
    mov ax, [platform_bridge_vendor]
    call .hex4
    mov al, ':'
    stosb
    mov ax, [platform_bridge_device]
    call .hex4
    mov si, platform_unknown_text
.last:
    call .copy
    mov byte [di], 0
    pop es
    popa
    ret
.copy:
    lodsb
    test al, al
    jz .copied
    stosb
    jmp .copy
.copied:
    ret
.hex4:
    mov cx, 4
.digit:
    rol ax, 4
    mov bx, ax
    and bx, 15
    mov bl, [hex_digits+bx]
    mov [di], bl
    inc di
    loop .digit
    ret
always_tick:
    tick config_audio_always,always_available
; CF set when the physical card cannot act as the virtual one (the driver's
; own rule, audio/pairing.asm). Greyed, the box keeps its stored value.
always_available:
    jmp card_pairing
%include "audio/pairing.asm"
platform_usable db 0
platform_text times 40 db 0
; Names by platform table row (platform.asm), then the EISA row.
platform_names dw .piix, .piix3, .piix4, .sio, .m1523, .m1533, .vt586, .vt596
    dw .vt686, .vt8231, .sis5597, .amd756, .viper, .firestar, .eisa
.piix db 'Intel PIIX',0
.piix3 db 'Intel PIIX3',0
.piix4 db 'Intel PIIX4',0
.sio db 'Intel 82378 SIO',0
.m1523 db 'ALi M1523',0
.m1533 db 'ALi M1533/35/43',0
.vt586 db 'VIA VT82C586',0
.vt596 db 'VIA VT82C596',0
.vt686 db 'VIA VT82C686',0
.vt8231 db 'VIA VT8231',0
.sis5597 db 'SiS 5597/5598',0
.amd756 db 'AMD-756',0
.viper db 'OPTi Viper',0
.firestar db 'OPTi FireStar',0
.eisa db 'EISA',0
; What each method gives, by method number.
platform_timings dw .type_f, .type_f, .type_a, .clock, .type_f
.type_f db 'Type F',0
.type_a db 'Type A',0
.clock db 'fast DMA clock',0
platform_separator db ': ',0
platform_off_text db 'off in BIOS',0
platform_bridge_text db 'Bridge ',0
platform_unknown_text db ': none known',0
platform_none_text db 'No fast DMA known',0
fastdma_label db 'Fast DMA',0
fastdma_help db 'Ticked: fast chipset DMA for the sound card. Untick if the sound is bad.',0
fastdma_grey db 'This chipset has no known fast DMA, or the BIOS turned it off.',0
chipset_label db 'Chipset',0
model_choice:
    choice sound_card,1,model_list,text_model,model_changed
port_choice:
    choice sb_base,2,port_list,text_hex3,0
irq_choice:
    choice sb_irq,1,irq_list,text_decimal,0
dma8_choice:
    choice sb_dma8,1,dma8_list,text_decimal,0
dma16_choice:
    choice sb_dma16,1,physical_dma16_list,text_decimal,0
virtual_port_choice:
    choice virtual_base,2,sb_port_list,text_hex3,0
virtual_irq_choice:
    choice virtual_irq,1,irq_list,text_decimal,0
virtual_dma8_choice:
    choice virtual_dma8,1,dma8_list,text_decimal,0
virtual_dma16_choice:
    choice virtual_dma16,1,virtual_dma16_list,text_decimal,0
virtual_model_choice:
    choice virtual_model,1,virtual_model_list,text_model,0
wss_port_choice:
    choice virtual_wss_base,2,wss_port_list,text_hex3,0
wss_irq_choice:
    choice virtual_wss_irq,1,wss_irq_list,text_decimal,0
model_values db 6
    dw 0,1,3,2,4,5
no_values db 0
virtual_model_values db 3
    dw 0,1,3
model_names dw sb16_name,pro_name,wss_name,sb_name,ess_name,ess_half_name
output_texts dw output_16,output_pro,output_16,output_sb,output_ess,output_ess_half

psp dw 0
resident_entry dd 0
resident_report times 26 db 0
handoff db 0
handoff_pointer dd 0
load_status db 0
menu_result db 0
load_messages dw empty_text,missing_message,old_message,invalid_message,unreadable_message
install_option db '-INSTALL'
status_buffer times 240 db 0
page_saved times CONFIG_SIZE db 0
page_changed db 0

main_title db 'uCDD Configuration',0
table_header db 'Card'
    times 9 db ' '
    db 'Model'
    times 20 db ' '
    db 'Port    IRQ   DMA Low  DMA High',0
physical_label db 'Physical',0
virtual_label db 'Virtual',0
output_label db 'Output',0
sb16_name db 'Sound Blaster 16',0
pro_name db 'Sound Blaster Pro',0
wss_name db 'Windows Sound System',0
sb_name db 'Sound Blaster 1.5/2.0',0
ess_name db 'ESS AudioDrive',0
ess_half_name db 'ESS AudioDrive 22 kHz',0
output_16 db '44.1 kHz, 16-bit stereo.',0
output_pro db '8-bit stereo. Approximate rate: 22.05 kHz.',0
output_sb db '22.22 kHz, 8-bit mono.',0
output_ess db '16-bit stereo. Approximate rate: 44.1 kHz.',0
output_ess_half db '16-bit stereo. Approximate rate: 22.05 kHz.',0
applications_text db 'Set your applications to use the ',0
virtual_cards_text db 'VIRTUAL CARDS',0
disk_label db 'Disk',0
pci_irq_label db 'PCI disk card IRQ',0
other_irq_label db 'Other disk card IRQ',0
always_label db 'uCDD always on',0
always_help db 'Ticked: uCDD stays on without a CD-Audio disc. Tick it for WSS games.',0
hotkeys_label db 'Hotkeys',0
mixer_label db 'Mixer',0
detect_label db 'Detect',0
test_label db 'Test',0
save_label db 'Save',0
cancel_label db 'Cancel',0
ok_label db 'OK',0
virtual_note db 'If possible, use the same settings as the physical card.',0
wss_note db 'The WSS codec uses the DMA Low channel of the virtual SB.',0
missing_message db 'UCDD.CFG was not found.',0
old_message db 'UCDD.CFG is from an older version.',0
invalid_message db 'UCDD.CFG is not valid.',0
unreadable_message db 'UCDDSET cannot read UCDD.CFG.',0
installed_message db 'The audio driver is installed. Restart DOS to use changed settings.',0
invalid_values_message db 'A setting is not valid.',0
save_message db 'UCDDSET cannot save the settings.',0
confirm_message db 'You did not save the changes.',10,'Press Y to exit. Press a different key to stay.',0
fixed_message db 'The selected card does not use this setting.',0
listen_message db 'A tone plays on the left speaker, then on the right speaker.',0
test_message db 'The test is complete.',0
test_error db 'The test failed. Check the sound card and its settings.',0
resident_test_message db 'The uCDD audio driver uses the card. Start DOS without UCDD -install.',0
blaster_set_message db 'BLASTER is set to ',0
period_line db '.',13,10,0
blaster_failed_message db 'BLASTER cannot be set. Set BLASTER=',0
blaster_failed_end db ' before you start a game.',13,10,0

saved_message db 'The settings are saved.$'
restart_message db ' Restart DOS to use them.'
crlf db 13,10,'$'
handoff_message db 'Use UCDD -install to install the driver.',13,10,'$'
path_message db 'UCDDSET cannot read the program directory.',13,10,'$'
setup_usage_message db 'UCDDSET sets the sound cards, hotkeys, and volumes for uCDD.',13,10,13,10
    db 'UCDDSET saves the settings in UCDD.CFG.',13,10
    db 'UCDD -install loads them and sets BLASTER for the virtual card.',13,10,'$'
%include "notice.inc"

%include "setup/hotkeys.asm"
%include "setup/mixer.asm"
%include "setup/config_file.asm"
%include "setup/blaster.asm"
%include "setup/detect.asm"
%include "disk_scan.asm"
%include "setup/disk.asm"
%include "audio/speaker.asm"
%include "config_path.asm"
setup_end:
