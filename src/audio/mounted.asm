; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%include "disc.inc"
%define CD_QUEUE_BYTES 524288
%define CD_READ_BYTES 4096
%ifdef RESIDENT_AUDIO
%define EXTERNAL_CD_BUFFERS 1
%define cd_half 0
%define cd_stage 0
%define cd_stack_top (CD_READ_BYTES+2048)
%define SB_TAIL_PARAS 128
%define CD_HALF_DATA_PARAS ((CD_HALF_BYTES+15)/16)
%define CD_HALF_PARAS (CD_HALF_DATA_PARAS+SB_TAIL_PARAS)
%define CD_WORK_PARAS ((cd_stack_top+15)/16)
%endif

; ISA DMA needs conventional RAM even when the parent is loaded high.
cd_memory_low:
    mov ax, 5800h
    int 21h
    jc .done
    mov [cd_allocation_strategy], ax
    mov ax, 5802h
    int 21h
    jc .done
    mov [cd_umb_link], al
    mov byte [cd_memory_saved], 1
    mov ax, 5801h
    xor bx, bx
    int 21h
    jc .done
    cmp byte [cd_umb_link], 0
    je .done
    mov ax, 5803h
    xor bx, bx
    int 21h
.done:
    ret

cd_memory_restore:
    cmp byte [cd_memory_saved], 0
    je .done
    cmp byte [cd_umb_link], 0
    je .strategy
    mov ax, 5803h
    movzx bx, byte [cd_umb_link]
    int 21h
.strategy:
    mov ax, 5801h
    mov bx, [cd_allocation_strategy]
    int 21h
    mov byte [cd_memory_saved], 0
.done:
    ret

cd_open:
%ifndef RESIDENT_AUDIO
    mov ax, 3523h
    int 21h
    mov [cd_old_break], bx
    mov [cd_old_break+2], es
    mov ax, 3524h
    int 21h
    mov [cd_old_critical], bx
    mov [cd_old_critical+2], es
    mov dx, cd_break
    mov ax, 2523h
    int 21h
    mov dx, cd_critical
    mov ax, 2524h
    int 21h
    mov byte [cd_vectors_set], 1
%endif
%ifdef RESIDENT_AUDIO
%ifdef EMS_QUEUE
    cmp byte [memory_mode], 1
    je .ems
%endif
%endif
    mov ax, 4300h
    int 2fh
    cmp al, 80h
    jne .bad
    mov ax, 4310h
    int 2fh
    mov [cd_xms], bx
    mov [cd_xms+2], es
    mov ah, 9
    mov dx, CD_QUEUE_BYTES/1024
    call far [cd_xms]
    cmp ax, 1
    jne .bad
    mov [cd_xms_handle], dx
    mov [cd_write_dest], dx
    mov [cd_read_source], dx
    jmp .queue_ready
%ifdef EMS_QUEUE
.ems:
    mov ah, 40h
    int 67h
    test ah, ah
    jnz .bad
    mov ah, 41h
    int 67h
    test ah, ah
    jnz .bad
    mov [cd_ems_frame], bx
    mov ah, 43h
    mov bx, CD_QUEUE_BYTES/16384
    int 67h
    test ah, ah
    jnz .bad
    mov [cd_ems_handle], dx
%endif
.queue_ready:
%ifdef EXTERNAL_CD_BUFFERS
    mov ax, [cd_work_segment]
    mov [cd_write_address+2], ax
    mov ax, [cd_half_segment]
    mov [cd_read_address+2], ax
%else
    mov [cd_write_address+2], cs
    mov [cd_read_address+2], cs
%endif
    mov ah, 34h
    int 21h
    mov [cd_indos], bx
    mov [cd_indos+2], es
%ifdef RESIDENT_AUDIO
    call cd_cache_open
%endif
%ifdef RESIDENT_AUDIO
    clc
    ret
%else
    push ds
    pop es
    xor bx, bx
    mov ax, 1500h
    int 2fh
    test bx, bx
    jz .bad
    cmp bx, 26
    ja .bad
    mov [cd_drives], bx
    mov bx, cd_devices
    mov ax, 1501h
    int 2fh
    xor si, si
