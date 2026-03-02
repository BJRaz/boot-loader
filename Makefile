AS=nasm
ASFLAGS=-f bin -I include/
BOOT_IMAGE=floppy.img
BINDIR=build
SRCDIR=src
OBJDIR=$(BINDIR)/obj
OBJS=$(addprefix $(OBJDIR)/, boot.bin boot2.bin)

# VirtualBox VM name
VM_NAME=boot-loader

.PHONY: all clean run run-vbox test test-asm test-binary test-quality

all: $(BOOT_IMAGE)

# Create properly sized floppy image (1.44 MB)
$(BOOT_IMAGE): $(OBJS)
	dd if=/dev/zero of=$(BOOT_IMAGE) bs=512 count=2880
	dd if=$(OBJDIR)/boot.bin of=$(BOOT_IMAGE) bs=512 conv=notrunc
	dd if=$(OBJDIR)/boot2.bin of=$(BOOT_IMAGE) bs=512 seek=1 conv=notrunc

# boot2.bin depends on print.asm due to %include directive
$(OBJDIR)/boot2.bin: $(SRCDIR)/boot2.asm include/print.asm | $(OBJDIR)
	$(AS) $(ASFLAGS) -o $@ $(SRCDIR)/boot2.asm

$(OBJDIR)/%.bin: $(SRCDIR)/%.asm | $(OBJDIR)
	$(AS) $(ASFLAGS) -o $@ $<

$(OBJDIR):
	mkdir -p $(OBJDIR)

# Create initial floppy image (1.44 MB)
floppy-image: $(BOOT_IMAGE)

# Run bootloader with QEMU (if available)
run: $(BOOT_IMAGE)
	qemu-system-i386 -fda $(BOOT_IMAGE) 2>/dev/null || echo "QEMU not found. Use 'make run-vbox' for VirtualBox instead."

# Run bootloader with VirtualBox using existing VM
run-vbox: $(BOOT_IMAGE)
	@echo "Attaching floppy image to $(VM_NAME)..."
	VBoxManage storageattach $(VM_NAME) --storagectl "Floppy" --port 0 --device 0 --type fdd --medium $(PWD)/$(BOOT_IMAGE)
	@echo "Starting VM in debug mode (GDB on localhost:5037)..."
	VBoxManage modifyvm $(VM_NAME) --guest-debug-provider=gdb --guest-debug-io-provider=tcp --guest-debug-address=localhost --guest-debug-port=5037
	VBoxManage startvm $(VM_NAME) --type gui

clean:
	rm -rf $(BOOT_IMAGE) $(BINDIR)

# Run all tests
test: all
	bash tests/run_all_tests.sh

# Run specific test suites
test-asm:
	bash tests/test_assembler.sh

test-binary:
	bash tests/test_binary_structure.sh

test-quality:
	bash tests/test_code_quality.sh



