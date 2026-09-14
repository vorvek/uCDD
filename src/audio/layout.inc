; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%ifndef OUTPUT_SHIFT
%define OUTPUT_SHIFT 12
%endif
%if OUTPUT_SHIFT < 9 || OUTPUT_SHIFT > 12
%error OUTPUT_SHIFT must be 9 to 12.
%endif
%define PERIOD_FRAMES (1 << OUTPUT_SHIFT)
%define PERIOD_BYTES (PERIOD_FRAMES * 4)
%define RING_BYTES (PERIOD_BYTES * 2)
%define RING_WORDS (RING_BYTES / 2)
%define RING_PARAS (RING_BYTES / 16)
%define PERIOD_SCALE (4096 / PERIOD_FRAMES)
%define DMA_FLIP 0
%define DMA_MASK 1
%define DMA_PAGE 2
%define DMA_ADDRESS 4
%define DMA_COUNT 6
%define DMA_SNAPSHOT 8

%ifdef RESIDENT_AUDIO
%define OUTPUT_RATE dword [output_rate]
%else
%define OUTPUT_RATE 44100
%endif
