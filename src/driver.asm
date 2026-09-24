; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

    jmp command_entry

header:
    dd 0ffffffffh
    dw 0c800h
    dw strategy, interrupt
    db 'UCDD0001'
    dw 0
    db 0
unit_count db 1
    db 'uCDD'
    dw 2
    dw control, 0

request dd 0
active_request dd 0
busy db 0
old_ss dw 0
old_sp dw 0
resident_psp dw 0
%ifdef RESIDENT_AUDIO
memory_mode db 0
%endif
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
candidate_total dd 0
candidate_limit dd 0
candidate_stride dw 0
candidate_payload dw 0
candidate_origin dd 0
candidate_count dw 0
read_skip dw 0
descriptor_sector dd 0
read_remaining dw 0
read_completed dw 0
read_chunk dw 0
read_destination dd 0
units_base dw 0

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
    call mdm_switch
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
    imul ax, UNIT_SIZE
    add ax, [units_base]
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
    cmp al, 83h
    je .audio
    cmp al, 84h
    je .audio
    cmp al, 85h
    je .audio
    cmp al, 88h
    je .audio
    mov ax, 8103h
    jmp .done
.audio:
    call audio_request
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
    cmp bp, 0ffech
    ja .bad
    cmp byte [fs:bp], 13
    je .header_ok
    cmp byte [fs:bp], 18
    je .header_ok
    cmp byte [fs:bp], 20
    jb .bad
.header_ok:
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
    cmp bl, 1
    je audio_request
    cmp bl, 4
    je audio_request
    cmp bl, 12
    je audio_request
    cmp bl, 15
    je .audio_status
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
.audio_status:
    cmp dword [si+AUDIO_ENTRY], 0
    jne audio_request
    cmp cx, 11
    jb request_error
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
    cmp dword [si+AUDIO_ENTRY], 0
    je .status_store
    or ax, 0310h
.status_store:
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
    mov byte [es:di+1], 1
    mov al, [si+TRACK_COUNT]
    mov [es:di+2], al
    mov eax, [si+DISC_SECTORS]
    sub eax, [si+ORIGIN]
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
    movzx ax, byte [es:di+1]
    test ax, ax
    jz request_unknown
    cmp ax, [si+TRACK_COUNT]
    ja request_unknown
    dec ax
    imul bx, ax, TRACK_SIZE
    add bx, si
    mov al, [bx+TRACKS+TRACK_CONTROL]
    mov [es:di+6], al
    mov eax, [bx+TRACKS+TRACK_START]
    sub eax, [si+ORIGIN]
    add eax, 150
    xor edx, edx
    mov ecx, 4500
    div ecx
    mov [es:di+4], al
    mov eax, edx
    xor edx, edx
    mov ecx, 75
    div ecx
    mov [es:di+2], dl
    mov [es:di+3], al
    mov byte [es:di+5], 0
    jmp request_ok
ioctl_sizes db 5,0,0,0,0,0,5,4,5,2,7,7,0,0,0,11

ioctl_output:
    call ioctl_buffer
    jc request_error
    mov al, [es:di]
    cmp al, 3
    je audio_request
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
    cmp dword [si+AUDIO_ENTRY], 0
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
    cmp dword [si+AUDIO_ENTRY], 0
    jne audio_request
    mov byte [si+CHANGED], 0ffh
    jmp request_ok

audio_request:
    cmp dword [si+AUDIO_ENTRY], 0
    je request_unknown
    call far [si+AUDIO_ENTRY]
    ret

read_sectors:
    cmp byte [fs:bp], 26
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
    cmp byte [fs:bp+25], 0
    jne request_unknown
    cmp byte [fs:bp], 27
    jb .interleave_ok
    cmp byte [fs:bp+26], 0
    jne request_unknown
.interleave_ok:
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
    add eax, [si+ORIGIN]
    movzx edx, word [si+STRIDE]
    imul eax, edx
    movzx edx, word [si+PAYLOAD]
    add eax, edx
    mov dx, [si+STRIDE]
    sub dx, 2048
    mov [read_skip], dx
    mov edx, eax
    shr eax, 16
    mov cx, ax
    mov bx, [si+HANDLE]
%ifdef RESIDENT_AUDIO
    cmp bx, [cd_handle]
    jne .audio_position_ready
    mov byte [cd_seek], 1
.audio_position_ready:
%endif
    call dos_enter
    mov ax, 4200h
    int 21h
    jc .io_failure
