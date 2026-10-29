; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%ifdef RESIDENT_AUDIO
%define UCDD_DIAG 1
%endif
%include "audio/diag.inc"

; The driver part reaches the audio part's data through GS (the audio segment)
; and its code through far entries. Without the internal host both parts are
; one segment.
%ifdef OWN_HOST
%define AUDSEG gs:
%macro AUDIO_CALL 2
    call far [cs:%1]
%endmacro
%macro AUDIO_LOAD_GS 0
    mov gs, [cs:audio_seg]
%endmacro
; SI is a unit of the driver part. FS gets the unit's segment for the call.
%macro AUDIO_BIND 0
    call far [cs:audio_bind_far]
%endmacro
%else
%define AUDSEG cs:
%macro AUDIO_CALL 2
    call %2
%endmacro
%macro AUDIO_LOAD_GS 0
%endmacro
%macro AUDIO_BIND 0
    push fs
    push cs
    pop fs
    call audio_bind
    pop fs
%endmacro
%endif

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
%ifndef UCDD_ENTRY_IP
%define UCDD_ENTRY_IP 32
%endif
%if ($-$$) != UCDD_ENTRY_IP
%error The driver header size does not match the EXE entry point.
%endif
    jmp helper_enter

request dd 0
active_request dd 0
busy db 0
old_ss dw 0
old_sp dw 0
resident_psp dw 0
%ifdef OWN_HOST
; The segment that the audio part's labels use, and the far entries into it.
; With the whole image in one block it is the driver's own segment.
audio_seg dw 0
audio_bind_far dw audio_bind_entry,0
clear_state_far dw clear_state_entry,0
reconsider_far dw reconsider_entry,0
volume_far dw hotkey_volume_entry,0
%else
%ifdef RESIDENT_AUDIO
memory_mode db 0
keep_vcpi db 0
%endif
%endif
caller_psp dw 0
; 1 between dos_enter and dos_leave: DOS calls use the resident PSP.
dos_entered db 0
sda_pointer dd 0
sda_size dw 0
indos_pointer dd 0
old_int23 dd 0
old_int24 dd 0
unit_pointer dw 0
control_op dw 0
control_result dw 0
path_pointer dd 0
candidate dw 0ffffh
candidate_sectors dd 0
candidate_total dd 0
candidate_file_total dd 0
candidate_file_origin dd 0
candidate_limit dd 0
candidate_stride dw 0
candidate_payload dw 0
candidate_origin dd 0
candidate_count dw 0
candidate_audio db 0
read_skip dw 0
descriptor_sector dd 0
read_remaining dw 0
read_completed dw 0
read_bytes dw 0
read_destination dd 0
%ifdef RESIDENT_AUDIO
%define DRIVER_STAGE 1
stage_valid db 0
stage_unit dw 0
stage_handle dw 0
stage_first dd 0
stage_count dd 0
stage_next dd 0
%endif
units_base dw 0
%ifdef OWN_HOST
cold_stack dw 0
%endif

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
    mov ds, ax
    AUDIO_LOAD_GS
%ifdef OWN_HOST
    mov ss, [cold_stack]
    mov sp, COLD_STACK_TOP
%else
    mov ss, ax
    mov sp, stack_top
%endif
    mov eax, [request]
    mov [active_request], eax
    sti
    cld
    call mdm_switch
    lfs bp, [active_request]
    cmp bp, 0fff3h
    ja .return_only_status
    ; Drives ignore the length field (Tunnel B1: 0 and 5, Jetstrike: IOCTL 0).
    ; Handlers check the bounds of the fields they read.
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
    ; A repeated INIT reports the status only (UBBFIX checks the busy bit).
    test al, al
    jz .success
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
    cmp al, 82h
    je .success
    cmp al, 83h
    je .seek
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
.seek:
    ; A data image has no head to move.
    cmp dword [si+AUDIO_ENTRY], 0
    jne .audio
    mov ax, 8102h
    cmp word [si+HANDLE], 0ffffh
    je .done
.success:
    mov ax, 0100h
.done:
%ifdef RESIDENT_AUDIO
    ; SHSUCDX requires an exact success status for data reads.
    cmp ax, 0100h
    jne .status
    lfs bp, [active_request]
    cmp byte [fs:bp+2], 80h
    je .status
    mov si, [unit_pointer]
    cmp dword [si+AUDIO_ENTRY], 0
    je .status
    cmp byte [AUDSEG cd_started], 0
    je .status
    mov edx, [AUDSEG cd_consumed]
    cmp edx, [AUDSEG cd_length]
    jae .status
    or ah, 2
.status:
%endif
    lfs bp, [active_request]
    mov [fs:bp+3], ax
.restore:
    cli
    mov ss, [cs:old_ss]
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
%ifdef UCDD_DIAG
    AUDIO_LOAD_GS
    inc word [AUDSEG diag_busy]
    mov al, [es:bx+2]
    mov [AUDSEG diag_busy_command], al
%endif
    mov word [es:bx+3], 810ch
    jmp .return

ioctl_buffer:
    cmp bp, 0ffech
    ja .bad
    ; Drives write the fixed control block size and ignore the count
    ; (Aegis, Warcraft II). Absolute Pinball sends a zero count.
    mov cx, [fs:bp+18]
    les di, [fs:bp+14]
    movzx bx, byte [es:di]
    xor ax, ax
    cmp byte [fs:bp+2], 3
    jne .output_size
    cmp bx, 15
    ja .extend
    mov al, [ioctl_sizes+bx]
    jmp .extend
.output_size:
    cmp bx, 5
    ja .extend
    mov al, [ioctl_output_sizes+bx]
.extend:
    test cx, cx
    jnz .count_ok
    mov cl, 11
.count_ok:
    cmp ax, cx
    jbe .size_ok
    mov cx, ax
