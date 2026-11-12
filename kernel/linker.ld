OUTPUT_FORMAT("elf32-i386")
OUTPUT_ARCH(i386)
ENTRY(kernel_main)


PHDRS {
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
    bss PT_LOAD FLAGS(6);
}

SECTIONS {
    . = 0x10000;

    .text : {
        *(.text)
    } :text

    /* . = ALIGN(0x1000); */
    .data : {
        *(.data)
    } :data

    /* . = ALIGN(0x1000); */
    .bss : {
        *(COMMON)
        *(.bss)
    } :data
}
