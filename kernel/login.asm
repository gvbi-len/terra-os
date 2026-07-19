[bits 32]

global login_screen

extern draw_string_at
extern draw_char_at
extern place_pixel
extern kb_get_char
extern kb_flush
extern clear_screen

; ─────────────────────────────────────────
;  Colour palette indices (Mode 13h default)
; ─────────────────────────────────────────
%define COL_BLACK       0
%define COL_BLUE        1
%define COL_DARK_GREEN  2
%define COL_DARK_CYAN   3
%define COL_RED         4
%define COL_DRK_MAGENTA 5
%define COL_BRONW       6
%define COL_LIGHT_GRAY  7
%define COL_DARK_GRAY   8
%define COL_BRIGHT_BLUE 9
%define COL_GREEN       10
%define COL_CYAN        11
%define COL_BRIGHT_RED  12
%define COL_MAGENTA     13
%define COL_YELLOW      14
%define COL_WHITE       15

; ─────────────────────────────────────────
;  Layout constants  (320×200, 8×8 font)
; ─────────────────────────────────────────
%define SCREEN_W        320
%define SCREEN_H        200
%define CHAR_W          8
%define CHAR_H          8

; Title position
%define TITLE_X         80
%define TITLE_Y         28

; Subtitle
%define SUBTITLE_X      68
%define SUBTITLE_Y      42

; Decorative line Y positions
%define LINE1_Y         54
%define LINE2_Y         56

; Field positions
%define LABEL_X         40
%define USER_LABEL_Y    72
%define PASS_LABEL_Y    90

%define FIELD_X         120
%define USER_FIELD_Y    72
%define PASS_FIELD_Y    90

%define FIELD_W         160     ; pixel width of field box
%define FIELD_H         10

; Max input lengths
%define MAX_INPUT       16

; Status message Y
%define STATUS_Y        118
%define STATUS_X        60

; Hint Y
%define HINT_Y          150

; ─────────────────────────────────────────
;  Static strings
; ─────────────────────────────────────────
section .data

; Placeholder Credentials
valid_user  db "gabi", 0
valid_pass  db "admin", 0

; ── UI text ──
str_title       db "TerraOS", 0
str_subtitle    db "PROTOTYPE v0.1", 0
str_user_label  db "USERNAME:", 0
str_pass_label  db "PASSWORD:", 0
str_enter_msg   db "PRESS ENTER TO CONFIRM", 0
str_granted     db "USER CONFIRMED", 0
str_denied      db "YOU ARE NOT ME!", 0
str_welcome     db "HULLOOO, GABI.", 0
str_hint_u      db "CREATED BY G. SARU", 0
str_hint_p      db "PASSWORD IS MINE", 0
str_cursor      db "_", 0
str_star        db "*", 0

; ── Input buffers ──
user_buf        times (MAX_INPUT+1) db 0
pass_buf        times (MAX_INPUT+1) db 0
user_len        dd 0
pass_len        dd 0

; ── State ──
login_state     db 0    ; 0=entering user, 1=entering pass, 2=result
login_result    db 0    ; 0=none, 1=granted, 2=denied
cursor_blink    dd 0

; ─────────────────────────────────────────
section .text

; ══════════════════════════════════════════
;  login_screen
;  Entry point called from kernel_main.
; ══════════════════════════════════════════
login_screen:
    pusha

    call clear_screen
    call draw_login_ui

    ; Clear input state
    mov dword [user_len], 0
    mov dword [pass_len],  0
    mov byte  [login_state],  0
    mov byte  [login_result], 0

.input_loop:
    call kb_get_char        ; Blocks until a key, returns ASCII in AL

    movzx ecx, al
    cmp byte [login_state], 2
    je  .result_wait        ; Already showing result – wait for Enter

                            ; Small input action handlers
    cmp al, 13              ; Enter
    je  .handle_enter

    cmp al, 8               ; Backspace
    je  .handle_backspace

    ; Only accept printable ASCII
    cmp al, 32
    jb  .input_loop
    cmp al, 126
    ja  .input_loop

    ; Route to correct buffer
    cmp byte [login_state], 0
    je  .append_user
    jmp .append_pass

; ── Append character to username ─────────────────
.append_user:
    mov ecx, [user_len]
    cmp ecx, MAX_INPUT
    jge .input_loop
    mov [user_buf + ecx], al
    inc dword [user_len]
    call redraw_user_field
    jmp .input_loop

