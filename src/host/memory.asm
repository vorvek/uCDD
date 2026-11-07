; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

HOST_PROTECTED
dpmi_memory_init:
%ifdef DPMI_MEMORY_FAIL
    stc
    ret
%endif
    pushad
    xor eax, eax
    mov [ebp+dpmi_block_count], eax
    mov [ebp+dpmi_block_pages], eax
    lea edi, [ebp+dpmi_blocks_page]
    mov ecx, DPMI_BLOCK_PAGES*2
    cld
    rep stosd
    call dpmi_blocks_grow
.done:
    popad
    ret

; Grow the block table below the locked-stack window.
dpmi_blocks_grow:
    pushad
    mov ebx, [ebp+dpmi_block_pages]
    cmp ebx, DPMI_BLOCK_PAGES
    jae .full
    call dpmi_page_allocate
    jc .full
    mov [ebp+dpmi_blocks_page+ebx*4], edx
    mov eax, [DPMI_BLOCK_PTE+ebx*4]
    mov [ebp+dpmi_blocks_pte+ebx*4], eax
    or edx, 3
    mov [DPMI_BLOCK_PTE+ebx*4], edx
    call dpmi_flush
    mov edi, ebx
    shl edi, 12
    add edi, dpmi_blocks
    xor eax, eax
    mov ecx, 1024
    cld
    rep stosd
    inc dword [ebp+dpmi_block_pages]
    add dword [ebp+dpmi_block_count], 256
    clc
    popad
    ret
.full:
    stc
    popad
    ret

dpmi_memory_info:
    mov ax, [ebx]
    mov edx, [ebx+8]
    DPMI_OFFSET16 edx, dx
    mov ecx, 48
    mov edi, 1
    call dpmi_buffer
    jc dpmi_error
    mov edi, eax
    call dpmi_free_pages
    ; Keep 64 pages for page tables and a margin of 1/8 of the free pages, up
    ; to 4 MiB. I Have No Mouth and I Must Scream allocates the largest block
    ; and then 404 KiB more.
    mov eax, edx
    shr eax, 3
    cmp eax, 1024
    jbe .margin
    mov eax, 1024
.margin:
    add eax, 64
    sub edx, eax
    jnc .count
    xor edx, edx
.count:
    mov eax, edx
    shl eax, 12
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
    mov [edi+16], edx
    mov [edi+20], edx
    shl edx, 12
    mov [edi], edx
    mov dword [edi+12], 0fc00h
    mov dword [edi+32], 0
    ; DOS/4GW clients fail on -1 total and free linear page counts.
    push esi
    xor eax, eax
    xor ecx, ecx
    mov esi, dpmi_blocks
    mov edx, [ebp+dpmi_block_count]
    test edx, edx
    jz .counted
.used:
    cmp dword [esi], 0
    je .next_used
    add ecx, [esi+4]
    test dword [esi+8], 80000000h
    jnz .next_used
    add eax, [esi+4]
.next_used:
    add esi, 16
    dec edx
    jnz .used
.counted:
    pop esi
    add eax, [edi+20]
    mov [edi+24], eax
    mov eax, 0fc00h
    sub eax, ecx
    jnc .linear
    xor eax, eax
.linear:
    mov [edi+28], eax
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
    call dpmi_memory_park
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
    call dpmi_memory_grow
    jc .move
    pop esi
    mov eax, [esi]
    mov edx, [esi+12]
    mov [ebx+32], ax
    shr eax, 16
    mov [ebx+24], ax
    mov [ebx+8], dx
    shr edx, 16
    mov [ebx+12], dx
    jmp mon_dpmi.success
.move:
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
    mov edi, [ebp+dpmi_block_count]
.slot:
    cmp dword [esi], 0
    je .found
    add esi, 16
    dec edi
    jnz .slot
    call dpmi_blocks_grow
    jc .full
.found:
    mov [esi+8], edx
    cmp dword [ebp+dpmi_map_source], 0
    je .owned
    or dword [esi+8], 80000000h
.owned:
    shr eax, 12
    mov [esi+4], eax
    cmp dword [ebp+dpmi_map_source], 0
    jne .place
    ; Refuse a block larger than the free pages before any page moves.
    call dpmi_free_pages
    cmp eax, edx
    ja .full
.place:
    mov edx, [ebp+dpmi_linear_floor]
    cmp dword [ebp+dpmi_allocate_hint], 0
    je .restart
    mov edx, [ebp+dpmi_allocate_hint]
