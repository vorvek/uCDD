%define CD_QUEUE_BYTES 16384
%define CD_READ_BYTES 4096

; Foreground calls only. The interrupt consumes published blocks.
cd_open:
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
    mov dx, cd_descriptor_name
    mov ax, 3d80h
    int 21h
    jc .bad
    mov bx, ax
    mov dx, cd_descriptor
    mov cx, 141
    mov ah, 3fh
    int 21h
    pushf
    push ax
    mov ah, 3eh
    int 21h
    pop ax
    popf
    jc .bad
    cmp ax, 140
    jne .bad
    cmp dword [cd_descriptor], 'CDS1'
    jne .bad
    cmp byte [cd_path+127], 0
    jne .bad
    cmp byte [cd_path], 0
    je .bad
    mov eax, [cd_length]
    test eax, eax
    jz .bad
    test eax, 3
    jnz .bad
    mov [cd_remaining], eax
    add eax, [cd_offset]
    jc .bad
    test eax, 80000000h
    jnz .bad
    mov [cd_end], eax
    mov eax, [cd_offset]
    test eax, 3
    jnz .bad
    mov si, cd_path
    mov di, cd_resolved
    push ds
    pop es
    mov ax, 6000h
    int 21h
    jc .bad
    mov bl, [cd_resolved]
    sub bl, 'A'
    cmp bl, 2
    jb .bad
    cmp bl, 25
    ja .bad
    cmp word [cd_resolved+1], 5c3ah
    jne .bad
    mov bh, 0
    mov cx, bx
    mov ax, 150bh
    int 2fh
    cmp bx, 0adadh
    jne .disk
    test ax, ax
    jnz .bad
.disk:
    mov bl, [cd_resolved]
    sub bl, 'A'-1
    mov ax, 4409h
    int 21h
    jc .bad
    test dx, 1000h
    jnz .bad
    mov dx, cd_resolved
    mov ax, 3d80h
    int 21h
    jc .bad
    mov [cd_handle], ax
    mov bx, ax
    mov ax, 4400h
    int 21h
    jc .bad
    test dx, 80h
    jnz .bad
    xor cx, cx
    xor dx, dx
    mov ax, 4202h
    int 21h
    jc .bad
    shl edx, 16
    mov dx, ax
    test edx, 80000000h
    jnz .bad
    cmp edx, [cd_end]
    jb .bad
    mov dx, [cd_offset]
    mov cx, [cd_offset+2]
    mov ax, 4200h
    int 21h
    jc .bad
    mov bx, CD_QUEUE_BYTES/16
    mov ah, 48h
    int 21h
    jc .bad
    mov [cd_segment], ax
%ifdef PM_CLIENT
    mov ah, 34h
    int 21h
    mov [cd_indos], bx
    mov [cd_indos+2], es
%endif
    call cd_pump
    cmp byte [cd_error], 0
    jne .bad
    clc
    ret
.bad:
    mov byte [cd_error], 1
    stc
    ret

cd_pump:
    cmp byte [cd_error], 0
    jne .done
    cmp dword [cd_remaining], 0
    je .done
    mov eax, [cd_produced]
    sub eax, [cd_consumed]
    cmp eax, CD_QUEUE_BYTES-CD_READ_BYTES
    ja .done
    mov dx, [cd_produced]
    and dx, CD_QUEUE_BYTES-1
    mov [cd_write_offset], dx
    mov ecx, CD_READ_BYTES
    cmp [cd_remaining], ecx
    jae .read
    mov ecx, [cd_remaining]
.read:
%ifdef CD_READ_ERROR
    cmp dword [cd_reads], 8
    jne .handle_ready
    mov bx, [cd_handle]
    mov ah, 3eh
    int 21h
.handle_ready:
%endif
    mov [cd_read_size], cx
    mov bx, [cd_handle]
    push ds
    mov ds, [cd_segment]
    mov ah, 3fh
    int 21h
    pop ds
    jc .bad
    cmp ax, [cd_read_size]
    jne .bad
    movzx eax, ax
    sub [cd_remaining], eax
    inc dword [cd_reads]
    mov es, [cd_segment]
    mov di, [cd_write_offset]
    add di, ax
    mov cx, CD_READ_BYTES
    sub cx, ax
    xor ax, ax
    cld
    rep stosb
    add dword [cd_produced], CD_READ_BYTES
    jmp cd_pump
.bad:
    mov byte [cd_error], 1
.done:
    ret

cd_begin_half:
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
    mov gs, [cd_segment]
    and ax, CD_QUEUE_BYTES-1
    mov [cd_position], ax
    mov byte [cd_valid], 1
.done:
    ret
.empty:
    mov byte [cd_error], 2
    ret

; DPMI 0301h calls this from the cooperative client's foreground loop.
%ifdef PM_CLIENT
cd_service:
    pushf
    cli
    pushad
    push ds
    push es
    push fs
    push gs
    push cs
    pop ds
    mov [cd_service_ss], ss
    mov [cd_service_sp], sp
    mov ax, cs
    mov ss, ax
    mov sp, cd_stack_top
    sti
    les bx, [cd_indos]
    cmp byte [es:bx], 0
    jne .done
    mov ah, 51h
    int 21h
    push bx
    mov bx, cs
    mov ah, 50h
    int 21h
    call cd_pump
    mov byte [cd_started], 1
    pop bx
    mov ah, 50h
    int 21h
.done:
    cli
    mov ss, [cd_service_ss]
    mov sp, [cd_service_sp]
    pop gs
    pop fs
    pop es
    pop ds
    popad
    popf
    retf
%endif

cd_close:
    cmp word [cd_handle], 0ffffh
    je .buffer
    mov bx, [cd_handle]
    mov ah, 3eh
    int 21h
    mov word [cd_handle], 0ffffh
.buffer:
    cmp word [cd_segment], 0
    je .done
    mov es, [cd_segment]
    mov ah, 49h
    int 21h
    mov word [cd_segment], 0
.done:
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
.return:
    ret

cd_break:
    mov byte [cs:cd_error], 1
    iret
cd_critical:
    mov byte [cs:cd_error], 1
    mov al, 3
    iret

cd_descriptor_name db 'CDSTREAM.DAT',0
cd_handle dw 0ffffh
cd_segment dw 0
%ifdef PM_CLIENT
cd_indos dd 0
cd_service_ss dw 0
cd_service_sp dw 0
%endif
cd_end dd 0
cd_remaining dd 0
cd_read_size dw 0
cd_write_offset dw 0
cd_valid db 0
cd_started db 0
cd_error db 0
cd_vectors_set db 0
cd_old_break dd 0
cd_old_critical dd 0
cd_produced dd 0
cd_consumed dd 0
cd_reads dd 0
cd_descriptor:
    dd 0
cd_offset dd 0
cd_length dd 0
cd_path times 129 db 0
cd_resolved times 128 db 0

%ifdef PM_CLIENT
times 2048 db 0
cd_stack_top:
%endif
