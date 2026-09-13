bits 16
cpu 386
org 100h

    jmp start

host dd 0
pm_entry dd protected_start
    dw 0
data_selector dw 0
buffer_segment dw 0
buffer_selector dw 0
ticks_selector dw 0
parent_port dd 0
parent_irq dd 0
irq_number db 0
stage db '0'
vendor db 'HDPMI',0
vendor_entry dd 0
    dw 0
old_vector dd 0
    dw 0
old_route dd 0,0,0
route_set db 0
vector_set db 0
trap_count dd 0
port_calls dd 0
owned_irqs dd 0
stolen_irqs dd 0
bridge_fault db 0
cleanup_fault db 0
playing db 0
last_count dw 0
trap_ports dw 2,3,0ah,0bh,0ch,83h,224h,225h,226h,22ah,22ch,22eh
port_count equ ($-trap_ports)/2
trap_handles times port_count dd 0
align 4
port_regs times 50 db 0
irq_regs times 50 db 0
failure db 'The protected audio test failed at step '
failure_stage db '0',13,10,'$'
success db 'The protected audio test passed.',13,10,'$'
%ifdef NO_ROUTE
expected_failure db 'Without IRQ routing, the client received the card interrupts.',13,10,'$'
%endif

start:
    cld
    mov sp, stack_top
    mov byte [stage], 'A'
    cmp byte [80h], 9
    jne failed_real
    mov eax, [81h]
    mov [parent_port], eax
    mov eax, [85h]
    mov [parent_irq], eax
    mov al, [89h]
    cmp al, 5
    je .irq_ok
    cmp al, 7
    jne failed_real
.irq_ok:
    mov [irq_number], al
    mov byte [stage], 'B'
    mov bx, (program_end-$$+100h+15)/16
    mov ah, 4ah
    int 21h
    jc failed_real
    mov byte [stage], 'C'
    mov ax, 1687h
    int 2fh
    test ax, ax
    jnz failed_real
    test bl, 1
    jz failed_real
    mov [host], di
    mov [host+2], es
    test si, si
    jz .enter
    mov bx, si
    mov ah, 48h
    int 21h
    jc failed_real
    mov es, ax
.enter:
    mov byte [stage], 'D'
    mov ax, 1
    call far [host]
    jc failed_real
    mov byte [stage], 'E'
    mov [data_selector], ds
    mov bx, cs
    mov ax, 000ah
    int 31h
    jc failed_real
    mov [pm_entry+4], ax
    mov byte [stage], 'F'
    mov bx, ax
    mov cx, 40fbh
    mov ax, 0009h
    int 31h
    jc failed_real
    jmp dword far [pm_entry]
failed_real:
    mov al, [stage]
    mov [failure_stage], al
    mov dx, failure
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

bits 32
protected_start:
    movzx esp, sp
    mov byte [stage], '1'
    mov esi, vendor
    mov ax, 168ah
    int 2fh
    test al, al
    jnz failed
    mov [vendor_entry], edi
    mov [vendor_entry+4], es
    push ds
    pop es
    mov byte [stage], '2'
    mov ax, 0002h
    mov bx, 40h
    int 31h
    jc failed
    mov [ticks_selector], ax
    mov bx, 512
    mov ax, 0100h
    int 31h
    jc failed
    mov [buffer_selector], dx
    mov [buffer_segment], ax
    mov es, dx
    movzx edi, ax
    shl edi, 4
    neg edi
    and edi, 4095
    mov [buffer_offset], edi
    mov ecx, 4096
.fill:
    mov ebx, ecx
    neg ebx
    and ebx, 63
    mov al, [waveform+ebx]
    stosb
    loop .fill
    push ds
    pop es
    mov eax, [parent_port]
    mov [port_regs+42], eax
    mov eax, [parent_irq]
    mov [irq_regs+42], eax
    mov word [port_regs+32], 2
    mov word [irq_regs+32], 2

    mov byte [stage], '3'
    xor ebp, ebp
.trap:
    movzx esi, word [trap_ports+ebp*2]
    mov edi, 1
    mov cx, cs
    mov bx, ds
    mov edx, port_bridge
    mov eax, 6
    call far [vendor_entry]
    jc failed
    mov [trap_handles+ebp*4], eax
    inc dword [trap_count]
    inc ebp
    cmp ebp, port_count
    jb .trap

    mov byte [stage], '4'
    mov bl, [irq_number]
    add bl, 8
    mov ax, 0204h
    int 31h
    jc failed
    mov [old_vector], edx
    mov [old_vector+4], cx
    movzx esi, byte [irq_number]
    mov eax, 0dh
    call far [vendor_entry]
    jc failed
    mov [old_route], ecx
    mov [old_route+4], edx
    mov [old_route+8], ebx
%ifdef NO_ROUTE
    xor ecx, ecx
    xor edx, edx
    xor ebx, ebx
%else
    mov ecx, cs
    mov edx, irq_bridge
    mov ebx, [parent_irq]
%endif
    mov eax, 0bh
    call far [vendor_entry]
    jc failed
    mov byte [route_set], 1
    mov bl, [irq_number]
    add bl, 8
    mov cx, cs
    mov edx, competing_irq
    mov ax, 0205h
    int 31h
    jc failed
    mov byte [vector_set], 1
    mov ax, 0204h
    int 31h
    jc failed
    cmp edx, competing_irq
    jne failed
    mov ax, cs
    cmp cx, ax
    jne failed

    mov byte [stage], '5'
    call reset
    mov ax, 22050
    call play
    call wait_second
    call reset
    call wait_second
    mov ax, 11025
    call play
    call wait_second
    call reset
    mov ax, 22050
    call play
    call wait_second
    mov dx, 22ch
    mov al, 0d0h
    out dx, al

    mov byte [stage], '6'
    cmp byte [bridge_fault], 0
    jne failed
    cmp dword [port_calls], 500
    jb failed
%ifdef NO_ROUTE
    cmp dword [owned_irqs], 0
    jne failed
    cmp dword [stolen_irqs], 25
    jb failed
    call cleanup
    cmp byte [cleanup_fault], 0
    jne failed
    mov edx, expected_failure
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
%endif
    cmp dword [owned_irqs], 25
    jb failed
    cmp dword [owned_irqs], 55
    ja failed
    cmp dword [stolen_irqs], 0
    jne failed
    mov es, [buffer_selector]
    mov edi, [buffer_offset]
    mov ecx, 4096
.check:
    mov ebx, ecx
    neg ebx
    and ebx, 63
    mov al, [waveform+ebx]
    cmp al, [es:edi]
    jne failed
    inc edi
    loop .check
    call cleanup
    mov byte [stage], '7'
    cmp byte [cleanup_fault], 0
    jne failed
    mov edx, success
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
failed:
    mov al, [stage]
    mov [failure_stage], al
    call cleanup
    mov edx, failure
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

cleanup:
    pushfd
    cli
    cmp byte [vector_set], 0
    je .route
    mov bl, [irq_number]
    add bl, 8
    mov cx, [old_vector+4]
    mov edx, [old_vector]
    mov ax, 0205h
    int 31h
    setc byte [cleanup_fault]
    mov byte [vector_set], 0
.route:
    cmp byte [route_set], 0
    je .traps
    movzx esi, byte [irq_number]
    mov ecx, [old_route]
    mov edx, [old_route+4]
    mov ebx, [old_route+8]
    mov eax, 0bh
    call far [vendor_entry]
    jnc .route_done
    mov byte [cleanup_fault], 1
.route_done:
    mov byte [route_set], 0
.traps:
    cmp dword [trap_count], 0
    je .done
    dec dword [trap_count]
    mov ebp, [trap_count]
    mov edx, [trap_handles+ebp*4]
    mov eax, 7
    call far [vendor_entry]
    jnc .traps
    mov byte [cleanup_fault], 1
    jmp .traps
.done:
    popfd
    ret

; The bridge reuses the real-mode experiment; it is not a resident design.
port_bridge:
    pushad
    push es
    inc dword [port_calls]
    mov [port_regs+28], eax
    shl ecx, 2
    mov [port_regs+24], ecx
    mov [port_regs+20], edx
    mov eax, [parent_port]
    mov [port_regs+42], eax
    mov word [port_regs+32], 2
    mov dword [port_regs+46], 0
    push ds
    pop es
    mov edi, port_regs
    xor ebx, ebx
    xor ecx, ecx
    mov ax, 0301h
    int 31h
    jnc .done
    mov byte [bridge_fault], 1
.done:
    mov eax, [port_regs+28]
    mov [ss:esp+32], eax
    pop es
    popad
    retf

irq_bridge:
    pushad
    push ds
    push es
    mov ds, [cs:data_selector]
    push ds
    pop es
    inc dword [owned_irqs]
    mov eax, [parent_irq]
    mov [irq_regs+42], eax
    mov word [irq_regs+32], 2
    mov dword [irq_regs+46], 0
    mov edi, irq_regs
    xor ebx, ebx
    xor ecx, ecx
    mov ax, 0302h
    int 31h
    jnc .done
    mov byte [bridge_fault], 1
.done:
    pop es
    pop ds
    popad
    iretd

competing_irq:
    push eax
    push edx
    push ds
    mov ds, [cs:data_selector]
    inc dword [stolen_irqs]
    mov dx, 22fh
    in al, dx
    mov al, 20h
    out 20h, al
    pop ds
    pop edx
    pop eax
    iretd

reset:
    mov byte [playing], 0
    mov dx, 226h
    mov al, 1
    out dx, al
    xor al, al
    out dx, al
    mov dx, 22eh
    in al, dx
    test al, 80h
    jz failed
    mov dx, 22ah
    in al, dx
    cmp al, 0aah
    jne failed
    ret

play:
    mov byte [playing], 1
    push eax
    mov al, 5
    out 0ah, al
    xor al, al
    out 0ch, al
    movzx eax, word [buffer_segment]
    shl eax, 4
    add eax, [buffer_offset]
    mov ebx, eax
    out 2, al
    mov al, ah
    out 2, al
    shr ebx, 16
    mov al, bl
    out 83h, al
    mov al, 0ffh
    out 3, al
    mov al, 0fh
    out 3, al
    mov al, 59h
    out 0bh, al
    mov al, 1
    out 0ah, al
    pop ebx
    mov dx, 22ch
    mov al, 41h
    out dx, al
    mov al, bh
    out dx, al
    mov al, bl
    out dx, al
    mov al, 0c6h
    out dx, al
    xor al, al
    out dx, al
    mov al, 0ffh
    out dx, al
    mov al, 0fh
    out dx, al
    ret

wait_second:
    mov fs, [ticks_selector]
    mov si, [fs:6ch]
    xor ebp, ebp
.wait:
    xor al, al
    out 0ch, al
    in al, 3
    mov bl, al
    in al, 3
    mov bh, al
    cmp bx, [last_count]
    je .time
    inc ebp
    mov [last_count], bx
.time:
    mov ax, [fs:6ch]
    sub ax, si
    cmp ax, 19
    jb .wait
    cmp byte [playing], 0
    je .idle
    cmp ebp, 50
    jb failed
    ret
.idle:
    cmp ebp, 1
    ja failed
    ret

buffer_offset dd 0
waveform:
    incbin "../build/GAMETEST.PCM"
times 4096 db 0
stack_top:
program_end:
