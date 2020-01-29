AS=nasm
LOSETUP=losetup
	
boot.bin:	boot2.asm
	$(AS) -f bin boot2.asm -o boot.bin
floppy.img: boot.bin	
	-$(LOSETUP) -d /dev/loop1
	dd if=/dev/zero of=floppy.img bs=1024 count=1440
	$(LOSETUP) /dev/loop1 floppy.img
	dd if=boot.bin of=/dev/loop1
	$(LOSETUP) -d /dev/loop1
install: floppy.img
	cp floppy.img /media/sf_VBoxLinuxShare/floppy_boot.img
clean:
	-rm floppy.img
	-rm boot.bin
	-rm boot2.bin	