.find:
    cmp si, [cd_drives]
    jae .bad
    imul di, si, 5
    mov bl, [cd_devices+di]
    les di, [cd_devices+di+1]
    cmp dword [es:di+10], 'UCDD'
    jne .next
    cmp dword [es:di+14], '0001'
    jne .next
    cmp dword [es:di+22], 'uCDD'
    jne .next
    cmp word [es:di+26], 2
    jne .next
    mov eax, [es:di+28]
    mov [cd_control], eax
    mov [cd_unit], bl
    mov ax, 3
    mov dx, cd_info
    call far [cd_control]
    test ax, ax
    jnz .next
    cmp word [cd_info+INFO_STRIDE], 2352
    jne .next
    jmp .found
.next:
    inc si
    jmp .find
.found:
    mov eax, [cd_info+INFO_ORIGIN]
    mov [cd_head_lba], eax
    mov dx, cd_info
    mov ax, 3da0h
    int 21h
    jc .bad
    mov [cd_handle], ax
    mov ax, 4
    mov bl, [cd_unit]
    mov dx, cd_request
    call far [cd_control]
    test ax, ax
    jnz .bad
    mov byte [cd_attached], 1
    clc
    ret
%endif
.bad:
    mov byte [cd_error], 1
    stc
    ret

; The drive calls this in the application's foreground CD request.
cd_request:
    pushf
    cli
    pushad
    push ds
    push es
    push fs
    push gs
    push cs
    pop ds
    mov [cd_call_ss], ss
    mov [cd_call_sp], sp
%ifdef EXTERNAL_CD_BUFFERS
    mov ax, [cd_work_segment]
%else
    mov ax, cs
%endif
    mov ss, ax
    mov sp, cd_stack_top
    sti
    cld
%ifdef OWN_HOST
    push es
    push bx
    cmp byte [own_host_refill], 1
    jne .refill_limit_ready
    les bx, [own_host_active]
    cmp byte [es:bx], 1
    jne .refill_limit_ready
    mov byte [cd_background_reads], 0ffh
.refill_limit_ready:
    pop bx
    pop es
%endif
    cmp byte [cd_started], 0
    je .dispatch
    mov eax, [cd_consumed]
    cmp eax, [cd_length]
    jb .dispatch
    call cd_clear_state
.dispatch:
    mov word [cd_result], 810ch
    mov al, [fs:bp+2]
    cmp al, 83h
    je .seek
    cmp al, 84h
    je .play
    cmp al, 85h
    je .stop
    cmp al, 88h
    je .resume
    cmp al, 3
    je .input
    cmp al, 0ch
    jne .done
    cmp byte [es:di], 2
    je .reset
    cmp byte [es:di], 3
    jne .done
    cmp cx, 9
    jb .done
    cmp byte [es:di+1], 0
    jne .done
    cmp byte [es:di+3], 1
    jne .done
    mov al, [es:di+2]
    mov [cd_volume], al
    mov al, [es:di+4]
    mov [cd_volume+1], al
    movzx eax, byte [cd_volume]
    test eax, eax
    jz .left_gain
    inc eax
.left_gain:
    mov [cd_gain], eax
    movzx eax, byte [cd_volume+1]
    test eax, eax
    jz .right_gain
    inc eax
.right_gain:
    mov [cd_gain+4], eax
    jmp .ok
.input:
    cmp byte [es:di], 1
    je .head
    cmp byte [es:di], 4
    je .volume
    cmp byte [es:di], 12
    je .q_channel
    cmp byte [es:di], 15
    jne .done
    cmp cx, 11
    jb .done
    push es
    push di
    call cd_foreground
    pop di
    pop es
    movzx ax, byte [cd_paused]
    mov [es:di+1], ax
    mov eax, [cd_status_start]
    mov [es:di+3], eax
    mov eax, [cd_status_end]
    mov [es:di+7], eax
    jmp .ok
.head:
    cmp cx, 6
    jb .done
    cmp byte [es:di+1], 1
    ja .done
    call cd_head
    cmp byte [es:di+1], 0
    je .head_lba
    call cd_msf
    jmp .head_store
.head_lba:
    sub eax, [cd_info+INFO_ORIGIN]
