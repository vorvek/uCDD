; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

command_entry:
    cld
    mov si, 81h
    movzx cx, byte [80h]
    push cs
    pop es
    mov di, arguments
    rep movsb
    xor al, al
    stosb
    push cs
    pop ds
    mov word [full_path+INFO_STRIDE], 2048
    mov word [full_path+INFO_COUNT], 1
    mov byte [mount_tracks+TRACK_CONTROL], 40h
    mov si, arguments
.parse:
    call token
    jc .parsed
    cmp byte [bx], '/'
    jne .option
    cmp byte [bx+1], '?'
    jne usage
    cmp byte [bx+2], 0
    jne usage
    cmp byte [operation], 0
    jne usage
    cmp byte [wanted_drive], 0ffh
    jne usage
%ifdef RESIDENT_AUDIO
%ifdef EMS_QUEUE
    cmp byte [fs:memory_mode], 0
    jne usage
%endif
    cmp byte [fs:keep_vcpi], 0
    jne usage
%endif
    call token
    jnc usage
    jmp command_help
.option:
    cmp byte [bx], '-'
    jne usage
    mov di, mount_option
    call option_equal
    je .mount
    mov di, unmount_option
    call option_equal
    je .unmount
    mov di, drive_option
    call option_equal
    je .drive
    mov di, install_option
    call option_equal
    je .install
%ifdef RESIDENT_AUDIO
    mov di, vcpi_option
    call option_equal
    je .vcpi
    mov di, status_option
    call option_equal
    je .status
    mov di, reset_option
    call option_equal
    je .reset
%ifdef EMS_QUEUE
    mov di, ems_option
    call option_equal
    je .ems
%endif
%endif
    jmp usage
.install:
    cmp byte [operation], 0
    jne usage
    mov byte [operation], 3
    jmp .parse
%ifdef RESIDENT_AUDIO
.status:
    cmp byte [operation], 0
    jne usage
    mov byte [operation], 4
    jmp .parse
.reset:
    cmp byte [status_reset], 0
    jne usage
    mov byte [status_reset], 1
    jmp .parse
.vcpi:
    cmp byte [fs:keep_vcpi], 0
    jne usage
    mov byte [fs:keep_vcpi], 1
    jmp .parse
%ifdef EMS_QUEUE
.ems:
    cmp byte [fs:memory_mode], 0
    jne usage
    mov byte [fs:memory_mode], 1
    jmp .parse
%endif
%endif
.mount:
    cmp byte [operation], 0
    jne usage
    mov byte [operation], 1
    call token
    jc usage
    mov [image_path], bx
    jmp .parse
.unmount:
    cmp byte [operation], 0
    jne usage
    mov byte [operation], 2
    mov bx, si
.unmount_space:
    cmp byte [bx], ' '
    jne .unmount_path
    inc bx
    jmp .unmount_space
.unmount_path:
    cmp byte [bx], 0
    je .parse
    cmp byte [bx], '-'
    je .parse
    call token
    jc usage
    mov [image_path], bx
    jmp .parse
.drive:
    cmp byte [wanted_drive], 0ffh
    jne usage
    call token
    jc usage
    mov al, [bx]
    and al, 0dfh
    sub al, 'A'
    cmp al, 25
    ja usage
    mov [wanted_drive], al
    cmp byte [bx+1], 0
    je .parse
    cmp byte [bx+1], ':'
    jne usage
    cmp byte [bx+2], 0
    jne usage
    jmp .parse
.parsed:
%ifdef RESIDENT_AUDIO
    ; -reset belongs to -status.
    cmp byte [status_reset], 0
    je .reset_clear
    cmp byte [operation], 4
    jne usage
.reset_clear:
%endif
    cmp byte [operation], 3
    jne .image_command
    cmp byte [wanted_drive], 0ffh
    jne usage
    push fs
    pop ds
    push fs
    push word install
    retf
.image_command:
%ifdef RESIDENT_AUDIO
%ifdef EMS_QUEUE
    cmp byte [fs:memory_mode], 0
    jne usage
%endif
    cmp byte [fs:keep_vcpi], 0
    jne usage
%endif
    cmp byte [operation], 0
    je usage
%ifdef RESIDENT_AUDIO
    ; -status takes no drive.
    cmp byte [operation], 4
    jne .not_status
    cmp byte [wanted_drive], 0ffh
    jne usage
.not_status:
%endif
    cmp byte [operation], 2
    jne .enumerate
    cmp word [image_path], 0
    je .enumerate
    mov si, [image_path]
    mov di, full_path
    mov ax, 6000h
    int 21h
    jc bad_image
    ; The driver keeps the BIN name of a CUE image.
    call prepare_image
    jc bad_image
    mov si, full_path
    mov di, named_path
    mov cx, 128/2
    rep movsw
.enumerate:
    xor bx, bx
    mov ax, 1500h
    int 2fh
    test bx, bx
    jz no_drives
    cmp bx, 26
    ja no_drives
    mov [drive_count], bx
    mov bx, device_list
    mov ax, 1501h
    int 2fh
    mov bx, drive_list
    mov ax, 150dh
    int 2fh
    mov word [selected_index], 0ffffh
    xor si, si
.select:
    cmp si, [drive_count]
    jae .selected
    push si
    call device_at_index
    pop si
    jc .next
    mov byte [found_ucdd], 1
    cmp byte [operation], 2
    jne .name_ok
    cmp word [image_path], 0
    je .name_ok
    push si
    push bx
    mov dx, full_path
    mov ax, 8
    call far [control_entry]
    test ax, ax
    jz .compare_name
    mov ax, 3
    call far [control_entry]
    test ax, ax
    jnz .name_miss
.compare_name:
    mov bx, full_path
    mov di, named_path
    call option_equal
    jne .name_miss
    pop bx
    pop si
    jmp .name_ok
.name_miss:
    pop bx
    pop si
    jmp .next
.name_ok:
%ifdef RESIDENT_AUDIO
    cmp byte [operation], 4
    je status_run
%endif
    mov al, [drive_list+si]
    cmp byte [wanted_drive], 0ffh
    je .automatic
    cmp al, [wanted_drive]
    jne .next
    mov [selected_index], si
    mov [selected_drive], al
    jmp .selected
.automatic:
    xor ax, ax
    call far [control_entry]
    test ax, 8000h
    jnz driver_error
    cmp byte [operation], 1
    jne .find_used
    test ax, ax
    jnz .next
    jmp .candidate
.find_used:
    test ax, ax
    jz .next
.candidate:
    mov al, [drive_list+si]
    cmp al, [selected_drive]
    jae .next
    mov [selected_index], si
    mov [selected_drive], al
.next:
    inc si
    jmp .select
.selected:
    cmp byte [found_ucdd], 0
    je no_drives
    cmp word [selected_index], 0ffffh
    jne .run
    cmp byte [wanted_drive], 0ffh
    jne invalid_drive
    cmp byte [operation], 1
    je full
    jmp empty
.run:
    cmp byte [operation], 1
    jne .eject
    mov si, [image_path]
    mov di, full_path
    push ds
    pop es
    mov ax, 6000h
    int 21h
    jc bad_image
    call mdm_local_path
    jc bad_source
    call is_mdm
    je .mdm
    call prepare_image
    jc bad_image
    call mdm_local_path
    jc bad_source
    mov si, [selected_index]
    call device_at_index
    jc invalid_drive
    mov dx, full_path
    mov ax, 1
    call far [control_entry]
    test ax, 8000h
    jnz driver_error
    jmp .refresh
.mdm:
    call prepare_mdm
    jc bad_mdm
    mov si, [selected_index]
    call device_at_index
    jc invalid_drive
    push ds
    mov ds, [mdm_segment]
    xor dx, dx
    mov ax, 7
    call far [cs:control_entry]
    pop ds
    push ax
    mov es, [mdm_segment]
    mov ah, 49h
    int 21h
    pop ax
    test ax, 8000h
    jnz driver_error
    jmp .refresh
.eject:
    mov si, [selected_index]
    call device_at_index
    jc invalid_drive
    xor ax, ax
    call far [control_entry]
    test ax, 8000h
    jnz driver_error
    test ax, ax
    jz empty
    mov ax, 2
    call far [control_entry]
    test ax, 8000h
    jnz driver_error
.refresh:
    push ds
    pop es
    mov word [packet+14], change_buffer
    mov [packet+16], ds
    mov bx, packet
    movzx cx, byte [selected_drive]
    mov ax, 1510h
    int 2fh
    cmp word [packet+3], 0100h
    jne refresh_error
    cmp byte [change_buffer+1], 0ffh
    jne refresh_error
    mov al, [selected_drive]
    add al, 'A'
    mov [done_drive], al
    mov dx, mounted_message
    cmp byte [operation], 1
    je .report
    mov dx, unmounted_message
.report:
    mov ah, 9
    int 21h
    mov dx, drive_message
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h

