; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only
%ifndef SB_STATE
%define SB_STATE 1
%define SB_TAIL_CACHE 1
guest_base dw 220h
guest_irq dw 5
guest_dma8 dw 1
guest_dma16 dw 5
guest_vector db 0dh
guest_irq_bit db 20h
guest_irq_priority db 3fh
guest_irq_higher db 1fh
guest_eoi db 65h
guest_dma_ports dw 2,3,83h,0c4h,0c6h,8bh
audio_irq_busy db 0
audio_irq_mask_bit db 0
sb_single db 0
sb_input db 0
sb_finished db 0
sb_paused db 0
sb_speaker db 1
sb_pcm_gain dd 32768,32768
sb_filter_legacy db 0
sb_filter_bypass db 0
sb_filter_state times 4 dd 0
sb_tail_mode db 0
sb_tail_valid db 0
sb_tail_segment dw 0
sb_tail_offset dw 0
sb_tail_consumed dd 0
sb_tail_read_offset dw 0
sb_pause_clock dd 0
sb_pause_mix_frame dd 0
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
