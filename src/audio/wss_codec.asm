; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

wss_read:
    mov dx, [sb_base]
    add dx, 4
    call physical_write
    inc dx
    call physical_read
    ret
indexed_write:
    mov dx, [sb_base]
    add dx, 4
    call physical_write
    inc dx
    mov al, ah
    call physical_write
    ret
wss_ready:
    mov dx, [sb_base]
    add dx, 4
    mov cx, 65535
.wait:
    call physical_read
    test al, 80h
    jz .ok
    loop .wait
    stc
    ret
.ok:
    clc
    ret
wss_calibrate:
    call wss_ready
    jc .done
    mov dx, [sb_base]
    add dx, 4
    xor al, al
    call physical_write
    call wss_ready
    jc .done
    mov cx, 65535
.assert:
    mov al, 11
    call wss_read
    test al, 20h
    jnz .active
    loop .assert
    stc
    ret
.active:
    mov cx, 65535
.wait:
    mov al, 11
    call wss_read
    test al, 20h
    jz wss_ready.ok
    loop .wait
    stc
.done:
    ret
