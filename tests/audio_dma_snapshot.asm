; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h
    jmp start
%include "audio/layout.inc"
%include "snapshot.inc"
start:
    mov si, dma8
    call emm_dma_snapshot
    cmp word [dma8+DMA_ADDRESS], 3232h
    jne fail
    cmp word [dma8+DMA_COUNT], 3333h
    jne fail
    cmp byte [dma8+DMA_PAGE], 0b3h
    jne fail
    mov si, dma16
    call emm_dma_snapshot
    cmp word [dma16+DMA_ADDRESS], 0f4f4h
    jne fail
    cmp word [dma16+DMA_COUNT], 0f6f6h
    jne fail
    cmp byte [dma16+DMA_PAGE], 0bbh
    jne fail
    mov ax, 4c00h
    int 21h
fail:
    mov ax, 4c01h
    int 21h
physical_read:
    mov al, dl
    add al, 30h
    ret
physical_write:
    ret
sb_dma8 db 3
sb_dma16 db 6
dma8 times 16 db 0
dma16 times 16 db 0
