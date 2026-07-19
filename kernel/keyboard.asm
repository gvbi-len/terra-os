[bits 32]

global keyboard_init
global keyboard_handler
global kb_get_char       ; Blocking: returns char in AL when available
global kb_flush

extern set_idt_gate

; ─────────────────────────────────────────
;  Shared state
; ─────────────────────────────────────────
section .bss
kb_buf:         resb 64     ; Circular input buffer
kb_buf_head:    resd 1      ; Write index
kb_buf_tail:    resd 1      ; Read  index
shift_held:     resb 1      ; 1 if shift currently down

section .data

; Scancode → ASCII table (unshifted), scancodes 0x00–0x39
sc_table:
    db 0,   27,  '1', '2', '3', '4', '5', '6'   ; 00-07
    db '7', '8', '9', '0', '-', '=',  8,   9    ; 08-0F  (8=BS, 9=TAB)
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i'   ; 10-17
    db 'o', 'p', '[', ']', 13,   0,  'a', 's'   ; 18-1F  (13=CR)
    db 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';'   ; 20-27
    db 39,  '`',  0,  '\', 'z', 'x', 'c', 'v'   ; 28-2F
    db 'b', 'n', 'm', ',', '.', '/',  0,  '*'   ; 30-37
    db 0,   ' '                                  ; 38-39

sc_table_shift:
    db 0,   27,  '!', '@', '#', '$', '%', '^'   ; 00-07
    db '&', '*', '(', ')', '_', '+',  8,   9    ; 08-0F
    db 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I'  ; 10-17
    db 'O', 'P', '{', '}', 13,   0,  'A', 'S'  ; 18-1F
    db 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':'  ; 20-27
    db 34,  '~',  0,  '|', 'Z', 'X', 'C', 'V'  ; 28-2F
    db 'B', 'N', 'M', '<', '>', '?',  0,  '*'  ; 30-37
    db 0,   ' '                                  ; 38-39

section .text

; ── keyboard_init ────────────────────────
; Wire IRQ1 to keyboard_handler in the IDT
; Expects: set_idt_gate already exported from idt.asm
; We call it directly after idt_init, so we duplicate the gate-set inline.
keyboard_init:
    pusha

    ; Clear buffer
    mov dword [kb_buf_head], 0
    mov dword [kb_buf_tail], 0
    mov byte  [shift_held],  0

    ; IRQ1 → INT 0x21  (PIC master remapped to 0x20)
    ; Set IDT entry 0x21
    mov eax, keyboard_handler
    mov ebx, 0x21
    call set_idt_gate

    ; Unmask IRQ1 on PIC master (bit 1 of IMR)
    in  al, 0x21
    and al, 0xFD        ; Clear bit 1
    out 0x21, al

    popa
    ret

; set_idt_gate is extern, called directly

; ── keyboard_handler (ISR) ───────────────
keyboard_handler:
    pusha

    in al, 0x60         ; Read scancode from keyboard port

    ; Check for shift press/release
    cmp al, 0x2A        ; Left shift make
    je  .shift_down
    cmp al, 0x36        ; Right shift make
    je  .shift_down
    cmp al, 0xAA        ; Left shift break
    je  .shift_up
    cmp al, 0xB6        ; Right shift break
    je  .shift_up

    ; Ignore break codes (bit 7 set) except shift
    test al, 0x80
    jnz .eoi

    ; Ignore scancodes beyond table
    cmp al, 0x39
    ja  .eoi

    ; Look up ASCII
    movzx ebx, al
    cmp byte [shift_held], 0
    jne .use_shift

    mov al, [sc_table + ebx]
    jmp .got_char

.use_shift:
    mov al, [sc_table_shift + ebx]

.got_char:
    test al, al
    jz  .eoi            ; Unmapped key

    ; Write into circular buffer
    mov ecx, [kb_buf_head]
    mov [kb_buf + ecx], al
    inc ecx
    and ecx, 63         ; Wrap at 64
    mov [kb_buf_head], ecx

    jmp .eoi

.shift_down:
    mov byte [shift_held], 1
    jmp .eoi

.shift_up:
    mov byte [shift_held], 0

.eoi:
    mov al, 0x20        ; Send EOI to master PIC
    out 0x20, al
    popa
    iret

; ── kb_get_char ──────────────────────────
; Waits (via hlt) until a character is available, returns it in AL
; hlt is essential: without it the tight spin prevents IRQs on some
; QEMU configs and causes missed or repeated keypresses.
kb_get_char:
.wait:
    mov eax, [kb_buf_head]
    mov ecx, [kb_buf_tail]
    cmp eax, ecx
    je  .halt           ; Buffer empty - sleep until next interrupt

    ; Character available - consume it
    mov eax, [kb_buf_tail]
    movzx eax, byte [kb_buf + eax]  ; char in AL, upper bytes clear
    push eax
    mov eax, [kb_buf_tail]
    inc eax
    and eax, 63
    mov [kb_buf_tail], eax
    pop eax                          ; AL = character
    ret

.halt:
    hlt                 ; Sleep until IRQ fires (keyboard or any other)
    jmp .wait           ; Re-check buffer

; ── kb_flush ─────────────────────────────
; Discard everything in the buffer
kb_flush:
    mov eax, [kb_buf_head]
    mov [kb_buf_tail], eax
    ret
