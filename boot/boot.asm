[BITS 16]
[ORG 0x7C00]

start:
    cli
    xor ax, ax              ; Segments:
    mov ds, ax              ; Data: 0x0000
    mov es, ax              ; Extra: 0x0000
    mov ss, ax              ; Stack: 0x0000
    mov sp, 0x7C00          ; Stack growth: Down from bootloader address
    sti

    call enable_a20         ; Access memory above 1MB

    mov ah, 0x00
    mov al, 0x13
    int 0x10                ; Video mode: 13h

    mov ax, 0x1000          ; ES = segment 0x1000 | Physical Address = 0x10000
    mov es, ax
    xor bx, bx              ; Load destination -> ES:BX

    mov si, msg_loading
    call print

    mov ah, 0x02            ; BIOS disk read
    mov al, 20              ; Sectors to read
    mov ch, 0               ; Cylinder
    mov dh, 0               ; Head
    mov cl, 2               ; Start at sector: 2
    int 0x13                ; Read from disk into ES:BX
    jc error

    mov si, msg_done
    call print

    mov si, msg_kernel_loaded
    call print

    call switch_to_pm       ; Switch to Protected Mode
    hlt

print:
    mov ah, 0x0E            ; BIOS teletype service

.loop:
    lodsb                   ; Load next char from DS:SI into AL
    test al, al             ; Check if we've reached the end of string
    jz .done
    int 0x10                ; Print char
    jmp .loop

.done:
    ret

enable_a20:
    in al, 0x92             ; Read from 0x92
    or al, 2                ; Set bit to 1
    out 0x92, al
    ret

error:
    mov si, msg_error
    call print
    hlt                     ; Stop process

switch_to_pm:
    cli
    lgdt [gdt_descriptor]

    mov eax, cr0
    or eax, 1               ; Set bit for PE (Protected Mode Enable)
    mov cr0, eax

    jmp CODE_SEG:init_pm    ; Jump to flush pipeline

[BITS 32]
init_pm:
    mov ax, DATA_SEG
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x90000        ; Set up stack
    mov ebp, esp

    jmp CODE_SEG:0x10000    ; Jump to kernel's entry point

msg_loading db "Loading Kernel...", 0
msg_done    db "Done!", 0
msg_error   db "Error!", 0
msg_kernel_loaded db "Kernel Loaded!", 0

gdt:
    dq 0x0000000000000000   ; Null descriptor
    dq 0x00CF9A000000FFFF   ; Code segment | base 0, 4GB limit
    dq 0x00CF92000000FFFF   ; Data segment | base 0, 4GB limit
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt - 1    ; GDT size - 1
    dd gdt                  ; GDT address

CODE_SEG equ 0x08           ; Code segment selector
DATA_SEG equ 0x10           ; Data segment selector

times 510-($-$$) db 0       ; Pad boot sector to 512B
dw 0xAA55                   ; Boot signature
