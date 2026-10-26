; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; The Disk row of the main screen: what the PCI scan (disk_scan.asm) found,
; and an IRQ set by hand for a controller it did not find. The driver runs the
; same scan at installation and builds the mask itself.

; Write what the PCI scan found to disk_found_text: the IRQ numbers, "+?"
; for a controller with no usable IRQ, or "--" with no PCI BIOS, the scan
; off, or nothing found.
disk_found_describe:
    mov di, disk_found_text
    mov si, disk_dash_text
    cmp byte [disk_pci], 1
    jne .copy
    mov ax, [disk_found]
    test ax, ax
    jnz .list
    cmp byte [disk_unknown], 0
    je .copy
    mov si, disk_more_text+1
.copy:
    jmp copy_text
.list:
    mov byte [disk_irq_first], 1
    call disk_irq_text
    cmp byte [disk_unknown], 0
    je .done
    mov si, disk_more_text
    call copy_text
.done:
    mov byte [disk_found_text+12], 0
    ret

; Main screen, the Detected column: the PCI disk IRQs, and a warning on the
; row above the buttons when a disk IRQ is a sound card's.
disk_draw:
    call disk_found_describe
    mov dx, 0d23h
    mov si, disk_found_text
    mov bl, A_BOX
    call put_text
    call disk_check
    test si, si
    jz .done
    mov dx, 1204h
    mov bl, A_TITLE
    call put_text
.done:
    ret

disk_irq_list:
    mov si, disk_irq_values
    ret

; 0 shows as "none": no IRQ set by hand.
text_disk_irq:
    test ax, ax
    jnz text_decimal
    mov si, disk_none_text
    jmp copy_text

disk_irq_choice:
    choice config_disk_irq,1,disk_irq_list,text_disk_irq,0
disk_irq_values db 10
    dw 0,3,4,5,6,7,9,10,11,12
disk_none_text db 'none',0
disk_dash_text db '--',0
disk_more_text db ' +?',0
disk_note db 'Set only for a disk card that the PCI scan cannot find.',0
disk_found_text times 48 db 0
