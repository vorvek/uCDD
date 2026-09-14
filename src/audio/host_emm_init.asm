; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

host_emm_install:
    call host_emm_register
    jc .bad
    mov word [host_api_entry], emm_qpi
    mov [host_api_entry+2], cs
    mov byte [host_installed], 1
    mov byte [host_backend], 2
    clc
    ret
.bad:
    cmp byte [host_emm_seen], 0
    je .failed
    mov word [audio_error_text], port_trap_rejected_message
.failed:
    stc
    ret
