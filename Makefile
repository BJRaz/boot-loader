AS=nasm

	
boot.bin:	boot.asm
	$(AS) -f bin boot.asm -o boot.bin
floppy.img: boot.bin	
	-losetup -d /dev/loop1
	dd if=/dev/zero of=floppy.img bs=1024 count=1440
	losetup /dev/loop1 floppy.img
	dd if=boot.bin of=/dev/loop1
	losetup -d /dev/loop1
install: floppy.img
	cp floppy.img /media/sf_VBoxLinuxShare/floppy_boot.img
clean:
	rm floppy.img
	rm boot.bin

	