; SI selects the paired MSCDEX device and letter lists. Return BL and entry.
device_at_index:
    push si
    push di
    push es
    mov ax, si
    mov di, 5
    mul di
    mov di, ax
    mov bl, [device_list+di]
    les di, [device_list+di+1]
    cmp dword [es:di+10], 'UCDD'
    jne .other
    cmp dword [es:di+14], '0001'
    jne .other
    cmp dword [es:di+22], 'uCDD'
    jne .other
    cmp word [es:di+26], 2
    jne .other
    mov eax, [es:di+28]
    mov [control_entry], eax
    pop es
    pop di
    pop si
    clc
    ret
.other:
    pop es
    pop di
    pop si
    stc
    ret

token:
.space:
    mov al, [si]
    cmp al, ' '
    je .skip
    cmp al, 9
    jne .start
.skip:
    inc si
    jmp .space
.start:
    test al, al
    jz .end
    cmp al, '"'
    jne .plain
    inc si
    mov bx, si
.quoted:
    mov al, [si]
    test al, al
    jz .bad_quote
    inc si
    cmp al, '"'
    jne .quoted
    mov byte [si-1], 0
    cmp byte [si], 0
    je .ready
    cmp byte [si], ' '
    je .ready
    cmp byte [si], 9
    je .ready
.bad_quote:
    jmp [quote_error]
.plain:
    mov bx, si
.scan:
    mov al, [si]
    test al, al
    jz .ready
    cmp al, ' '
    je .terminate
    cmp al, 9
    je .terminate
    inc si
    jmp .scan
.terminate:
    mov byte [si], 0
    inc si
.ready:
    clc
    ret
.end:
    stc
    ret

option_equal:
    push bx
    push di
.next:
    mov al, [bx]
    cmp al, 'a'
    jb .compare
    cmp al, 'z'
    ja .compare
    sub al, 32
.compare:
    cmp al, [di]
    jne .done
    test al, al
    jz .done
    inc bx
    inc di
    jmp .next
.done:
    pop di
    pop bx
    ret

usage:
    mov dx, usage_message
    jmp error
command_help:
    mov dx, usage_message
    mov ah, 9
    int 21h
    mov dx, license_notice
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
no_drives:
    mov dx, no_drives_message
    jmp error
full:
    mov dx, full_message
    jmp error
empty:
    mov dx, empty_message
    jmp error
invalid_drive:
    mov dx, drive_error_message
    jmp error
bad_source:
    mov dx, source_error_message
    jmp error
bad_image:
    mov dx, image_error_message
    jmp error
driver_error:
    cmp ax, 8007h
    je bad_mdm
    cmp ax, 8004h
    je bad_image
    cmp ax, 8003h
    je bad_image
    mov dx, operation_error_message
    jmp error
bad_mdm:
    mov dx, mdm_error_message
    jmp error
refresh_error:
    mov dx, refresh_error_message
error:
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

%ifdef RESIDENT_AUDIO
; UCDD -status: BL is the unit and control_entry the driver. Control 10 copies
; the diagnostic block to full_path (audio/resident.asm), control 11 also
; sets the counts to 0.
status_run:
    mov ax, 10
    cmp byte [status_reset], 0
    je .read
    inc ax
.read:
    mov dx, full_path
    call far [control_entry]
    test ax, 8000h
    jnz .old_driver
    cmp word [full_path], 1
    jne .old_driver
    mov si, status_table
    call status_print
    cmp byte [full_path+50], 0
    mov si, status_fault_table
    jne .fault
    mov si, status_clear_table
.fault:
    call status_print
    mov ax, [full_path+76]
    cmp word [full_path+94], 0
    jne .stops
    mov si, status_free_table
    jmp .abort
.stops:
    mov si, status_exception_table
    cmp ax, 0f1h
    jb .abort
    mov si, status_callback_table
    je .abort
    mov si, status_stack_table
    cmp ax, 0f2h
    je .abort
    mov si, status_return_table
.abort:
    call status_print
    ; Only a page fault has an address.
    cmp word [full_path+94], 0
    je .exit
    cmp word [full_path+76], 0fh
    jne .exit
    mov si, status_page_table
    call status_print
.exit:
    ; A driver from 0.9.5-a1 has no state word.
    cmp word [full_path+2], 144
    jb .state_done
    mov dx, status_active
    cmp byte [full_path+140], 0
    jne .state
    mov dx, status_inactive
.state:
    mov ah, 9
    int 21h
.state_done:
    mov ax, 4c00h
    int 21h
.old_driver:
    mov dx, status_old_message
    jmp error

; SI: a table of entries. An entry is a kind byte, a block offset byte, then
; text that ends with '$'. The text prints first, then the value. The kind
; FFh ends the table. Kinds: 0 no value, 1 word, 2 dword, 4 complement of a
; dword or none, 5 hex byte, 6 hex word, 7 hex dword, 8 hex byte of the word
; minus 1.
status_print:
    lodsb
    cmp al, 0ffh
    je .end
    mov cl, al
    lodsb
    movzx bx, al
    mov dx, si
    mov ah, 9
    int 21h
.skip:
    lodsb
    cmp al, '$'
    jne .skip
    test cl, cl
    jz status_print
    push si
    movzx eax, word [full_path+bx]
    cmp cl, 1
    je .decimal
    cmp cl, 5
    je .hex_byte
    cmp cl, 6
    je .hex_word
    cmp cl, 8
    je .hex_excp
    mov eax, [full_path+bx]
    cmp cl, 7
    je .hex_dword
    cmp cl, 4
    jne .decimal
    ; The queue low mark is stored as a complement. 0 is none.
    test eax, eax
    jnz .complement
    mov dx, status_none
    mov ah, 9
    int 21h
    jmp .printed
.complement:
    not eax
.decimal:
    mov di, status_number+10
    mov byte [di], '$'
    mov ebx, 10
.digit:
    xor edx, edx
    div ebx
    add dl, '0'
    dec di
    mov [di], dl
    test eax, eax
    jnz .digit
    mov dx, di
    mov ah, 9
    int 21h
    jmp .printed
.hex_excp:
    dec ax
.hex_byte:
    mov cl, 2
    jmp .hex
.hex_word:
    mov cl, 4
    jmp .hex
.hex_dword:
    mov cl, 8
.hex:
    movzx bx, cl
    mov di, status_number+8
    mov byte [di], '$'
    mov cx, 8
.hex_digit:
    dec di
    mov dl, al
    and dl, 0fh
    add dl, '0'
    cmp dl, '9'
    jbe .hex_store
    add dl, 7
.hex_store:
    mov [di], dl
    shr eax, 4
    loop .hex_digit
    mov dx, status_number+8
    sub dx, bx
    mov ah, 9
    int 21h
.printed:
    pop si
    jmp status_print
.end:
    ret

%macro STAT 3+
    db %1, %2, %3, '$'
%endmacro

status_table:
    STAT 0, 0, 'uCDD status. The counts start at installation or at -reset.',13,10,'Periods: '
    STAT 2, 4, ''
    STAT 1, 12, 13,10,'Interrupts raised: '
    STAT 1, 14, ', taken: '
    STAT 1, 16, ', ended: '
    STAT 1, 18, ', overrun: '
    STAT 1, 20, ', not for uCDD: '
    STAT 1, 22, '.',13,10,'Refills run: timer '
    STAT 1, 24, ', audio IRQ '
    STAT 1, 26, ', host '
    STAT 1, 28, ', request '
    STAT 1, 126, ', DOS wait '
    STAT 1, 30, '.',13,10,'Refills refused: queue full '
    STAT 1, 32, ', busy '
    STAT 1, 34, ', BIOS '
    STAT 1, 36, ', DSP '
    STAT 1, 38, ', PIC '
    STAT 1, 40, ', DOS '
    STAT 1, 42, ', client '
    STAT 1, 56, '.',13,10,'Host refused: STI '
    STAT 1, 58, ', inactive '
    STAT 1, 60, ', VIF '
    STAT 1, 62, ', busy '
    STAT 1, 64, ', callback '
    STAT 1, 66, ', exception '
    STAT 1, 68, ', stack '
    STAT 1, 70, ', retrace '
    STAT 1, 72, ', clock '
    STAT 1, 74, ', queue '
    STAT 1, 112, '.',13,10,'Client refills run: '
    STAT 1, 114, ', refused: not in a call '
    STAT 1, 116, ', DOS busy '
    STAT 1, 118, ', interrupts off '
    STAT 1, 120, ', host busy '
    STAT 1, 122, ', program area '
    STAT 1, 124, ', queue full enough '
    STAT 1, 128, '.',13,10,'Delayed interrupt fired by: access '
    STAT 1, 130, ', step '
    STAT 1, 132, ', tick '
    STAT 1, 134, ', mask '
    STAT 1, 136, '. Armed: V86 '
    STAT 1, 138, ', protected '
    STAT 4, 8, '.',13,10,'Queue low (bytes): '
    STAT 1, 44, '.',13,10,'Driver requests refused: '
    STAT 5, 48, ', last command '
    STAT 1, 46, 'h.',13,10,'uCDD entered DOS again: '
    STAT 0, 0, '.',13,10
    db 0ffh
status_fault_table:
    STAT 5, 50, 'Sound fault at site '
    STAT 6, 52, 'h: port '
    STAT 5, 51, 'h, value '
    STAT 5, 54, 'h, DSP command '
    STAT 5, 55, 'h, DMA mode '
    STAT 0, 0, 'h.',13,10
    db 0ffh
status_clear_table:
    STAT 0, 0, 'No sound fault.',13,10
    db 0ffh
status_free_table:
    STAT 0, 0, 'uCDD did not stop a program.',13,10
    db 0ffh
status_exception_table:
    STAT 8, 76, 'uCDD stopped the program: exception '
    STAT 6, 90, 'h at '
    STAT 7, 82, ':'
    STAT 7, 78, '.',13,10,'Error code '
    STAT 1, 94, 'h. Programs stopped: '
    STAT 0, 0, '.',13,10
    db 0ffh
status_page_table:
    STAT 7, 86, 'Page address '
    STAT 0, 0, 'h.',13,10
    db 0ffh
status_callback_table:
    STAT 1, 94, 'uCDD stopped the program: a callback ended in an error. Programs stopped: '
    STAT 0, 0, '.',13,10
    db 0ffh
status_stack_table:
    STAT 1, 94, 'uCDD stopped the program: the locked stack is not valid. Programs stopped: '
    STAT 0, 0, '.',13,10
    db 0ffh
status_return_table:
    STAT 1, 94, 'uCDD stopped the program: a return from a call is not valid. Programs stopped: '
    STAT 0, 0, '.',13,10
    db 0ffh
status_none db 'none$'
status_old_message db 'This uCDD version cannot show the status.',13,10,'$'
status_active db 'uCDD is active.',13,10,'$'
status_inactive db 'uCDD is inactive (no CD-Audio image mounted).',13,10,'$'
status_number times 12 db 0
%endif
operation db 0
%ifdef RESIDENT_AUDIO
status_reset db 0
%endif
found_ucdd db 0
wanted_drive db 0ffh
selected_drive db 0ffh
selected_index dw 0ffffh
image_path dw 0
; A bad quote is a usage error on the command line and an image error in a CUE.
%define QUOTE_ERROR 1
quote_error dw usage
drive_count dw 0
control_entry dd 0
mount_option db '-MOUNT',0
unmount_option db '-UNMOUNT',0
drive_option db '-DRIVE',0
install_option db '-INSTALL',0
%ifdef RESIDENT_AUDIO
vcpi_option db '-VCPI',0
status_option db '-STATUS',0
reset_option db '-RESET',0
%ifdef EMS_QUEUE
ems_option db '-EMS',0
%endif
%endif
packet:
    db 20,0,3
    dw 0
    times 8 db 0
    db 0
    dd 0
    dw 2
change_buffer db 9,0
usage_message db 'UCDD -install'
%ifdef RESIDENT_AUDIO
%ifdef EMS_QUEUE
    db ' [-ems]'
%endif
    db ' [-vcpi]'
%endif
    db 13,10
    db 'UCDD -mount image [-drive d]',13,10
    db 'UCDD -unmount [image] [-drive d]',13,10
%ifdef RESIDENT_AUDIO
    db 'UCDD -status [-reset]',13,10
%endif
    db 'd: drive letter.',13,10
%ifdef RESIDENT_AUDIO
    db 'Use -status to see what uCDD counted. Use -reset to set the counts to 0.',13,10
%endif
    db '$'
no_drives_message db 'No uCDD drive is available.',13,10,'$'
full_message db 'No uCDD drive is free.',13,10,'$'
empty_message db 'No image is mounted on this drive.',13,10,'$'
drive_error_message db 'This is not a uCDD drive.',13,10,'$'
source_error_message db 'Use an image on a local hard disk.',13,10,'$'
image_error_message db 'uCDD cannot open the image, or the image is not valid.',13,10,'$'
mdm_error_message db 'Check the disc images and XMS memory.',13,10
    db 'Mount only one MDM file at a time.',13,10,'$'
operation_error_message db 'The drive is locked or in use.',13,10,'$'
refresh_error_message db 'The image changed, but the drive cache did not update.',13,10,'$'
mounted_message db 'The image is mounted.',13,10,'$'
unmounted_message db 'The image is unmounted.',13,10,'$'
drive_message db 'Drive '
done_drive db '?',':',13,10,'$'
%include "notice.inc"
full_path equ arguments+128
mount_tracks equ full_path+INFO_TRACKS
device_list equ full_path+INFO_SIZE
drive_list equ device_list+26*5

%include "cue.asm"
%include "mdm_helper.asm"
; Zero-filled command buffers
arguments:
    times 128+INFO_SIZE+26*5+26 db 0
