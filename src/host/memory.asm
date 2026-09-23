; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

HOST_PROTECTED
dpmi_memory_init:
%ifdef DPMI_MEMORY_FAIL
    stc
    ret
%endif
    pushad
    call dpmi_page_allocate
    jc .done
    mov [ebp+dpmi_blocks_page], edx
    mov eax, [0ffc00ff4h]
    mov [ebp+dpmi_blocks_pte], eax
    or edx, 3
    mov [0ffc00ff4h], edx
    call dpmi_flush
    mov edi, dpmi_blocks
    xor eax, eax
    mov ecx, 1024
    cld
    rep stosd
    clc
.done:
    popad
    ret

dpmi_memory_info:
    mov ax, [ebx]
    mov edx, [ebx+8]
    mov ecx, 48
    mov edi, 1
    call dpmi_buffer
    jc dpmi_error
    mov edi, eax
    pushad
    mov ax, 0de03h
    call far [ebp+mon_server]
    mov [esp+20], edx
    popad
    add edx, [ebp+dpmi_pool_count]
    sub edx, 64
    jnc .count
    xor edx, edx
.count:
    call dpmi_largest_gap
    shr eax, 12
    cmp edx, eax
    jbe .available
    mov edx, eax
.available:
    push edi
    mov eax, -1
    mov ecx, 12
    rep stosd
    pop edi
    mov [edi+4], edx
    mov [edi+8], edx
    mov [edi+20], edx
    shl edx, 12
    mov [edi], edx
    mov dword [edi+12], 0fc00h
    mov dword [edi+16], 0
    mov dword [edi+32], 0
    jmp mon_dpmi.success

dpmi_allocate:
    movzx eax, word [ebx+24]
    shl eax, 16
    mov ax, [ebx+32]
    call dpmi_memory_allocate
    jc dpmi_error
    mov [ebx+32], ax
    shr eax, 16
    mov [ebx+24], ax
    mov [ebx+8], dx
    shr edx, 16
    mov [ebx+12], dx
    jmp mon_dpmi.success
dpmi_free:
    movzx eax, word [ebx+12]
    shl eax, 16
    mov ax, [ebx+8]
    call dpmi_memory_find
    jc .bad
    test dword [esi+8], 80000000h
    jnz .bad
    call dpmi_memory_release
    jmp mon_dpmi.success
.bad:
    mov ax, 8023h
    jmp dpmi_error

dpmi_resize:
    movzx eax, word [ebx+12]
    shl eax, 16
    mov ax, [ebx+8]
    call dpmi_memory_find
    jc dpmi_free.bad
    test dword [esi+8], 80000000h
    jnz dpmi_free.bad
    push esi
    movzx eax, word [ebx+24]
    shl eax, 16
    mov ax, [ebx+32]
    mov ecx, [esi+8]
    cmp ecx, eax
    jbe .size
    mov ecx, eax
.size:
    call dpmi_memory_allocate
    pop esi
    jc dpmi_error
    mov [ebx+32], ax
    mov edi, eax
    shr eax, 16
    mov [ebx+24], ax
    mov [ebx+8], dx
    shr edx, 16
    mov [ebx+12], dx
    push esi
    mov esi, [esi]
    rep movsb
    pop esi
    call dpmi_memory_release
    jmp mon_dpmi.success

; EAX=bytes, returns EAX=linear address and EDX=handle.
dpmi_memory_allocate:
    HOST_COUNT allocate, 0
    push ebx
    push ecx
    push esi
    push edi
    test eax, eax
    jz .value
    cmp eax, 0fc00000h
    ja .full
    mov edx, eax
    add eax, 4095
    and eax, 0fffff000h
    mov ecx, eax
    mov esi, dpmi_blocks
    mov edi, DPMI_BLOCK_COUNT
.slot:
    cmp dword [esi], 0
    je .found
    add esi, 16
    dec edi
    jnz .slot
    jmp .full
.found:
    mov [esi+8], edx
    cmp dword [ebp+dpmi_map_source], 0
    je .owned
    or dword [esi+8], 80000000h
.owned:
    shr eax, 12
    mov [esi+4], eax
    mov edx, 400000h
.restart:
    mov edi, dpmi_blocks
    lea eax, [edx+ecx]
    cmp eax, 10000000h
    ja .full
    mov ebx, DPMI_BLOCK_COUNT
.range:
    cmp dword [edi], 0
    je .next
    cmp eax, [edi]
    jbe .next
    push eax
    mov eax, [edi+4]
    shl eax, 12
    add eax, [edi]
    cmp edx, eax
    jae .no_overlap
    mov edx, eax
    pop eax
    jmp .restart
.no_overlap:
    pop eax
.next:
    add edi, 16
    dec ebx
    jnz .range
    mov [esi], edx
    mov edi, edx
    xor ebx, ebx
.map:
    call dpmi_page_table
    jc .rollback
    xor ecx, ecx
    cmp dword [ebp+dpmi_map_source], 0
    jne .physical
    HOST_COUNT page, 0
    mov ecx, [ebp+dpmi_pool_head]
    mov edx, ecx
    jecxz .fresh
    jmp .map_page
.fresh:
    call dpmi_page_allocate.uncounted
    jc .rollback
    jmp .map_page
.physical:
    mov edx, ebx
    shl edx, 12
    add edx, [ebp+dpmi_map_source]
    or edx, 18h
.map_page:
    ; The final mapping also exposes a pooled page's next link.
    mov eax, edi
    shr eax, 10
    or edx, 7
    mov [eax+0ffc00000h], edx
    call dpmi_flush
    jecxz .mapped
    mov edx, [edi]
    mov [ebp+dpmi_pool_head], edx
    dec dword [ebp+dpmi_pool_count]
.mapped:
    inc ebx
    add edi, 4096
    cmp ebx, [esi+4]
    jb .map
    inc dword [ebp+dpmi_next_handle]
    jnz .handle
    inc dword [ebp+dpmi_next_handle]
.handle:
    mov edx, [ebp+dpmi_next_handle]
    mov [esi+12], edx
    mov eax, [esi]
    clc
    jmp .done
.rollback:
    mov [esi+4], ebx
    call dpmi_memory_release
.full:
    mov eax, 8012h
    stc
    jmp .done
.value:
    mov eax, 8021h
    stc
.done:
    pop edi
    pop esi
    pop ecx
    pop ebx
    ret

dpmi_memory_find:
    mov esi, dpmi_blocks
    mov ecx, DPMI_BLOCK_COUNT
.scan:
    cmp dword [esi], 0
    je .next
    cmp eax, [esi+12]
    je .found
.next:
    add esi, 16
    loop .scan
    stc
    ret
.found:
    clc
    ret

dpmi_memory_release:
    pushad
    mov edi, [esi]
    mov ecx, [esi+4]
    jecxz .empty
.page:
    mov eax, edi
    shr eax, 10
    test dword [esi+8], 80000000h
    jnz .unmap
    mov edx, [ebp+dpmi_pool_head]
    mov [edi], edx
    mov edx, [eax+0ffc00000h]
    and edx, 0fffff000h
    mov [ebp+dpmi_pool_head], edx
    inc dword [ebp+dpmi_pool_count]
.unmap:
    xor edx, edx
    mov [eax+0ffc00000h], edx
    add edi, 4096
    loop .page
    call dpmi_flush
.empty:
    xor eax, eax
    mov [esi], eax
    mov [esi+4], eax
    mov [esi+8], eax
    mov [esi+12], eax
    mov ebx, 1
.table:
    mov edx, [0fffff000h+ebx*4]
    test dl, 1
    jz .next_table
    mov edi, ebx
    shl edi, 12
    add edi, 0ffc00000h
    mov ecx, 1024
    xor eax, eax
    repe scasd
    jne .next_table
    mov dword [0fffff000h+ebx*4], 0
    and edx, 0fffff000h
    call dpmi_flush
    call dpmi_page_free
.next_table:
    inc ebx
    cmp ebx, 64
    jb .table
    popad
    ret

dpmi_memory_cleanup:
    call dpmi_bridge_remove
    call dpmi_ivt_cleanup
    call dpmi_locked_free
    pushad
    cmp dword [ebp+dpmi_blocks_page], 0
    je .done
    mov esi, dpmi_blocks
    mov ecx, DPMI_BLOCK_COUNT
.block:
    cmp dword [esi], 0
    je .next
    call dpmi_memory_release
.next:
    add esi, 16
    loop .block
.pool:
    cmp dword [ebp+dpmi_pool_head], 0
    je .metadata
    call dpmi_page_allocate
    call dpmi_page_free
    jmp .pool
.metadata:
    xor edx, edx
    xchg edx, [ebp+dpmi_blocks_page]
    mov eax, [ebp+dpmi_blocks_pte]
    mov [0ffc00ff4h], eax
    call dpmi_flush
    call dpmi_page_free
%ifdef DPMI_CLEANUP_FAULT
    ud2
%endif
.done:
    popad
    ret

; EAX=largest available linear span; other registers stay intact.
dpmi_largest_gap:
    pushad
    mov edx, 400000h
    xor ebx, ebx
    xor edi, edi
