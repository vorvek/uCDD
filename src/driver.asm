bits 16
cpu 386
org 0

%define MAX_UNITS 4
%define UNIT_SIZE 8
%define HANDLE 0
%define SECTORS 2
%define CHANGED 6
%define LOCKED 7

    jmp install

header:
    dd 0ffffffffh
    dw 0c800h
    dw strategy, interrupt
    db 'UCDD0001'
    dw 0
    db 0
unit_count db 2
    db 'uCDD'
    dw 1
    dw control, 0

request dd 0
active_request dd 0
busy db 0
old_ss dw 0
old_sp dw 0
resident_psp dw 0
caller_psp dw 0
sda_pointer dd 0
sda_size dw 0
indos_pointer dd 0
old_int24 dd 0
unit_pointer dw 0
control_op dw 0
control_result dw 0
path_pointer dd 0
candidate dw 0ffffh
candidate_sectors dd 0
descriptor_sector dd 0
read_remaining dw 0
read_completed dw 0
read_chunk dw 0
read_destination dd 0
units:
%rep MAX_UNITS
    dw 0ffffh
    dd 0
    db 0ffh, 0
%endrep

strategy:
    mov [cs:request], bx
    mov [cs:request+2], es
    retf

interrupt:
    pushf
    pushad
    push ds
    push es
    push fs
    push gs
    cli
    cmp byte [cs:busy], 0
    jne .busy
    mov byte [cs:busy], 1
    mov [cs:old_ss], ss
    mov [cs:old_sp], sp
    mov ax, cs
    mov ss, ax
    mov sp, stack_top
    mov ds, ax
    mov eax, [request]
    mov [active_request], eax
    sti
    cld
    lfs bp, [active_request]
    cmp bp, 0fff3h
    ja .return_only_status
    cmp byte [fs:bp], 13
    jb .bad_length
    movzx eax, byte [fs:bp]
    movzx edx, bp
    add eax, edx
    cmp eax, 10000h
    ja .bad_length
    movzx ax, byte [fs:bp+1]
    cmp al, [unit_count]
    jae .bad_unit
    shl ax, 3
    add ax, units
    mov [unit_pointer], ax
    mov si, ax
    mov al, [fs:bp+2]
    cmp al, 3
    je .ioctl_in
    cmp al, 0ch
    je .ioctl_out
    cmp al, 0dh
    je .success
    cmp al, 0eh
    je .success
    cmp al, 80h
    je .read
    mov ax, 8103h
    jmp .done
.ioctl_in:
    call ioctl_input
    jmp .done
.ioctl_out:
    call ioctl_output
    jmp .done
.read:
    call read_sectors
    jmp .done
.bad_unit:
    mov ax, 8101h
    jmp .done
.bad_length:
    mov ax, 810ch
    jmp .done
.return_only_status:
    cmp bp, 0fffbh
    ja .restore
    mov ax, 810ch
    jmp .done
.success:
    mov ax, 0100h
.done:
    lfs bp, [active_request]
    mov [fs:bp+3], ax
.restore:
    cli
    mov ax, [old_ss]
    mov ss, ax
    mov sp, [cs:old_sp]
    mov byte [cs:busy], 0
.return:
    pop gs
    pop fs
    pop es
    pop ds
    popad
    popf
    retf
.busy:
    les bx, [cs:request]
    cmp bx, 0fffbh
    ja .return
    mov word [es:bx+3], 810ch
    jmp .return

ioctl_buffer:
    cmp byte [fs:bp], 20
    jb .bad
    mov cx, [fs:bp+18]
    test cx, cx
    jz .bad
    les di, [fs:bp+14]
    movzx eax, di
    movzx edx, cx
    add eax, edx
    cmp eax, 10000h
    ja .bad
    clc
    ret
.bad:
    stc
    ret

ioctl_input:
    call ioctl_buffer
    jc request_error
    movzx bx, byte [es:di]
    cmp bx, 15
    ja request_unknown
    mov al, [ioctl_sizes+bx]
    test al, al
    jz request_unknown
    movzx ax, al
    cmp cx, ax
    jb request_error
    mov [fs:bp+18], ax
    cmp bl, 0
    je .header
    cmp bl, 6
    je .status
    cmp bl, 7
    je .sector_size
    cmp bl, 9
    je .changed
    cmp word [si+HANDLE], 0ffffh
    je request_not_ready
    cmp bl, 8
    je .size
    cmp bl, 10
    je .disc
    cmp bl, 11
    je .track
    xor eax, eax
    mov [es:di+1], ax
    mov [es:di+3], eax
    mov [es:di+7], eax
    jmp request_ok
.header:
    mov word [es:di+1], header
    mov [es:di+3], cs
    jmp request_ok
.status:
    xor eax, eax
    cmp byte [si+LOCKED], 0
    jne .lock_status
    or ax, 2