.size_ok:
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
    ; Only code 1 comes here. A data image reports its first sector.
    cmp dword [si+AUDIO_ENTRY], 0
    jne audio_request
    xor eax, eax
    cmp [es:di+1], al
    je .location
    mov ah, 2
.location:
    mov [es:di+2], eax
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
    mov eax, 400h
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
    cmp dword [si+AUDIO_ENTRY], 0
    jne audio_request
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
    call lba_msf
    mov [es:di+3], eax
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
    call lba_msf
    mov [es:di+2], eax
    jmp request_ok
ioctl_sizes db 5,6,0,0,9,0,5,4,5,2,7,7,11,0,0,11
ioctl_output_sizes db 1,2,1,9,0,1

; EAX: image sector. Return frame, second and minute in bytes 0 to 2 of EAX.
lba_msf:
    sub eax, [si+ORIGIN]
    add eax, 150
    xor edx, edx
    mov ecx, 4500
    div ecx
    shl eax, 16
    xchg ax, dx
    mov cl, 75
    div cl
    xchg al, ah
    ret

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
    ; Keep the MDM set. Eject only the current disc, as the hotkey does.
    cmp si, [mdm_unit]
    jne .eject_image
    mov byte [mdm_ejected], 1
    call clear_unit
    jmp .ejected
.eject_image:
    call dos_enter
    call eject_unit
    call dos_leave
.ejected:
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
    ; Drives ignore the length field (Necromantics: 0).
    cmp bp, 10000h-26
    ja request_error
    mov cx, [fs:bp+18]
    mov [read_remaining], cx
    mov word [read_completed], 0
    mov word [fs:bp+18], 0
    cmp word [si+HANDLE], 0ffffh
    je request_not_ready
    cmp byte [fs:bp+13], 1
    ja request_unknown
    cmp byte [fs:bp+24], 0
    jne request_unknown
    ; A zero skip is contiguous for any interleave size.
    cmp byte [fs:bp], 27
    jb .interleave_ok
    cmp byte [fs:bp+26], 0
    jne request_unknown
.interleave_ok:
    mov eax, [fs:bp+20]
    cmp byte [fs:bp+13], 0
    je .hsg
    ; Red Book: minute*4500 + second*75 + frame - 150. The range check
    ; below also rejects a result under zero.
    movzx edx, al
    movzx ebx, ah
    imul ebx, ebx, 75
    add edx, ebx
    movzx eax, byte [fs:bp+22]
    imul eax, eax, 4500
    add eax, edx
    sub eax, 150
.hsg:
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
    mov edx, [si+TRACKS+TRACK_CONTROL]
    shr edx, 8
    sub eax, edx
%ifdef RESIDENT_AUDIO
    ; Short raw reads: one DOS read stages several sectors.
    cmp word [si+STRIDE], 2048
    je .direct
    cmp word [read_remaining], CD_STAGE_SECTORS
    jbe read_staged
.direct:
%endif
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
    cmp bx, [AUDSEG cd_handle]
    jne .audio_position_ready
    mov byte [AUDSEG cd_seek], 1
.audio_position_ready:
%endif
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
    mov cx, ax
    shl cx, 11
    cmp word [read_skip], 0
    je .read_chunk
    ; Raw input must fit in the caller's remaining cooked buffer.
    mov ax, cx
    sub ax, 2048
    xor dx, dx
    mov bx, [read_skip]
    add bx, 2048
    div bx
    mul bx
    add ax, 2048
    mov cx, ax
.read_chunk:
    mov [read_bytes], cx
    mov si, [cs:unit_pointer]
    mov bx, [cs:si+HANDLE]
    lds dx, [cs:read_destination]
    mov ah, 3fh
    int 21h
    push cs
    pop ds
    jc .io_failure
    mov dx, ax
    cmp word [read_skip], 0
    je .cooked_result
    push dx
    call compact_raw_read
    pop dx
    jmp .count_result
.cooked_result:
    shr ax, 11
.count_result:
    add [read_completed], ax
    cmp dx, [read_bytes]
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

%ifdef RESIDENT_AUDIO
; EAX=image sector of the first sector, SI=unit. Copy the payloads from the stage.
read_staged:
    mov [stage_next], eax
    mov bx, [si+HANDLE]
    cmp bx, [AUDSEG cd_handle]
    jne .position_ready
    mov byte [AUDSEG cd_seek], 1
.position_ready:
    call dos_enter
.next:
    mov si, [unit_pointer]
    mov eax, [stage_next]
    cmp byte [stage_valid], 0
    je .fill
    cmp si, [stage_unit]
    jne .fill
    mov bx, [si+HANDLE]
    cmp bx, [stage_handle]
    jne .fill
    sub eax, [stage_first]
    jb .fill
    cmp eax, [stage_count]
    jb .copy
.fill:
    mov byte [stage_valid], 0
    mov eax, [stage_next]
    movzx edx, word [si+STRIDE]
    imul eax, edx
    mov dx, ax
    shr eax, 16
    mov cx, ax
    mov bx, [si+HANDLE]
    mov ax, 4200h
    int 21h
    jc read_sectors.io_failure
    mov ax, CD_STAGE_SECTORS
    mul word [si+STRIDE]
    mov cx, ax
    mov bx, [si+HANDLE]
    push ds
    mov ds, [AUDSEG cd_work_segment]
    xor dx, dx
    mov ah, 3fh
    int 21h
    pop ds
    jc read_sectors.io_failure
    xor dx, dx
    div word [si+STRIDE]
    movzx eax, ax
    test eax, eax
    jz read_sectors.io_failure
    mov [stage_count], eax
    mov eax, [stage_next]
    mov [stage_first], eax
    mov [stage_unit], si
    mov bx, [si+HANDLE]
    mov [stage_handle], bx
    mov byte [stage_valid], 1
    xor eax, eax
