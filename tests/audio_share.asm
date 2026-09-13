bits 16
cpu 386
org 100h

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

start:
    cld
    mov sp, main_stack_top
    mov bx, (program_end-$$+100h+15)/16
    mov ah, 4ah
    int 21h
    jc failed
    call config_load
    jc failed
    mov ax, 1684h
    mov bx, 4354h
    int 2fh
    test al, al
    jnz failed
    mov [qpi], di
    mov [qpi+2], es
    mov bx, 4096
    mov ah, 48h
    int 21h
    jc failed
    mov [output_allocation], ax
    add ax, 07ffh
    and ax, 0f800h
    mov [output_segment], ax
    mov es, ax
    xor di, di
    call mix_half
    call mix_half
    call trap_install
    jc cleanup
    call sb_start
    jc cleanup
%ifdef OUTPUT_TEST
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
    cmp byte [child_result], 0
    jne failed
    cmp byte [fault], 0
    jne failed
    cmp word [periods], 25
    jb failed
    cmp word [periods], 55
    ja failed
%ifndef OUTPUT_TEST
    cmp word [virtual_starts], 3
    jne failed
    cmp word [virtual_resets], 3
    jne failed
%endif
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

child_name db 'ACLIENT.COM',0
exec_block dw 0,command_tail,0,5ch,0,6ch,0
command_tail db 0,13
%ifdef OUTPUT_TEST
success db 'The sound test has stopped.',13,10,'$'
%else
success db 'The shared audio test passed.',13,10,'$'
%endif
failure db 'The shared audio test failed.',13,10,'$'
align 4
cd_samples:
    incbin "../build/CDTEST.PCM"
times 1024 db 0
main_stack_top:
program_end:
