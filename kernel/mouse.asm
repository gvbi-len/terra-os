[bits 32]

global mouse_init
global mouse_handler

; Exported state - read by world.asm
global mouse_x          ; current X  (word, 0-319)
global mouse_y          ; current Y  (word, 0-199)
global mouse_buttons    ; bit0=left, bit1=right
global mouse_event      ; incremented each time a full packet is processed

extern set_idt_gate

; ─────────────────────────────────────────
;  8042 ports
; ─────────────────────────────────────────
%define KBD_DATA    0x60
%define KBD_STATUS  0x64
%define KBD_CMD     0x64

; ─────────────────────────────────────────
section .bss
mouse_x         resw 1
mouse_y         resw 1
mouse_buttons   resb 1
mouse_event     resb 1

; Internal packet accumulation
pkt_phase       resb 1   ; 0/1/2 = which byte we're expecting
pkt_byte0       resb 1
pkt_byte1       resb 1

section .text

; ── Wait helpers ─────────────────────────
; Wait until 8042 input buffer empty (bit 1 of status = 0)
wait_write:
    push eax
.spin:
    in  al, KBD_STATUS
    test al, 0x02
    jnz .spin
    pop eax
    ret

; Wait until 8042 output buffer full (bit 0 of status = 1)
wait_read:
    push eax
.spin:
    in  al, KBD_STATUS
    test al, 0x01
    jz  .spin
    pop eax
    ret

; Send byte in AL to mouse device
mouse_write:
    push eax
    push ebx
    mov  bl, al             ; save data byte

    call wait_write
    mov  al, 0xD4           ; tell 8042 to forward next byte to mouse
    out  KBD_CMD, al

    call wait_write
    mov  al, bl
    out  KBD_DATA, al

    pop  ebx
    pop  eax
    ret

; ── mouse_init ───────────────────────────
mouse_init:
    pusha

    ; Clear packet state
    mov byte [pkt_phase], 0
    mov word [mouse_x], 160    ; start centre screen
    mov word [mouse_y], 100
    mov byte [mouse_buttons], 0
    mov byte [mouse_event], 0

    ; Enable auxiliary (mouse) device via 8042
    call wait_write
    mov  al, 0xA8              ; Enable aux device command
    out  KBD_CMD, al

    ; Read and patch the 8042 Command Byte: set bit 1 (enable IRQ12)
    call wait_write
    mov  al, 0x20              ; Get Command Byte
    out  KBD_CMD, al
    call wait_read
    in   al, KBD_DATA
    or   al, 0x02              ; Set AUX IRQ enable bit
    and  al, 0xDF              ; Clear AUX disable bit (bit 5)
    mov  bl, al
    call wait_write
    mov  al, 0x60              ; Set Command Byte
    out  KBD_CMD, al
    call wait_write
    mov  al, bl
    out  KBD_DATA, al

    ; Send "set defaults" to mouse
    mov  al, 0xF6
    call mouse_write
    call wait_read
    in   al, KBD_DATA          ; consume ACK

    ; Send "enable data reporting" to mouse
    mov  al, 0xF4
    call mouse_write
    call wait_read
    in   al, KBD_DATA          ; consume ACK

    ; Wire IRQ12 → INT 0x2C in IDT
    mov  eax, mouse_handler
    mov  ebx, 0x2C
    call set_idt_gate

    ; Unmask IRQ12 on slave PIC (bit 4 of slave IMR)
    in   al, 0xA1
    and  al, 0xEF              ; Clear bit 4
    out  0xA1, al

    popa
    ret

