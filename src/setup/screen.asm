; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; Text screen and form helpers for UCDDSET. Rows and columns start at 0.
; The look follows SNDCTRL and SNDMIXER: a white box with a shadow, red
; titles, each value as a white-on-black input, and the selected input in red.

%define A_SCREEN 07h
%define A_BOX 0f0h
%define A_TITLE 0f4h
%define A_FIELD 0fh
%define A_SELECT 4fh
%define A_SHADOW 80h
%define BOX_ROW 1
%define BOX_COL 2
%define BOX_WIDTH 76
%define BOX_HEIGHT 22
%define TITLE_ROW 2
%define TRACK_TOP 5
%define TRACK_BOTTOM 16

%define ITEM_ROW 0
%define ITEM_COL 1
%define ITEM_WIDTH 2
%define ITEM_PARAM 3
%define ITEM_UP 4
%define ITEM_DOWN 5
%define ITEM_LEFT 6
%define ITEM_RIGHT 7
%define ITEM_FORMAT 8
%define ITEM_ACTION 10
%define ITEM_ADJUST 12
%define ITEM_DATA 14
%define ITEM_SIZE 16
%define NONE 0ffh
%define ADJUST 0feh

; row, column, width, parameter, up, down, left, right, format, action, adjust, data
%macro item 12
    db %1,%2,%3,%4,%5,%6,%7,%8
    dw %9,%10,%11,%12
%endmacro

%define CHOICE_VALUE 0
%define CHOICE_SIZE 2
%define CHOICE_LIST 4
%define CHOICE_TEXT 6
%define CHOICE_CHANGED 8

; value, size, list routine, text routine, change check or 0
%macro choice 5
    dw %1
    db %2,0
    dw %3,%4,%5
%endmacro

%macro form_save 0
    push word [form_title]
    push word [form_items]
    push word [form_count]
    push word [form_selected]
    push word [form_draw]
    push word [form_keys]
    push word [form_notes]
    push word [form_status_row]
%endmacro

%macro form_restore 0
    pop word [form_status_row]
    pop word [form_notes]
    pop word [form_keys]
    pop word [form_draw]
    pop word [form_selected]
    pop word [form_count]
    pop word [form_items]
    pop word [form_title]
%endmacro

screen_start:
    mov ax, 3
    int 10h
    ; Bit 7 of an attribute selects a bright background, not blinking.
    mov ax, 1003h
    xor bx, bx
    int 10h
    mov ah, 1
    mov cx, 2000h
    int 10h
    mov byte [screen_active], 1
    ret

screen_stop:
    cmp byte [screen_active], 0
    je .done
    mov ax, 3
    int 10h
    mov ax, 1003h
    mov bx, 1
    int 10h
    mov byte [screen_active], 0
.done:
    ret

; DH row, DL column. Return DI screen offset.
screen_offset:
    push ax
    movzx ax, dh
    imul ax, 80
    movzx di, dl
    add ax, di
    shl ax, 1
    mov di, ax
    pop ax
    ret

; DH row, DL column, SI text, BL attribute. Byte 10 starts the next row at
; the first column. DL returns the column after the text.
put_text:
    push ax
    push di
    push es
    push dx
    mov ax, 0b800h
    mov es, ax
    call screen_offset
    mov ah, bl
.next:
    lodsb
    test al, al
    jz .done
    cmp al, 10
    je .row
    stosw
    inc dl
    jmp .next
.row:
    inc dh
    pop ax
    push ax
    mov dl, al
    call screen_offset
    mov ah, bl
    jmp .next
.done:
    pop ax
    mov dh, ah
    pop es
    pop di
    pop ax
    ret

; DH row, DL column, CX count, AL character, BL attribute.
put_repeat:
    push ax
    push cx
    push di
    push es
    push ax
    mov ax, 0b800h
    mov es, ax
    pop ax
    call screen_offset
    mov ah, bl
    add dl, cl
    rep stosw
    pop es
    pop di
    pop cx
    pop ax
    ret

; SI text. Return CX length.
text_length:
    push ax
    push si
    xor cx, cx
.next:
    lodsb
    test al, al
    jz .done
    inc cx
    jmp .next
.done:
    pop si
    pop ax
    ret

; DH top row, DL left column, AH rows, AL columns, DI box characters,
; BL attribute.
draw_box:
    pusha
    mov [box_left], dl
    mov [box_columns], al
    movzx bp, ah
    sub bp, 2
    mov cx, 1
    mov al, [di]
    call put_repeat
    movzx cx, byte [box_columns]
    sub cx, 2
    mov al, [di+1]
    call put_repeat
    mov cx, 1
    mov al, [di+2]
    call put_repeat
.side:
    inc dh
    test bp, bp
    jz .bottom
    mov dl, [box_left]
    mov al, [di+3]
    call put_repeat
    mov dl, [box_left]
    add dl, [box_columns]
    dec dl
    call put_repeat
    dec bp
    jmp .side
.bottom:
    mov dl, [box_left]
    mov al, [di+4]
    call put_repeat
    movzx cx, byte [box_columns]
    sub cx, 2
    mov al, [di+1]
    call put_repeat
    mov cx, 1
    mov al, [di+5]
    call put_repeat
    popa
    ret

; Clear the screen. Draw the box, its shadow, the title, and the status.
form_frame:
    push es
    mov ax, 0b800h
    mov es, ax
    xor di, di
    mov ax, A_SCREEN*256+' '
    mov cx, 2000
    rep stosw
    pop es
    mov al, ' '
    mov bl, A_SHADOW
    mov dx, (BOX_ROW+BOX_HEIGHT)*256+BOX_COL+2
    mov cx, BOX_WIDTH
    call put_repeat
    mov dh, BOX_ROW+1
    mov cx, 2
.shadow:
    mov dl, BOX_COL+BOX_WIDTH
    call put_repeat
    inc dh
    cmp dh, BOX_ROW+BOX_HEIGHT
    jb .shadow
    mov bl, A_BOX
    mov dh, BOX_ROW
    mov cx, BOX_WIDTH
.body:
    mov dl, BOX_COL
    call put_repeat
    inc dh
    cmp dh, BOX_ROW+BOX_HEIGHT
    jb .body
    mov dx, BOX_ROW*256+BOX_COL
    mov ax, BOX_HEIGHT*256+BOX_WIDTH
    mov di, box_single
    call draw_box
    mov si, [form_title]
    call text_length
    mov dl, 80
    sub dl, cl
    shr dl, 1
    mov dh, TITLE_ROW
    mov bl, A_TITLE
    call put_text

; Show the status message, or the note for the selected item.
status_draw:
    mov si, [status]
    mov bl, A_TITLE
    cmp byte [si], 0
    jne .put
    mov si, [form_notes]
    test si, si
    jz .done
    mov bx, [form_selected]
    shl bx, 1
    mov si, [si+bx]
    test si, si
    jz .done
    mov bl, A_BOX
.put:
    mov dh, [form_status_row]
    mov dl, 4
    call put_text
.done:
    ret

; SI message. Show it now.
status_now:
    mov [status], si
    pusha
    mov dh, [form_status_row]
    movzx bp, byte [form_status_rows]
    mov al, ' '
    mov bl, A_BOX
    mov cx, BOX_WIDTH-2
.clear:
    mov dl, BOX_COL+1
    call put_repeat
    inc dh
    dec bp
    jnz .clear
    call status_draw
    popa
    ret

; Run the form in form_items until an action sets form_done.
form_run:
    mov byte [form_done], 0
.redraw:
    call form_frame
    call [form_draw]
    xor cx, cx
.item:
    cmp cx, [form_count]
    jae .key
    mov bx, cx
    shl bx, 4
    add bx, [form_items]
    call item_draw
    inc cx
    jmp .item
.key:
    xor ah, ah
    int 16h
    mov bx, [form_selected]
    shl bx, 4
    add bx, [form_items]
    mov word [status], empty_text
    call [form_keys]
    jc .handled
    cmp ah, 48h
    je .up
    cmp ah, 50h
    je .down
    cmp ah, 4bh
    je .left
    cmp ah, 4dh
    je .right
    cmp al, 9
    je .next
    cmp ah, 0fh
    je .previous
    cmp al, 13
    je .action
    cmp al, ' '
    je .action
    mov cx, 1
    cmp al, '+'
    je .adjust
    mov cx, -1
    cmp al, '-'
    je .adjust
    jmp .key
.up:
    mov al, [bx+ITEM_UP]
    mov cx, 1
    jmp .side
.down:
    mov al, [bx+ITEM_DOWN]
    mov cx, -1
    jmp .side
.left:
    mov al, [bx+ITEM_LEFT]
    mov cx, -1
    jmp .side
.right:
    mov al, [bx+ITEM_RIGHT]
    mov cx, 1
.side:
    cmp al, ADJUST
    je .adjust
    cmp al, NONE
    je .handled
    movzx ax, al
    mov [form_selected], ax
    jmp .handled
.next:
    mov ax, [form_selected]
    inc ax
    cmp ax, [form_count]
    jb .select
    xor ax, ax
    jmp .select
.previous:
    mov ax, [form_selected]
    test ax, ax
    jnz .back
    mov ax, [form_count]
.back:
    dec ax
.select:
    mov [form_selected], ax
    jmp .handled
.adjust:
    cmp word [bx+ITEM_ADJUST], 0
    je .handled
    call [bx+ITEM_ADJUST]
    jmp .handled
.action:
    call [bx+ITEM_ACTION]
.handled:
    cmp byte [form_done], 0
    je .redraw
    ret

; BX item. Draw its value as an input. A setting that the card does not use
; shows its text in the box color. A fader also draws its track.
item_draw:
    pusha
    mov byte [item_disabled], 0
    mov di, field_text
    call [bx+ITEM_FORMAT]
    mov al, [bx+ITEM_WIDTH]
    mov [item_width], al
    mov dh, [bx+ITEM_ROW]
    mov dl, [bx+ITEM_COL]
    mov cx, bx
    sub cx, [form_items]
    shr cx, 4
    cmp cx, [form_selected]
    sete [item_focus]
    cmp word [bx+ITEM_FORMAT], format_button
    je .button
    cmp word [bx+ITEM_FORMAT], format_fader
    jne .value
    call fader_track
.value:
    mov bl, A_BOX
    cmp byte [item_disabled], 0
    jne .line
    mov bl, A_FIELD
    cmp byte [item_focus], 0
    je .line
    mov bl, A_SELECT
.line:
    call item_line
    popa
    ret
.button:
    mov bl, A_BOX
    mov di, box_single
    cmp byte [item_focus], 0
    je .button_draw
    mov bl, A_TITLE
    mov di, box_double
.button_draw:
    push dx
    call item_line
    pop dx
    dec dh
    mov ah, 3
    mov al, [item_width]
    add al, 2
    call draw_box
    popa
    ret

; DH row, DL column, BL attribute. Draw field_text in a cell of item_width
; plus one space on each side. A cell narrower than 12 centers the text.
item_line:
    mov si, field_text
    call text_length
    movzx ax, byte [item_width]
    cmp cx, ax
    jbe .fits
    mov cx, ax
.fits:
    sub ax, cx
    mov [pad_after], ax
    mov word [pad_before], 0
    cmp byte [item_width], 12
    jae .draw
    shr ax, 1
    mov [pad_before], ax
    sub [pad_after], ax
.draw:
    push cx
    mov al, ' '
    mov cx, [pad_before]
    inc cx
    call put_repeat
    pop cx
    jcxz .after
.character:
    lodsb
    push cx
    mov cx, 1
    call put_repeat
    pop cx
    loop .character
.after:
    mov al, ' '
    mov cx, [pad_after]
    inc cx
    call put_repeat
    ret

; BX item, DL column. Draw a track of ten cells, filled from the bottom. The
; value is in percent. A half cell shows 5 percent.
fader_track:
    pusha
    mov si, [bx+ITEM_DATA]
    movzx ax, byte [si]
    cmp byte [item_disabled], 0
    je .level
    xor ax, ax
.level:
    mov cl, 5
    div cl
    mov [fader_halves], al
    mov [fader_column], dl
    mov dh, TRACK_TOP
    mov ah, TRACK_BOTTOM-TRACK_TOP+1
    mov al, 6
    mov di, box_single
    mov bl, A_BOX
    call draw_box
    mov dh, TRACK_BOTTOM-1
.cell:
    mov al, TRACK_BOTTOM
    sub al, dh
    shl al, 1
    mov ah, 0b0h
    cmp [fader_halves], al
    jae .full
    dec al
    cmp [fader_halves], al
    jb .empty
    mov ah, 0dch
    jmp .filled
.full:
    mov ah, 0dbh
.filled:
    cmp byte [item_focus], 0
    je .empty
    mov bl, A_TITLE
.empty:
    mov al, ah
    mov dl, [fader_column]
    inc dl
    mov cx, 4
    call put_repeat
    mov bl, A_BOX
    dec dh
    cmp dh, TRACK_TOP
    ja .cell
    popa
    ret

; Format routines. BX item, DI output.
format_button:
    jmp format_label

format_label:
    mov si, [bx+ITEM_DATA]
    jmp copy_text

format_choice:
    mov si, [bx+ITEM_DATA]
    call choice_value
    push ax
    call [si+CHOICE_LIST]
    pop ax
    cmp byte [si], 0
    jne .text
    mov byte [item_disabled], 1
    mov si, star_text
    jmp copy_text
.text:
    mov si, [bx+ITEM_DATA]
    jmp [si+CHOICE_TEXT]

; SI choice. Return AX value.
choice_value:
    push bx
    mov bx, [si+CHOICE_VALUE]
    movzx ax, byte [bx]
    cmp byte [si+CHOICE_SIZE], 1
    je .done
    mov ax, [bx]
.done:
    pop bx
    ret

; SI choice, AX value.
choice_store:
    push bx
    mov bx, [si+CHOICE_VALUE]
    mov [bx], al
    cmp byte [si+CHOICE_SIZE], 1
    je .done
    mov [bx], ax
.done:
    pop bx
    ret

; SI copies to DI with the terminator. DI points to the terminator.
copy_text:
    lodsb
    stosb
    test al, al
    jnz copy_text
    dec di
    ret

; Cycle a choice. BX item, CX +1 or -1.
choice_cycle:
    mov si, [bx+ITEM_DATA]
    call choice_value
    mov [choice_old], ax
    push si
    call [si+CHOICE_LIST]
    movzx dx, byte [si]
    shl dx, 1
    jz .disabled
    xor bx, bx
.find:
    cmp bx, dx
    jae .first
    cmp [bx+si+1], ax
    je .found
    add bx, 2
    jmp .find
.first:
    xor bx, bx
    jmp .take
.found:
    add bx, cx
    add bx, cx
    jns .upper
    mov bx, dx
    sub bx, 2
.upper:
    cmp bx, dx
    jb .take
    xor bx, bx
.take:
    mov ax, [bx+si+1]
    pop si
    jmp choice_apply
.disabled:
    pop si
    ret

; SI choice, AX new value. Check the change and keep the old value if the
; check fails.
choice_apply:
    cmp ax, [choice_old]
    je .same
    call choice_store
    cmp word [si+CHOICE_CHANGED], 0
    je .done
    push si
    call [si+CHOICE_CHANGED]
    pop si
    jnc .done
    mov ax, [choice_old]
    jmp choice_store
.done:
    mov byte [changed], 1
.same:
    ret

; Open a list below the item. BX item.
choice_popup:
    mov si, [bx+ITEM_DATA]
    call choice_value
    mov [choice_old], ax
    push si
    call [si+CHOICE_LIST]
    movzx cx, byte [si]
    test cx, cx
    jz .disabled
    mov [popup_list], si
    mov [popup_count], cx
    mov word [popup_index], 0
    xor di, di
.find:
    cmp di, cx
    jae .located
    push bx
    mov bx, di
    shl bx, 1
    cmp [bx+si+1], ax
    pop bx
    je .current
    inc di
    jmp .find
.current:
    mov [popup_index], di
.located:
    pop si
    mov [popup_choice], si
    mov al, [bx+ITEM_ROW]
    inc al
    mov ah, cl
    add ah, al
    add ah, 2
    cmp ah, BOX_ROW+BOX_HEIGHT
    jbe .row
    mov al, [bx+ITEM_ROW]
    sub al, cl
    sub al, 2
.row:
    mov [popup_row], al
    mov al, [bx+ITEM_COL]
    mov [popup_column], al
    mov al, [bx+ITEM_WIDTH]
    mov [popup_width], al
.draw:
    call popup_draw
    xor ah, ah
    int 16h
    cmp al, 27
    je .done
    cmp al, 13
    je .choose
    cmp ah, 48h
    je .up
    cmp ah, 50h
    jne .draw
    mov ax, [popup_index]
    inc ax
    cmp ax, [popup_count]
    jae .draw
    mov [popup_index], ax
    jmp .draw
.up:
    cmp word [popup_index], 0
    je .draw
    dec word [popup_index]
    jmp .draw
.choose:
    mov si, [popup_list]
    mov bx, [popup_index]
    shl bx, 1
    mov ax, [bx+si+1]
    mov si, [popup_choice]
    jmp choice_apply
.disabled:
    pop si
    mov word [status], fixed_message
.done:
    ret

popup_draw:
    pusha
    mov dh, [popup_row]
    mov dl, [popup_column]
    mov ah, byte [popup_count]
    add ah, 2
    mov al, [popup_width]
    add al, 2
    mov di, box_single
    mov bl, A_FIELD
    call draw_box
    mov al, [popup_width]
    mov [item_width], al
    xor bp, bp
.entry:
    cmp bp, [popup_count]
    jae .done
    inc dh
    mov si, [popup_list]
    mov bx, bp
    shl bx, 1
    mov ax, [bx+si+1]
    mov di, field_text
    push bp
    push dx
    mov si, [popup_choice]
    call [si+CHOICE_TEXT]
    pop dx
    pop bp
    mov bl, A_FIELD
    cmp bp, [popup_index]
    jne .attribute
    mov bl, A_SELECT
.attribute:
    mov dl, [popup_column]
    push dx
    call item_line
    pop dx
    ; The cell covers both borders. Draw them again.
    mov bl, A_FIELD
    mov al, 0b3h
    mov cx, 1
    call put_repeat
    add dl, [popup_width]
    call put_repeat
    inc bp
    jmp .entry
.done:
    popa
    ret

; Text builders. DI output. Each routine writes a terminator.
; AX value, three hexadecimal digits.
text_hex3:
    push ax
    push bx
    push cx
    mov cx, 3
    add di, 2
.digit:
    mov bx, ax
    and bx, 15
    mov bl, [hex_digits+bx]
    mov [di], bl
    dec di
    shr ax, 4
    loop .digit
    add di, 4
    mov byte [di], 0
    pop cx
    pop bx
    pop ax
    ret

; AX value, decimal.
text_decimal:
    push ax
    push bx
    push cx
    push dx
    mov bx, 10
    xor cx, cx
.divide:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .divide
.store:
    pop ax
    add al, '0'
    stosb
    loop .store
    mov byte [di], 0
    pop dx
    pop cx
    pop bx
    pop ax
    ret

text_percent:
    call text_decimal
    mov ax, '%'
    stosw
    dec di
    ret

form_items dw 0
form_count dw 0
form_selected dw 0
form_draw dw 0
form_keys dw 0
form_notes dw 0
form_title dw 0
form_status_row db 0
form_status_rows db 1
form_done db 0
item_disabled db 0
item_focus db 0
item_width db 0
pad_before dw 0
pad_after dw 0
box_left db 0
box_columns db 0
fader_halves db 0
fader_column db 0
screen_active db 0
changed db 0
status dw empty_text
choice_old dw 0
popup_list dw 0
popup_choice dw 0
popup_count dw 0
popup_index dw 0
popup_row db 0
popup_column db 0
popup_width db 0
field_text times 96 db 0
hex_digits db '0123456789ABCDEF'
box_single db 0dah,0c4h,0bfh,0b3h,0c0h,0d9h
box_double db 0c9h,0cdh,0bbh,0bah,0c8h,0bch
star_text db '*',0
empty_text db 0