.lock_status:
    cmp word [si+HANDLE], 0ffffh
    jne .status_done
    or ax, 0800h
.status_done:
    mov [es:di+1], eax
    jmp request_ok
.sector_size:
    cmp byte [es:di+1], 0
    jne request_unknown
    mov word [es:di+2], 2048
    jmp request_ok
.changed:
    mov al, [si+CHANGED]
    mov [es:di+1], al
    mov byte [si+CHANGED], 1
    jmp request_ok
.size:
    mov eax, [si+SECTORS]
    mov [es:di+1], eax
    jmp request_ok
.disc:
    mov word [es:di+1], 0101h
    mov eax, [si+SECTORS]
    add eax, 150
    xor edx, edx
    mov ecx, 4500
    div ecx
    mov [es:di+5], al
    mov eax, edx
    xor edx, edx
    mov ecx, 75
    div ecx
    mov [es:di+3], dl
    mov [es:di+4], al
    mov byte [es:di+6], 0
    jmp request_ok
.track:
    cmp byte [es:di+1], 1
    jne request_unknown
    mov dword [es:di+2], 00000200h
    mov byte [es:di+6], 40h
    jmp request_ok
ioctl_sizes db 5,0,0,0,0,0,5,4,5,2,7,7,0,0,0,11

ioctl_output:
    call ioctl_buffer
    jc request_error
    mov al, [es:di]
    cmp al, 1
    je .lock
    cmp al, 2
    je .reset
    cmp al, 5
    je request_ok
    test al, al
    jnz request_unknown
    cmp byte [si+LOCKED], 0
    jne request_error
    call dos_enter
    call eject_unit
    call dos_leave
    jc request_error
    jmp request_ok
.lock:
    cmp cx, 2
    jb request_error
    mov al, [es:di+1]
    cmp al, 1
    ja request_unknown
    mov [si+LOCKED], al
    jmp request_ok
.reset:
    mov byte [si+CHANGED], 0ffh
    jmp request_ok

read_sectors:
    cmp byte [fs:bp], 27
    jb request_error
    mov cx, [fs:bp+18]
    mov [read_remaining], cx
    mov word [read_completed], 0
    mov word [fs:bp+18], 0
    cmp word [si+HANDLE], 0ffffh
    je request_not_ready
    cmp byte [fs:bp+13], 0
    jne request_unknown
    cmp byte [fs:bp+24], 0
    jne request_unknown
    cmp word [fs:bp+25], 0
    jne request_unknown
    mov eax, [fs:bp+20]
    movzx edx, cx
    add edx, eax
    jc .range
    cmp edx, [si+SECTORS]
    ja .range
    test cx, cx
    jz request_ok
    movzx edx, word [fs:bp+14]
    movzx ebx, word [fs:bp+16]
    shl ebx, 4
    add ebx, edx
    movzx edx, cx
    shl edx, 11
    add edx, ebx
    cmp edx, 100000h
    ja .range
    mov dx, bx
    and dx, 15
    shr ebx, 4
    mov [read_destination], dx
    mov [read_destination+2], bx
    shl eax, 11
    mov edx, eax
    shr eax, 16
    mov cx, ax
    mov bx, [si+HANDLE]
    call dos_enter
    mov ax, 4200h
    int 21h
    jc .io_failure
.next:
    mov ax, [cs:read_remaining]
    cmp ax, 31
    jbe .chunk
    mov ax, 31
.chunk:
    mov [cs:read_chunk], ax
    mov cx, ax
    shl cx, 11
    mov si, [cs:unit_pointer]
    mov bx, [cs:si+HANDLE]
    lds dx, [cs:read_destination]
    mov ah, 3fh
    int 21h
    push cs
    pop ds
    jc .io_failure
    mov dx, ax
    shr ax, 11
    add [read_completed], ax
    cmp ax, [read_chunk]
    jne .io_failure
    test dx, 2047
    jnz .io_failure
    sub [read_remaining], ax
    jz .read_done
    shl ax, 7
    add [read_destination+2], ax
    jmp .next
.read_done:
    call dos_leave
    lfs bp, [active_request]
    mov ax, [read_completed]
    mov [fs:bp+18], ax
    jmp request_ok
.io_failure:
    push cs
    pop ds
    call dos_leave
    lfs bp, [active_request]
    mov ax, [read_completed]
    mov [fs:bp+18], ax
    mov ax, 810bh
    ret
.range:
    mov ax, 8108h
    ret

request_ok:
    mov ax, 0100h
    ret
request_unknown:
    mov ax, 8103h
    ret
request_error:
    mov ax, 810ch
    ret
request_not_ready:
    mov ax, 8102h
    ret