; ── mouse_handler (ISR for INT 0x2C) ────
; PS/2 mouse sends a 3-byte packet: flags, dx, dy
; Bytes arrive one at a time, each triggering this IRQ.
mouse_handler:
    pusha

    ; Drain any stale keyboard byte first (shouldn't happen, but be safe)
    in  al, KBD_STATUS
    test al, 0x20              ; Bit 5: aux data ready
    jz  .spurious

    in  al, KBD_DATA           ; Read the mouse byte

    movzx ecx, byte [pkt_phase]
    cmp   ecx, 0
    je   .byte0
    cmp   ecx, 1
    je   .byte1
    ; else byte 2 (dy)
    jmp  .byte2

.byte0:
    ; Sanity check: bit 3 must always be set in first byte
    test al, 0x08
    jz  .eoi                   ; Desync – discard and wait for a good byte0
    mov [pkt_byte0], al
    mov byte [pkt_phase], 1
    jmp .eoi

.byte1:
    mov [pkt_byte1], al
    mov byte [pkt_phase], 2
    jmp .eoi

.byte2:
    ; Full packet in pkt_byte0 (flags), pkt_byte1 (dx), al (dy)
    mov byte [pkt_phase], 0    ; Reset for next packet

    ; ── Update buttons ──
    mov bl, [pkt_byte0]
    and bl, 0x03               ; bits 0-1: left/right button
    mov [mouse_buttons], bl

    ; ── Update X ──
    ; PS/2 gives a 9-bit two's complement delta:
    ;   low 8 bits = pkt_byte1, sign bit = pkt_byte0 bit 4.
    ; Zero-extend the magnitude first, then apply the sign separately.
    ; If X-overflow bit (pkt_byte0 bit 6) is set, movement overflowed –
    ; clamp the delta to ±255 in the appropriate direction.
    test byte [pkt_byte0], 0x40  ; X overflow?
    jnz  .x_overflow
    movzx ecx, byte [pkt_byte1]  ; ECX = unsigned delta
    test byte [pkt_byte0], 0x10  ; X sign bit set → negative
    jz   .dx_positive
    ; Negative: convert 8-bit magnitude to signed 32-bit two's complement
    or   ecx, 0xFFFFFF00
    jmp  .dx_done
.dx_positive:
    ; Positive: already zero-extended above
    jmp  .dx_done
.x_overflow:
    ; Overflow: clamp to max delta, sign from bit4
    test byte [pkt_byte0], 0x10
    jz   .x_ovf_pos
    mov  ecx, -255
    jmp  .dx_done
.x_ovf_pos:
    mov  ecx, 255
.dx_done:
    movzx eax, word [mouse_x]
    add  eax, ecx
    cmp  eax, 0
    jge  .x_clamp_hi
    xor  eax, eax
    jmp  .x_store
.x_clamp_hi:
    cmp  eax, 319
    jle  .x_store
    mov  eax, 319
.x_store:
    mov  [mouse_x], ax

    ; ── Update Y ──
    ; Same 9-bit scheme; bit 5 = Y sign, bit 7 = Y overflow.
    ; PS/2 Y is positive-upward, screen is positive-downward → negate.
    ; Save AL (raw dy byte) before we clobber it.
    mov  bl, al                  ; BL = raw dy byte (AL still valid here)
    test byte [pkt_byte0], 0x80  ; Y overflow?
    jnz  .y_overflow
    movzx ecx, bl                ; ECX = unsigned delta
    test byte [pkt_byte0], 0x20  ; Y sign bit set → negative in PS/2 = down on screen
    jz   .dy_positive
    or   ecx, 0xFFFFFF00         ; sign-extend
    neg  ecx                     ; negate: PS/2 negative = move down → positive screen Y
    jmp  .dy_done
.dy_positive:
    neg  ecx                     ; negate: PS/2 positive = move up → negative screen Y
    jmp  .dy_done
.y_overflow:
    test byte [pkt_byte0], 0x20
    jz   .y_ovf_pos
    mov  ecx, 255                ; was going up (negative PS/2) → positive screen
    jmp  .dy_done
.y_ovf_pos:
    mov  ecx, -255
.dy_done:
    movzx eax, word [mouse_y]
    add  eax, ecx
    cmp  eax, 0
    jge  .y_clamp_hi
    xor  eax, eax
    jmp  .y_store
.y_clamp_hi:
    cmp  eax, 199
    jle  .y_store
    mov  eax, 199
.y_store:
    mov  [mouse_y], ax

    ; Signal that a new event is ready
    inc  byte [mouse_event]

.spurious:
.eoi:
    ; Send EOI to slave PIC then master PIC
    mov  al, 0x20
    out  0xA0, al
    out  0x20, al

    popa
    iret
