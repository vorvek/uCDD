bits 16
cpu 386
org 100h
%define VIRTUAL_IRQ 1
%define BRIDGE_LAUNCHER 1
    jmp start
host dd 0
pm_entry dd protected_start
    dw 0
data_selector dw 0
parent_port dd 0
parent_irq dd 0
parent_take dd 0
irq_number db 0
stage db '0'
vendor db 'HDPMI',0
vendor_entry dd 0
    dw 0
old_route dd 0,0,0
route_set db 0
trap_count dd 0
port_calls dd 0
owned_irqs dd 0
bridge_fault db 0
cleanup_fault db 0
child_result db 1
trap_ports:
%include "audio/ports.inc"
port_count equ ($-trap_ports)/2
trap_handles times port_count dd 0
port_regs times 50 db 0
irq_regs times 50 db 0
game_vector dd 0
    dw 0
failure db 'The audio launcher failed at step '
failure_stage db '0',13,10,'$'
success db 'The audio launcher test passed.',13,10,'$'
start:
    cld
    mov sp, stack_top
    mov byte [stage], 'A'
%ifdef VIRTUAL_IRQ
    cmp byte [80h], 13
%else
    cmp byte [80h], 9
%endif
    jne failed_real
    mov eax, [81h]
    mov [parent_port], eax
    mov eax, [85h]
    mov [parent_irq], eax
%ifdef VIRTUAL_IRQ
    mov eax, [8ah]
    mov [parent_take], eax
%endif
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

    mov byte [stage], '5'
    mov ax, ds
    mov [exec_block+4], ax
    mov edx, child_name
    mov ebx, exec_block
    mov ax, 4b00h
    int 21h
    jc failed
    mov ah, 4dh
    int 21h
    mov [child_result], al
    mov byte [stage], '6'
    call cleanup
    cmp byte [child_result], 0
    jne failed
    cmp byte [bridge_fault], 0
    jne failed
    cmp byte [cleanup_fault], 0
    jne failed
    cmp dword [owned_irqs], 80
    jb failed
    cmp dword [port_calls], 150
    jb failed
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


%include "audio/pm_bridge.inc"
%ifdef QUAKE_TEST
child_name db 'QUAKE.EXE',0
command_tail db command_end-command_args
command_args db ' -dsp 2 -nocdaudio -noserial -noipx -noudp -condebug'
command_end db 13
%else
child_name db 'GAME.COM',0
command_tail db 0,13
%endif
exec_block dd command_tail,0,0,0,0,0
times 4096 db 0
stack_top:
program_end:
