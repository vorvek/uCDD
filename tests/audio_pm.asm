; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h
%include "audio/layout.inc"
%ifndef CLIENT_RING_BYTES
%define CLIENT_RING_BYTES 4096
%endif
%ifndef CLIENT_BLOCK_BYTES
%define CLIENT_BLOCK_BYTES 4096
%endif
%ifdef CLIENT_STEREO
%define CLIENT_DMA_UNIT 2
%define CLIENT_DMA_ADDRESS_PORT 0c4h
%define CLIENT_DMA_COUNT_PORT 0c6h
%define CLIENT_DMA_PAGE_PORT 8bh
%define CLIENT_DMA_MASK_PORT 0d4h
%define CLIENT_DMA_MODE_PORT 0d6h
%define CLIENT_DMA_FLIP_PORT 0d8h
%define CLIENT_DSP_ACK 22fh
%else
%define CLIENT_DMA_UNIT 1
%define CLIENT_DMA_ADDRESS_PORT 2
%define CLIENT_DMA_COUNT_PORT 3
%define CLIENT_DMA_PAGE_PORT 83h
%define CLIENT_DMA_MASK_PORT 0ah
%define CLIENT_DMA_MODE_PORT 0bh
%define CLIENT_DMA_FLIP_PORT 0ch
%define CLIENT_DSP_ACK 22eh
%endif
%ifdef STREAM_TEST
%define TIMED_TEST 1
%endif
%ifdef ONSET_TEST
%define TIMED_TEST 1
%endif

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
%ifdef VIRTUAL_IRQ
parent_take dd 0
%endif
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
trap_ports:
%define PORT_RANGES 1
%include "audio/ports.inc"
%undef PORT_RANGES
port_count equ ($-trap_ports)/4
%if port_count > 16
%error The HDPMI port range limit is 16.
%endif
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
%ifndef EXTERNAL_BRIDGE
%ifdef CD_IMAGE_TEST
    cmp byte [80h], 17
%elifdef VIRTUAL_IRQ
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
%ifdef CD_IMAGE_TEST
    mov eax, [8eh]
    mov [cd_entry], eax
%endif
    mov al, [89h]
    cmp al, 5
    je .irq_ok
    cmp al, 7
    jne failed_real
.irq_ok:
    mov [irq_number], al
%endif
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
%ifdef CD_IMAGE_TEST
cd_poll:
    pushad
    push es
    push ds
    pop es
    mov eax, [cd_entry]
    mov [cd_regs+42], eax
    mov dword [cd_regs+46], 0
    mov word [cd_regs+32], 2
    mov edi, cd_regs
    xor bx, bx
    xor cx, cx
    mov ax, 0301h
    int 31h
    pop es
    popad
    jc failed
    ret
align 4
cd_regs times 50 db 0
cd_entry dd 0
%endif
protected_start:
    movzx esp, sp
    mov byte [stage], '1'
%ifndef EXTERNAL_BRIDGE
    mov esi, vendor
    mov ax, 168ah
    int 2fh
    test al, al
    jnz failed
    mov [vendor_entry], edi
    mov [vendor_entry+4], es
    push ds
    pop es
%endif
    mov byte [stage], '2'
    mov ax, 0002h
    mov bx, 40h
    int 31h
    jc failed
    mov [ticks_selector], ax
    mov bx, CLIENT_RING_BYTES*2/16
    mov ax, 0100h
    int 31h
    jc failed
    mov [buffer_selector], dx
    mov [buffer_segment], ax
    mov es, dx
    movzx edi, ax
    shl edi, 4
    neg edi
    and edi, CLIENT_RING_BYTES-1
    mov [buffer_offset], edi
    mov ecx, CLIENT_RING_BYTES
.fill:
%ifdef ONSET_TEST
    mov ebx, 4096
    sub ebx, ecx
    mov al, [onset_samples+ebx]
%else
    mov ebx, ecx
    neg ebx
    and ebx, 63
    mov al, [waveform+ebx]
