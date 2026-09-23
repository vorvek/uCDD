; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%ifndef HOST_PROFILE_MACROS
%define HOST_PROFILE_MACROS 1

; The second argument is zero only where incoming flags are dead.
%macro HOST_COUNT 1-2 1
%ifdef HOST_PROFILE
%if %2
    pushfd
%endif
    inc dword [ebp+host_profile_%1]
%if %2
    popfd
%endif
%endif
%endmacro

; The step decoder replaces incoming arithmetic flags.
%macro HOST_SAMPLE_STEP 0
%ifdef HOST_PROFILE
    inc dword [ebp+host_profile_step]
    test word [ebp+host_profile_step], 4095
    jnz %%done
    push eax
    push edx
    mov eax, [ebp+host_profile_step]
    shr eax, 12
    and eax, 3
    mov edx, [ebx+48]
    mov [ebp+host_profile_samples+eax*8], edx
    mov edx, [ebx+52]
    mov [ebp+host_profile_samples+eax*8+4], edx
    pop edx
    pop eax
%%done:
%endif
%endmacro

%endif
