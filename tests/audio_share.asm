bits 16
cpu 386
org 100h
%include "audio/layout.inc"
%ifdef STREAM_TEST
%define TIMED_TEST 1
%endif
%ifdef ONSET_TEST
%define TIMED_TEST 1
%endif

    jmp start

qpi dd 0
output_segment dw 0
output_allocation dw 0
fault db 0
child_result db 1
cd_position dw 0
game_phase dd 0
game_step dd 32768
game_limit dd 4096*65536
game_rate dw 22050
game_segment dw 0
game_offset dw 0
game_started dd 0
game_active db 0
launch_ss dw 0
launch_sp dw 0

%include "audio/mix.asm"
%include "audio/sb16.asm"
%include "audio/trap.asm"
%include "audio/config.asm"
%ifdef CD_IMAGE_TEST
%include "audio/stream.asm"
%endif
%ifdef VIRTUAL_IRQ
%include "audio/irq.asm"
%endif

start:
    cld
%ifdef PERIOD_SEED
    mov dword [periods], PERIOD_SEED
%endif
    mov sp, main_stack_top
    mov bx, (program_end-$$+100h+15)/16
    mov ah, 4ah
    int 21h
    jc failed
    call config_load
    jc failed
%ifdef CD_IMAGE_TEST
    call cd_open
    jc cleanup_cd
%endif
    mov ax, 1684h
    mov bx, 4354h
    int 2fh
    test al, al
%ifdef CD_IMAGE_TEST
    jnz cleanup_cd
%else
    jnz failed
%endif
    mov [qpi], di
    mov [qpi+2], es
%ifdef VIRTUAL_IRQ
    call virtual_irq_init
%endif
    mov bx, RING_PARAS*2
    mov ah, 48h
    int 21h
%ifdef CD_IMAGE_TEST
    jc cleanup_cd
%else
    jc failed
%endif
    mov [output_allocation], ax
    add ax, RING_PARAS-1
    and ax, ~(RING_PARAS-1)
    mov [output_segment], ax
    mov es, ax
    xor di, di
%ifdef CD_IMAGE_TEST
%ifdef OUTPUT_TEST
    mov byte [cd_started], 1
%endif
%endif
    call mix_half
    call mix_half
    call trap_install
    jc cleanup
    call sb_start
    jc cleanup
%ifdef OUTPUT_TEST
%ifdef CD_IMAGE_TEST
    mov dx, cd_prompt
    mov ah, 9
    int 21h
.stream:
    call cd_pump
    cmp byte [cd_error], 0
    jne cleanup
    mov ah, 1
    int 16h
    jz .progress
    xor ah, ah
    int 16h
    cmp al, 27
    je .stopped
.progress:
    mov eax, [cd_consumed]
    cmp eax, [cd_length]
    jb .stream
    mov eax, [periods]
    add eax, 2
.drain:
    cmp [periods], eax
    jb .drain
.stopped:
    mov byte [child_result], 0
    jmp cleanup
%else
    push ds
    mov ax, 40h
    mov ds, ax
    mov bx, [6ch]
.wait:
    mov ax, [6ch]
    sub ax, bx
    cmp ax, 55
    jb .wait
    pop ds
    mov byte [child_result], 0
    jmp cleanup
%endif
%endif
%ifdef PM_CLIENT
    mov [command_tail+3], cs
    mov [command_tail+7], cs
    mov al, [sb_irq]
    mov [command_tail+9], al
%ifdef VIRTUAL_IRQ
    mov [command_tail+12], cs
%endif
%ifdef CD_IMAGE_TEST
    mov [command_tail+16], cs
%endif
%endif
    mov [exec_block+4], cs
    mov [exec_block+8], cs
    mov [exec_block+12], cs
    mov [launch_ss], ss
    mov [launch_sp], sp
    mov dx, child_name
    mov bx, exec_block
    push cs
    pop es
    mov ax, 4b00h
    int 21h
    cli
    mov ss, [cs:launch_ss]
    mov sp, [cs:launch_sp]
    sti
    push cs
    pop ds
    jc cleanup
    mov ah, 4dh
    int 21h
    mov [child_result], al
