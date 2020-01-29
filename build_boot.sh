#!/bin/bash
# example from:
#
#	https://wiki.osdev.org/Real_mode_assembly_I
#

# build kernel.bin
# run as root or sudo


	nasm boot.asm -f bin -o boot.bin
	# make floppy.img
	dd if=/dev/zero of=floppy.img bs=1024 count=1440
	# setup loopdevice
	losetup /dev/loop1 floppy.img
	# copy kernel.bin to floppy.img
	dd if=boot.bin of=/dev/loop1
	# copy floppy.img to VirtualBox etc.
	# delete loopdevice
	losetup -d /dev/loop1

# done..