.next:
    mov ax, 1
    cmp word [read_skip], 0
    jne .chunk
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
    cmp word [read_skip], 0
    je .next
    mov dx, [read_skip]
    xor cx, cx
    mov si, [unit_pointer]
    mov bx, [si+HANDLE]
    mov ax, 4201h
    int 21h
    jc .io_failure
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

; AX: 0 query, 1 mount, 2 eject, 3 describe, 4 attach, 5 detach. BL: unit.
; AX: 7 mount MDM, 8 copy its name (128 bytes). See MDM_INPUT_SIZE.
; DS:DX points to image info (1/3) or the audio callback (4/5).
; AX returns 0/1 for empty/loaded, or 8001h..8007h for an error.
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
    imul si, UNIT_SIZE
    add si, [units_base]
    mov [unit_pointer], si
    cmp word [control_op], 0
    je .query
    cmp word [control_op], 3
    je .describe
    cmp word [control_op], 4
    je .attach
    cmp word [control_op], 5
    je .detach
    cmp word [control_op], 8
    je .mdm_name
%ifdef RESIDENT_AUDIO
    cmp word [control_op], 6
    je .audio_report
%endif
    mov word [control_result], 8002h
    cmp byte [si+LOCKED], 0
    jne .done
    cmp dword [si+AUDIO_ENTRY], 0
%ifdef RESIDENT_AUDIO
    je .change
    cmp word [si+AUDIO_ENTRY], cd_request
    jne .done
    mov ax, cs
    cmp [si+AUDIO_ENTRY+2], ax
%endif
    jne .done
%ifdef RESIDENT_AUDIO
.change:
%endif
    les bx, [indos_pointer]
    cmp byte [es:bx], 0
    jne .done
    cmp word [control_op], 2
    je .eject
    cmp word [control_op], 7
    je .mdm_mount
    cmp word [control_op], 1
    jne .done
    cmp word [path_pointer], 10000h-INFO_SIZE
    ja .done
    call dos_enter
    call mount_image
    call dos_leave
    jmp .done
.mdm_mount:
    call dos_enter
    call mdm_mount
    call dos_leave
    jmp .done
.mdm_name:
    call mdm_name
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
    cmp si, [mdm_unit]
    je .loaded
    cmp word [si+HANDLE], 0ffffh
    je .state
.loaded:
    inc ax
.state:
    mov [control_result], ax
    jmp .done
%ifdef RESIDENT_AUDIO
.audio_report:
    les di, [path_pointer]
    cmp di, 10000h-26
    ja .done
    mov ax, 4
    stosw
    mov ax, cs
    stosw
    mov ax, [resident_paragraphs]
    stosw
    mov ax, [output_allocation]
    stosw
    mov ax, [output_segment]
    stosw
    mov al, [fault]
    or al, [cd_error]
    or al, [pm_bridge_fault]
    or al, [pm_cleanup_fault]
    xor ah, ah
    stosw
    mov ax, [resident_psp]
    stosw
    mov ax, [cd_half_allocation]
    stosw
    mov ax, [cd_half_segment]
    stosw
    mov ax, [cd_work_allocation]
    stosw
    mov ax, [cd_work_segment]
    stosw
    movzx ax, byte [memory_mode]
    stosw
%ifdef OWN_HOST
    mov ax, [own_host_stack]
%else
    xor ax, ax
%endif
    stosw
    mov word [control_result], 0
    jmp .done
%endif
.describe:
    cmp word [si+HANDLE], 0ffffh
    je .done
    les di, [path_pointer]
    cmp di, 10000h-INFO_SIZE
    ja .done
    push si
    add si, IMAGE_PATH
    mov cx, 128
    rep movsb
    pop si
    push si
    add si, STRIDE
    mov cx, 4
    rep movsw
    pop si
    mov ax, [si+TRACK_COUNT]
    stosw
    push si
    add si, TRACKS
    mov cx, MAX_TRACKS*TRACK_SIZE/2
    rep movsw
    pop si
    mov eax, [si+DISC_SECTORS]
    stosd
    mov word [control_result], 0
    jmp .done
.attach:
    cmp word [si+HANDLE], 0ffffh
    je .done
    cmp dword [si+AUDIO_ENTRY], 0
    jne .done
    mov eax, [path_pointer]
    test eax, eax
    jz .done
    mov [si+AUDIO_ENTRY], eax
    mov word [control_result], 0
    jmp .done
.detach:
    mov eax, [path_pointer]
    cmp eax, [si+AUDIO_ENTRY]
    jne .done
    mov dword [si+AUDIO_ENTRY], 0
    mov word [control_result], 0
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
    test eax, 80000000h
    jnz .reject
    les di, [path_pointer]
    movzx ecx, word [es:di+INFO_STRIDE]
    cmp cx, 2048
    je .iso_format
    cmp cx, 2352
    jne .reject
    cmp word [es:di+INFO_PAYLOAD], 16
    jne .reject
    jmp .format_ok
