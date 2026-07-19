[bits 32]

global world_run

extern clear_screen
extern mouse_x
extern mouse_y
extern mouse_buttons
extern mouse_event

;  Constants
%define SCREEN_W        320
%define SCREEN_H        200
%define VRAM            0xA0000

%define CURSOR_SIZE     8       ; cursor block size in pixels
%define STAMP_SIZE      8       ; placed block size in pixels

%define COL_BG          0       ; world background: black
%define COL_CURSOR      11      ; cyan cursor
%define COL_STAMP       10      ; bright green placed blocks
%define COL_STAMP_DARK  2       ; dark green placed block outline

; Maximum placed blocks we can track for erasing the cursor without
; overwriting them.  160 blocks fills the 320x200 screen.
%define MAX_STAMPS      160

section .bss

; Previous cursor position (so we can erase it cleanly)
prev_cursor_x   resw 1
prev_cursor_y   resw 1

; Whether left button was down last frame (edge detection)
prev_lbutton    resb 1

; Last event counter we processed
last_event      resb 1

; Stamp list: pairs of words [x, y]
stamp_list      resw MAX_STAMPS * 2
stamp_count     resw 1

section .text

;  world_run
;  Called after login succeeds. Never returns.
world_run:
    call clear_screen

    ; Draw a thin border so the world feels bounded
    call draw_border

    ; Initialise state
    mov word [prev_cursor_x], 160
    mov word [prev_cursor_y], 100
    mov byte [prev_lbutton],  0
    mov word [stamp_count],   0

    ; Snapshot the event counter so the first frame is quiet
    mov al,  [mouse_event]
    mov [last_event], al

    ; Draw initial cursor
    movzx ebx, word [prev_cursor_x]
    movzx edi, word [prev_cursor_y]
    mov   dl,  COL_CURSOR
    call  draw_block

.world_loop:
    ; Has the mouse moved / button changed?
    mov al, [mouse_event]
    cmp al, [last_event]
    je  .no_event

    mov [last_event], al

    ; Erase old cursor
    movzx ebx, word [prev_cursor_x]
    movzx edi, word [prev_cursor_y]
    ; Check if a stamp lives here before painting BG over it
    push ebx
    push edi
    call is_stamp_at    ; returns 1 in eax if stamp here, else 0
    pop  edi
    pop  ebx
    test eax, eax
    jnz  .skip_erase
    mov  dl,  COL_BG
    call draw_block
.skip_erase:

    ; Redraw any stamp at old pos (if cursor was hiding one)
    ; (already handled by skip_erase – we left it painted)

    ; New cursor position
    movzx ebx, word [mouse_x]
    movzx edi, word [mouse_y]

    ; Clamp so 8-pixel block stays on screen
    cmp  ebx, SCREEN_W - CURSOR_SIZE
    jle  .cx_ok
    mov  ebx, SCREEN_W - CURSOR_SIZE
.cx_ok:
    cmp  edi, SCREEN_H - CURSOR_SIZE
    jle  .cy_ok
    mov  edi, SCREEN_H - CURSOR_SIZE
.cy_ok:

    ; Save as new prev
    mov  [prev_cursor_x], bx
    mov  [prev_cursor_y], di

    ; Left-click edge: stamp a block
    mov  al, [mouse_buttons]
    test al, 0x01              ; left button down?
    jz   .no_click

    cmp  byte [prev_lbutton], 1
    je   .held                 ; already held – don't re-stamp

    ; Leading edge: record stamp
    mov  byte [prev_lbutton], 1
    call stamp_block
    jmp  .draw_cursor

.held:
    jmp  .draw_cursor

.no_click:
    mov  byte [prev_lbutton], 0

.draw_cursor:
    ; Draw cursor on top (overwrites any stamp that happens to share the cell;
    ; the stamp is still in stamp_list and will be redrawn when cursor moves away)
    mov  dl,  COL_CURSOR
    call draw_block

.no_event:
    hlt
    jmp .world_loop

;  stamp_block
;  Records current cursor pos in stamp_list and draws it.
;  EBX = x, EDI = y (clamped cursor position)

stamp_block:
    pusha

    ; Don't exceed max stamps
    movzx eax, word [stamp_count]
    cmp  eax, MAX_STAMPS
    jge  .done

    ; Check for duplicate
    push ebx
    push edi
    call is_stamp_at
    pop  edi
    pop  ebx
    test eax, eax
    jnz  .done              ; already a stamp here

    ; Append to list
    movzx eax, word [stamp_count]
    mov  ecx, eax
    shl  ecx, 2              ; *4 (two words per entry)
    mov  [stamp_list + ecx],     bx
    mov  [stamp_list + ecx + 2], di
    inc  word [stamp_count]

    ; Draw the stamp
    mov  dl,  COL_STAMP
    call draw_block

.done:
    popa
    ret

;  is_stamp_at
;  Returns EAX=1 if stamp_list contains (EBX, EDI), else EAX=0
is_stamp_at:
    push ecx
    push esi

    movzx ecx, word [stamp_count]
    test ecx, ecx
    jz   .not_found

    xor  esi, esi
.check_loop:
    mov  ax,  [stamp_list + esi]
    movzx eax, ax
    cmp  eax, ebx
    jne  .next
    mov  ax,  [stamp_list + esi + 2]
    movzx eax, ax
    cmp  eax, edi
    je   .found
.next:
    add  esi, 4
    dec  ecx
    jnz  .check_loop

.not_found:
    xor  eax, eax
    jmp  .ret
.found:
    mov  eax, 1
.ret:
    pop  esi
    pop  ecx
    ret

;  draw_block
;  Fills an 8x8 block of pixels directly into VRAM.
;  EBX = x, EDI = y, DL = colour
;  Writes directly to 0xA0000 – no per-pixel call overhead.
;  Safe for X up to 319 (no AL width limit).
draw_block:
    pusha

    ; VRAM address of top-left pixel
    mov  eax, edi
    imul eax, SCREEN_W
    add  eax, ebx
    add  eax, VRAM

    movzx ecx, dl           ; colour
    mov  edx, CURSOR_SIZE   ; row counter

.row:
    push eax                ; save row start address
    mov  esi, CURSOR_SIZE   ; column counter
.col:
    mov  [eax], cl
    inc  eax
    dec  esi
    jnz  .col
    pop  eax                ; restore row start
    add  eax, SCREEN_W      ; next row
    dec  edx
    jnz  .row

    popa
    ret

;  draw_border
;  Draws a 1-pixel bright-green border around the screen edge.
draw_border:
    pusha

    ; Top row (y=0)
    mov  edi, VRAM
    mov  ecx, SCREEN_W
    mov  al,  COL_STAMP
    rep  stosb

    ; Bottom row (y=199)
    mov  edi, VRAM + (SCREEN_H - 1) * SCREEN_W
    mov  ecx, SCREEN_W
    rep  stosb

    ; Left and right columns
    mov  ecx, SCREEN_H
    mov  edi, VRAM
.sides:
    mov  byte [edi], COL_STAMP            ; left
    mov  byte [edi + SCREEN_W - 1], COL_STAMP  ; right
    add  edi, SCREEN_W
    dec  ecx
    jnz  .sides

    popa
    ret
