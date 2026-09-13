; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
org 100h
%ifndef EXIT_CODE
%define EXIT_CODE 0
%endif
mov dx, 0e4h
mov al, 12
out dx, al
inc dx
mov al, EXIT_CODE
out dx, al
inc dx
mov al, 3
out dx, al
cli
hlt
jmp $
