; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 32
dpmi_dos_frame:
    lea edi, [ebp+dpmi_dos_regs]
    push edi
    xor eax, eax
    mov ecx, 50
    rep stosb
    pop edi
    ret
dpmi_dos_call:
    mov ax, 21h
    call mon_real_int
    test byte [edi+32], 1
    ret
dpmi_dos_allocate:
    call dpmi_dos_begin
    cmp word [ebx+24], 0
    je dpmi_dos_bad_value
    call dpmi_dos_frame
    mov ax, [ebx+24]
    mov [edi+16], ax
    mov word [edi+28], 4800h
    call dpmi_dos_call
    jnz dpmi_dos_error
    mov ax, [edi+28]
    mov [ebx+36], ax
    push edi
    mov ecx, 1
    call dpmi_descriptor_allocate
    pop edi
    jc .full
    mov edx, eax
    shr edx, 3
    mov byte [ebp+dpmi_used+edx], 3
    mov [ebx+28], ax
    test dword [ebx+20], 10000h
    je .result
    mov [ebx+36], ax
.result:
    movzx eax, word [edi+28]
    shl eax, 4
    mov [esi+2], ax
    shr eax, 16
    mov [esi+4], al
    movzx eax, word [ebx+24]
    shl eax, 4
    dec eax
    mov [esi], ax
    shr eax, 16
    mov [esi+6], al
    jmp dpmi_dos_success
.full:
    mov ax, [edi+28]
    mov [edi+34], ax
    mov word [edi+28], 4900h
    call dpmi_dos_call
    mov ax, 8011h
    jmp dpmi_dos_finish_error
dpmi_dos_free:
    call dpmi_dos_begin
    mov ax, [ebx+28]
    call dpmi_dos_descriptor
    jc dpmi_dos_bad_selector
    call dpmi_descriptor_base
    shr eax, 4
    push eax
    call dpmi_dos_frame
    pop eax
    mov [edi+34], ax
    mov word [edi+28], 4900h
    call dpmi_dos_call
    jnz dpmi_dos_error
    movzx eax, word [ebx+28]
    call dpmi_clear_selector
    shr eax, 3
    mov byte [ebp+dpmi_used+eax], 0
    mov dword [esi], 0
    mov dword [esi+4], 0
    jmp dpmi_dos_success
dpmi_dos_resize:
    call dpmi_dos_begin
    cmp word [ebx+24], 0
    je dpmi_dos_bad_value
    mov ax, [ebx+28]
    call dpmi_dos_descriptor
    jc dpmi_dos_bad_selector
    call dpmi_descriptor_base
    shr eax, 4
    push eax
    call dpmi_dos_frame
    pop eax
    mov [edi+34], ax
    mov ax, [ebx+24]
    mov [edi+16], ax
    mov word [edi+28], 4a00h
    call dpmi_dos_call
    jnz dpmi_dos_error
    movzx eax, word [ebx+24]
    shl eax, 4
    dec eax
    mov [esi], ax
    shr eax, 16
    and byte [esi+6], 70h
    or [esi+6], al
    jmp dpmi_dos_success
dpmi_dos_error:
    mov ax, [edi+16]
    mov [ebx+24], ax
    mov ax, [edi+28]
    jmp dpmi_dos_finish_error

dpmi_dos_begin:
    cmp byte [ebp+dpmi_dos_via21], 0
    jne .direct
    mov dword [ebx+20], 0
.direct:
    mov byte [ebp+dpmi_dos_via21], 0
    ret
dpmi_dos_restore_dx:
    test dword [ebx+20], 10000h
    jz .done
    push eax
    mov ax, [ebx+20]
    mov [ebx+28], ax
    pop eax
.done:
    ret
dpmi_dos_success:
    call dpmi_dos_restore_dx
    jmp mon_dpmi.success
dpmi_dos_bad_value:
    mov ax, 8021h
    jmp dpmi_dos_finish_error
dpmi_dos_bad_selector:
    mov ax, 8022h
dpmi_dos_finish_error:
    call dpmi_dos_restore_dx
    jmp dpmi_error

dpmi_dos_regs times 50 db 0
dpmi_dos_via21 db 0

dpmi_dos_descriptor:
    movzx eax, ax
    mov edx, eax
    and edx, 7
    cmp edx, 7
    jne .bad
    shr eax, 3
    cmp eax, DPMI_LDT_COUNT
    jae .bad
    cmp byte [ebp+dpmi_used+eax], 3
    jne .bad
    lea esi, [ebp+dpmi_ldt+eax*8]
    clc
    ret
.bad:
    stc
    ret

dpmi_dos_translate:
    cmp byte [ebp+dpmi_reflect_vector], 21h
    jne .ordinary
    mov byte [ebp+dpmi_dos_via21], 1
    movzx eax, word [ebx+28]
    or eax, 10000h
    mov [ebx+20], eax
    cmp byte [ebx+37], 48h
    je dpmi_dos_allocate
    cmp byte [ebx+37], 49h
    jne .resize
    mov ax, [ebx]
    mov [ebx+28], ax
    jmp dpmi_dos_free
.resize:
    cmp byte [ebx+37], 4ah
    jne .ordinary
    mov ax, [ebx]
    mov [ebx+28], ax
    jmp dpmi_dos_resize
.ordinary:
    call dpmi_dos_frame
    mov al, [ebp+dpmi_reflect_vector]
    sub al, [ebp+mon_master]
    cmp al, 8
    jb .hardware
    mov al, [ebp+dpmi_reflect_vector]
    sub al, [ebp+mon_slave]
    cmp al, 8
    jb .hardware
    call dpmi_register_interrupt
    jnc .hardware
    mov ax, [ebx+4]
    test ax, ax
    jz .ds_ready
    call dpmi_descriptor
    jc dpmi_dos.unsupported
    call dpmi_descriptor_base
    cmp eax, 100000h
    jae dpmi_dos.unsupported
    test al, 0fh
    jnz dpmi_dos.unsupported
    shr eax, 4
.ds_ready:
    mov [edi+36], ax
    mov ax, [ebx]
    test ax, ax
    jz .es_ready
    call dpmi_descriptor
    jc dpmi_dos.unsupported
    call dpmi_descriptor_base
    cmp eax, 100000h
    jae dpmi_dos.unsupported
    test al, 0fh
    jnz dpmi_dos.unsupported
    shr eax, 4
.es_ready:
    mov [edi+34], ax
.reflect:
    push edi
    lea esi, [ebx+8]
    mov ecx, 8
    rep movsd
    pop edi
    mov word [edi+32], 202h
    movzx eax, byte [ebp+dpmi_reflect_vector]
    call mon_real_int
    cmp byte [ebp+dpmi_reflect_vector], 10h
    jne .registers
    cmp word [ebx+36], 1130h
    jne .registers
    mov ax, [edi+34]
    call dpmi_segment_descriptor
    jc .descriptor_full
    mov [ebx], ax
.registers:
    mov esi, edi
    lea edi, [ebx+8]
    mov ecx, 8
    rep movsd
    and word [ebx+48], 0f72ah
    mov ax, [esi]
    and ax, 08d5h
    or [ebx+48], ax
    jmp mon_dpmi.done
.descriptor_full:
    mov ax, 8011h
    jmp dpmi_error
.hardware:
    call dpmi_pic_reflect
    mov dword [edi+34], 0
    jmp .reflect

; Carry clear if the supported service has no segment-pointer inputs.
dpmi_register_interrupt:
    mov al, [ebp+dpmi_reflect_vector]
    cmp al, 11h
    je .yes
    cmp al, 12h
    je .yes
    cmp al, 16h
    je .yes
    cmp al, 1ah
    jne .video
    cmp byte [ebx+37], 7
    jbe .yes
    jmp .no
.video:
    cmp al, 10h
    jne .dos
    cmp word [ebx+36], 1130h
    je .yes
    mov al, [ebx+37]
    cmp al, 0fh
    jbe .yes
    jmp .no
.dos:
    cmp al, 21h
    jne .no
    mov al, [ebx+37]
    cmp al, 30h
    je .yes
    cmp al, 19h
    je .yes
    cmp al, 0eh
    je .yes
    cmp al, 2ah
    je .yes
    cmp al, 2ch
    je .yes
    cmp al, 36h
    je .yes
    cmp al, 3eh
    je .yes
    cmp al, 42h
    je .yes
    cmp al, 4dh
    je .yes
.no:
    stc
    ret
.yes:
    clc
    ret