.copy:
    movzx edx, word [si+STRIDE]
    imul eax, edx
    movzx edx, word [si+PAYLOAD]
    add eax, edx
    push ds
    push es
    les di, [read_destination]
    mov ds, [AUDSEG cd_work_segment]
    mov si, ax
    mov cx, 512
    cld
    rep movsd
    pop es
    pop ds
    add word [read_destination+2], 128
    inc dword [stage_next]
    inc word [read_completed]
    dec word [read_remaining]
    jnz .next
    jmp read_sectors.read_done
%endif

compact_raw_read:
    push bx
    push cx
    push si
    push di
    push bp
    push ds
    push es
    cmp ax, 2048
    jb .empty
    sub ax, 2048
    xor dx, dx
    mov bx, [read_skip]
    add bx, 2048
    div bx
    inc ax
    cmp ax, 1
    jbe .done
    push ax
    mov bp, ax
    dec bp
    lds si, [read_destination]
    push ds
    pop es
    mov di, si
    add di, 2048
    add si, bx
.copy:
    mov cx, 512
    rep movsd
    add si, [cs:read_skip]
    dec bp
    jnz .copy
    pop ax
    jmp .done
.empty:
    xor ax, ax
.done:
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop cx
    pop bx
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
; AX: 9 set the CD sample filter of the caller, or remove it with 0:0.
; AX: 10 copy the diagnostic block (UCDD -status), 11 the same and then reset it.
; DS:DX points to image info (1/3), the audio callback (4/5), the filter (9),
; or a buffer of DIAG_BYTES bytes (10/11).
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
    mov ds, ax
    AUDIO_LOAD_GS
%ifdef OWN_HOST
    mov ss, [cold_stack]
    mov sp, COLD_STACK_TOP
%else
    mov ss, ax
    mov sp, stack_top
%endif
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
    cmp word [control_op], 9
    je .filter
    cmp word [control_op], 10
    je .diag
    cmp word [control_op], 11
    je .diag
%endif
    mov word [control_result], 8002h
    cmp byte [si+LOCKED], 0
    jne .done
    cmp dword [si+AUDIO_ENTRY], 0
%ifdef RESIDENT_AUDIO
    je .change
    cmp word [si+AUDIO_ENTRY], cd_request
    jne .done
%ifdef OWN_HOST
    mov ax, [audio_seg]
%else
    mov ax, cs
%endif
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
    jmp .reconsider
.mdm_mount:
    call dos_enter
    call mdm_mount
    call dos_leave
    jmp .reconsider
.mdm_name:
    call mdm_name
    jmp .done
.eject:
    call dos_enter
    call eject_unit
    call dos_leave
    jc .reconsider
    mov word [control_result], 0
.reconsider:
%ifdef RESIDENT_AUDIO
    ; A mount or an eject may change whether the driver has anything to add.
    AUDIO_CALL reconsider_far, audio_reconsider
%endif
    jmp .done
.query:
    xor ax, ax
    cmp si, [mdm_unit]
    je .loaded
    cmp word [si+HANDLE], 0ffffh
    jne .loaded
    ; A hotkey eject keeps the image mounted.
    cmp si, [units_base]
    jne .state
    cmp word [eject_handle], 0ffffh
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
    mov ax, [AUDSEG resident_paragraphs]
    stosw
    mov ax, [AUDSEG output_allocation]
    stosw
    mov ax, [AUDSEG output_segment]
    stosw
    mov al, [AUDSEG fault]
    or al, [AUDSEG cd_error]
    or al, [AUDSEG pm_bridge_fault]
    or al, [AUDSEG pm_cleanup_fault]
    xor ah, ah
    stosw
    mov ax, [resident_psp]
    stosw
    mov ax, [AUDSEG cd_half_allocation]
    stosw
    mov ax, [AUDSEG cd_half_segment]
    stosw
    mov ax, [AUDSEG cd_work_allocation]
    stosw
    mov ax, [AUDSEG cd_work_segment]
    stosw
    movzx ax, byte [AUDSEG memory_mode]
    stosw
%ifdef OWN_HOST
    mov ax, [AUDSEG own_host_stack]
%else
    xor ax, ax
%endif
    stosw
    mov word [control_result], 0
    jmp .done
; The block (audio/resident.asm) with the periods since the reset. The copy
; and the reset run with interrupts off.
.diag:
    les di, [path_pointer]
    cmp di, 10000h-DIAG_BYTES
    ja .done
    mov si, diag_block
    mov cx, DIAG_BYTES/4
    cli
    push ds
%ifdef OWN_HOST
    mov ds, [audio_seg]
%endif
    rep movsd
    pop ds
    mov eax, [AUDSEG periods]
    sub eax, [AUDSEG diag_periods]
    mov [es:di-DIAG_BYTES+4], eax
    movzx eax, byte [AUDSEG audio_engaged]
    mov [es:di-4], eax
    cmp word [control_op], 11
    jne .diag_done
    mov eax, [AUDSEG periods]
    mov [AUDSEG diag_periods], eax
%ifdef OWN_HOST
    mov es, [audio_seg]
%else
    push cs
    pop es
%endif
    mov di, diag_queue_low
    mov cx, (diag_end-diag_queue_low)/4
    xor eax, eax
    rep stosd
.diag_done:
    sti
    mov word [control_result], 0
    jmp .done
.filter:
    les bx, [sda_pointer]
    mov ax, [es:bx+10h]
    mov [AUDSEG cd_filter_owner], ax
    mov eax, [path_pointer]
    mov [AUDSEG cd_filter_hook], eax
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
    mov ss, [cs:old_ss]
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
    call handle_record
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
    ; The helper sets payload 16 (MODE1) or 24 (MODE2 Form 1).
    mov dx, [es:di+INFO_PAYLOAD]
    or dl, 8
    cmp dx, 24
    jne .reject
    jmp .format_ok