cleanup:
    call sb_stop
    call trap_remove
    mov es, [output_allocation]
    mov ah, 49h
    int 21h
%ifdef CD_IMAGE_TEST
cleanup_cd:
    call cd_close
%ifdef CD_REPORT
    call cd_report
%endif
    cmp byte [cd_error], 0
    jne cd_failed
%endif
    cmp byte [child_result], 0
    jne failed
    cmp byte [fault], 0
    jne failed
%ifdef CD_IMAGE_TEST
    jmp passed
%endif
%ifdef QUAKE_TEST
    cmp word [virtual_starts], 1
    jb failed
    cmp word [virtual_resets], 2
    jb failed
    jmp passed
%endif
    mov eax, [periods]
%ifdef PERIOD_SEED
    sub eax, PERIOD_SEED
%endif
%ifdef TIMED_TEST
    cmp eax, 80
    jb failed
    cmp eax, 160
%elifdef VIRTUAL_IRQ
    cmp eax, 65*PERIOD_SCALE
    jb failed
    cmp eax, 120*PERIOD_SCALE
%else
    cmp eax, 25
    jb failed
    cmp eax, 55
%endif
    ja failed
%ifndef OUTPUT_TEST
%ifdef STREAM_TEST
    cmp word [virtual_starts], 1
%elifdef ONSET_TEST
    cmp word [virtual_starts], 6
%elifdef VIRTUAL_IRQ
    cmp word [virtual_starts], 4
%else
    cmp word [virtual_starts], 3
%endif
    jne failed
%ifdef STREAM_TEST
    cmp word [virtual_resets], 1
%elifdef ONSET_TEST
    cmp word [virtual_resets], 6
%elifdef VIRTUAL_IRQ
    cmp word [virtual_resets], 5
%else
    cmp word [virtual_resets], 3
%endif
    jne failed
%endif
passed:
    mov dx, success
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
failed:
    mov dx, failure
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

%ifdef CD_IMAGE_TEST
cd_failed:
    mov dx, cd_failure
    cmp byte [cd_error], 2
    jne .report
    mov dx, cd_empty
.report:
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
cd_failure db 'The CD image read failed.',13,10,'$'
cd_empty db 'The CD audio buffer is empty.',13,10,'$'
cd_prompt db 'Press Esc to stop.',13,10,'$'
%endif

%ifdef CD_REPORT
cd_report:
    mov dx, cd_report_name
    xor cx, cx
    mov ah, 3ch
    int 21h
    jc .done
    mov bx, ax
    mov dx, cd_error
    mov cx, 1
    mov ah, 40h
    int 21h
    mov dx, cd_produced
    mov cx, 12
    mov ah, 40h
    int 21h
    mov dx, fault
    mov cx, 2
    mov ah, 40h
    int 21h
    mov ah, 3eh
    int 21h
.done:
    ret
cd_report_name db 'CDSTAT.DAT',0
%endif

%ifdef PM_CLIENT
child_name db 'APM.COM',0
%else
child_name db 'ACLIENT.COM',0
%endif
exec_block dw 0,command_tail,0,5ch,0,6ch,0
%ifdef PM_CLIENT
%ifdef CD_IMAGE_TEST
command_tail db 17
%elifdef VIRTUAL_IRQ
command_tail db 13
%else
command_tail db 9
%endif
    dw port_callback,0,audio_irq,0
    db 5
%ifdef VIRTUAL_IRQ
    dw virtual_irq_take,0
%endif
%ifdef CD_IMAGE_TEST
    dw cd_service,0
%endif
    db 13
%else
command_tail db 0,13
%endif
%ifdef OUTPUT_TEST
success db 'The sound test has stopped.',13,10,'$'
%else
success db 'The shared audio test passed.',13,10,'$'
%endif
failure db 'The shared audio test failed.',13,10,'$'
align 4
cd_samples:
%ifndef CD_IMAGE_TEST
    incbin "../build/CDTEST.PCM"
%endif
times 1024 db 0
main_stack_top:
program_end:
