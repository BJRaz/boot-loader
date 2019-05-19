# boot-loader
An extremely simple boot-loader - just as a learning project


## build on Linux

Run as root or "sudo" build_boot.sh

The script use the NASM assembler, and produces two files:

* an image file - floppy.img - use that in a floppy-device in your preferred virtual/emulated setup e.g. virtualbox.

* a binary file - boot.bin - use that to write to a disk, cd-rom etc, or use in a virtural/emulated setup.

## Prepare floppy.img with data to read 

* dd if=test.txt of=floppy.img bs=512 seek=1 conv=notrunc

This will put the contents of test.txt, at second sector on the floppy image. The program will then read the sector
and place content at memory location 0x7e00