%endif
    stosb
    loop .fill
%ifdef STREAM_TEST
    call stream_init
%endif
    push ds
    pop es
%ifndef EXTERNAL_BRIDGE
    mov eax, [parent_port]
    mov [port_regs+42], eax
    mov eax, [parent_irq]
    mov [irq_regs+42], eax
    mov word [port_regs+32], 2
    mov word [irq_regs+32], 2

    mov byte [stage], '3'
    xor ebp, ebp
.trap:
    movzx esi, word [trap_ports+ebp*4]
    movzx edi, word [trap_ports+ebp*4+2]
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
%endif
%ifdef VIRTUAL_IRQ
%ifndef POLL_TEST
    call virtual_client_install
%endif
%endif

    mov byte [stage], '5'
%ifdef ONSET_TEST
    call onset_test
    jmp check_result
%endif
%ifdef STREAM_TEST
%ifdef POLL_TEST
    call poll_test
%else
    call stream_test
%endif
    jmp check_result
%endif
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
%ifdef VIRTUAL_IRQ
    call virtual_client_checks
%endif
    mov dx, 22ch
    mov al, 0d0h
    out dx, al

check_result:
    mov byte [stage], '6'
%ifndef EXTERNAL_BRIDGE
    cmp byte [bridge_fault], 0
    jne failed
%ifdef ONSET_TEST
    cmp dword [port_calls], 120
%elifdef VIRTUAL_IRQ
    cmp dword [port_calls], 150
%else
    cmp dword [port_calls], 500
%endif
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
%ifdef CD_IMAGE_TEST
    cmp dword [owned_irqs], 500
    jb failed
    cmp dword [owned_irqs], 800
%elifdef TIMED_TEST
    cmp dword [owned_irqs], 80
    jb failed
    cmp dword [owned_irqs], 160
%elifdef VIRTUAL_IRQ
    cmp dword [owned_irqs], 65*PERIOD_SCALE
    jb failed
    cmp dword [owned_irqs], 120*PERIOD_SCALE
%else
    cmp dword [owned_irqs], 25
    jb failed
    cmp dword [owned_irqs], 55
%endif
    ja failed
    cmp dword [stolen_irqs], 0
    jne failed
%endif
%ifdef STREAM_TEST
    jmp buffer_checked
%endif
    mov es, [buffer_selector]
    mov edi, [buffer_offset]
    mov ecx, CLIENT_RING_BYTES
.check:
%ifdef ONSET_TEST
    mov ebx, 4096
    sub ebx, ecx
    mov al, [onset_samples+ebx]
%else
    mov ebx, ecx
    neg ebx
    and ebx, 63
    mov al, [waveform+ebx]
%endif
    cmp al, [es:edi]
    jne failed
    inc edi
    loop .check
buffer_checked:
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
%ifdef VIRTUAL_IRQ
    call virtual_client_remove
%endif
    cmp byte [vector_set], 0
    je .route
    mov bl, [irq_number]
    add bl, 8
    mov cx, [old_vector+4]
    mov edx, [old_vector]
    mov ax, 0205h
    int 31h
    jnc .vector_done
    mov byte [cleanup_fault], 1
.vector_done:
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

%ifndef EXTERNAL_BRIDGE
%include "audio/pm_bridge.inc"
%endif

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
%ifdef VIRTUAL_IRQ
    mov [client_rate], ax
%endif
    mov byte [playing], 1
    push eax
%ifdef CLIENT_STEREO
    xor al, al
    out 0ch, al
    mov al, 34h
    out 3, al
%endif
    mov al, 5
    out CLIENT_DMA_MASK_PORT, al
    xor al, al
    out CLIENT_DMA_FLIP_PORT, al
    movzx eax, word [buffer_segment]
    shl eax, 4
    add eax, [buffer_offset]
    mov ebx, eax
%ifdef CLIENT_STEREO
    shr eax, 1
%endif
    out CLIENT_DMA_ADDRESS_PORT, al
    mov al, ah
    out CLIENT_DMA_ADDRESS_PORT, al
    shr ebx, 16
    mov al, bl
    out CLIENT_DMA_PAGE_PORT, al
    mov al, (CLIENT_RING_BYTES/CLIENT_DMA_UNIT-1) & 0ffh
    out CLIENT_DMA_COUNT_PORT, al
    mov al, (CLIENT_RING_BYTES/CLIENT_DMA_UNIT-1) >> 8
    out CLIENT_DMA_COUNT_PORT, al
%ifdef CLIENT_STEREO
    mov al, 12h
    out 3, al
    xor al, al
    out 0ch, al
    in al, 3
    cmp al, 34h
    jne failed
    in al, 3
    cmp al, 12h
    jne failed
    xor al, al
    out 0dch, al
%endif
    mov al, 59h
    out CLIENT_DMA_MODE_PORT, al
    mov al, 1
    out CLIENT_DMA_MASK_PORT, al
    pop ebx
    mov dx, 22ch
%ifdef LEGACY_DSP
    xor al, al
    out 0eh, al
    mov al, 40h
    out dx, al
    mov al, 156
    out dx, al
    mov al, 48h
    out dx, al
    mov al, (CLIENT_BLOCK_BYTES-1) & 0ffh
    out dx, al
    mov al, (CLIENT_BLOCK_BYTES-1) >> 8
    out dx, al
    mov al, 1ch
    out dx, al
    ret
%endif
    mov al, 41h
    out dx, al
    mov al, bh
    out dx, al
    mov al, bl
    out dx, al
%ifdef CLIENT_STEREO
    mov al, 0b6h
%else
    mov al, 0c6h
%endif
    out dx, al
%ifdef CLIENT_STEREO
    mov al, 30h
%else
    xor al, al
%endif
    out dx, al
    mov al, (CLIENT_BLOCK_BYTES/CLIENT_DMA_UNIT-1) & 0ffh
    out dx, al
    mov al, (CLIENT_BLOCK_BYTES/CLIENT_DMA_UNIT-1) >> 8
    out dx, al
    ret

wait_second:
%ifdef VIRTUAL_IRQ
    jmp virtual_client_wait
%endif
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
%ifdef NO_ROUTE
    ret
%endif
    cmp byte [playing], 0
    je .idle
    cmp ebp, 50
    jb failed
    ret
.idle:
    cmp ebp, 1
    ja failed
    ret

%ifdef VIRTUAL_IRQ
%include "../tests/audio_irq_client.inc"
%endif
%ifdef ONSET_TEST
onset_test:
    mov byte [onset_index], 0
.next:
    call reset
    mov ax, 22050
    test byte [onset_index], 1
    jz .play
    mov ax, 11025
.play:
    call play
    mov al, [onset_index]
    add al, 40h
    call test_mark
    mov cx, 2
    call wait_ticks
    mov dx, 22ch
    mov al, 0d0h
    out dx, al
    mov al, [onset_index]
    add al, 50h
    call test_mark
    mov cx, 2
    call wait_ticks
    inc byte [onset_index]
    cmp byte [onset_index], 6
    jb .next
    cmp byte [event_fault], 0
    jne failed
    ret
onset_index db 0
onset_samples:
%ifdef ONSET_SILENT
    incbin "../build/QUIET.PCM"
%else
    incbin "../build/ONSET.PCM"
%endif
%endif
%ifdef STREAM_TEST
%include "../tests/audio_refill_client.inc"
%endif
%ifdef POLL_TEST
%include "../tests/audio_poll_client.inc"
%endif
%ifdef TIMED_TEST
test_mark:
    pushad
    mov bl, al
    mov al, 26
    out 0e4h, al
    mov al, bl
    out 0e5h, al
    mov al, 4
    out 0e6h, al
    popad
    ret
%endif
buffer_offset dd 0
waveform:
    incbin "../build/GAMETEST.PCM"
times 4096 db 0
stack_top:
program_end:
