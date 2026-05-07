[bits 32]

section .data
frame_offset dd 0
frame_count dd 0
color_offset db 0

boot_msg1 db "COLOUR TEST: OK!", 0
boot_msg2 db "0123456789 .,!?;:", 0
boot_msg3 db "ABCDEFGHIJKLMNOPQRSTUVWXYZ", 0
boot_msg4 db "FONT TEST: OK!", 0

section .text
global kernel_main
global place_pixel

extern draw_char_at
extern draw_string_at
extern font_table
extern idt_init

kernel_main:
    cli
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    mov esp, 0x90000
    mov ebp, esp

    call idt_init
    sti

    call colour_test        ; First Colour Test
    call delay_long
    call clear_screen

    call colour_cycle_test  ; Second Colour Test

    call clear_screen       ; TODO: For some reason, non 0 values don't work for
                            ; the text bit, so for now, there won't be a 3rd clear
                            ; screen to make the text visible.
    call colour_test
    call delay_medium

    ; Test out the text
    mov ebx, 10
    mov edi, 30
    mov dl, 0
    mov esi, boot_msg1
    call draw_string_at

    call delay_medium

    mov ebx, 10
    mov edi, 46
    mov dl, 0
    mov esi, boot_msg2
    call draw_string_at

    call delay_medium

    mov ebx, 10
    mov edi, 62
    mov dl, 0
    mov esi, boot_msg3
    call draw_string_at

    call delay_medium

    mov ebx, 10
    mov edi, 78
    mov dl, 0
    mov esi, boot_msg4
    call draw_string_at

main_loop:
    hlt
    jmp main_loop

colour_cycle_test:
    pusha
    
    mov ecx, 0              ; Frame counter

.cycle_loop:
    push ecx

    mov edi, 0x000A0000
    xor ebx, ebx            ; Row counter
    mov edx, 200            ; Total rows

.draw_bars:
    mov al, bl              ; Base color from row number
    add al, [color_offset]  ; Add offset
    and al, 0x0F            ; 0-15 range

    mov esi, 320            ; pixels per row
.fill_row:
    mov [edi], al
    inc edi
    dec esi
    jnz .fill_row

    inc ebx
    dec edx
    jnz .draw_bars

    inc byte [color_offset]
    and byte [color_offset], 0x0F

    ; Delay for visibility
    mov esi, 0x1FFFFFF
.delay:
    dec esi
    jnz .delay

    pop ecx
    inc ecx
    cmp ecx, 32             ; Do 32 cycles
    jl .cycle_loop

    popa
    ret

colour_test:
    mov edi, 0x000A0000
    xor ebx, ebx
    mov ecx, 200

.fill_rows:
    mov al, bl
    mov edx, 320

.fill_cols:
    mov [edi], al
    inc edi
    dec edx
    jnz .fill_cols

    inc ebx
    dec ecx
    jnz .fill_rows

    ret

place_pixel:
    push ebx
    push ecx
    push edx

    mov ebx, eax
    mov ecx, edi

    cmp ebx, 320
    jae .done
    cmp ecx, 200
    jae .done

    mov edx, ecx
    imul edx, 320
    add edx, ebx
    mov edi, 0xA0000
    add edi, edx

    mov [edi], ah

.done:
    pop edx
    pop ecx
    pop ebx
    ret

clear_screen:
    pusha
    mov edi, 0x000A0000
    mov al, 0              ; Black color
    mov ecx, 320*200
    rep stosb              ; Fill entire screen with black
    popa
    ret

delay_short:
    pusha
    mov ecx, 0x2FFFFFF
.delay_loop_short:
    dec ecx
    jnz .delay_loop_short
    popa
    ret

delay_medium:
    pusha
    mov ecx, 0x7FFFFFF
.delay_loop_medium:
    dec ecx
    jnz .delay_loop_medium
    popa
    ret

delay_long:
    pusha
    mov ecx, 0x1FFFFFFF
.delay_loop_long:
    dec ecx
    jnz .delay_loop_long
    popa
    ret