; Foreground ABI: AX=0 query, 1 mount, 2 eject; BL=unit; DS:DX=path.
; AX returns 0/1 for empty/loaded, or 8001h..8006h for an error.
control:
    pushf
    pushad
    push ds
    push es
    push fs
    push gs
    cli
    cmp byte [cs:busy], 0
    jne .busy
    mov byte [cs:busy], 1
    mov [cs:old_ss], ss
    mov [cs:old_sp], sp
    mov [cs:control_op], ax
    mov [cs:path_pointer], dx
    mov [cs:path_pointer+2], ds
    mov ax, cs
    mov ss, ax
    mov sp, stack_top
    mov ds, ax
    sti
    cld
    mov word [control_result], 8001h
    cmp bl, [unit_count]
    jae .done
    movzx si, bl
    shl si, 3
    add si, units
    mov [unit_pointer], si
    cmp word [control_op], 0
    je .query
    mov word [control_result], 8002h
    cmp byte [si+LOCKED], 0
    jne .done
    les bx, [indos_pointer]
    cmp byte [es:bx], 0
    jne .done
    cmp word [control_op], 2
    je .eject
    cmp word [control_op], 1
    jne .done
    call dos_enter
    call mount_image
    call dos_leave
    jmp .done
.eject:
    call dos_enter
    call eject_unit
    call dos_leave
    jc .done
    mov word [control_result], 0
    jmp .done
.query:
    xor ax, ax
    cmp word [si+HANDLE], 0ffffh
    je .state
    inc ax
.state:
    mov [control_result], ax
.done:
    cli
    mov ax, [old_ss]
    mov ss, ax
    mov sp, [cs:old_sp]
    mov byte [cs:busy], 0
    pop gs
    pop fs
    pop es
    pop ds
    popad
    popf
    mov ax, [cs:control_result]
    retf
.busy:
    pop gs
    pop fs
    pop es
    pop ds
    popad
    popf
    mov ax, 8002h
    retf

mount_image:
    mov word [control_result], 8003h
    lds dx, [path_pointer]
    mov ax, 3d20h
    int 21h
    push cs
    pop ds
    jc .return
    mov [candidate], ax
    mov bx, ax
    xor cx, cx
    xor dx, dx
    mov ax, 4202h
    int 21h
    jc .reject
    mov word [control_result], 8004h
    movzx eax, ax
    movzx edx, dx
    shl edx, 16
    or eax, edx
    test eax, 800007ffh
    jnz .reject
    shr eax, 11
    cmp eax, 18
    jb .reject
    mov [candidate_sectors], eax
    mov dword [descriptor_sector], 16
.descriptor:
    mov bx, [candidate]
    mov eax, [descriptor_sector]
    shl eax, 11
    mov edx, eax
    shr eax, 16
    mov cx, ax
    mov ax, 4200h
    int 21h
    jc .reject
    mov dx, pvd
    mov cx, 192
    mov ah, 3fh
    int 21h
    jc .reject
    cmp ax, 192
    jne .reject
    cmp dword [pvd+1], 'CD00'
    jne .reject
    cmp byte [pvd+5], '1'
    jne .reject
    cmp byte [pvd+6], 1
    jne .reject
    cmp byte [pvd], 1
    je .primary
    cmp byte [pvd], 255
    je .reject
    inc dword [descriptor_sector]
    mov eax, [descriptor_sector]
    cmp eax, [candidate_sectors]
    jb .descriptor
    jmp .reject
.primary:
    cmp dword [pvd+128], 00080800h
    jne .reject
    mov eax, [pvd+80]
    cmp eax, 18
    jb .reject
    cmp eax, [candidate_sectors]
    ja .reject
    mov edx, [pvd+84]
    xchg dl, dh
    rol edx, 16
    xchg dl, dh
    cmp eax, edx
    jne .reject
    mov [candidate_sectors], eax
    cmp byte [pvd+156], 34
    jb .reject
    test byte [pvd+181], 2
    jz .reject
    cmp byte [pvd+188], 1
    jne .reject
    cmp byte [pvd+189], 0
    jne .reject
    mov eax, [pvd+158]
    mov edx, [pvd+162]
    xchg dl, dh
    rol edx, 16
    xchg dl, dh
    cmp eax, edx
    jne .reject
    mov ebx, eax
    mov eax, [pvd+166]
    mov edx, [pvd+170]
    xchg dl, dh
    rol edx, 16
    xchg dl, dh
    cmp eax, edx
    jne .reject
    test eax, eax
    jz .reject
    add eax, 2047
    jc .reject
    shr eax, 11
    add eax, ebx
    jc .reject
    cmp eax, [candidate_sectors]
    ja .reject
    mov si, [unit_pointer]
    mov word [control_result], 8005h
    call eject_unit
    jc .reject
    mov ax, [candidate]
    mov [si+HANDLE], ax
    mov eax, [candidate_sectors]
    mov [si+SECTORS], eax
    mov byte [si+CHANGED], 0ffh
    mov word [control_result], 0
    ret
