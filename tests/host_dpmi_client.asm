; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 100h
%ifdef CALLBACK_IRQ
%define CALLBACK_VECTOR 9
%else
%define CALLBACK_VECTOR 65h
%endif
    mov sp, program_end+512
    mov bx, (program_end-$$+100h+512+15)/16
    mov ah, 4ah
    int 21h
    jc fail16
    mov ax, 1687h
    int 2fh
    test ax, ax
    jnz fail16
    mov [host], di
    mov [host+2], es
    mov ax, 1
    call far [host]
    jc fail16
    mov eax, esp
    shr eax, 16
    jnz fail16
    mov ax, ss
    lar eax, eax
    jnz fail16
    test eax, 400000h
    jz fail16
    mov ax, ds
    lar eax, eax
    jnz fail16
    test eax, 400000h
    jz fail16
    mov bx, cs
    mov ax, 000ah
    int 31h
    jc fail16
    mov [entry+4], ax
    mov bx, ax
    mov cx, 40fah
    mov ax, 0009h
    int 31h
    jc fail16
    jmp dword far [entry]
fail16:
    mov ax, 4c01h
    int 21h
bits 32
client:
    call flags_test
    call vif_state_test
    mov ax, 0003h
    int 31h
    jc fail
    cmp ax, 8
    jne fail
    mov cx, 2
    xor ax, ax
    int 31h
    jc fail
    mov bx, ax
    mov [selectors], ax
    mov ax, 0007h
    mov cx, 1234h
    mov dx, 5678h
    int 31h
    jc fail
    mov ax, 0006h
    int 31h
    jc fail
    cmp cx, 1234h
    jne fail
    cmp dx, 5678h
    jne fail
    mov ax, 0008h
    xor cx, cx
    mov dx, 0ffffh
    int 31h
    jc fail
    mov ax, 0001h
    int 31h
    jc fail
    add bx, 8
    mov ax, 0001h
    int 31h
    jc fail
    mov bx, 48h
    mov cx, 1234h
    mov ax, 0501h
    int 31h
    jc fail
    mov [allocation], di
    mov [allocation+2], si
%ifdef BAD_RAW_GATE
    int 0f0h
    mov ax, 4c00h
    int 21h
%endif
%ifdef BAD_REFLECT_GATE
    push dword 21h
    int 0f2h
    mov ax, 4c00h
    int 21h
%endif
    mov dx, cx
    mov cx, bx
    push ecx
    push edx
    mov cx, 1
    xor ax, ax
    int 31h
    jc fail
    mov bx, ax
    pop edx
    pop ecx
    mov ax, 0007h
    int 31h
    jc fail
    mov cx, 48h
    mov dx, 1fffh
    mov ax, 0008h
    int 31h
    jc fail
    mov es, bx
    xor edi, edi
.write:
    mov [es:edi], edi
    add edi, 4096
    cmp edi, 481234h
    jb .write
    xor edi, edi
.read:
    cmp [es:edi], edi
    jne fail
    add edi, 4096
    cmp edi, 481234h
    jb .read
    xor ax, ax
    mov es, ax
    mov si, [allocation+2]
    mov di, [allocation]
    mov ax, 0502h
    int 31h
    jc fail
    mov ax, 0502h
    int 31h
    jnc fail
    cmp ax, 8023h
    jne fail
    mov bx, 48h
    mov cx, 1234h
    mov ax, 0501h
    int 31h
    jc fail
    call callback_test
    call raw_test
    mov bx, 6
    mov cx, cs
    mov edx, exception
    mov ax, 0203h
    int 31h
    jc fail
    ud2
    cmp byte [exception_seen], 1
    jne fail
    cli
    ud2
    mov ax, 0902h
    int 31h
    cmp al, 1
    jne fail
    mov ax, 4c00h
    int 21h
fail:
    mov ax, 4c01h
    int 21h
vif_state_test:
    mov ax, 0900h
    int 31h
    jc fail
    cmp ax, 0901h
    jne fail
    int 31h
    jc fail
    cmp ax, 0900h
    jne fail
    int 31h
    jc fail
    cmp ax, 0901h
    jne fail
    int 31h
    jc fail
    cmp ax, 0900h
    jne fail
    ret
