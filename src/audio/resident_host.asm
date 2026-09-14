; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

pm_bridge_fault db 0
pm_cleanup_fault db 0
own_host_entry dw 0,0
own_host_active dd 0

audio_enter_pm:
    mov dx, installed_message
    mov ah, 9
    int 21h
    mov dx, [resident_paragraphs]
    mov ax, 3100h
    int 21h
