AS=nasm
LOSETUP=losetup
	
boot.bin:	boot.asm boot2.bin
	$(AS) -f bin boot.asm -o boot.bin
boot2.bin:	boot2.asm
	$(AS) -f bin boot2.asm -o boot2.bin
floppy.img: boot.bin	
	-$(LOSETUP) -d /dev/loop1
	dd if=/dev/zero of=floppy.img bs=1024 count=1440
	$(LOSETUP) /dev/loop1 floppy.img
	dd if=boot.bin of=/dev/loop1
	$(LOSETUP) -d /dev/loop1
	dd if=boot2.bin of=floppy.img bs=512 seek=1 conv=notrunc
install: floppy.img
	cp floppy.img /media/sf_VBoxLinuxShare/floppy_boot.img
clean:
	-rm floppy.img
	-rm boot.bin
	-rm boot2.bin
