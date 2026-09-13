bits 16
cpu 386
org 100h
    jmp start

%include "audio/irq.asm"

start:
    mov byte [virtual_pic_mask], 0
    mov byte [virtual_pic_request], 20h
    mov byte [simulated_isr], 1
    push cs
    call virtual_irq_take
    test ax, ax
    jnz failed
    cmp byte [virtual_pic_request], 20h
    jne failed

    mov byte [simulated_isr], 40h
    push cs
    call virtual_irq_take
    cmp ax, 1
    jne failed
    cmp byte [virtual_pic_request], 0
    jne failed
    cmp byte [virtual_pic_service], 20h
    jne failed
    mov dx, 20h
    mov al, 20h
    call virtual_pic_write
    cmp byte [virtual_pic_service], 0
    jne failed
    cmp byte [physical_eois], 0
    jne failed

    mov byte [virtual_pic_service], 20h
    mov byte [simulated_isr], 1
    mov al, 20h
    call virtual_pic_write
    cmp byte [virtual_pic_service], 20h
    jne failed
    cmp byte [physical_eois], 1
    jne failed
    mov al, 65h
    call virtual_pic_write
    cmp byte [virtual_pic_service], 0
    jne failed
    cmp byte [physical_eois], 1
    jne failed

    mov byte [simulated_isr], 40h
    mov al, 20h
    call virtual_pic_write
    cmp byte [physical_eois], 2
    jne failed
    cmp byte [fault], 0
    jne failed
    mov dx, success
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
failed:
    mov dx, failure
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

physical_read:
    mov al, [simulated_isr]
    ret
physical_write:
    cmp al, 20h
    jne .done
    inc byte [physical_eois]
.done:
    ret
output_clock:
    xor eax, eax
    ret

simulated_isr db 0
physical_eois db 0
fault db 0
sb_irq db 5
game_active db 0
dma_masked db 0
game_started dd 0
game_rate dw 22050
success db 'The interrupt priority test passed.',13,10,'$'
failure db 'The interrupt priority test failed.',13,10,'$'