.restart:
    mov edi, dpmi_blocks
    lea eax, [edx+ecx]
    cmp eax, 10000000h
    ja .full
    mov ebx, [ebp+dpmi_block_count]
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
    cmp dword [ebp+dpmi_allocate_hint], 0
    jne .blocked
    mov edx, eax
    pop eax
    jmp .restart
.blocked:
    pop eax
    jmp .full
.no_overlap:
    pop eax
.next:
    add edi, 16
    dec ebx
    jnz .range
    mov [esi], edx
    mov edi, edx
    call dpmi_parked_take
    mov eax, ebx
    shl eax, 12
    add edi, eax
    jmp .check
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
    ; The final mapping also exposes a pooled page's next link. The entry
    ; was not present, so the TLB holds nothing to flush until the end.
    mov eax, edi
    shr eax, 10
    or edx, 7
    mov [eax+0ffc00000h], edx
    jecxz .clear
    mov edx, [edi]
    mov [ebp+dpmi_pool_head], edx
    dec dword [ebp+dpmi_pool_count]
.clear:
    ; Loaders expect new pages to be zero (Tao FLIPLAY.EXE data).
    cmp dword [ebp+dpmi_map_source], 0
    jne .mapped
    push edi
    mov ecx, 1024
    xor eax, eax
    rep stosd
    pop edi
.mapped:
    inc ebx
    add edi, 4096
.check:
    cmp ebx, [esi+4]
    jb .map
    call dpmi_flush
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

; Keep the block address when the next linear pages are free.
dpmi_memory_grow:
    pushad
    test eax, eax
    jz .bad
    cmp eax, 0fc00000h
    ja .bad
    mov ecx, eax
    add ecx, 4095
    shr ecx, 12
    cmp ecx, [esi+4]
    jb .bad
    je .size
    mov edi, [esi+4]
    shl edi, 12
    add edi, [esi]
    mov [ebp+dpmi_allocate_hint], edi
    mov eax, ecx
    sub eax, [esi+4]
    shl eax, 12
    call dpmi_memory_allocate
    mov dword [ebp+dpmi_allocate_hint], 0
    jc .bad
    cmp eax, edi
    pushfd
    push esi
    mov eax, edx
    call dpmi_memory_find
    pop edi
    popfd
    jne .release
    xor eax, eax
    mov [esi], eax
    mov [esi+4], eax
    mov [esi+8], eax
    mov [esi+12], eax
    mov esi, edi
    mov eax, [esp+28]
    mov ecx, eax
    add ecx, 4095
    shr ecx, 12
    mov [esi+4], ecx
.size:
    mov eax, [esp+28]
    mov [esi+8], eax
    popad
    clc
    ret
.release:
    call dpmi_memory_release
.bad:
    popad
    stc
    ret

; A freed block stays mapped until the next allocation. A client that
; frees and allocates again at the same address reuses its pages.
dpmi_memory_park:
    pushad
    call dpmi_parked_drop
    mov eax, [esi]
    mov [ebp+dpmi_parked], eax
    mov eax, [esi+4]
    mov [ebp+dpmi_parked+4], eax
    xor eax, eax
    mov [esi], eax
    mov [esi+4], eax
    mov [esi+8], eax
    mov [esi+12], eax
    popad
    ret

; EDX=free pages of the server, the pool, and the parked block.
dpmi_free_pages:
    pushad
    mov ax, 0de03h
    call far [ebp+mon_server]
    mov [esp+20], edx
    popad
    add edx, [ebp+dpmi_pool_count]
    add edx, [ebp+dpmi_parked+4]
    ret

dpmi_parked_drop:
    pushad
    lea esi, [ebp+dpmi_parked]
    cmp dword [esi+4], 0
    je .done
    call dpmi_memory_release
.done:
    popad
    ret

; EDX=start of the block at ESI. Returns EBX=pages already mapped there.
dpmi_parked_take:
    xor ebx, ebx
    cmp dword [ebp+dpmi_map_source], 0
    jne .drop
    cmp edx, [ebp+dpmi_parked]
    jne .drop
    mov ebx, [ebp+dpmi_parked+4]
    cmp ebx, [esi+4]
    jbe .take
    ; Release the parked pages past the end of the new block.
    mov ebx, [esi+4]
    sub [ebp+dpmi_parked+4], ebx
    push ebx
    shl ebx, 12
    add [ebp+dpmi_parked], ebx
    pop ebx
.drop:
    call dpmi_parked_drop
.take:
    mov dword [ebp+dpmi_parked], 0
    mov dword [ebp+dpmi_parked+4], 0
    ret

; Return EAX=first 4 MB boundary above the floor and all blocks.
dpmi_linear_top:
    push ecx
    push edx
    push esi
    mov eax, [ebp+dpmi_linear_floor]
    mov esi, dpmi_blocks
    mov ecx, [ebp+dpmi_block_count]
    jecxz .done
.block:
    cmp dword [esi], 0
    je .next
    mov edx, [esi+4]
    shl edx, 12
    add edx, [esi]
    cmp edx, eax
    jbe .next
    mov eax, edx
.next:
    add esi, 16
    loop .block
.done:
    add eax, 3fffffh
    and eax, 0ffc00000h
    pop esi
    pop edx
    pop ecx
    ret

dpmi_memory_find:
    mov esi, dpmi_blocks
    mov ecx, [ebp+dpmi_block_count]
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
    call dpmi_parked_drop
    mov esi, dpmi_blocks
    mov ecx, [ebp+dpmi_block_count]
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
    mov ebx, [ebp+dpmi_block_pages]
.metadata_page:
    dec ebx
    xor edx, edx
    xchg edx, [ebp+dpmi_blocks_page+ebx*4]
    mov eax, [ebp+dpmi_blocks_pte+ebx*4]
    mov [DPMI_BLOCK_PTE+ebx*4], eax
    call dpmi_flush
    call dpmi_page_free
    test ebx, ebx
    jnz .metadata_page
    mov [ebp+dpmi_block_count], ebx
    mov [ebp+dpmi_block_pages], ebx
%ifdef DPMI_CLEANUP_FAULT
    ud2
%endif
.done:
    popad
    ret

; EAX=bytes that are enough, or 0. Returns EAX=the largest available linear
; span, or a span of at least EAX bytes. Other registers stay intact.
dpmi_largest_gap:
    pushad
    ; The range above all blocks is usually enough. Queen: The Eye calls
    ; 0500h with thousands of blocks, and the full search is quadratic.
    mov edx, [ebp+dpmi_linear_floor]
    xor edi, edi
    mov esi, dpmi_blocks
    mov ecx, [ebp+dpmi_block_count]
    jecxz .top_ready
.top:
    cmp dword [esi], 0
    jne .top_used
    mov edi, 1
    jmp .top_next
.top_used:
    mov ebx, [esi+4]
    shl ebx, 12
    add ebx, [esi]
    cmp ebx, edx
    jbe .top_next
    mov edx, ebx
.top_next:
    add esi, 16
    loop .top
.top_ready:
    mov ebx, 10000000h
    sub ebx, edx
    jae .top_size
    xor ebx, ebx
.top_size:
    mov eax, [esp+28]
    test eax, eax
    jz .search
    cmp ebx, eax
    jae .done
.search:
    mov edx, [ebp+dpmi_linear_floor]
    xor ebx, ebx
    xor edi, edi
.gap:
    mov ecx, 10000000h
    mov esi, dpmi_blocks
    mov eax, [ebp+dpmi_block_count]
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
    cmp dword [ebp+dpmi_block_pages], DPMI_BLOCK_PAGES
    jb .result
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
    ; Use a temporary mapping for a pooled page.
    mov ebx, [0ffc00ff4h]
    mov eax, edx
    or eax, 3
    mov [0ffc00ff4h], eax
    call dpmi_flush
    mov eax, [DPMI_PAGE_SCRATCH]
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
    inc dword [ebp+dpmi_page_generation]
    push eax
    mov eax, cr3
    mov cr3, eax
    pop eax
    ret

align 4
dpmi_next_handle dd 0
dpmi_blocks equ 3d0000h
DPMI_BLOCK_PAGES equ 16
DPMI_BLOCK_PTE equ 0ffc00000h+(dpmi_blocks >> 12)*4
DPMI_PAGE_SCRATCH equ 3fd000h
dpmi_block_count dd 0
dpmi_block_pages dd 0
dpmi_blocks_page times DPMI_BLOCK_PAGES dd 0
dpmi_blocks_pte times DPMI_BLOCK_PAGES dd 0
dpmi_pool_head dd 0
dpmi_pool_count dd 0
dpmi_parked dd 0,0,0,0
dpmi_linear_floor dd 400000h
dpmi_map_source dd 0
dpmi_allocate_hint dd 0
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
    mov ecx, [ebp+dpmi_block_count]
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