.gap:
    mov ecx, 10000000h
    mov esi, dpmi_blocks
    mov eax, DPMI_BLOCK_COUNT
.scan:
    cmp dword [esi], 0
    jne .occupied
    mov edi, 1
    jmp .next
.occupied:
    cmp [esi], edx
    jb .next
    cmp [esi], ecx
    jae .next
    mov ecx, [esi]
.next:
    add esi, 16
    dec eax
    jnz .scan
    mov eax, ecx
    sub eax, edx
    cmp eax, ebx
    jbe .advance
    mov ebx, eax
.advance:
    cmp ecx, 10000000h
    je .done
    mov esi, dpmi_blocks
.find:
    cmp [esi], ecx
    je .end
    add esi, 16
    jmp .find
.end:
    mov edx, [esi+4]
    shl edx, 12
    add edx, ecx
    jmp .gap
.done:
    test edi, edi
    jnz .result
    xor ebx, ebx
.result:
    mov [esp+28], ebx
    popad
    ret

; EDI=user page address. All registers stay intact.
dpmi_page_table:
    pushad
    mov ebx, edi
    shr ebx, 22
    test byte [0fffff000h+ebx*4], 1
    jnz .ok
    call dpmi_page_allocate
    jc .done
    or edx, 7
    mov [0fffff000h+ebx*4], edx
    call dpmi_flush
    mov edi, ebx
    shl edi, 12
    add edi, 0ffc00000h
    xor eax, eax
    mov ecx, 1024
    rep stosd
.ok:
    clc
.done:
    popad
    ret

dpmi_page_allocate:
    HOST_COUNT page, 0
.uncounted:
    pushad
    mov edx, [ebp+dpmi_pool_head]
    test edx, edx
    jz .vcpi
    ; Borrow the metadata mapping while interrupts are disabled.
    mov ebx, [0ffc00ff4h]
    mov eax, edx
    or eax, 3
    mov [0ffc00ff4h], eax
    call dpmi_flush
    mov eax, [dpmi_blocks]
    mov [ebp+dpmi_pool_head], eax
    dec dword [ebp+dpmi_pool_count]
    mov [0ffc00ff4h], ebx
    call dpmi_flush
    jmp .ok
.vcpi:
    mov ax, 0de04h
    call far [ebp+mon_server]
    test ah, ah
    jnz .bad
.ok:
    mov [esp+20], edx
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

dpmi_page_free:
    pushad
    mov ax, 0de05h
    call far [ebp+mon_server]
    test ah, ah
    jnz .bad
    popad
    clc
    ret
.bad:
    mov byte [ebp+dpmi_release_failed], 1
    popad
    stc
    ret

dpmi_flush:
    HOST_COUNT flush
    push eax
    mov eax, cr3
    mov cr3, eax
    pop eax
    ret

align 4
dpmi_next_handle dd 0
dpmi_blocks equ 3fd000h
DPMI_BLOCK_COUNT equ 256
dpmi_blocks_page dd 0
dpmi_blocks_pte dd 0
dpmi_pool_head dd 0
dpmi_pool_count dd 0
dpmi_map_source dd 0
dpmi_release_failed db 0

dpmi_physical_map:
    movzx edx, word [ebx+24]
    shl edx, 16
    mov dx, [ebx+32]
    cmp edx, 100000h
    jb dpmi_bad_value
    movzx eax, word [ebx+12]
    shl eax, 16
    mov ax, [ebx+8]
    test eax, eax
    jz dpmi_bad_value
    mov ecx, edx
    add ecx, eax
    jc dpmi_bad_value
    mov ecx, edx
    and ecx, 4095
    add eax, ecx
    and edx, 0fffff000h
    mov [ebp+dpmi_map_source], edx
    call dpmi_memory_allocate
    mov dword [ebp+dpmi_map_source], 0
    jc dpmi_error
    add eax, ecx
    mov [ebx+32], ax
    shr eax, 16
    mov [ebx+24], ax
    jmp mon_dpmi.success
dpmi_physical_unmap:
    movzx eax, word [ebx+24]
    shl eax, 16
    mov ax, [ebx+32]
    and eax, 0fffff000h
    mov esi, dpmi_blocks
    mov ecx, DPMI_BLOCK_COUNT
.find:
    cmp dword [esi], 0
    je .next
    cmp eax, [esi]
    je .found
.next:
    add esi, 16
    loop .find
    jmp dpmi_bad_value
.found:
    test dword [esi+8], 80000000h
    jz dpmi_bad_value
    call dpmi_memory_release
    jmp mon_dpmi.success