.iso_format:
    cmp word [es:di+INFO_PAYLOAD], 0
    jne .reject
    cmp word [es:di+INFO_COUNT], 1
    jne .reject
.format_ok:
    mov [candidate_stride], cx
    mov dx, [es:di+INFO_PAYLOAD]
    mov [candidate_payload], dx
    xor edx, edx
    div ecx
    test edx, edx
    jnz .reject
    mov [candidate_total], eax
    mov [candidate_limit], eax
    mov eax, [es:di+INFO_ORIGIN]
    mov [candidate_origin], eax
    mov ax, [es:di+INFO_COUNT]
    test ax, ax
    jz .reject
    cmp ax, MAX_TRACKS
    ja .reject
    mov [candidate_count], ax
    cmp byte [es:di+INFO_TRACKS+TRACK_CONTROL], 40h
    jne .reject
    mov eax, [es:di+INFO_TRACKS+TRACK_START]
    cmp eax, [candidate_origin]
    jne .reject
    mov cx, [candidate_count]
    add di, INFO_TRACKS
    xor ebx, ebx
.validate_track:
    mov eax, [es:di+TRACK_INDEX0]
    cmp eax, ebx
    jb .reject
    cmp eax, [es:di+TRACK_START]
    ja .reject
    mov eax, [es:di+TRACK_START]
    cmp eax, [candidate_total]
    jae .reject
    mov ebx, eax
    inc ebx
    mov al, [es:di+TRACK_CONTROL]
    and al, 0bfh
    jnz .reject
    add di, TRACK_SIZE
    loop .validate_track
    cmp word [candidate_count], 1
    je .data_limit
    les di, [path_pointer]
    mov eax, [es:di+INFO_TRACKS+TRACK_SIZE+TRACK_INDEX0]
    mov [candidate_limit], eax
.data_limit:
    mov eax, [candidate_limit]
    sub eax, [candidate_origin]
    cmp eax, 18
    jb .reject
    mov [candidate_sectors], eax
    mov dword [descriptor_sector], 16
.descriptor:
    mov bx, [candidate]
    mov eax, [descriptor_sector]
    add eax, [candidate_origin]
    movzx edx, word [candidate_stride]
    imul eax, edx
    movzx edx, word [candidate_payload]
    add eax, edx
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
    mov edx, [candidate_total]
    sub edx, [candidate_origin]
    cmp eax, edx
    ja .reject
    mov edx, [pvd+84]
    xchg dl, dh
    rol edx, 16
    xchg dl, dh
    cmp eax, edx
    jne .reject
    ; Some mixed-mode discs include audio sectors in the volume size.
    cmp eax, [candidate_sectors]
    jae .volume_limit
    mov [candidate_sectors], eax
.volume_limit:
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
    cmp word [control_op], 7
    jne .commit
    mov word [control_result], 0
    ret
.commit:
    mov si, [unit_pointer]
    mov word [control_result], 8005h
    call eject_unit
    jc .reject
    mov ax, [candidate]
    mov [si+HANDLE], ax
    mov eax, [candidate_sectors]
    mov [si+SECTORS], eax
    mov eax, [candidate_total]
    mov [si+DISC_SECTORS], eax
    mov ax, [candidate_stride]
    mov [si+STRIDE], ax
    mov ax, [candidate_payload]
    mov [si+PAYLOAD], ax
    mov eax, [candidate_origin]
    mov [si+ORIGIN], eax
    mov ax, [candidate_count]
    mov [si+TRACK_COUNT], ax
    mov di, si
    add di, IMAGE_PATH
    push ds
    pop es
    lds si, [path_pointer]
    mov cx, 128
    rep movsb
    push cs
    pop ds
    mov di, [unit_pointer]
    add di, TRACKS
    lds si, [path_pointer]
    add si, INFO_TRACKS
    mov cx, [cs:candidate_count]
    imul cx, TRACK_SIZE
    rep movsb
    push cs
    pop ds
    mov si, [unit_pointer]
    mov byte [si+CHANGED], 0ffh
%ifdef RESIDENT_AUDIO
    call audio_bind
%endif
    mov word [control_result], 0
    ret
.reject:
    mov bx, [candidate]
    mov ah, 3eh
    int 21h
.return:
    ret

eject_unit:
    cmp si, [mdm_unit]
    jne .single
    call mdm_release
    pushf
    call .empty
    popf
    ret
.single:
    mov bx, [si+HANDLE]
    cmp bx, 0ffffh
    je .empty
    mov ah, 3eh
    int 21h
    jc .return
.empty:
    call clear_unit
    ret
.return:
    ret

clear_unit:
%ifdef RESIDENT_AUDIO
    call cd_clear_state
    mov word [cd_handle], 0ffffh
    mov dword [si+AUDIO_ENTRY], 0
%endif
    mov word [si+HANDLE], 0ffffh
    mov dword [si+SECTORS], 0
    mov byte [si+CHANGED], 0ffh
    clc
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

%include "mdm.asm"

%ifdef RESIDENT_AUDIO
%include "audio/resident.asm"
audio_error_text dw audio_unit_message
%endif

pvd times 192 db 0
    align 16
    times 1024 db 0
stack_top:
sda_save:
    times 4096+MAX_UNITS*UNIT_SIZE+16 db 0

install:
    cld
    mov ah, 62h
    int 21h
    mov [resident_psp], bx
    mov es, bx
    mov bx, 16+((program_end-$$+15)/16)+64
    mov ah, 4ah
    int 21h
    jc install_dos_error
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
    mov di, sda_save+15
    add di, cx
    and di, 0fff0h
    mov [units_base], di
    push ds
    pop es
    movzx cx, byte [unit_count]
.init_unit:
    mov ax, 0ffffh
    stosw
    xor ax, ax
    stosw
    stosw
    mov ax, 00ffh
    stosw
    push cx
    xor ax, ax
    mov cx, (UNIT_SIZE-8)/2
    rep stosw
    pop cx
    loop .init_unit
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
%ifdef RESIDENT_AUDIO
    push es
    push bx
    call audio_prepare
    jc .audio_error
%ifdef OWN_HOST
    call resident_relocate
    jc .audio_error
    test ax, ax
    jnz .relocated
%endif
    call audio_activate
    jc .audio_error
    pop bx
    pop es
    mov byte [audio_linked], 1
    jmp .audio_link
.audio_error:
    pop bx
    pop es
    jmp install_audio_error
%ifdef OWN_HOST
.relocated:
    pop bx
    pop es
    mov dx, ax
    mov fs, ax
    mov eax, [es:bx]
    mov [fs:header], eax
    mov [fs:header+30], dx
    pushf
    cli
    mov word [es:bx], header
    mov [es:bx+2], dx
    mov byte [fs:audio_linked], 1
    popf
    push fs
    pop es
    mov ax, [es:resident_psp]
    mov es, ax
    mov ax, [es:2ch]
    test ax, ax
    jz .relocated_message
    mov word [es:2ch], 0
    mov es, ax
    mov ah, 49h
    int 21h
.relocated_message:
    push cs
    pop ds
    mov dx, installed_message
    mov ah, 9
    int 21h
    mov ax, [resident_psp]
    cli
    mov ss, ax
    mov sp, 100h
    sti
    mov dx, 16
    mov ax, 3100h
    int 21h
%endif
.audio_link:
%endif
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
%ifndef RESIDENT_AUDIO
    mov dx, installed_message
    mov ah, 9
    int 21h
%endif
    movzx dx, byte [unit_count]
    imul dx, UNIT_SIZE
    add dx, [units_base]
    add dx, 15
    shr dx, 4
    add dx, 16
%ifdef RESIDENT_AUDIO
    mov [resident_paragraphs], dx
    jmp audio_enter_pm
%endif
    mov ax, 3100h
    int 21h
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
installed_message db 'The uCDD driver is installed.',13,10,'$'
dos_message db 'This DOS version is not supported.',13,10,'$'
duplicate_message db 'The uCDD driver is already installed.',13,10,'$'
%ifdef RESIDENT_AUDIO
trap_resident_message db 'uCDD keeps its port-trap code in memory.',13,10,'$'
audio_unit_message db 'CD audio currently requires one uCDD drive.',13,10,'$'
dpmi_host_message db 'A compatible DPMI host is not available.',13,10,'$'
port_trap_missing_message db 'No compatible port-trap service is available.',13,10
    db 'Use HIMEM with EMM386, JEMMEX, JEMM386, or 386MAX.',13,10,'$'
port_trap_rejected_message db 'The memory manager rejected the port-trap request.',13,10
    db 'Check for another sound virtualizer.',13,10,'$'
