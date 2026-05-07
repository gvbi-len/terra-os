[bits 32]

global idt_init

IDT_ENT_COUNT equ 256

struc idt_entry
    .offset_low resw 1
    .selector resw 1
    .zero resb 1
    .type_attr resb 1
    .offset_high resw 1
endstruc

section .bss
align 8
idt_table:
    resb IDT_ENT_COUNT * 8

section .data
idt_descriptor:
    dw IDT_ENT_COUNT * 8 - 1
    dd idt_table

section .text

set_idt_gate:
    push edx
    push ebx
    
    mov edx, idt_table
    imul ebx, 8
    add edx, ebx
    
    mov word [edx + idt_entry.offset_low], ax
    mov word [edx + idt_entry.selector], 0x08
    mov byte [edx + idt_entry.zero], 0
    mov byte [edx + idt_entry.type_attr], 0x8E
    shr eax, 16
    mov word [edx + idt_entry.offset_high], ax
    
    pop ebx
    pop edx
    ret

pic_remap:
    pusha
    
    mov al, 0x11
    out 0x20, al
    out 0xA0, al
    
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al
    
    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al
    
    mov al, 0x01
    out 0x21, al
    out 0xA1, al
    
    mov al, 0x00
    out 0x21, al
    out 0xA1, al
    
    popa
    ret

default_int_handler:
    pusha
    
    mov al, 0x20
    out 0x20, al
    out 0xA0, al
    
    popa
    iret

idt_init:
    cli
    
    call pic_remap
    
    mov ebx, 0
    mov ecx, IDT_ENT_COUNT
    
.setup_loop:
    mov eax, default_int_handler
    call set_idt_gate
    inc ebx
    loop .setup_loop
    
    lidt [idt_descriptor]
    
    sti
    ret