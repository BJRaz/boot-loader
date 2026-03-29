AS=nasm
ASFLAGS=-f bin
FLOPPYIMG=bin/floppy.img
BINDIR=bin

all:	$(FLOPPYIMG)


$(BINDIR):
	mkdir -p $(BINDIR)

$(FLOPPYIMG): bin/boot.bin bin/boot2.bin | $(BINDIR)	
	dd if=/dev/zero of=$(FLOPPYIMG) bs=1024 count=1440
	dd if=bin/boot.bin of=$(FLOPPYIMG) bs=512 conv=notrunc
	dd if=bin/boot2.bin of=$(FLOPPYIMG) bs=512 seek=1 conv=notrunc
bin/boot.bin: boot.asm print.asm | $(BINDIR)
	$(AS) $(ASFLAGS) -o $@ $< 
bin/boot2.bin: boot2.asm bin/boot.bin | $(BINDIR)
	$(AS) $(ASFLAGS) -o $@ $<
install: $(FLOPPYIMG)
	cp $(FLOPPYIMG) /media/sf_VBoxLinuxShare/floppy_boot.img
clean:
	-rm -rf $(BINDIR)