callback_test:
    push ds
    pop es
    push ds
    push cs
    pop ds
    mov esi, callback
    mov edi, callback_regs
    mov ax, 0303h
    int 31h
    pop ds
    jc fail
    mov [callback_address], dx
    mov [callback_address+2], cx
    mov bx, CALLBACK_VECTOR
    mov ax, 0200h
    int 31h
    jc fail
    mov [callback_old_vector], dx
    mov [callback_old_vector+2], cx
    mov cx, [callback_address+2]
    mov dx, [callback_address]
    mov ax, 0201h
    int 31h
    jc fail
    mov bx, ds
    mov ax, 0006h
    int 31h
    jc fail
    shl ecx, 16
    mov cx, dx
    shr ecx, 4
    mov [real_regs+44], cx
    mov [real_regs+36], cx
    mov word [real_regs+42], callback_caller
    mov edi, real_regs
    xor cx, cx
    mov ax, 0301h
    int 31h
    jc fail
    cmp dword [real_regs+28], 12345678h
    jne fail
    mov cx, [callback_address+2]
    mov dx, [callback_address]
    mov ax, 0304h
    int 31h
    jc fail
    mov ax, [callback_stack_selector]
    lar eax, eax
    jz fail
    mov ax, 0304h
    int 31h
    jnc fail
    cmp ax, 8024h
    jne fail
    mov bx, CALLBACK_VECTOR
    mov ax, 0200h
    int 31h
    jc fail
    cmp dx, [callback_old_vector]
    jne fail
    cmp cx, [callback_old_vector+2]
    jne fail
%ifdef CALLBACK_REVOKED
    mov edi, real_regs
    xor cx, cx
    mov ax, 0301h
    int 31h
    mov ax, 4c00h
    int 21h
%endif
    ret
raw_test:
    mov ax, 0306h
    int 31h
    jc fail
    mov [raw_to_pm], cx
    mov [raw_to_pm+2], bx
    mov [raw_to_rm], edi
    mov [raw_to_rm+4], si
    mov [raw_saved_sp], esp
    mov [raw_saved_ss], ss
    mov [raw_saved_ds], ds
    mov [raw_saved_cs], cs
    movzx eax, word [real_regs+36]
    mov ecx, eax
    mov edx, eax
    mov esi, eax
    mov ebx, esp
    mov edi, raw_real
    mov ebp, 12345678h
    jmp far [raw_to_rm]
raw_return:
    cmp ebp, 12345678h
    jne fail
    ret
flags_test:
    mov bx, 60h
    mov cx, cs
    mov edx, 10000h
    mov ax, 0205h
    int 31h
    jnc fail
    mov edx, flags_handler
    mov ax, 0205h
    int 31h
    jc fail
    int 60h
    cmp byte [flags_seen], 1
    jne fail
    mov bx, 30h
    mov cx, cs
    mov edx, flags_handler
    mov ax, 0205h
    int 31h
    jc fail
    mov byte [flags_seen], 0
    int 30h
    cmp byte [flags_seen], 1
    jne fail
    cli
    int 60h
    cmp byte [flags_seen], 0
    jne fail
    mov ax, 0902h
    int 31h
    test al, al
    jnz fail
    sti
    cli
    push dword 202h
    db 36h
    popfd
    mov ax, 0902h
    int 31h
    cmp al, 1
    jne fail
    cli
    push dword 202h
    mov ax, ss
    mov ss, ax
    popfd
    mov ax, 0902h
    int 31h
    cmp al, 1
    jne fail
    cli
    push dword 202h
    push ss
    pop ss
    popfd
    mov ax, 0902h
    int 31h
    cmp al, 1
    jne fail
    call ss_memory_test
    call narrow_stack_test
    cli
    pushfd
    pop eax
    test eax, 300h
    jnz fail
    pushfd
    pop eax
    or eax, 200h
    push eax
    popfd
    mov ax, 0902h
    int 31h
    cmp al, 1
    jne fail
    cli
    push dword 202h
    push cs
    push dword .returned
    iretd
.returned:
    mov ax, 0902h
    int 31h
    cmp al, 1
    jne fail
    ret
flags_handler:
    push eax
    mov ax, 0902h
    int 31h
    mov [flags_seen], al
    pop eax
    iretd