.iso_format:
    cmp word [es:di+INFO_PAYLOAD], 0
    jne .reject
    cmp word [es:di+INFO_COUNT], 1
    jbe .format_ok
    mov ebx, [es:di+INFO_TRACKS+TRACK_SIZE+TRACK_INDEX0]
    mov edx, [es:di+INFO_TRACKS+TRACK_CONTROL]
    shr edx, 8
    sub ebx, edx
    jc .reject
    imul edx, ebx, 2048
    jo .reject
    sub eax, edx
    jc .reject
    xor edx, edx
    mov ecx, 2352
    div ecx
    test edx, edx
    jnz .reject
    add eax, ebx
    mov ecx, 2048
    jmp .sector_count
.format_ok:
    xor edx, edx
    div ecx
    test edx, edx
    jnz .reject
.sector_count:
    mov [candidate_stride], cx
    mov dx, [es:di+INFO_PAYLOAD]
    mov [candidate_payload], dx
    mov [candidate_total], eax
    mov [candidate_file_total], eax
    mov [candidate_limit], eax
    mov eax, [es:di+INFO_ORIGIN]
    mov [candidate_origin], eax
    mov edx, [es:di+INFO_TRACKS+TRACK_CONTROL]
    shr edx, 8
    sub eax, edx
    jc .reject
    mov [candidate_file_origin], eax
    mov ax, [es:di+INFO_COUNT]
    test ax, ax
    jz .reject
    cmp ax, MAX_TRACKS
    ja .reject
    mov [candidate_count], ax
    mov al, [es:di+INFO_TRACKS+TRACK_CONTROL]
    ; An audio CD has no data track. Data reads fail as on a drive.
    mov [candidate_audio], al
    test al, 40h
    jnz .data_first
    cmp word [candidate_stride], 2352
    jne .reject
    jmp .first_ok
.data_first:
    and al, 0dfh
    cmp al, 40h
    jne .reject
.first_ok:
    mov eax, [es:di+INFO_TRACKS+TRACK_START]
    cmp eax, [candidate_origin]
    jne .reject
    mov cx, [candidate_count]
    add di, INFO_TRACKS
    xor ebx, ebx
    xor edx, edx
.validate_track:
    mov eax, [es:di+TRACK_INDEX0]
    sub eax, edx
    jc .reject
    cmp eax, ebx
    jb .reject
    mov ebx, eax
    mov eax, [es:di+TRACK_CONTROL]
    shr eax, 8
    cmp eax, edx
    jb .reject
    mov edx, eax
    mov eax, [es:di+TRACK_START]
    sub eax, edx
    jc .reject
    cmp eax, ebx
    jb .reject
    cmp eax, [candidate_file_total]
    jae .reject
    mov ebx, eax
    inc ebx
    mov al, [es:di+TRACK_CONTROL]
    test al, 0fh
    jnz .reject
    test al, 40h
    jz .control_ok
    test al, 90h
    jnz .reject
.control_ok:
    add di, TRACK_SIZE
    loop .validate_track
    mov eax, [candidate_file_total]
    add eax, edx
    jc .reject
    movzx ebx, word [candidate_stride]
    cmp word [candidate_count], 1
    je .disc_bytes
    mov ebx, 2352
.disc_bytes:
    imul ebx, eax
    jo .reject
    test ebx, ebx
    js .reject
    mov [candidate_total], eax
    mov [candidate_limit], eax
    cmp word [candidate_count], 1
    je .data_limit
    les di, [path_pointer]
    mov eax, [es:di+INFO_TRACKS+TRACK_SIZE+TRACK_INDEX0]
    mov [candidate_limit], eax
.data_limit:
    test byte [candidate_audio], 40h
    jnz .data_track
    mov dword [candidate_sectors], 0
    jmp .checked
.data_track:
    mov eax, [candidate_limit]
    sub eax, [candidate_origin]
    cmp eax, 18
    jb .reject
    mov [candidate_sectors], eax
    mov dword [descriptor_sector], 16
.descriptor:
    mov bx, [candidate]
    mov eax, [descriptor_sector]
    add eax, [candidate_file_origin]
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
    mov si, pvd+80
    call both_endian
    jne .reject
    cmp eax, 18
    jb .reject
    ; The City of Lost Children states a volume larger than its image.
    ; Limit directory validation, not sector reads, to the ISO volume.
    cmp eax, [candidate_sectors]
    jbe .volume_limit
    mov eax, [candidate_sectors]
.volume_limit:
    mov [candidate_limit], eax
    cmp byte [pvd+156], 34
    jb .reject
    ; FX Fighter and Hexen have nonstandard root record name bytes.
    test byte [pvd+181], 2
    jz .reject
    mov si, pvd+158
    call both_endian
    jne .reject
    mov ebx, eax
    call both_endian
    jne .reject
    test eax, eax
    jz .reject
    add eax, 2047
    jc .reject
    shr eax, 11
    add eax, ebx
    jc .reject
    cmp eax, [candidate_limit]
    ja .reject
.checked:
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
%ifdef DRIVER_STAGE
    mov byte [cs:stage_valid], 0
%endif
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
    AUDIO_BIND
%endif
    mov word [control_result], 0
    ret
.reject:
    mov bx, [candidate]
    mov ah, 3eh
    int 21h
.return:
    ret

; DS:SI: an ISO both-endian dword. Return EAX, ZF set if both halves agree.
both_endian:
    lodsd
    xchg eax, edx
    lodsd
    xchg al, ah
    rol eax, 16
    xchg al, ah
    cmp eax, edx
    xchg eax, edx
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
    jne .close
    ; A hotkey eject keeps the image open.
    cmp si, [units_base]
    jne .empty
    xchg bx, [eject_handle]
    cmp bx, 0ffffh
    je .empty
.close:
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
    AUDIO_CALL clear_state_far, cd_clear_state
    mov word [AUDSEG cd_handle], 0ffffh
    mov dword [si+AUDIO_ENTRY], 0
%endif
    mov word [si+HANDLE], 0ffffh
%ifdef DRIVER_STAGE
    mov byte [cs:stage_valid], 0
%endif
    mov dword [si+SECTORS], 0
    mov byte [si+CHANGED], 0ffh
    clc
    ret

; The file handles belong to the resident PSP. Save DOS state for nested reads.
dos_enter:
    pushad
    push ds
    push es
%ifdef UCDD_DIAG
    cmp byte [cs:dos_entered], 0
    je .first
%ifdef OWN_HOST
    push gs
    AUDIO_LOAD_GS
    inc word [AUDSEG diag_nested]
    pop gs
%else
    inc word [cs:diag_nested]
%endif
.first:
%endif
    lds si, [cs:sda_pointer]
%ifdef OWN_HOST
    mov es, [cs:cold_stack]
    mov di, COLD_SDA_OFFSET
%else
    push cs
    pop es
    mov di, sda_save
%endif
    mov cx, [cs:sda_size]
    cld
    rep movsb
    mov ah, 62h
    int 21h
    mov [cs:caller_psp], bx
    mov bx, [cs:resident_psp]
    mov ah, 50h
    int 21h
    call handle_check
    xor ax, ax
    mov es, ax
    ; A nested entry keeps the hooks and the saved vectors of the outer one.
    cmp byte [cs:dos_entered], 0
    jne .vectors_kept
    pushf
    cli
    mov eax, [es:23h*4]
    mov [cs:old_int23], eax
    mov word [es:23h*4], break_ignore
    mov [es:23h*4+2], cs
    mov eax, [es:24h*4]
    mov [cs:old_int24], eax
    mov word [es:24h*4], critical_error
    mov [es:24h*4+2], cs
    popf
.vectors_kept:
    mov byte [cs:dos_entered], 1
    pop es
    pop ds
    popad
    ret

; Ultimate Body Blows writes into the first SFT block and changes the
; SFT numbers. Keep the resident handles on their SFT entries.
handle_sft times 20 dd 0

; BX=handle of the resident PSP.
handle_record:
    pushad
    push es
    cmp bx, 20
    jae .done
    mov bp, bx
    shl bp, 2
    mov ax, 1220h
    int 2fh
    jc .done
    movzx bx, byte [es:di]
    mov ax, 1216h
    int 2fh
    jc .done
    mov [cs:handle_sft+bp], di
    mov [cs:handle_sft+bp+2], es
.done:
    pop es
    popad
    ret

handle_check:
    pushad
    push es
    xor bp, bp
.next:
    cmp dword [cs:handle_sft+bp], 0
    je .skip
    mov bx, bp
    shr bx, 2
    mov ax, 1220h
    int 2fh
    jc .skip
    movzx bx, byte [es:di]
    cmp bl, 0ffh
    je .skip
    push es
    push di
    call .match
    je .kept
    xor bx, bx
.find:
    call .match
    je .found
    jc .kept
    inc bx
    cmp bx, 0ffh
    jb .find
    jmp .kept
.found:
    pop di
    pop es
    mov [es:di], bl
    jmp .skip
.kept:
    pop di
    pop es
.skip:
    add bp, 4
    cmp bp, 20*4
    jb .next
    pop es
    popad
    ret
; ZF set when SFT entry BX is the recorded entry. CF set past the last entry.
.match:
    ; DOS returns the index inside the block in BX.
    push bx
    mov ax, 1216h
    int 2fh
    pop bx
    jc .end
    cmp di, [cs:handle_sft+bp]
    jne .other
    mov ax, es
    cmp ax, [cs:handle_sft+bp+2]
.other:
    clc
    ret
.end:
    or al, 1
    stc
    ret

dos_leave:
    pushf
    pushad
    push ds
    push es
    mov byte [cs:dos_entered], 0
    xor ax, ax
    mov es, ax
    pushf
    cli
    mov eax, [cs:old_int23]
    mov [es:23h*4], eax
    mov eax, [cs:old_int24]
    mov [es:24h*4], eax
    popf
    mov bx, [cs:caller_psp]
    mov ah, 50h
    int 21h
    push cs
    pop ds
    les di, [sda_pointer]
    mov cx, [sda_size]
%ifdef OWN_HOST
    mov ds, [cs:cold_stack]
    mov si, COLD_SDA_OFFSET
%else
    mov si, sda_save
%endif
    cld
    rep movsb
    pop es
    pop ds
    popad
    popf
    ret

critical_error:
    mov al, 3
break_ignore:
    iret

%ifdef OWN_HOST
; Far entries for the audio part.
dos_enter_entry:
    call dos_enter
    retf
dos_leave_entry:
    call dos_leave
    retf
%endif

%include "mdm.asm"

pvd times 192 db 0
    align 16
%ifdef OWN_HOST
; The driver part ends with the one unit. The audio part follows at a
; paragraph boundary, so that it can sit in a block of its own: its segment
; is the block's segment less audio_start/16, and its labels keep their
; offsets. The SDA copy and the driver stack are in the cold block.
units times UNIT_SIZE db 0
    align 16
audio_start:
%include "audio/resident.asm"
    align 16
; The CD information of the audio part (cd_info) is the last item. Nothing is
; mounted while the install runs, so the install-only code runs in its place
; and the install clears the area afterwards. DOS gets back what the install
; code needs beyond the area.
cd_overlay:
cd_info equ cd_overlay-INFO_STRIDE
resident_tail:
%include "audio/resident_install.asm"
    align 16
