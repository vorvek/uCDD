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
    mov si, arguments
.parse:
    call token
    jc .parsed
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
    mov di, units_option
    call option_equal
    je .units
    jmp usage
.install:
    cmp byte [operation], 0
    jne usage
    mov byte [operation], 3
    jmp .parse
.units:
    cmp byte [requested_units], 0
    jne usage
    call token
    jc usage
    cmp byte [bx+1], 0
    jne usage
    mov al, [bx]
    sub al, '1'
    cmp al, MAX_UNITS-1
    ja usage
    inc al
    mov [requested_units], al
    jmp .parse
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
    cmp byte [operation], 3
    jne .image_command
    cmp byte [wanted_drive], 0ffh
    jne usage
    mov al, [requested_units]
    test al, al
    jz install
    mov [unit_count], al
    jmp install
.image_command:
    cmp byte [requested_units], 0
    jne usage
    cmp byte [operation], 0
    je usage
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
    mov al, [full_path]
    and al, 0dfh
    sub al, 'A'
    cmp al, 2
    jb bad_source
    cmp al, 25
    ja bad_source
    cmp word [full_path+1], 5c3ah
    jne bad_source
    mov [source_drive], al
    xor si, si
.source_check:
    cmp si, [drive_count]
    jae .local_check
    mov al, [drive_list+si]
    cmp al, [source_drive]
    je bad_source
    inc si
    jmp .source_check
.local_check:
    mov bl, [source_drive]
    inc bl
    mov ax, 4409h
    int 21h
    jc bad_source
    test dx, 1000h
    jnz bad_source
    call prepare_image
    jc bad_image
    mov al, [full_path]
    and al, 0dfh
    sub al, 'A'
    cmp al, 2
    jb bad_source
    cmp al, 25
    ja bad_source
    cmp word [full_path+1], 5c3ah
    jne bad_source
    mov [source_drive], al
    xor si, si
.bin_source:
    cmp si, [drive_count]
    jae .bin_local
    cmp al, [drive_list+si]
    je bad_source
    inc si
    jmp .bin_source
.bin_local:
    mov bl, al
    inc bl
    mov ax, 4409h
    int 21h
    jc bad_source
    test dx, 1000h
    jnz bad_source
    mov si, [selected_index]
    call device_at_index
    jc invalid_drive
    mov dx, full_path
    mov ax, 1
    call far [control_entry]
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
    jz usage
    inc si
    cmp al, '"'
    jne .quoted
    mov byte [si-1], 0
    cmp byte [si], 0
    je .ready
    cmp byte [si], ' '
    je .ready
    cmp byte [si], 9
    jne usage
    jmp .ready
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
    cmp ax, 8004h
    je bad_image
    cmp ax, 8003h
    je bad_image
    mov dx, operation_error_message
    jmp error
refresh_error:
    mov dx, refresh_error_message
error:
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

operation db 0
requested_units db 0
found_ucdd db 0
wanted_drive db 0ffh
selected_drive db 0ffh
source_drive db 0
selected_index dw 0ffffh
image_path dw 0
drive_count dw 0
control_entry dd 0
mount_option db '-MOUNT',0
unmount_option db '-UNMOUNT',0
drive_option db '-DRIVE',0
install_option db '-INSTALL',0
units_option db '-UNITS',0
packet:
    db 20,0,3
    dw 0
    times 8 db 0
    db 0
    dd 0
    dw 2
change_buffer db 9,0
usage_message db 'Use UCDD -install [-units <1 to 4>].',13,10
    db 'Use UCDD -mount <image> [-drive <letter>].',13,10
    db 'Use UCDD -unmount [-drive <letter>].',13,10,'$'
no_drives_message db 'No uCDD drive is available.',13,10,'$'
full_message db 'All uCDD drives are in use.',13,10,'$'
empty_message db 'No image is mounted on the selected drive.',13,10,'$'
drive_error_message db 'The selected drive is not a uCDD drive.',13,10,'$'
source_error_message db 'Use an image on a local hard disk.',13,10,'$'
image_error_message db 'The image cannot be opened or is not valid.',13,10,'$'
operation_error_message db 'The drive is locked or in use. Try again.',13,10,'$'
refresh_error_message db 'The image changed. The drive cache update failed.',13,10,'$'
mounted_message db 'The image is mounted.',13,10,'$'
unmounted_message db 'The image is unmounted.',13,10,'$'
drive_message db 'Drive '
done_drive db '?',':',13,10,'$'
arguments times 128 db 0
full_path times 128 db 0
    dw 2048,0
    dd 0
    dw 1
mount_tracks:
    dd 0,0
    db 40h,0,0,0
    times (MAX_TRACKS-1)*TRACK_SIZE db 0
    dd 0
device_list times 26*5 db 0
drive_list times 26 db 0

%include "cue.asm"
