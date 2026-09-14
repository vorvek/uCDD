; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only
%ifndef SB_STATE
%define SB_STATE 1
sb_single db 0
sb_finished db 0
sb_paused db 0
sb_speaker db 1
sb_pause_clock dd 0
sb_test_register db 0
game_origin dd 0
%ifdef RESIDENT_AUDIO
sb_patch_active db 0
sb_patch_available db 0
sb_patch_clock dd 0
sb_patch_limit dd 0
sb_patch_base dw 0
%endif
%endif