.head_store:
    mov [es:di+2], eax
    jmp .ok
.q_channel:
    cmp cx, 11
    jb .done
    push es
    push di
    call cd_foreground
    pop di
    pop es
    call cd_head
    mov ebx, eax
    mov si, cd_info+INFO_TRACKS
    movzx ecx, word [cd_info+INFO_COUNT]
    test cx, cx
    jz .done
    mov dl, 1
.q_track:
    cmp cx, 1
    je .q_found
    cmp eax, [si+TRACK_SIZE+TRACK_INDEX0]
    jb .q_found
    add si, TRACK_SIZE
    inc dl
    loop .q_track
.q_found:
    mov al, [si+TRACK_CONTROL]
    or al, 1
    mov [es:di+1], al
    mov al, dl
    aam
    shl ah, 4
    or al, ah
    mov [es:di+2], al
    mov byte [es:di+3], 1
    mov eax, ebx
    sub eax, [si+TRACK_START]
    jnc .q_relative
    neg eax
    mov byte [es:di+3], 0
.q_relative:
    call cd_frames_msf
    mov [es:di+6], al
    mov [es:di+5], ah
    shr eax, 16
    mov [es:di+4], al
    mov byte [es:di+7], 0
    mov eax, ebx
    call cd_msf
    mov [es:di+10], al
    mov [es:di+9], ah
    shr eax, 16
    mov [es:di+8], al
    jmp .ok
.seek:
    cmp bp, 10000h-24
    ja .done
    cmp byte [fs:bp], 13
    je .seek_header
    cmp byte [fs:bp], 24
    jb .done
.seek_header:
    mov eax, [fs:bp+20]
    call cd_address
    jc .done
    cmp eax, [cd_info+INFO_TOTAL]
    jae .done
    call cd_clear_state
    mov [cd_head_lba], eax
    mov byte [cd_error], 0
    jmp .ok
.volume:
    cmp cx, 9
    jb .done
    mov byte [es:di+1], 0
    mov al, [cd_volume]
    mov [es:di+2], al
    mov byte [es:di+3], 1
    mov al, [cd_volume+1]
    mov [es:di+4], al
    mov word [es:di+5], 2
    mov word [es:di+7], 3
    jmp .ok
.reset:
    call cd_clear_state
    jmp .ok
.stop:
    cmp byte [cd_started], 0
    je .reset
%ifdef OWN_HOST
    mov byte [cd_refill_pending], 0
%endif
    mov byte [cd_started], 0
    mov byte [cd_paused], 1
    mov eax, [cd_consumed]
    xor edx, edx
    mov ecx, 2352
    div ecx
    add eax, [cd_start_lba]
    call cd_msf
    mov [cd_status_start], eax
    jmp .ok
.resume:
    cmp byte [cd_error], 0
    jne .done
    cmp byte [cd_paused], 1
    jne .done
    mov byte [cd_paused], 0
    mov byte [cd_started], 1
    jmp .ok
.play:
    cmp bp, 10000h-22
    ja .done
    cmp byte [fs:bp], 13
    je .play_header
    cmp byte [fs:bp], 22
    jb .done
.play_header:
    mov eax, [fs:bp+14]
    call cd_address
    jc .done
    mov edx, [fs:bp+18]
    test edx, edx
    jz .done
    add edx, eax
    jc .done
    cmp edx, [cd_info+INFO_TOTAL]
    ja .done
    mov si, cd_info+INFO_TRACKS
    mov cx, [cd_info+INFO_COUNT]
.track:
    cmp eax, [si+TRACK_START]
    jb .done
    cmp cx, 1
    je .track_found
    cmp eax, [si+TRACK_SIZE+TRACK_START]
    jb .track_found
    add si, TRACK_SIZE
    loop .track
.track_found:
    test byte [si+TRACK_CONTROL], 40h
    jnz .done
.range_track:
    cmp cx, 1
    je .range_ok
    cmp edx, [si+TRACK_SIZE+TRACK_START]
    jbe .range_ok
    add si, TRACK_SIZE
    dec cx
    test byte [si+TRACK_CONTROL], 40h
    jnz .done
    jmp .range_track
.range_ok:
%ifdef OWN_HOST
    mov byte [cd_refill_pending], 0
%endif
    mov byte [cd_started], 0
    mov byte [cd_paused], 0
    mov [cd_start_lba], eax
    mov [cd_end_lba], edx
    sub edx, eax
    imul edx, 2352
    mov [cd_length], edx
    mov [cd_remaining], edx
    imul eax, 2352
    mov [cd_offset], eax
    mov dword [cd_produced], 0
    mov dword [cd_consumed], 0
%ifdef RESIDENT_AUDIO
    mov dword [cd_fraction], 0
    mov dword [cd_step_error], 0
%endif
%ifndef CD_FAILURE_TEST
    mov byte [cd_error], 0
%endif
    mov byte [cd_seek], 1
    call cd_foreground
    cmp byte [cd_error], 0
    jne .done
    mov eax, [cd_start_lba]
    call cd_msf
    mov [cd_status_start], eax
    mov eax, [cd_end_lba]
    call cd_msf
    mov [cd_status_end], eax
    mov byte [cd_started], 1
.ok:
    mov word [cd_result], 100h
    cmp byte [cd_error], 0
    jne .io_error
    cmp byte [cd_started], 0
    je .done
    mov eax, [cd_consumed]
    cmp eax, [cd_length]
    jae .done
    or word [cd_result], 200h
    jmp .done
.io_error:
    mov word [cd_result], 810bh
.done:
    cli
%ifdef OWN_HOST
    mov byte [cd_background_reads], 0
%endif
    mov ss, [cd_call_ss]
    mov sp, [cd_call_sp]
    pop gs
    pop fs
    pop es
    pop ds
    popad
    mov ax, [cs:cd_result]
    popf
    retf

cd_clear_state:
    push eax
    call cd_head
    mov [cd_head_lba], eax
    pop eax
%ifdef OWN_HOST
    mov byte [cd_refill_pending], 0
%endif
    mov byte [cd_started], 0
    mov byte [cd_paused], 0
    mov dword [cd_remaining], 0
    mov dword [cd_status_start], 0
    mov dword [cd_status_end], 0
    ret

cd_msf:
    sub eax, [cd_info+INFO_ORIGIN]
    add eax, 150
cd_frames_msf:
    push ebx
    xor edx, edx
    mov ecx, 4500
    div ecx
    mov ebx, eax
    shl ebx, 16
    mov eax, edx
    xor edx, edx
    mov ecx, 75
    div ecx
    shl eax, 8
    or eax, ebx
    or eax, edx
    pop ebx
    ret

cd_address:
    cmp byte [fs:bp+13], 0
    je .lba
    cmp byte [fs:bp+13], 1
    jne .bad
    test eax, 0ff000000h
    jnz .bad
    movzx edx, al
    cmp dl, 75
    jae .bad
    movzx ecx, ah
    cmp cl, 60
    jae .bad
    shr eax, 16
    imul eax, 60
    add eax, ecx
    imul eax, 75
    add eax, edx
    sub eax, 150
    jc .bad
.lba:
    add eax, [cd_info+INFO_ORIGIN]
    ret
.bad:
    stc
    ret

cd_head:
    push ecx
    push edx
    mov eax, [cd_head_lba]
    cmp byte [cd_started], 0
    jne .active
    cmp byte [cd_paused], 0
    je .done
.active:
    mov eax, [cd_consumed]
    cmp eax, [cd_length]
    jbe .position
    mov eax, [cd_length]
.position:
    xor edx, edx
    mov ecx, 2352
    div ecx
    add eax, [cd_start_lba]
.done:
    pop edx
    pop ecx
    ret

cd_foreground:
%ifdef OWN_HOST
    cmp byte [cd_background_reads], 0ffh
    je .done
%endif
    cmp dword [cd_remaining], 0
    je .done
%ifdef EXTERNAL_CD_BUFFERS
    call dos_enter
%else
    les bx, [cd_indos]
    cmp byte [es:bx], 0
    jne .bad
    mov ah, 51h
    int 21h
    push bx
    mov bx, cs
    mov ah, 50h
    int 21h
%endif
    cmp byte [cd_seek], 0
    je .pump
    mov byte [cd_seek], 0
    mov bx, [cd_handle]
    mov dx, [cd_offset]
    mov cx, [cd_offset+2]
    mov ax, 4200h
    int 21h
    jc .read_bad
.pump:
    call cd_pump
    jmp .restore
.read_bad:
    mov byte [cd_error], 1
.restore:
%ifdef RESIDENT_AUDIO
    call dos_leave
%else
    pop bx
    mov ah, 50h
    int 21h
%endif
    ret
%ifndef RESIDENT_AUDIO
.bad:
    mov byte [cd_error], 1
    ret
%endif
.done:
    ret

cd_pump:
%ifdef CD_STARVE
    cmp dword [cd_reads], CD_QUEUE_BYTES/CD_READ_BYTES
    jae .done
%endif
    cmp byte [cd_error], 0
    jne .done
    cmp dword [cd_remaining], 0
    je .done
    mov eax, [cd_produced]
    sub eax, [cd_consumed]
    cmp eax, CD_QUEUE_BYTES-CD_READ_BYTES
    ja .done
    mov ecx, CD_READ_BYTES
%ifdef RESIDENT_AUDIO
    mov edx, [cd_offset]
    and edx, 511
    jz .aligned_read
    neg edx
    add edx, 512
    cmp ecx, edx
    jbe .aligned_read
    mov ecx, edx
.aligned_read:
%endif
    cmp [cd_remaining], ecx
    jae .read
    mov cx, [cd_remaining]
.read:
    mov [cd_read_size], cx
%ifdef CD_READ_ERROR
    cmp dword [cd_reads], CD_QUEUE_BYTES/CD_READ_BYTES+32
    jne .handle_ready
    mov bx, [cd_handle]
    mov ah, 3eh
    int 21h
.handle_ready:
%endif
    mov bx, [cd_handle]
%ifdef EXTERNAL_CD_BUFFERS
    push ds
    mov dx, [cd_work_segment]
    mov ds, dx
%endif
    mov dx, cd_stage
    mov ah, 3fh
    int 21h
%ifdef EXTERNAL_CD_BUFFERS
    pop ds
%endif
    jc .bad
    cmp ax, [cd_read_size]
    jne .bad
    movzx eax, ax
%ifdef RESIDENT_AUDIO
    add [cd_offset], eax
%endif
    sub [cd_remaining], eax
    inc dword [cd_reads]
%ifdef RESIDENT_AUDIO
    mov es, [cd_work_segment]
%else
    push ds
    pop es
%endif
    mov di, cd_stage
    add di, ax
    mov cx, CD_READ_BYTES
    sub cx, ax
    xor ax, ax
    rep stosb
    mov eax, [cd_produced]
    and eax, CD_QUEUE_BYTES-1
    mov [cd_write_offset], eax
%ifdef RESIDENT_AUDIO
    call cd_write_chunk
%else
    call cd_queue_write
%endif
    cmp ax, 1
    jne .bad
%ifdef RESIDENT_AUDIO
    movzx eax, word [cd_read_size]
    add [cd_produced], eax
    cmp byte [cd_background_reads], 0
    je cd_pump
    dec byte [cd_background_reads]
    jz .done
%else
    add dword [cd_produced], CD_READ_BYTES
%endif
    jmp cd_pump
.bad:
    mov byte [cd_error], 1
.done:
    ret

%ifdef RESIDENT_AUDIO
%define CD_QUEUE_HELPERS 1
%include "audio/cd_resample.asm"
%endif
cd_begin_half:
%ifdef RESIDENT_AUDIO
    jmp cd_begin_resampled
%endif
    mov byte [cd_valid], 0
    cmp byte [cd_started], 0
    je .done
    cmp byte [cd_error], 0
    jne .done
    mov eax, [cd_consumed]
    cmp eax, [cd_length]
    jae .done
    cmp eax, [cd_produced]
    jae .empty
    and eax, CD_QUEUE_BYTES-1
    mov [cd_read_offset], eax
    pushad
    push es
    call cd_queue_read
    cmp ax, 1
    pop es
    popad
    jne .empty
    push ds
    pop gs
    mov word [cd_position], cd_half
    mov byte [cd_valid], 1
.done:
    ret
.empty:
    mov byte [cd_error], 2
    ret

%ifdef RESIDENT_AUDIO
cd_write_chunk:
    movzx eax, word [cd_read_size]
    mov [cd_write_move], eax
    mov word [cd_write_address], cd_stage
    mov ecx, CD_QUEUE_BYTES
    sub ecx, [cd_write_offset]
    cmp eax, ecx
    jbe cd_queue_write
    mov [cd_write_move], ecx
    call cd_queue_write
    cmp ax, 1
    jne .done
    mov eax, [cd_write_move]
    add [cd_write_address], ax
    movzx ecx, word [cd_read_size]
    sub ecx, eax
    mov [cd_write_move], ecx
    mov dword [cd_write_offset], 0
    call cd_queue_write
.done:
    ret
%endif
cd_queue_write:
%ifdef RESIDENT_AUDIO
%ifdef EMS_QUEUE
    cmp byte [memory_mode], 1
    je cd_ems_write
%endif
%endif
    mov si, cd_write_move
    mov ah, 0bh
    call far [cd_xms]
    ret

cd_queue_read:
%ifdef RESIDENT_AUDIO
%ifdef EMS_QUEUE
    cmp byte [memory_mode], 1
    je cd_ems_read
%endif
%endif
    mov si, cd_read_move
    mov ah, 0bh
    call far [cd_xms]
    ret

%ifdef EMS_QUEUE
cd_ems_write:
    pushf
    cli
    mov eax, [cd_write_offset]
    mov [cd_ems_offset], eax
    mov ax, [cd_write_move]
    mov [cd_ems_remaining], ax
    mov ax, [cd_write_address]
    mov [cd_ems_buffer], ax
    mov byte [cd_ems_direction], 0
    jmp cd_ems_transfer

cd_ems_read:
    pushf
    cli
    mov eax, [cd_read_offset]
    mov [cd_ems_offset], eax
    mov ax, [cd_read_move]
    mov [cd_ems_remaining], ax
    mov ax, [cd_read_address]
    mov [cd_ems_buffer], ax
    mov byte [cd_ems_direction], 1

cd_ems_transfer:
    pushad
    push ds
    push es
    push fs
    push cs
    pop fs
    mov byte [fs:cd_ems_error], 0
    mov byte [fs:cd_ems_saved], 0
    mov dx, [fs:cd_ems_handle]
    mov ah, 47h
    int 67h
    test ah, ah
    jnz .failed
    mov byte [fs:cd_ems_saved], 1
.page:
    mov eax, [fs:cd_ems_offset]
    mov ebx, eax
    shr ebx, 14
    mov dx, [fs:cd_ems_handle]
    mov ah, 44h
    xor al, al
    int 67h
    test ah, ah
    jnz .failed
    mov eax, [fs:cd_ems_offset]
    and ax, 3fffh
    mov bp, 4000h
    sub bp, ax
    cmp bp, [fs:cd_ems_remaining]
    jbe .size_ready
    mov bp, [fs:cd_ems_remaining]
.size_ready:
    mov cx, bp
    cld
    cmp byte [fs:cd_ems_direction], 0
    jne .read
    mov di, ax
    mov si, [fs:cd_ems_buffer]
    mov ds, [fs:cd_work_segment]
    mov es, [fs:cd_ems_frame]
    rep movsb
    jmp .advanced
.read:
    mov si, ax
    mov di, [fs:cd_ems_buffer]
    mov ds, [fs:cd_ems_frame]
    mov es, [fs:cd_half_segment]
    rep movsb
.advanced:
    movzx eax, bp
    add [fs:cd_ems_offset], eax
    add [fs:cd_ems_buffer], bp
    sub [fs:cd_ems_remaining], bp
    jnz .page
    jmp .restore
.failed:
    mov byte [fs:cd_ems_error], 1
.restore:
    cmp byte [fs:cd_ems_saved], 0
    je .restored
    mov dx, [fs:cd_ems_handle]
    mov ah, 48h
    int 67h
    test ah, ah
    jz .restored
    mov byte [fs:cd_ems_error], 1