.reject:
    mov bx, [candidate]
    mov ah, 3eh
    int 21h
.return:
    ret

eject_unit:
    mov bx, [si+HANDLE]
    cmp bx, 0ffffh
    je .empty
    mov ah, 3eh
    int 21h
    jc .return
.empty:
    mov word [si+HANDLE], 0ffffh
    mov dword [si+SECTORS], 0
    mov byte [si+CHANGED], 0ffh
    clc
.return:
    ret

; The file handles belong to the resident PSP. Save DOS state for nested reads.
dos_enter:
    pushad
    push ds
    push es
    lds si, [cs:sda_pointer]
    push cs
    pop es
    mov di, sda_save
    mov cx, [cs:sda_size]
    cld
    rep movsb
    mov ah, 62h
    int 21h
    mov [cs:caller_psp], bx
    mov bx, [cs:resident_psp]
    mov ah, 50h
    int 21h
    xor ax, ax
    mov es, ax
    pushf
    cli
    mov eax, [es:24h*4]
    mov [cs:old_int24], eax
    mov word [es:24h*4], critical_error
    mov [es:24h*4+2], cs
    popf
    pop es
    pop ds
    popad
    ret

dos_leave:
    pushf
    pushad
    push ds
    push es
    xor ax, ax
    mov es, ax
    pushf
    cli
    mov eax, [cs:old_int24]
    mov [es:24h*4], eax
    popf
    mov bx, [cs:caller_psp]
    mov ah, 50h
    int 21h
    push cs
    pop ds
    mov si, sda_save
    les di, [sda_pointer]
    mov cx, [sda_size]
    cld
    rep movsb
    pop es
    pop ds
    popad
    popf
    ret

critical_error:
    mov al, 3
    iret

pvd times 192 db 0
    align 16
    times 1024 db 0
stack_top:
sda_save:
    times 4096 db 0

install:
    cld
    mov [cs:resident_psp], ds
    push ds
    pop es
    push cs
    pop ds
    mov si, 81h
.spaces:
    mov al, [es:si]
    inc si
    cmp al, ' '
    je .spaces
    cmp al, 13
    je .options_done
    dec si
    mov di, units_option
    mov cx, 7
.option:
    mov al, [es:si]
    cmp al, [di]
    jne install_usage
    inc si
    inc di
    loop .option
    mov al, [es:si]
    sub al, '1'
    cmp al, MAX_UNITS-1
    ja install_usage
    inc al
    mov [unit_count], al
    inc si
.trailing:
    mov al, [es:si]
    inc si
    cmp al, ' '
    je .trailing
    cmp al, 13
    jne install_usage
.options_done:
    mov ah, 30h
    int 21h
    cmp al, 5
    jb install_dos_error
    mov ax, 5d06h
    clc
    int 21h
    jc install_dos_error_restore
    mov [cs:sda_pointer], si
    mov [cs:sda_pointer+2], ds
    push cs
    pop ds
    test cx, cx
    jz install_dos_error
    cmp cx, 4096
    ja install_dos_error
    mov [sda_size], cx
    mov ah, 34h
    int 21h
    mov [indos_pointer], bx
    mov [indos_pointer+2], es
    mov ah, 52h
    int 21h
    add bx, 22h
    push es
    push bx
.scan:
    cmp dword [es:bx+10], 'UCDD'
    jne .next_device
    cmp dword [es:bx+14], '0001'
    je install_duplicate
.next_device:
    cmp word [es:bx], 0ffffh
    je .link
    les bx, [es:bx]
    jmp .scan
.link:
    pop bx
    pop es
    mov eax, [es:bx]
    mov [header], eax
    mov [header+30], cs
    pushf
    cli
    mov word [es:bx], header
    mov [es:bx+2], cs
    popf
    mov es, [resident_psp]
    mov ax, [es:2ch]
    test ax, ax
    jz .message
    mov word [es:2ch], 0
    mov es, ax
    mov ah, 49h
    int 21h
.message:
    mov dx, installed_message
    mov ah, 9
    int 21h
    mov dx, [sda_size]
    add dx, sda_save+15
    shr dx, 4
    add dx, 16
    mov ax, 3100h
    int 21h
install_usage:
    mov dx, usage_message
    jmp install_fail
install_dos_error:
    mov dx, dos_message
    jmp install_fail
install_dos_error_restore:
    push cs
    pop ds
    jmp install_dos_error
install_duplicate:
    mov dx, duplicate_message
install_fail:
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
units_option db '-units '
installed_message db 'The uCDD driver is installed.',13,10,'$'
usage_message db 'Use UCDDRV -units 1 to 4.',13,10,'$'
dos_message db 'This DOS version is not supported.',13,10,'$'
duplicate_message db 'The uCDD driver is already installed.',13,10,'$'