resident_tail_end:
CD_INFO_BYTES equ INFO_SIZE-INFO_STRIDE
audio_end equ cd_overlay+((CD_INFO_BYTES+15)/16)*16
cd_overlay_check equ 1 / ((resident_tail_end-cd_overlay) >= CD_INFO_BYTES)
%else
%ifdef RESIDENT_AUDIO
%include "audio/resident.asm"
%endif
    times 1024 db 0
stack_top:
sda_save:
    times 4096+MAX_UNITS*UNIT_SIZE+16 db 0
%endif

install:
    cld
    mov ah, 62h
    int 21h
    mov [resident_psp], bx
    mov es, bx
    mov bx, 16+((program_end-$$+15)/16)+64
    mov ah, 4ah
    int 21h
    mov dx, resize_message
    jc install_fail
    mov ah, 30h
    int 21h
    cmp al, 5
    mov dx, dos_message
    jb install_fail
    mov ax, 5d06h
    clc
    int 21h
    mov dx, sda_message
    jc install_sda_error
    mov [cs:sda_pointer], si
    mov [cs:sda_pointer+2], ds
    push cs
    pop ds
    test cx, cx
    jz install_fail
    cmp cx, 4096
    ja install_fail
    mov [sda_size], cx
%ifdef OWN_HOST
    ; The image has room for one unit.
    cmp byte [unit_count], 1
    mov dx, audio_unit_message
    ja install_fail
%endif
%ifdef OWN_HOST
    ; The cold block holds the driver stack and the SDA copy.
    add cx, 15+COLD_SDA_OFFSET
    shr cx, 4
    mov [cold_paras], cx
    mov di, units
%else
    mov di, sda_save+15
    add di, cx
    and di, 0fff0h
%endif
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
    call resident_prepare
    call resident_relocate
    jc .audio_error
    test ax, ax
    jnz .relocated
%endif
    call audio_activate
    jc .audio_error
%ifdef OWN_HOST
    push cs
    pop es
    call cd_info_clear
    push fs
    push cs
    pop fs
    xor ax, ax
    xor dx, dx
    call ems_guard_build
    pop fs
    cmp byte [resident_umb_short], 0
    je .umb_report_done
    mov ax, (AUDIO_PEAK_PARAS+63)/64
    mov bl, 10
    div bl
    add ax, 3030h
    mov [umb_short_kb], ax
    mov dx, umb_short_message
    mov ah, 9
    int 21h
.umb_report_done:
%endif
    pop bx
    pop es
%ifndef OWN_HOST
    mov byte [audio_linked], 1
%endif
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
    popf
    mov ax, [guard_driver]
    mov dx, [guard_audio]
    mov fs, [audio_seg]
    call ems_guard_build
    mov ax, [resident_psp]
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
    mov dx, [relocated_keep]
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
    call unit_paragraphs
    add dx, 16
%ifdef RESIDENT_AUDIO
    mov [resident_paragraphs], dx
    jmp audio_enter_pm
%endif
    mov ax, 3100h
    int 21h
; Return DX: paragraphs from the image start to the end of what stays.
unit_paragraphs:
%ifdef OWN_HOST
    mov dx, KEPT_PARAS
%else
    movzx dx, byte [unit_count]
    imul dx, UNIT_SIZE
    add dx, [units_base]
    add dx, 15
    shr dx, 4
%endif
    ret
install_sda_error:
    push cs
    pop ds
    jmp install_fail
install_duplicate:
    mov dx, duplicate_message
install_fail:
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
installed_message db 'uCDD ',UCDD_VERSION,' is installed.',13,10,'$'
dos_message db 'uCDD cannot use this DOS version. Use DOS 5 or later.',13,10,'$'
resize_message db 'uCDD cannot change its memory block size.',13,10,'$'
sda_message db 'DOS did not supply its swappable data area.',13,10,'$'
duplicate_message db 'uCDD is already installed.',13,10,'$'
%ifdef RESIDENT_AUDIO
trap_resident_message db 'uCDD keeps its port-trap code in memory.',13,10,'$'
audio_unit_message db 'For CD audio, use only one uCDD drive.',13,10,'$'
dpmi_host_message db 'A compatible DPMI host is not available.',13,10,'$'
port_trap_missing_message db 'No compatible port-trap service is available.',13,10
    db 'Use JEMMEX or JEMM386 5.86 or later.',13,10,'$'
port_trap_rejected_message db 'The memory manager rejected the port-trap request.',13,10
    db 'Check for another sound virtualizer.',13,10,'$'
memory_control_message db 'DOS does not supply the necessary memory functions.',13,10,'$'
xms_memory_message db 'uCDD cannot allocate XMS memory for the CD audio queue.',13,10,'$'
%ifdef EMS_QUEUE
ems_memory_message db 'uCDD cannot allocate EMS memory for the CD audio queue.',13,10,'$'
%endif
irq_table_memory_message db 'uCDD cannot allocate DOS memory for the IRQ table.',13,10,'$'
cd_half_memory_message db 'uCDD cannot allocate DOS memory for the CD mix buffer.',13,10,'$'
%ifdef OWN_HOST
cold_memory_message db 'uCDD cannot allocate DOS memory for the driver data.',13,10,'$'
%endif
cd_work_memory_message db 'uCDD cannot allocate DOS memory for the CD work buffer.',13,10,'$'
dma_memory_message db 'uCDD cannot allocate DOS memory for the DMA buffer.',13,10,'$'
sound_card_message db 'The selected sound card did not start.',13,10
    db 'Check the settings with UCDDSET.',13,10,'$'
ess_answer_message db 'uCDD cannot find an ESS AudioDrive at the selected port.',13,10
    db 'Check the settings with UCDDSET.',13,10,'$'
ess_interrupt_message db 'The sound card does not send interrupts.',13,10
    db 'Check the IRQ setting with UCDDSET.',13,10,'$'
ess_resource_message db 'The IRQ or DMA channel of the ESS card is different from the UCDDSET setting.',13,10
    db 'Check the settings with UCDDSET.',13,10,'$'
ess_rate_message db 'The output rate of the sound card is not correct.',13,10
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
    mov dx, [relocated_keep]
    jmp .stay
.in_place:
%endif
    call unit_paragraphs
    add dx, 16
.stay:
    mov ax, 3101h
    int 21h
%include "audio/configure.asm"
%include "audio/guest_config.asm"
%include "config_path.asm"
%include "audio/ess_install.asm"
%include "disk_scan.asm"
audio_prepare:
    mov word [audio_error_text], audio_unit_message
    cmp byte [unit_count], 1
    jne .bad
    call audio_configure
    jc .bad
    call sb_model
    ; The disk controller IRQs of this machine, found now, and the one set by
    ; hand in UCDDSET. Never the physical card's, which the record just gave.
    call disk_scan
    call disk_mask
    mov [config_disk_mask], ax
%ifdef RESIDENT_AUDIO
    ; The platform for the fast DMA option, found by the scan.
    mov al, [platform_method]
    mov [fast_dma_method], al
    mov ax, [platform_bridge]
    mov [fast_dma_bridge], ax
    mov ax, [platform_device]
    mov [fast_dma_device], ax
%endif
    call disk_report
    call guest_configure
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

; Report the disk IRQs beyond 14 and 15, and a disk IRQ that a sound card
; setting uses too.
disk_report:
    call disk_used
    test ax, ax
    jz .warning
    mov dx, disk_report_message
    mov ah, 9
    int 21h
    mov di, disk_report_buffer
    call disk_mask
    mov byte [disk_irq_first], 1
    call disk_irq_text
    mov si, disk_report_buffer
    call disk_print
.warning:
    call disk_check
    test si, si
    jz .done
    call disk_print
.done:
    ret

; SI text ending in 0. Print it and a line break.
disk_print:
    mov dx, si
    xor cx, cx
.length:
    lodsb
    test al, al
    jz .write
    inc cx
    jmp .length
.write:
    mov bx, 1
    mov ah, 40h
    int 21h
    mov dx, disk_crlf_message
    mov ah, 9
    int 21h
    ret

disk_report_message db 'Disk controller IRQs go to DOS directly: $'
disk_crlf_message db 13,10,'$'
disk_report_buffer times 56 db 0
%ifdef OWN_HOST

; Tie the two parts together in the image that is about to be copied.
; AX: driver segment. DX: segment of the audio part's labels.
resident_set_segments:
    mov [audio_seg], dx
    mov [audio_bind_far+2], dx
    mov [clear_state_far+2], dx
    mov [reconsider_far+2], dx
    mov [volume_far+2], dx
    mov [driver_seg], ax
    mov [dos_enter_far+2], ax
    mov [dos_leave_far+2], ax
    mov [mdm_scan_far+2], ax
    mov [mdm_hooks_far+2], ax
    ret

; ES: the audio segment. The install-only code ran in the area of cd_info.
cd_info_clear:
    push ax
    push cx
    push di
    mov di, cd_info+INFO_STRIDE
    mov cx, (CD_INFO_BYTES+1)/2
    xor ax, ax
    cld
    rep stosw
    pop di
    pop cx
    pop ax
    ret

; Values for the audio part that only the install knows.
resident_prepare:
    mov ax, [resident_psp]
    mov [audio_psp], ax
    mov word [resident_paragraphs], KEPT_PARAS
    mov al, [config_modifiers]
    mov [hot_modifiers], al
    mov al, [config_disc_keys]
    mov [hot_disc_keys], al
    push ds
    pop es
    mov si, config_keys
    mov di, hot_keys
    mov cx, 11
    cld
    rep movsb
    ret

; The program image is the driver part and the audio part with the
; install-only code. In upper memory the parts go in one block, or in two
; when no block is large enough; the install-only code goes when the
; activation ends. The driver part stays in the image when it finds no block.
; Return AX: the driver segment after a copy, or 0 when the install stays in
; place. [relocated_keep]: paragraphs that DOS keeps at the PSP.
resident_relocate:
    mov ax, cs
    cmp ax, 0a000h
    jae .in_place
    mov word [relocated_keep], 16
    mov word [driver_alloc], 0
    mov word [guard_driver], 0
    mov word [guard_audio], 0
%ifdef SPLIT_TEST
    jmp .split
%endif
    mov bx, RESIDENT_PEAK_PARAS
    call resident_allocate_high
    jc .split
    mov [audio_block], ax
    mov [driver_block], ax
    mov [guard_driver], ax
    mov dx, ax
    call resident_set_segments
    mov es, ax
    mov cx, RESIDENT_PEAK_PARAS*8
    xor si, si
    xor di, di
    rep movsw
    mov dx, [driver_block]
    jmp .activate
.split:
    mov bx, AUDIO_PEAK_PARAS
    call resident_allocate_high
    jc .in_place
    cmp ax, AUDIO_BASE_PARAS
    jae .audio_ok
    mov es, ax
    mov ah, 49h
    int 21h
    jmp .in_place
.audio_ok:
    mov [audio_block], ax
    mov [guard_audio], ax
%ifdef SPLIT_TEST
%if SPLIT_TEST == 2
    jmp .driver_low
%endif
%endif
    mov bx, AUDIO_BASE_PARAS
    call resident_allocate_high
    jnc .driver_high
.driver_low:
    ; The driver part stays here: DOS keeps it with the PSP.
    mov ax, cs
    mov word [relocated_keep], 16+AUDIO_BASE_PARAS
    jmp .driver_ready
.driver_high:
    mov [driver_alloc], ax
    mov [guard_driver], ax
