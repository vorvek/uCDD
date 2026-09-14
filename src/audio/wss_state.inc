; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

wss_hold:
    cmp byte [game_source], 1
    jne .done
    cmp byte [game_active], 0
    je .done
    cmp byte [wss_paused], 0
    jne .done
    test byte [wss_index], 20h
    jz .done
    test byte [wss_status], 1
    jz .done
    call output_clock
    mov [wss_pause_clock], eax
    mov byte [wss_paused], 1
.done:
    ret
wss_release:
    cmp byte [wss_paused], 0
    je .done
    cmp byte [game_source], 1
    jne .clear
    cmp byte [game_active], 0
    je .clear
    call output_clock
    sub eax, [wss_pause_clock]
    add [game_started], eax
.clear:
    mov byte [wss_paused], 0
.done:
    ret

wss_paused db 0
wss_pause_clock dd 0
wss_board db 22h
wss_index db 40h
wss_status db 0cch
wss_count_valid db 0
wss_registers db 0,0,88h,88h,88h,88h,80h,80h,0,8,0,0,0ah,0,0,0
wss_aci_end dd 0
wss_block_origin dd 0
wss_gain dd 0,0
wss_guest_irq dw 11
wss_irq_event dw 0ffffh
wss_irqs db 5,7,9,10,11,12,14,15
wss_rates dw 8000,5510,16000,11025,27420,18900,32000,22050
    dw 0,37800,0,44100,48000,33075,9600,6615
wss_attenuation:
    dd 65536,55142,46396,39037,32846,27636,23253,19565
    dd 16462,13851,11654,9806,8250,6942,5841,4915
    dd 4135,3479,2927,2463,2072,1744,1467,1234
    dd 1039,874,735,619,521,438,369,310
    dd 261,220,185,155,131,110,93,78
    dd 66,55,46,39,33,28,23,20
    dd 16,14,12,10,8,7,6,5
    dd 4,3,3,2,2,2,1,1