; ── Append character to password ─────────────────
.append_pass:
    mov ecx, [pass_len]
    cmp ecx, MAX_INPUT
    jge .input_loop
    mov [pass_buf + ecx], al
    inc dword [pass_len]
    call redraw_pass_field
    jmp .input_loop

; ── Backspace Handler ──────────────────────────
.handle_backspace:
    cmp byte [login_state], 0
    je  .bs_user
    ; backspace on pass
    mov ecx, [pass_len]
    test ecx, ecx
    jz  .input_loop
    dec dword [pass_len]
    mov ecx, [pass_len]
    mov byte [pass_buf + ecx], 0
    call redraw_pass_field
    jmp .input_loop
.bs_user:
    mov ecx, [user_len]
    test ecx, ecx
    jz  .input_loop
    dec dword [user_len]
    mov ecx, [user_len]
    mov byte [user_buf + ecx], 0
    call redraw_user_field
    jmp .input_loop

; ── Enter Handler ──────────────────────────────
.handle_enter:
    cmp byte [login_state], 0
    jne .enter_pass
    ; Move from user → pass field
    mov byte [login_state], 1
    call redraw_user_field  ; Remove cursor from username
    call redraw_pass_field
    jmp .input_loop

.enter_pass:
    ; Validate
    call validate_login
    mov byte [login_state], 2
    call draw_result
    jmp .input_loop

.result_wait:
    cmp al, 13
    jne .input_loop
    cmp byte [login_result], 1
    je  .success
    ; Retry – clear state FIRST, then redraw so fields appear empty
    mov dword [user_len], 0
    mov dword [pass_len],  0
    mov byte  [login_state],  0
    mov byte  [login_result], 0
    ; Clear input buffers
    push es
    push 0x10
    pop  es
    mov edi, user_buf
    mov ecx, MAX_INPUT+1
    xor al, al
    rep stosb
    mov edi, pass_buf
    mov ecx, MAX_INPUT+1
    rep stosb
    pop es
    call clear_screen
    call draw_login_ui
    jmp .input_loop

.success:
    popa
    ret

; ══════════════════════════════════════════
;  validate_login
;  Compares user_buf / pass_buf to valid_*
; ══════════════════════════════════════════
validate_login:
    pusha

    ; Compare username
    mov esi, user_buf
    mov edi, valid_user
.cmp_user:
    mov al, [esi]
    mov bl, [edi]
    cmp al, bl
    jne .fail
    test al, al
    jz  .user_ok
    inc esi
    inc edi
    jmp .cmp_user

.user_ok:
    ; Compare password
    mov esi, pass_buf
    mov edi, valid_pass
.cmp_pass:
    mov al, [esi]
    mov bl, [edi]
    cmp al, bl
    jne .fail
    test al, al
    jz  .pass_ok
    inc esi
    inc edi
    jmp .cmp_pass

.pass_ok:
    mov byte [login_result], 1
    popa
    ret

.fail:
    mov byte [login_result], 2
    popa
    ret

; ══════════════════════════════════════════
;  draw_login_ui  –  static frame
; ══════════════════════════════════════════
draw_login_ui:
    pusha

    ; ── Title ──
    mov ebx, TITLE_X
    mov edi, TITLE_Y
    mov dl,  COL_MAGENTA
    mov esi, str_title
    call draw_string_at

    ; ── Subtitle ──
    mov ebx, SUBTITLE_X
    mov edi, SUBTITLE_Y
    mov dl,  COL_DARK_GREEN
    mov esi, str_subtitle
    call draw_string_at

    ; ── Decorative lines ──
    call draw_deco_lines

    ; ── Field labels ──
    mov ebx, LABEL_X
    mov edi, USER_LABEL_Y
    mov dl,  COL_CYAN
    mov esi, str_user_label
    call draw_string_at

    mov ebx, LABEL_X
    mov edi, PASS_LABEL_Y
    mov dl,  COL_CYAN
    mov esi, str_pass_label
    call draw_string_at

    ; ── Empty field boxes ──
    call draw_field_boxes

    ; ── Hint text ──
    mov ebx, 40
    mov edi, HINT_Y
    mov dl,  COL_DARK_GRAY
    mov esi, str_hint_u
    call draw_string_at

    mov ebx, 40
    mov edi, HINT_Y + 12
    mov dl,  COL_DARK_GRAY
    mov esi, str_hint_p
    call draw_string_at

    ; ── Enter hint ──
    mov ebx, 56
    mov edi, HINT_Y + 26
    mov dl,  COL_DARK_GRAY
    mov esi, str_enter_msg
    call draw_string_at

    ; Draw empty fields + cursor on user
    call redraw_user_field
    call redraw_pass_field

    popa
    ret

; ──────────────────────────────────────────
;  draw_deco_lines  –  horizontal separators
; ──────────────────────────────────────────
draw_deco_lines:
    pusha
    mov edi, 0xA0000

    ; Line 1
    mov ecx, LINE1_Y
    imul ecx, SCREEN_W
    add edi, ecx
    add edi, 20         ; left margin
    mov ecx, 280        ; width
    mov al, COL_DRK_MAGENTA
.line1:
    mov [edi], al
    inc edi
    dec ecx
    jnz .line1

    ; Line 2 (one pixel below, brighter)
    mov edi, 0xA0000
    mov ecx, LINE2_Y
    imul ecx, SCREEN_W
    add edi, ecx
    add edi, 20
    mov ecx, 280
    mov al, COL_MAGENTA
.line2:
    mov [edi], al
    inc edi
    dec ecx
    jnz .line2

    popa
    ret

; ──────────────────────────────────────────
;  draw_field_boxes  –  outline rectangles
; ──────────────────────────────────────────
draw_field_boxes:
    pusha
    ; Username box  (store colour in AL last so we don't lose it)
    mov [.fx], dword FIELD_X - 2
    mov [.fy], dword USER_FIELD_Y - 1
    mov [.fw], dword FIELD_W + 4
    mov [.fh], dword FIELD_H + 2

    mov eax, [.fx]
    mov ebx, [.fy]
    mov ecx, [.fw]
    mov edx, [.fh]
    mov al,  COL_DARK_GREEN
    call draw_rect_outline

    ; Password box
    mov [.fy], dword PASS_FIELD_Y - 1
    mov eax, [.fx]
    mov ebx, [.fy]
    mov ecx, [.fw]
    mov edx, [.fh]
    mov al,  COL_DARK_GREEN
    call draw_rect_outline
    popa
    ret

section .data
.fx dd 0
.fy dd 0
.fw dd 0
.fh dd 0
section .text

; draw_rect_outline: EAX=x, EBX=y, ECX=w, EDX=h, AL=colour
; Draws top and bottom horizontal lines only (enough for field boxing)
draw_rect_outline:
    pusha
    mov [.rx],  eax
    mov [.ry],  ebx
    mov [.rw],  ecx
    mov [.rh],  edx
    mov [.rc],  al

    ; Top line
    mov ebx, [.ry]
    call .hline
    ; Bottom line
    mov eax, [.rh]
    dec eax
    add ebx, eax
    call .hline

    ; Left/right verticals (simple: just corner pixels via pixel loop)
    mov ebx, [.ry]
    mov ecx, [.rh]
.vloop:
    push ecx
    push ebx
    ; left pixel
    mov eax, [.rx]
    mov ah,  [.rc]
    mov edi, ebx
    call place_pixel
    ; right pixel
    mov eax, [.rx]
    add eax, [.rw]
    dec eax
    mov ah,  [.rc]
    mov edi, ebx
    call place_pixel
    pop ebx
    pop ecx
    inc ebx
    dec ecx
    jnz .vloop

    popa
    ret

.hline:
    ; Draw horizontal line at Y=EBX, X=[.rx], len=[.rw], col=[.rc]
    push ecx
    push edi
    mov ecx, [.rw]
    mov edi, [.rx]
.hl_px:
    push ecx
    push edi
    mov eax, edi
    mov ah,  [.rc]
    call place_pixel
    pop edi
    pop ecx
    inc edi
    dec ecx
    jnz .hl_px
    pop edi
    pop ecx
    ret

section .data
.rx  dd 0
.ry  dd 0
.rw  dd 0
.rh  dd 0
.rc  db 0

section .text

; ══════════════════════════════════════════
;  redraw_user_field
;  Clears the username field area, redraws text + cursor if active
; ══════════════════════════════════════════
redraw_user_field:
    pusha
    ; Clear field background
    mov edi, 0xA0000
    mov eax, USER_FIELD_Y
    imul eax, SCREEN_W
    add eax, FIELD_X
    add edi, eax
    mov ecx, FIELD_H
.clear_row:
    push edi
    push ecx
    mov ecx, FIELD_W
    mov al, COL_BLACK
.clear_px:
    mov [edi], al
    inc edi
    dec ecx
    jnz .clear_px
    pop ecx
    pop edi
    add edi, SCREEN_W
    dec ecx
    jnz .clear_row

    ; Draw text
    mov ecx, [user_len]
    test ecx, ecx
    jz  .no_text
    mov ebx, FIELD_X
    mov edi, USER_FIELD_Y
    mov dl,  COL_WHITE
    mov esi, user_buf
    call draw_string_at

.no_text:
    ; Draw cursor if this field is active
    cmp byte [login_state], 0
    jne .done
    mov ecx, [user_len]
    mov ebx, FIELD_X
    imul ecx, CHAR_W
    add ebx, ecx
    mov edi, USER_FIELD_Y
    mov dl,  COL_GREEN
    mov esi, str_cursor
    call draw_string_at
.done:
    popa
    ret

; ══════════════════════════════════════════
;  redraw_pass_field
;  Same but draws * for each character
; ══════════════════════════════════════════
redraw_pass_field:
    pusha
    ; Clear
    mov edi, 0xA0000
    mov eax, PASS_FIELD_Y
    imul eax, SCREEN_W
    add eax, FIELD_X
    add edi, eax
    mov ecx, FIELD_H
.clear_row:
    push edi
    push ecx
    mov ecx, FIELD_W
    mov al, COL_BLACK
.clear_px:
    mov [edi], al
    inc edi
    dec ecx
    jnz .clear_px
    pop ecx
    pop edi
    add edi, SCREEN_W
    dec ecx
    jnz .clear_row

    ; Draw stars
    mov ecx, [pass_len]
    test ecx, ecx
    jz  .no_stars
    mov ebx, FIELD_X
    xor edx, edx
.star_loop:
    push ecx
    push ebx
    push edx
    mov edi, PASS_FIELD_Y
    mov al,  '*'
    mov dl,  COL_CYAN
    call draw_char_at
    pop edx
    pop ebx
    pop ecx
    add ebx, CHAR_W
    dec ecx
    jnz .star_loop

.no_stars:
    ; Cursor if active
    cmp byte [login_state], 1
    jne .done
    mov ecx, [pass_len]
    mov ebx, FIELD_X
    imul ecx, CHAR_W
    add ebx, ecx
    mov edi, PASS_FIELD_Y
    mov dl,  COL_GREEN
    mov esi, str_cursor
    call draw_string_at
.done:
    popa
    ret

; ══════════════════════════════════════════
;  draw_result
;  Clears the screen and shows result centred,
;  replacing the login UI entirely so nothing appends.
; ══════════════════════════════════════════
draw_result:
    pusha

    ; Full clear – wipes input fields, labels, everything
    call clear_screen

    ; Redraw title and subtitle so the screen isn't completely bare
    mov ebx, TITLE_X
    mov edi, TITLE_Y
    mov dl,  COL_MAGENTA
    mov esi, str_title
    call draw_string_at

    mov ebx, SUBTITLE_X
    mov edi, SUBTITLE_Y
    mov dl,  COL_DARK_GREEN
    mov esi, str_subtitle
    call draw_string_at

    call draw_deco_lines

    cmp byte [login_result], 1
    je  .show_granted

    ; ── DENIED ──
    ; Centre "INCORRECT USERNAME OR PASSWORD" (30 chars = 240px) → X=40
    mov ebx, 40
    mov edi, 90
    mov dl,  COL_BRIGHT_RED
    mov esi, str_denied
    call draw_string_at

    ; "PRESS ENTER TO TRY AGAIN" hint
    mov ebx, 56
    mov edi, 108
    mov dl,  COL_RED
    mov esi, str_enter_msg
    call draw_string_at
    jmp .done

.show_granted:
    ; ── GRANTED ──
    ; Centre "USER CONFIRMED" (14 chars = 112px) → X=104
    mov ebx, 104
    mov edi, 90
    mov dl,  COL_GREEN
    mov esi, str_granted
    call draw_string_at

    mov ebx, 72
    mov edi, 108
    mov dl,  COL_YELLOW
    mov esi, str_welcome
    call draw_string_at

.done:
    popa
    ret
