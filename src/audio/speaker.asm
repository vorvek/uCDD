; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%define DIRECT_OUTPUT 1
%define OUTPUT_SHIFT 9
%include "audio/layout.inc"

speaker_test:
    pushad
    push ds
    push es
    mov byte [fault], 1
    mov byte [speaker_policy], 0
    mov word [output_allocation], 0
    mov ax, 5800h
    int 21h
    jc .done
    mov [speaker_strategy], ax
    mov ax, 5802h
    int 21h
    jc .done
    mov [speaker_umb], al
    mov byte [speaker_policy], 1
    test al, al
    jz .strategy
    xor bx, bx
    mov ax, 5803h
    int 21h
    jc .restore
.strategy:
    xor bx, bx
    mov ax, 5801h
    int 21h
    jc .restore
    mov bx, RING_PARAS*2
    mov ah, 48h
    int 21h
    jc .restore
    mov [output_allocation], ax
    add ax, RING_PARAS-1
    and ax, ~(RING_PARAS-1)
    mov [output_segment], ax
    mov es, ax
    xor di, di
    mov word [speaker_half], 0
    mov word [next_half], 0
    mov dword [periods], 0
    mov byte [fault], 0
    call mix_half
    call mix_half
    call sb_start
    jc .failed
    mov ax, 40h
    mov es, ax
    mov bx, [es:6ch]
.wait:
    cmp dword [periods], 28*PERIOD_SCALE
    jae .stop
    mov ax, [es:6ch]
    sub ax, bx
    cmp ax, 55
    jb .wait
.failed:
    mov byte [fault], 1
.stop:
    call sb_stop
    mov es, [output_allocation]
    mov ah, 49h
    int 21h
    jnc .restore
    mov byte [fault], 1
.restore:
    cmp byte [speaker_policy], 0
    je .done
    mov bx, [speaker_strategy]
    mov ax, 5801h
    int 21h
    jnc .umb
    mov byte [fault], 1
.umb:
    cmp byte [speaker_umb], 0
    je .done
    movzx bx, byte [speaker_umb]
    mov ax, 5803h
    int 21h
    jnc .done
    mov byte [fault], 1
.done:
    cmp byte [fault], 1
    cmc
    pop es
    pop ds
    popad
    ret

mix_half:
    mov dx, [speaker_half]
    inc word [speaker_half]
    xor bx, bx
    mov cx, PERIOD_FRAMES
.frame:
    xor ax, ax
    cmp dx, 12*PERIOD_SCALE
    jae .left
    mov ax, [speaker_tone+bx]
.left:
    stosw
    xor ax, ax
    cmp dx, 16*PERIOD_SCALE
    jb .right
    cmp dx, 28*PERIOD_SCALE
    jae .right
    mov ax, [speaker_tone+bx]
.right:
    stosw
    add bx, 2
    and bx, 127
    loop .frame
    ret

speaker_policy db 0
speaker_strategy dw 0
speaker_umb db 0
speaker_half dw 0
output_allocation dw 0
output_segment dw 0
fault db 0
speaker_tone:
    dw 0,588,1171,1742,2296,2828,3333,3806
    dw 4243,4638,4989,5292,5543,5742,5885,5971
    dw 6000,5971,5885,5742,5543,5292,4989,4638
    dw 4243,3806,3333,2828,2296,1742,1171,588
    dw 0,-588,-1171,-1742,-2296,-2828,-3333,-3806
    dw -4243,-4638,-4989,-5292,-5543,-5742,-5885,-5971
    dw -6000,-5971,-5885,-5742,-5543,-5292,-4989,-4638
    dw -4243,-3806,-3333,-2828,-2296,-1742,-1171,-588

%include "audio/sb16.asm"