.driver_ready:
    mov [driver_block], ax
    mov dx, [audio_block]
    sub dx, AUDIO_BASE_PARAS
    call resident_set_segments
    cmp word [driver_alloc], 0
    je .audio_copy
    mov es, [driver_alloc]
    mov cx, AUDIO_BASE_PARAS*8
    xor si, si
    xor di, di
    rep movsw
.audio_copy:
    mov es, [audio_block]
    mov cx, AUDIO_PEAK_PARAS*8
    mov si, audio_start
    xor di, di
    rep movsw
    mov dx, [audio_seg]
.activate:
    mov [relocated_entry+2], dx
    mov ds, dx
    call far [cs:relocated_entry]
    jc .activate_bad
    push cs
    pop ds
    mov es, [audio_seg]
    call cd_info_clear
    ; Give back the install-only code: the end of the audio block.
    mov es, [audio_block]
    mov bx, AUDIO_KEEP_PARAS
    mov ax, es
    cmp ax, [driver_block]
    jne .shrink
    mov bx, KEPT_PARAS
.shrink:
    mov ah, 4ah
    int 21h
    mov ax, [driver_block]
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
    mov es, [audio_block]
    mov ah, 49h
    int 21h
    cmp word [driver_alloc], 0
    je .retained
    mov es, [driver_alloc]
    mov ah, 49h
    int 21h
.retained:
    stc
    ret
.in_place:
    push cs
    pop ds
    mov ax, cs
    mov dx, ax
    call resident_set_segments
    xor ax, ax
    clc
    ret

; BX: paragraphs. Return AX: the block, or CF set.
resident_allocate_high:
    mov [resident_request], bx
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
    mov bx, [resident_request]
    mov ah, 48h
    int 21h
    jnc .allocated
    ; Upper memory is there, but no block is large enough.
    mov byte [resident_umb_short], 1
    jmp .restore
.allocated:
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

AUDIO_BASE_PARAS equ (audio_start-$$)/16
AUDIO_KEEP_PARAS equ (audio_end-audio_start)/16
AUDIO_PEAK_PARAS equ (resident_tail_end-audio_start)/16
RESIDENT_PEAK_PARAS equ (resident_tail_end-$$)/16
KEPT_PARAS equ (audio_end-$$)/16
relocated_entry dw audio_activate_far,0
relocated_keep dw 16
resident_allocation dw 0
resident_strategy dw 0
resident_request dw 0
resident_umb db 0
resident_umb_short db 0
umb_short_message db 'uCDD stays in conventional memory. It needs a free upper memory block of '
umb_short_kb db '00 KB.',13,10,'$'
audio_block dw 0
driver_block dw 0
driver_alloc dw 0
guard_driver dw 0
guard_audio dw 0

; A game can map EMS pages over a UMB. List the mappable pages that overlap a
; uCDD block, so that the host refuses EMS map calls into them.
; FS: the audio segment. AX, DX: the relocated driver block and audio block,
; or 0.
ems_guard_build:
    push ds
    push es
    push gs
    pushad
    mov [ems_guard_blocks+2], ax
    mov [ems_guard_blocks+14], dx
    mov ax, [resident_psp]
    mov [ems_guard_blocks], ax
    mov ax, [fs:output_allocation]
    mov [ems_guard_blocks+4], ax
    mov ax, [fs:cd_half_allocation]
    mov [ems_guard_blocks+6], ax
    mov ax, [fs:cd_work_allocation]
    mov [ems_guard_blocks+8], ax
    mov ax, [fs:cold_allocation]
    mov [ems_guard_blocks+12], ax
    mov ax, [fs:host_irq_table_block]
    mov [ems_guard_blocks+16], ax
    mov ax, [fs:own_host_active+2]
    mov [ems_guard_blocks+10], ax
    test ax, ax
    jz .done
    cmp word [fs:own_host_guard], 0
    je .done
    mov ax, 5801h
    int 67h
    test ah, ah
    jnz .done
    cmp cx, EMS_MAP_MAX
    ja .done
    mov [ems_map_left], cx
    push ds
    pop es
    mov di, ems_map_buffer
    mov ax, 5800h
    int 67h
    test ah, ah
    jnz .done
    mov es, [fs:own_host_active+2]
    mov di, [fs:own_host_guard]
    mov si, ems_map_buffer
.page:
    cmp word [ems_map_left], 0
    je .done
    ; The page covers segments AX to AX+3FFh.
    mov ax, [si]
    mov bx, ems_guard_blocks
    mov cx, EMS_GUARD_BLOCKS
.block:
    mov dx, [bx]
    test dx, dx
    jz .next_block
    dec dx
    mov gs, dx
    cmp byte [gs:0], 'M'
    je .arena
    cmp byte [gs:0], 'Z'
    jne .next_block
.arena:
    ; The block with its arena header covers DX to BP-1.
    mov bp, dx
    add bp, [gs:3]
    inc bp
    cmp ax, bp
    jae .next_block
    mov bp, ax
    add bp, 400h
    cmp dx, bp
    jae .next_block
    mov bp, [es:di]
    cmp bp, [es:di+2]
    jae .done
    shl bp, 2
    add bp, di
    mov dx, [si+2]
    mov [es:bp+4], dx
    mov [es:bp+6], ax
    inc word [es:di]
    jmp .next_page
.next_block:
    add bx, 2
    loop .block
.next_page:
    add si, 4
    dec word [ems_map_left]
    jmp .page
.done:
    popad
    pop gs
    pop es
    pop ds
    ret

EMS_GUARD_BLOCKS equ 9
EMS_MAP_MAX equ 64
; PSP, driver block, DMA rings, CD half buffer, CD work buffer, host gateway,
; cold block, audio block, JEMMEX IRQ table.
ems_guard_blocks times EMS_GUARD_BLOCKS dw 0
ems_map_left dw 0
ems_map_buffer times EMS_MAP_MAX*4 db 0
%endif
%endif
