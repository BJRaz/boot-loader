AS=nasm
ASFLAGS=-f bin
LOSETUP=losetup
FLOPPYIMG=floppy.img

floppy.img: boot.bin boot2.bin	
	#-$(LOSETUP) -d /dev/loop1
	dd if=/dev/zero of=$(FLOPPYIMG) bs=1024 count=1440
	$(LOSETUP) -f --show $(FLOPPYIMG)
	dd if=boot.bin of=/dev/loop0
	$(LOSETUP) -d /dev/loop0
	dd if=boot2.bin of=$(FLOPPYIMG) bs=512 seek=1 conv=notrunc
boot.bin: boot.asm 
	$(AS) $(ASFLAGS) -o $@ $< 
boot2.bin: boot2.asm
	$(AS) $(ASFLAGS) -o $@ $<
install: $(FLOPPYIMG)
	cp $(FLOPPYIMG) /media/sf_VBoxLinuxShare/floppy_boot.img
clean:
	-rm $(FLOPPYIMG)
	-rm boot.bin
	-rm boot2.bin

