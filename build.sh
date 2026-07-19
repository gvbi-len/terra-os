#!/bin/bash
set -e
clear

echo 'Running TerraOS build script'

echo 'Building Bootloader...'
nasm -f bin boot/boot.asm -o boot.bin

echo 'Building Kernel...'
nasm -f elf32 kernel/kernel.asm -o kernel.o

echo 'Building Font functions...'
nasm -f elf32 graphics/draw_font.asm -o draw_font.o

echo 'Building IDT...'
nasm -f elf32 kernel/idt.asm -o idt.o

echo 'Building Keyboard driver...'
nasm -f elf32 kernel/keyboard.asm -o keyboard.o

echo 'Building Mouse driver...'
nasm -f elf32 kernel/mouse.asm -o mouse.o

echo 'Building Login screen...'
nasm -f elf32 kernel/login.asm -o login.o

echo 'Building World...'
nasm -f elf32 kernel/world.asm -o world.o

echo 'Linking...'
ld -m elf_i386 -T kernel/linker.ld -o kernel.elf \
    kernel.o idt.o draw_font.o keyboard.o mouse.o login.o world.o

echo 'Converting to binary...'
objcopy -O binary kernel.elf kernel.bin

echo 'Combining bootloader + kernel...'
cat boot.bin kernel.bin > os_image.bin

echo ''
echo 'Build successful!'
echo 'Running TerraOS'
qemu-system-x86_64 -drive format=raw,file=os_image.bin -vga std