ss_memory_test:
    mov [narrow_saved_ss], ss
    cli
    push dword 202h
    mov ss, [narrow_saved_ss]
    popfd
    mov ax, 0902h
    int 31h
    cmp al, 1
    jne fail
    mov esi, narrow_saved_ss
    mov ecx, 1
    cli
    push dword 202h
    mov ss, [esi+ecx*2-2]
    popfd
    mov ax, 0902h
    int 31h
    cmp al, 1
    jne fail
    mov bx, narrow_saved_ss
    xor si, si
    cli
    push dword 202h
    mov ss, [bx+si]
    popfd
    mov ax, 0902h
    int 31h
    cmp al, 1
    jne fail
    cli
    push dword 202h
    mov [lss_pointer], esp
    mov [lss_pointer+4], ss
    lss esp, [lss_pointer]
    popfd
    mov ax, 0902h
    int 31h
    cmp al, 1
    jne fail
    mov word [lss_pointer], 1234h
    mov [lss_pointer+2], ss
    cli
    push dword 202h
    lss cx, [lss_pointer]
    popfd
    cmp cx, 1234h
    jne fail
    mov ax, 0902h
    int 31h
    cmp al, 1
    jne fail
    ret
narrow_stack_test:
    mov [narrow_saved_ss], ss
    mov [narrow_saved_sp], esp
    mov bx, ss
    mov ax, 000ah
    int 31h
    jc fail
    mov [narrow_selector], ax
    mov bx, ax
    mov cx, 00f2h
    mov ax, 0009h
    int 31h
    jc fail
    mov ss, bx
    or esp, 12340000h
    cli
    int 60h
    pushfd
    pop eax
    test eax, 300h
    jnz .bad
    mov eax, esp
    shr eax, 16
    cmp ax, 1234h
    jne .bad
    sti
    mov ss, [narrow_saved_ss]
    mov esp, [narrow_saved_sp]
    mov bx, [narrow_selector]
    mov ax, 0001h
    int 31h
    jc fail
    ret
.bad:
    mov ss, [narrow_saved_ss]
    mov esp, [narrow_saved_sp]
    jmp fail
callback:
%ifdef CALLBACK_UD2
    ud2
%endif
%ifdef CALLBACK_EXIT
    mov ax, 4c00h
    int 21h
%endif
    mov ax, ss
    lsl eax, eax
    jnz fail
    cmp eax, 4095
    jne fail
    sub esp, 3072
    mov dword [ss:esp], 1234abcch
    mov [es:callback_stack_selector], ds
    mov eax, [esi]
    mov [es:edi+42], eax
    add word [es:edi+46], 4
    mov dword [es:edi+28], 12345678h
    push ds
    push edi
    push es
    pop ds
    mov cx, [callback_address+2]
    mov dx, [callback_address]
    mov ax, 0304h
    int 31h
    jnc fail
    cmp ax, 8024h
    jne fail
    mov edi, nested_regs
    mov word [edi+28], 3000h
    mov bx, 21h
    xor cx, cx
    mov ax, 0300h
    int 31h
    pop edi
    pop ds
    jc fail
    cmp dword [ss:esp], 1234abcch
    jne fail
    add esp, 3072
    iretd
exception:
    add dword [ss:esp+12], 2
    or dword [ss:esp+20], 200h
    mov byte [exception_seen], 1
    push eax
    sub esp, 16
%assign field 0
%rep 8
    mov eax, [ss:esp+20+field]
    mov [ss:esp+4+field], eax
%assign field field+4
%endrep
    pop eax
    retf
bits 16
raw_real:
    cmp ebp, 12345678h
    jne fail16
    mov ax, 3000h
    int 21h
    movzx eax, word [raw_saved_ds]
    mov ecx, eax
    movzx edx, word [raw_saved_ss]
    movzx esi, word [raw_saved_cs]
    mov ebx, [raw_saved_sp]
    mov edi, raw_return
    mov ebp, 12345678h
%ifdef BAD_RAW_CODE
    mov esi, 10h
%endif
%ifdef BAD_RAW_STACK
    mov edx, 10h
%endif
%ifdef BAD_RAW_DATA
    mov eax, 10h
%endif
    jmp far [raw_to_pm]
callback_caller:
    call far [cs:callback_address]
    retf
host dd 0
entry dd client
    dw 0
selectors dw 0
allocation dd 0
callback_address dd 0
callback_old_vector dd 0
callback_stack_selector dw 0
callback_regs times 50 db 0
real_regs times 50 db 0
nested_regs times 50 db 0
raw_to_rm dd 0
    dw 0
raw_to_pm dd 0
raw_saved_sp dd 0
raw_saved_ss dw 0
raw_saved_ds dw 0
raw_saved_cs dw 0
exception_seen db 0
flags_seen db 0
narrow_saved_ss dw 0
narrow_selector dw 0
narrow_saved_sp dd 0
lss_pointer dd 0
    dw 0
program_end:
