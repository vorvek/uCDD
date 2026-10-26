; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; Disk controller IRQs. A PCI disk controller holds its level-triggered
; request until its real-mode handler runs. If a protected-mode program waits
; in a real-mode call for that disk, the request must go to the handler
; directly, or the program never continues. The driver does this for IRQ 14,
; IRQ 15, the IRQs found here at installation, and the IRQ set by hand in the
; Disk row of UCDDSET. UCDDSET runs the scan too, to show what it finds.
; The same walk finds the platform for the fast DMA option (platform.asm).

; Find PCI mass storage controllers (class 01h) and the IRQs that the BIOS
; gave them. A machine without a PCI BIOS has none to find. A controller with
; no interrupt pin, like a chipset IDE port in compatibility mode, uses IRQ 14
; and 15.
disk_scan:
    xor ax, ax
    mov [disk_found], ax
    mov [disk_unknown], al
    mov [disk_pci], al
    mov [platform_method], al
    mov [platform_bridge_vendor], ax
    mov byte [platform_row], 0ffh
    ; SET UCDDPCI=OFF skips the scan, for a PCI BIOS that fails under the
    ; memory manager.
    call disk_scan_allowed
    jc .off
    ; The PCI BIOS may use 1 KB of the caller's stack. Use one of 2 KB.
    cli
    mov [disk_old_stack], sp
    mov [disk_old_stack+2], ss
    mov ax, cs
    mov ss, ax
    mov sp, disk_stack_top
    sti
    call disk_scan_pci
    cli
    mov ss, [cs:disk_old_stack+2]
    mov sp, [cs:disk_old_stack]
    sti
    jmp platform_eisa
.off:
    mov byte [disk_pci], 2
    jmp platform_eisa

disk_scan_pci:
    pushad
    push es
    mov ax, 0b101h
    xor edi, edi
    int 1ah
    jc .done
    test ah, ah
    jnz .done
    cmp edx, 20494350h
    jne .done
    mov byte [disk_pci], 1
    mov [disk_last_bus], cl
    xor bh, bh
.bus:
    ; BL holds the device in bits 3 to 7 and the function in bits 0 to 2.
    xor bl, bl
.device:
    xor di, di
    call pci_read_word
    jc .next_device
    cmp cx, 0ffffh
    je .next_device
    mov di, 0eh
    call pci_read_byte
    jc .next_device
    mov [disk_header], cl
.function:
    call disk_function
    call platform_function
    ; Bit 7 of the header type marks a device with more than one function.
    test byte [disk_header], 80h
    jz .next_device
.next_function:
    inc bl
    test bl, 7
    jz .device_done
    xor di, di
    call pci_read_word
    jc .next_function
    cmp cx, 0ffffh
    je .next_function
    jmp .function
.next_device:
    and bl, 0f8h
    add bl, 8
.device_done:
    ; BL wraps to 0 after device 31.
    test bl, bl
    jnz .device
    cmp bh, [disk_last_bus]
    jae .done
    inc bh
    jmp .bus
.done:
    pop es
    popad
    ret

; BH bus, BL device and function.
disk_function:
    mov di, 0bh
    call pci_read_byte
    jc .done
    cmp cl, 1
    jne .done
    ; An IDE controller with both channels in compatibility mode (programming
    ; interface bits 0 and 2 clear) uses IRQ 14 and 15. Some report a routed
    ; interrupt line all the same.
    mov di, 0ah
    call pci_read_byte
    jc .done
    cmp cl, 1
    jne .native
    mov di, 09h
    call pci_read_byte
    jc .done
    test cl, 5
    jz .done
.native:
    mov di, 3dh
    call pci_read_byte
    jc .done
    test cl, cl
    jz .done
    mov di, 3ch
    call pci_read_byte
    jc .done
    ; 0FFh means no IRQ. IRQ 0, 1, 2, 8, and 13 cannot be a PCI IRQ.
    cmp cl, 15
    ja .unknown
    movzx cx, cl
    bt word [disk_invalid], cx
    jc .unknown
    bts [disk_found], cx
    ret
.unknown:
    inc byte [disk_unknown]
.done:
    ret

%include "platform.asm"

; BH bus, BL device and function, DI register. Return CL, or CF set.
pci_read_byte:
    push ax
    push bx
    push dx
    push si
    push di
    mov ax, 0b108h
    int 1ah
    jmp pci_read_end

; BH bus, BL device and function, DI register. Return CX, or CF set.
pci_read_word:
    push ax
    push bx
    push dx
    push si
    push di
    mov ax, 0b109h
    int 1ah
