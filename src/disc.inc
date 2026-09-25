; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

%define MAX_UNITS 4
%define MAX_TRACKS 99
%define TRACK_SIZE 12
%define TRACK_START 0
%define TRACK_INDEX0 4
%define TRACK_CONTROL 8
; The upper 24 bits hold the cumulative synthetic gap in sectors.
%define HANDLE 0
%define SECTORS 2
%define CHANGED 6
%define LOCKED 7
%define STRIDE 8
%define PAYLOAD 10
%define ORIGIN 12
%define DISC_SECTORS 16
%define TRACK_COUNT 20
%define AUDIO_ENTRY 22
%define IMAGE_PATH 26
%define TRACKS 154
%define UNIT_SIZE (TRACKS + MAX_TRACKS * TRACK_SIZE)
%define INFO_STRIDE 128
%define INFO_PAYLOAD 130
%define INFO_ORIGIN 132
%define INFO_COUNT 136
%define INFO_TRACKS 138
%define INFO_TOTAL (INFO_TRACKS + MAX_TRACKS * TRACK_SIZE)
%define INFO_SIZE (INFO_TOTAL + 4)
%define MDM_MAX 10
%define MDM_INFO 130
%define MDM_SCRATCH (MDM_INFO + MDM_MAX * INFO_SIZE)
%define MDM_INPUT_SIZE (MDM_SCRATCH + UNIT_SIZE)
%define MDM_BACKUP (128 + MDM_MAX * UNIT_SIZE)
