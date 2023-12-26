AS=nasm
ASFLAGS=-f bin
FLOPPYIMG=floppy.img

floppy.img: boot.bin boot2.bin	
	dd if=/dev/zero of=$(FLOPPYIMG) bs=1024 count=1440
	dd if=boot.bin of=$(FLOPPYIMG) bs=512 conv=notrunc
	dd if=boot2.bin of=$(FLOPPYIMG) bs=512 seek=1 conv=notrunc
boot.bin: boot.asm print.asm 
	$(AS) $(ASFLAGS) -o $@ $< 
boot2.bin: boot2.asm boot.bin 
	$(AS) $(ASFLAGS) -o $@ $<
install: $(FLOPPYIMG)
	cp $(FLOPPYIMG) /media/sf_VBoxLinuxShare/floppy_boot.img
clean:
	-rm -rf $(FLOPPYIMG)
	-rm -rf boot.bin
	-rm -rf boot2.bin