.restored:
    pop fs
    pop es
    pop ds
    popad
    cmp byte [cs:cd_ems_error], 0
    jne .bad
    mov ax, 1
    popf
    ret
.bad:
    xor ax, ax
    popf
    ret
%endif

cd_close:
%ifdef RESIDENT_AUDIO
    call cd_cache_close
%endif
%ifdef OWN_HOST
    mov byte [cd_refill_pending], 0
%endif
    mov byte [cd_started], 0
%ifndef RESIDENT_AUDIO
    cmp byte [cd_attached], 0
    je .file
    mov ax, 5
    mov bl, [cd_unit]
    mov dx, cd_request
    call far [cd_control]
    mov byte [cd_attached], 0
.file:
    mov bx, [cd_handle]
    cmp bx, 0ffffh
    je .xms
    mov ah, 3eh
    int 21h
    mov word [cd_handle], 0ffffh
%endif
.xms:
%ifdef RESIDENT_AUDIO
%ifdef EMS_QUEUE
    cmp byte [memory_mode], 1
    jne .free_xms
    mov dx, [cd_ems_handle]
    test dx, dx
    jz .done
    mov ah, 45h
    int 67h
    mov word [cd_ems_handle], 0
    jmp .done
.free_xms:
%endif
%endif
    mov dx, [cd_xms_handle]
    test dx, dx
    jz .done
    mov ah, 0ah
    call far [cd_xms]
    mov word [cd_xms_handle], 0
.done:
%ifndef RESIDENT_AUDIO
    cmp byte [cd_vectors_set], 0
    je .return
    push ds
    lds dx, [cd_old_break]
    mov ax, 2523h
    int 21h
    pop ds
    push ds
    lds dx, [cd_old_critical]
    mov ax, 2524h
    int 21h
    pop ds
    mov byte [cd_vectors_set], 0
%endif
.return:
    ret

%ifndef RESIDENT_AUDIO
cd_break:
    mov byte [cs:cd_error], 1
    iret
cd_critical:
    mov byte [cs:cd_error], 1
    mov al, 3
    iret

cd_old_break dd 0
cd_old_critical dd 0
cd_vectors_set db 0
%endif
cd_xms dd 0
cd_parent_segment dw 0
cd_allocation_strategy dw 0
cd_umb_link db 0
cd_memory_saved db 0
cd_xms_handle dw 0
%ifdef EMS_QUEUE
cd_ems_handle dw 0
cd_ems_frame dw 0
cd_ems_offset dd 0
cd_ems_remaining dw 0
cd_ems_buffer dw 0
cd_ems_direction db 0
cd_ems_saved db 0
cd_ems_error db 0
%endif
cd_indos dd 0
cd_call_ss dw 0
cd_call_sp dw 0
cd_result dw 0
%ifndef RESIDENT_AUDIO
cd_control dd 0
cd_unit db 0
cd_attached db 0
cd_drives dw 0
cd_devices times 26*5 db 0
%endif
%ifdef RESIDENT_AUDIO
cd_info equ $-INFO_STRIDE
    times INFO_SIZE-INFO_STRIDE db 0
%else
cd_info times INFO_SIZE db 0
%endif
cd_handle dw 0ffffh
cd_offset dd 0
cd_length dd 0
cd_remaining dd 0
cd_start_lba dd 0
cd_head_lba dd 0
cd_end_lba dd 0
cd_status_start dd 0
cd_status_end dd 0
cd_read_size dw 0
cd_valid db 0
cd_started db 0
cd_paused db 0
cd_seek db 0
cd_volume db 255,255
cd_gain dd 256,256
cd_error db 0
cd_produced dd 0
cd_consumed dd 0
cd_reads dd 0
cd_write_move:
    dd CD_READ_BYTES
    dw 0
cd_write_address dw cd_stage,0
cd_write_dest dw 0
cd_write_offset dd 0
cd_read_move:
    dd PERIOD_BYTES
cd_read_source dw 0
cd_read_offset dd 0
    dw 0
cd_read_address dw cd_half,0
%ifdef RESIDENT_AUDIO
%else
cd_half times PERIOD_BYTES db 0
cd_stage times CD_READ_BYTES db 0
    times 2048 db 0
cd_stack_top:
%endif
