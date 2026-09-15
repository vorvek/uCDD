; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

bits 16
cpu 386
org 0
%define MDM_SUPPORT 1

%ifdef RESIDENT_AUDIO
%ifndef NO_EMS_QUEUE
%define EMS_QUEUE 1
%endif
%endif

%include "disc.inc"
%include "driver.asm"
%include "helper.asm"