pci_read_end:
    pop di
    pop si
    pop dx
    pop bx
    jc .failed
    test ah, ah
    jnz .failed
    pop ax
    clc
    ret
.failed:
    pop ax
    stc
    ret

; Return AX: the IRQs that go straight to the real-mode handler. IRQ 14 and
; 15, the PCI disk controllers, and the IRQ set by hand, never the IRQ of the
; physical sound card.
disk_mask:
    push cx
    call disk_used
    or ax, 0c000h
    and ax, 0def8h
    movzx cx, byte [sb_irq]
    btr ax, cx
    pop cx
    ret

; Return AX: the IRQs of the PCI disk controllers and the IRQ set by hand.
disk_used:
    push cx
    mov ax, [disk_found]
    movzx cx, byte [config_disk_irq]
    jcxz .done
    bts ax, cx
.done:
    pop cx
    ret

; Return SI: a warning about the disk IRQs and the sound card IRQs in
; disk_warning, or 0. IRQ 14 and 15 are never sound card IRQs.
disk_check:
    push ax
    push cx
    push di
    call disk_used
    xor si, si
    movzx cx, byte [sb_irq]
    mov di, disk_physical_text
    bt ax, cx
    jc .warn
    movzx cx, byte [virtual_irq]
    mov di, disk_virtual_text
    bt ax, cx
    jc .warn
    movzx cx, byte [virtual_wss_irq]
    mov di, disk_wss_text
    bt ax, cx
    jnc .done
.warn:
    ; The text has a # where the IRQ number goes.
    mov si, di
    mov di, disk_warning
.copy:
    lodsb
    cmp al, '#'
    jne .store
    mov ax, cx
    call disk_decimal
    jmp .copy
.store:
    stosb
    test al, al
    jnz .copy
    mov si, disk_warning
.done:
    pop di
    pop cx
    pop ax
    ret

; DI buffer. Write the IRQ numbers in AX, lowest first, separated by spaces.
disk_irq_text:
    push ax
    push bx
    push cx
    mov bx, ax
    xor cx, cx
.irq:
    bt bx, cx
    jnc .next
    cmp byte [disk_irq_first], 0
    jne .number
    mov byte [di], ' '
    inc di
.number:
    mov byte [disk_irq_first], 0
    mov ax, cx
    call disk_decimal
.next:
    inc cx
    cmp cx, 16
    jb .irq
    mov byte [di], 0
    pop cx
    pop bx
    pop ax
    ret

; AX value. Write it in decimal at DI, with a 0 after it, and leave DI on
; that 0.
disk_decimal:
    push ax
    push bx
    push cx
    push dx
    mov bx, 10
    xor cx, cx
.divide:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .divide
.store:
    pop ax
    add al, '0'
    stosb
    loop .store
    mov byte [di], 0
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Return CF set if the environment has UCDDPCI=OFF (any case).
disk_scan_allowed:
    push ds
    push bx
    push si
    push di
    mov ah, 62h
    int 21h
    mov ds, bx
    mov si, [2ch]
    test si, si
    jz .allowed
    mov ds, si
    xor si, si
.variable:
    cmp byte [si], 0
    je .allowed
    mov di, disk_env_name
.compare:
    mov al, [cs:di]
    test al, al
    jz .found
    mov ah, [si]
    cmp ah, 'a'
    jb .upper
    cmp ah, 'z'
    ja .upper
    sub ah, 20h
.upper:
    cmp ah, al
    jne .skip
    inc si
    inc di
    jmp .compare
.skip:
    lodsb
    test al, al
    jnz .skip
    jmp .variable
.found:
    ; The value must end after OFF.
    cmp byte [si], 0
    jne .skip
    stc
    jmp .done
.allowed:
    clc
.done:
    pop di
    pop si
    pop bx
    pop ds
    ret

; IRQs that no PCI device can use.
disk_invalid dw 2107h
disk_found dw 0
disk_unknown db 0
; 0 no PCI BIOS, 1 scanned, 2 scan off.
disk_pci db 0
disk_last_bus db 0
disk_header db 0
disk_irq_first db 0
disk_physical_text db 'The physical card and a disk controller both use IRQ #.',0
disk_virtual_text db 'A disk controller uses IRQ #. Set the virtual SB to a different IRQ.',0
disk_wss_text db 'A disk controller uses IRQ #. Set the virtual WSS to a different IRQ.',0
disk_env_name db 'UCDDPCI=OFF',0
disk_old_stack dd 0
disk_warning times 80 db 0
    align 2
disk_stack times 2048 db 0
disk_stack_top:
