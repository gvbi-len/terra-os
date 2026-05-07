#!/bin/bash

clear

echo 'Running TerraOS build script'

# Assemble the bootloader
echo 'Building Bootloader...'
nasm -f bin boot/boot.asm -o boot.bin || exit 1

# Assemble the kernel
echo 'Building Kernel...'
nasm -f elf32 kernel/kernel.asm -o kernel.o || exit 1

# Assemble draw_font (font table is now INSIDE this file)
echo 'Building Font functions...'
nasm -f elf32 graphics/draw_font.asm -o draw_font.o || exit 1

# Building IDT
echo 'Building IDT...'
nasm -f elf32 kernel/idt.asm -o idt.o || exit 1

# Link the kernel (REMOVED font.o)
echo 'Linking files...'
ld -m elf_i386 -T kernel/linker.ld -o kernel.elf kernel.o idt.o draw_font.o || exit 1

# Check if link succeeded
if [ $? -ne 0 ]; then
    echo "Linking failed!"
    exit 1
fi

# Convert the kernel to a binary
echo 'Converting to binary...'
objcopy -O binary kernel.elf kernel.bin || exit 1

# Check kernel size
KERNEL_SIZE=$(stat -c%s kernel.bin)
SECTORS_NEEDED=$(( (KERNEL_SIZE + 511) / 512 ))
SECTORS_LOADED=20

# echo "Kernel size: $KERNEL_SIZE bytes"
# echo "Sectors needed: $SECTORS_NEEDED"
# echo "Sectors loaded by bootloader: $SECTORS_LOADED"

# if [ $SECTORS_NEEDED -gt $SECTORS_LOADED ]; then
#     echo "ERROR: Kernel too large! Need $SECTORS_NEEDED sectors but only loading $SECTORS_LOADED"
#     echo "Update boot/boot.asm to load more sectors (mov al, $SECTORS_NEEDED)"
#     exit 1
# fi

# Combine the bootloader and kernel
echo 'Combining builds...'
cat boot.bin kernel.bin > os_image.bin || exit 1

# TOTAL_SIZE=$(stat -c%s os_image.bin)
# echo "OS image size: $TOTAL_SIZE bytes"

# Show symbols to verify font_table is included
# echo ""
# echo "Checking for font_table in kernel.elf..."
# objdump -t kernel.elf | grep font_table && echo "font_table fuckin' exists" || echo "WARNING: font_table not found in kernel.elf!"

echo ""
echo 'Build successful!'

# Run the OS
echo 'Running TerraOS'
qemu-system-x86_64 -drive format=raw,file=os_image.bin -vga std
