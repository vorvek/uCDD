; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%macro trap_range 2
%ifdef PORT_RANGES
    dw %1,%2
%else
%assign port_index 0
%rep %2
    dw %1+port_index
%assign port_index port_index+1
%endrep
%endif
%endmacro
    trap_range 2,2
    trap_range 0ah,3
    trap_range 0eh,1
%ifdef VIRTUAL_IRQ
    trap_range 20h,2
%endif
    trap_range 83h,1
    trap_range 8bh,1
    trap_range 0c4h,1
    trap_range 0c6h,1
    trap_range 0d4h,1
    trap_range 0d6h,1
    trap_range 0d8h,1
    trap_range 0dch,1
    trap_range 224h,3
    trap_range 22ah,1
    trap_range 22ch,1
    trap_range 22eh,2
%ifdef WSS_INPUT
    trap_range 530h,8
%endif
%unmacro trap_range 2
