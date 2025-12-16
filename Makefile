AS=nasm
ASFLAGS=-f bin
FLOPPYIMG=floppy.img
BINDIR=bin
OBJS=$(addprefix $(BINDIR)/, boot.bin boot2.bin interrupt.bin print.bin program.bin)

all:	$(OBJS)  
	dd if=/dev/zero of=$(FLOPPYIMG) bs=1024 count=1440
	dd if=bin/boot.bin of=$(FLOPPYIMG) bs=512 conv=notrunc
	dd if=bin//boot2.bin of=$(FLOPPYIMG) bs=512 seek=1 conv=notrunc
$(BINDIR)/%.bin: %.asm | $(BINDIR) 
	$(AS) $(ASFLAGS) -o $@ $< 
$(BINDIR): 
	mkdir bin
clean:
	-rm -rf $(FLOPPYIMG)
	-rm -rf $(BINDIR) 

