; SPDX-License-Identifier: GPL-3.0-only

; The platform, for the fast DMA option (docs/platform-dma.md): the ISA
; bridge found on the PCI bus, looked up in the platform table, or an EISA
; machine. UCDDSET shows what is found; the driver uses it while its output
; runs (audio/standby.asm, fast_dma_set). Included by disk_scan.asm, which
; calls platform_function for every PCI function it walks.

; Fast DMA methods (docs/platform-dma.md section 4).
PLATFORM_NONE equ 0
PLATFORM_MBDMA equ 1                    ; Intel PIIX family: config 76h/77h
PLATFORM_DCEM_F equ 2                   ; ALi: 40Bh/4D6h, Type F
PLATFORM_DCEM_A equ 3                   ; Intel SIO, EISA: 40Bh/4D6h, Type A
PLATFORM_VIA45 equ 4                    ; VIA: config 45h, a bit a channel
PLATFORM_SIS71 equ 5                    ; SiS: config 71h, a bit a channel

; The platform table: vendor, device, lowest and highest revision, method.
; The ISA bridge is function 0 in every row. The row's place is its number
; for UCDDSET's names (setup.asm, platform_names).
%macro platform 5
    dw %1, %2
    db %3, %4, %5
%endmacro
platform_table:
    platform 8086h, 122eh, 0, 0ffh, PLATFORM_MBDMA    ; Intel PIIX
    platform 8086h, 7000h, 0, 0ffh, PLATFORM_MBDMA    ; Intel PIIX3
    platform 8086h, 7110h, 0, 0ffh, PLATFORM_MBDMA    ; Intel PIIX4
    platform 8086h, 0484h, 0, 0ffh, PLATFORM_DCEM_A   ; Intel 82378 SIO
    platform 10b9h, 1523h, 0, 0ffh, PLATFORM_DCEM_F   ; ALi M1523
    platform 10b9h, 1533h, 0, 0ffh, PLATFORM_DCEM_F   ; ALi M1533, M1543
    platform 1106h, 0586h, 0, 0ffh, PLATFORM_VIA45    ; VIA VT82C586
    platform 1106h, 0596h, 0, 0ffh, PLATFORM_VIA45    ; VIA VT82C596
    platform 1106h, 0686h, 0, 0ffh, PLATFORM_VIA45    ; VIA VT82C686
    platform 1106h, 8231h, 0, 0ffh, PLATFORM_VIA45    ; VIA VT8231
    platform 1039h, 0008h, 1, 1, PLATFORM_SIS71       ; SiS 5597, 5598, 5582
    platform 1022h, 7408h, 0, 0ffh, PLATFORM_VIA45    ; AMD-756
    platform 1045h, 0c558h, 0, 0ffh, PLATFORM_DCEM_F  ; OPTi 82C558M Viper-M
    platform 1045h, 0c701h, 0, 0ffh, PLATFORM_DCEM_F  ; OPTi 82C700 FireStar
    dw 0
%unmacro platform 5
; The row after the table's last: an EISA machine (platform_eisa).
PLATFORM_EISA_ROW equ ($ - platform_table - 2) / 7

; BH bus, BL device and function, a function that answers (disk_scan_pci).
; The first match of the platform table wins; the first PCI-to-ISA bridge
; (class 06h, subclass 01h) is kept too, so that UCDDSET can name one the
; table lacks.
platform_function:
    test bl, 7
    jnz .done
    cmp byte [platform_method], PLATFORM_NONE
    jne .done
    pushad
    xor di, di
    call pci_read_word
    jc .popped
    mov dx, cx
    mov di, 2
    call pci_read_word
    jc .popped
    mov di, 0ah
    push cx
    call pci_read_word
    mov ax, cx
    pop cx
    jc .popped
    cmp ax, 0601h
    jne .table
    cmp word [platform_bridge_vendor], 0
    jne .table
    mov [platform_bridge_vendor], dx
    mov [platform_bridge_device], cx
.table:
    mov si, platform_table
    xor ah, ah
.row:
    cmp word [si], 0
    je .popped
    cmp [si], dx
    jne .next
    cmp [si+2], cx
    jne .next
    push cx
    mov di, 8
    call pci_read_byte
    mov al, cl
    pop cx
    jc .popped
    cmp al, [si+4]
    jb .next
    cmp al, [si+5]
    ja .next
    mov al, [si+6]
    mov [platform_method], al
    mov [platform_row], ah
    mov [platform_bridge], bx
    mov [platform_device], cx
    jmp .popped
.next:
    add si, 7
    inc ah
    jmp .row
.popped:
    popad
.done:
    ret

; After the PCI scan: with no table match, an EISA machine ("EISA" at
; F000:FFD9, RBIL MEMORY.LST) takes Type A through the EISA extended mode
; registers, which the 82374 ESC and every EISA chipset have.
platform_eisa:
    cmp byte [platform_method], PLATFORM_NONE
    jne .done
    push es
    push ax
    mov ax, 0f000h
    mov es, ax
    cmp dword [es:0ffd9h], 'EISA'
    jne .not_eisa
    mov byte [platform_method], PLATFORM_DCEM_A
    mov byte [platform_row], PLATFORM_EISA_ROW
.not_eisa:
    pop ax
    pop es
.done:
    ret

; What the scan found. platform_row is the table's row, or PLATFORM_EISA_ROW.
platform_method db PLATFORM_NONE
platform_row db 0ffh
platform_bridge dw 0
platform_device dw 0
; The first PCI-to-ISA bridge seen, matched or not (vendor 0: none).
platform_bridge_vendor dw 0
platform_bridge_device dw 0
