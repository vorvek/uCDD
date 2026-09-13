; One 32 KiB DMA ring; configuration selects the physical card resources.
physical_read:
    push bx
    push cx
    mov ax, 1a00h
    call far [qpi]
    mov al, bl
    pop cx
    pop bx
    ret
physical_write:
    push ax
    push bx
    push cx
    mov bl, al
    mov ax, 1a01h
    call far [qpi]
    pop cx
    pop bx
    pop ax
    ret
dsp_write:
    push ax
    push cx
    mov cx, 65535
    mov dx, [sb_base]
    add dx, 0ch
.wait:
    call physical_read
    test al, 80h
    jz .ready
    loop .wait
    mov byte [fault], 1
.ready:
    pop cx
    pop ax
    call physical_write
    ret
physical_reset:
    mov dx, [sb_base]
    add dx, 6
    mov al, 1
    call physical_write
    mov cx, 64
.delay:
    call physical_read
    loop .delay
    xor al, al
    call physical_write
    mov cx, 65535
.ready:
    mov dx, [sb_base]
    add dx, 0eh
    call physical_read
    test al, 80h
    jnz .data
    loop .ready
    stc
    ret
.data:
    mov dx, [sb_base]
    add dx, 0ah
    call physical_read
    cmp al, 0aah
    je .success
    loop .ready
    stc
    ret
.success:
    clc
    ret
sb_start:
    cmp byte [sound_card], 0
    jne .fail
    movzx bx, byte [sb_dma16]
    mov al, [dma_pages+bx-5]
    mov [dma_page_port], al
    mov ax, bx
    sub ax, 4
    mov [dma_channel], al
    shl ax, 2
    add ax, 0c0h
    mov [dma_address_port], ax
    add ax, 2
    mov [dma_count_port], ax
    call physical_reset
    jc .fail
    mov dx, [sb_base]
    add dx, 4
    mov al, 80h
    call physical_write
    inc dx
    call physical_read
    mov [saved_irq], al
    mov al, 2
    cmp byte [sb_irq], 5
    je .irq_value
    mov al, 4
.irq_value:
    call physical_write
    dec dx
    mov al, 81h
    call physical_write
    inc dx
    call physical_read
    mov [saved_dma], al
    mov cl, [sb_dma8]
    mov al, 1
    shl al, cl
    mov ah, al
    mov cl, [sb_dma16]
    mov al, 1
    shl al, cl
    or al, ah
    call physical_write
    mov si, mixer_registers
    mov di, mixer_saved
    mov cx, 4
.mixer:
    mov dx, [sb_base]
    add dx, 4
    lodsb
    call physical_write
    inc dx
    call physical_read
    mov [di], al
    inc di
    mov al, 0f8h
    call physical_write
    loop .mixer
    mov al, [sb_irq]
    add al, 8
    mov ah, 35h
    int 21h
    mov [old_irq], bx
    mov [old_irq+2], es
    mov dx, audio_irq
    mov al, [sb_irq]
    add al, 8
    mov ah, 25h
    int 21h
    in al, 21h
    mov [saved_pic], al
    mov cl, [sb_irq]
    mov ah, 1
    shl ah, cl
    not ah
    and al, ah
    out 21h, al
    cli
    mov al, [dma_channel]
    or al, 4
    out 0d4h, al
    xor al, al
    out 0d8h, al
    movzx eax, word [output_segment]
    shl eax, 4
    mov ebx, eax
    shr eax, 1
    mov dx, [dma_address_port]
    out dx, al
    mov al, ah
    out dx, al
    shr ebx, 16
    mov al, bl
    mov dx, [dma_page_port]
    out dx, al
    mov al, 0ffh
    mov dx, [dma_count_port]
    out dx, al
    mov al, 3fh
    out dx, al
    mov al, [dma_channel]
    or al, 58h
    out 0d6h, al
    mov al, [dma_channel]
    out 0d4h, al
    sti
    mov al, 41h
    call dsp_write
    mov al, 0ach
    call dsp_write
    mov al, 44h
    call dsp_write
    mov al, 0b6h
    call dsp_write
    mov al, 30h
    call dsp_write
    mov al, 0ffh
    call dsp_write
    mov al, 1fh
    call dsp_write
    mov byte [sb_running], 1
    clc
    ret
.fail:
    stc
    ret
sb_stop:
    cmp byte [sb_running], 0
    je .done
    mov al, 0d5h
    call dsp_write
    mov al, [dma_channel]
    or al, 4
    out 0d4h, al
    mov dx, [sb_base]
    add dx, 0fh
    call physical_read
    mov al, [saved_pic]
    out 21h, al
    push ds
    mov al, [sb_irq]
    add al, 8
    lds dx, [old_irq]
    mov ah, 25h
    int 21h
    pop ds
    mov si, mixer_registers
    mov di, mixer_saved
    mov cx, 4
.mixer:
    mov dx, [sb_base]
    add dx, 4
    lodsb
    call physical_write
    inc dx
    mov al, [di]
    inc di
    call physical_write
    loop .mixer
    mov dx, [sb_base]
    add dx, 4
    mov al, 80h
    call physical_write
    inc dx
    mov al, [saved_irq]
    call physical_write
    dec dx
    mov al, 81h
    call physical_write
    inc dx
    mov al, [saved_dma]
    call physical_write
.done:
    ret
audio_irq:
    push ds
    push ax
    mov ax, cs
    mov ds, ax
    mov [irq_ss], ss
    mov [irq_sp], sp
    mov ss, ax
    mov sp, irq_stack_top
    pushad
    push es
    push fs
    cld
    mov dx, [sb_base]
    add dx, 0fh
    call physical_read
    inc word [periods]
    mov es, [output_segment]
    mov di, [next_half]
    xor word [next_half], 16384
    call mix_half
    mov al, 20h
    out 20h, al
    pop fs
    pop es
    popad
    mov ss, [irq_ss]
    mov sp, [irq_sp]
    pop ax
    pop ds
    iret

old_irq dd 0
dma_pages db 8bh,89h,8ah
dma_channel db 1
dma_page_port dw 8bh
dma_address_port dw 0c4h
dma_count_port dw 0c6h
irq_ss dw 0
irq_sp dw 0
next_half dw 0
periods dw 0
saved_pic db 0
saved_irq db 0
saved_dma db 0
sb_running db 0
mixer_registers db 30h,31h,32h,33h
mixer_saved times 4 db 0
times 1024 db 0
irq_stack_top:
