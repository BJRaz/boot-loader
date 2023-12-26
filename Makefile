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
boot.bin: boot.asm print.asm 
	$(AS) $(ASFLAGS) -o $@ $< 
boot2.bin: boot2.asm print.asm
	$(AS) $(ASFLAGS) -o $@ $<
install: $(FLOPPYIMG)
	cp $(FLOPPYIMG) /media/sf_VBoxLinuxShare/floppy_boot.img
clean:
	-rm -rf $(FLOPPYIMG)
	-rm -rf boot.bin
	-rm -rf boot2.bin