memory_control_message db 'DOS does not provide the required memory controls.',13,10,'$'
xms_memory_message db 'uCDD cannot allocate XMS memory for the CD audio queue.',13,10,'$'
%ifdef EMS_QUEUE
ems_memory_message db 'uCDD cannot allocate EMS memory for the CD audio queue.',13,10,'$'
%endif
cd_half_memory_message db 'uCDD cannot allocate DOS memory for the CD mix buffer.',13,10,'$'
cd_work_memory_message db 'uCDD cannot allocate DOS memory for the CD work buffer.',13,10,'$'
dma_memory_message db 'uCDD cannot allocate DOS memory for the DMA buffer.',13,10,'$'
sound_card_message db 'The selected sound card did not start.',13,10
    db 'Check the settings with UCDDSET.',13,10,'$'
internal_host_message db 'The internal DPMI host did not start.',13,10,'$'
install_audio_error:
    mov dx, [audio_error_text]
    cmp byte [audio_detach_failed], 0
    je install_fail
    mov ah, 9
    int 21h
    mov dx, trap_resident_message
    mov ah, 9
    int 21h
%ifdef OWN_HOST
    cmp word [relocated_entry+2], 0
    je .in_place
    mov ax, [resident_psp]
    cli
    mov ss, ax
    mov sp, 100h
    sti
    mov dx, 16
    jmp .stay
.in_place:
%endif
    movzx dx, byte [unit_count]
    imul dx, UNIT_SIZE
    add dx, [units_base]
    add dx, 15
    shr dx, 4
    add dx, 16
.stay:
    mov ax, 3101h
    int 21h
    jmp install_fail
%include "audio/configure.asm"
%include "audio/guest_config.asm"
%include "config_path.asm"
audio_prepare:
    mov word [audio_error_text], audio_unit_message
    cmp byte [unit_count], 1
    jne .bad
    call guest_configure
    jc .bad
    call audio_configure
    jc .bad
    cmp byte [sound_card], 3
    jne .pro_rate
    mov dword [output_rate], 44444
    mov dword [cd_step], (44100*65536)/44444
    mov dword [cd_step_remainder], (44100*65536) % 44444
    jmp .format_ready
.pro_rate:
    cmp byte [sound_card], 1
    jne .format_ready
    mov dword [output_rate], 43478
    mov dword [cd_step], (44100*65536)/43478
    mov dword [cd_step_remainder], (44100*65536) % 43478
.format_ready:
    clc
    ret
.bad:
    stc
    ret
%ifdef OWN_HOST

resident_relocate:
    mov ax, cs
    cmp ax, 0a000h
    jae .in_place
    movzx bx, byte [unit_count]
    imul bx, UNIT_SIZE
    add bx, [units_base]
    add bx, 15
    shr bx, 4
    mov [resident_paragraphs], bx
    push bx
    call resident_allocate_high
    pop dx
    jc .in_place
    mov [relocated_entry+2], ax
    mov es, ax
    mov cx, dx
    shl cx, 3
    xor si, si
    xor di, di
    rep movsw
    mov [es:resident_paragraphs], dx
    mov ds, ax
    call far [cs:relocated_entry]
    jc .activate_bad
    push cs
    pop ds
    mov ax, [relocated_entry+2]
    clc
    ret
.activate_bad:
    mov dx, [audio_error_text]
    mov cl, [audio_detach_failed]
    push cs
    pop ds
    mov [audio_error_text], dx
    mov [audio_detach_failed], cl
    test cl, cl
    jnz .retained
    mov es, [relocated_entry+2]
    mov ah, 49h
    int 21h
.retained:
    stc
    ret
.in_place:
    push cs
    pop ds
    xor ax, ax
    clc
    ret

resident_allocate_high:
    mov word [resident_allocation], 0
    mov ax, 5800h
    int 21h
    jc .bad
    mov [resident_strategy], ax
    mov ax, 5802h
    int 21h
    jc .bad
    mov [resident_umb], al
    mov ax, 5803h
    mov bx, 1
    int 21h
    jc .bad
    mov ax, 5801h
    mov bx, 40h
    int 21h
    jc .restore_umb
    mov bx, [resident_paragraphs]
    mov ah, 48h
    int 21h
    jc .restore
    mov [resident_allocation], ax
.restore:
    mov bx, [resident_strategy]
    mov ax, 5801h
    int 21h
.restore_umb:
    movzx bx, byte [resident_umb]
    mov ax, 5803h
    int 21h
    mov ax, [resident_allocation]
    test ax, ax
    jz .bad
    clc
    ret
.bad:
    stc
    ret

relocated_entry dw audio_activate_far,0
resident_allocation dw 0
resident_strategy dw 0
resident_umb db 0
%endif
%endif
