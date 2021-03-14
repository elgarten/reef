.POSIX:

BUILDDIR = build
SRCDIR = src
INCLUDEDIR = include
SKELETONDIR = skel

SRCSUFFIXES = .c .s .S
SRCS = $(foreach SUFFIX, $(SRCSUFFIXES), $(wildcard $(SRCDIR)/**/*$(SUFFIX)) $(wildcard $(SRCDIR)/*$(SUFFIX)))
EFIOBJS = $(filter-out $(basename $(MBRIMG)).o, $(foreach SRC, $(SRCS), $(subst $(SRCDIR), $(BUILDDIR), $(basename $(SRC)).o)))
EFIBIN = $(BUILDDIR)/bootx64.efi
DISKIMG = disk.img
ESPIMG = esp.img
MBRIMG = $(BUILDDIR)/bootsector.img
ESPMOUNTPOINT = mnt

PARTITIONFILE = partfile.txt
LINKERSCRIPT = kernel.ld

VMBIOS = tools/OVMF.fd
VMLOG = tools/qemu.log
VM = qemu-system-x86_64

TARGET = x86_64-pe
AS = clang
LD = x86_64-pe-ld 
CC = clang

CFLAGS = -I$(INCLUDEDIR) -target x86_64-w64-windows-gnu -ffreestanding -fshort-wchar -mno-red-zone -Werror -std=c99 -pedantic -pedantic-errors
ASFLAGS = -target x86_64-w64-windows-gnu -Wall -Wextra -Werror
LDFLAGS = --oformat pei-x86-64 --subsystem 10 -pie -e bootstrap_entry -T$(LINKERSCRIPT)

.PHONY: build run log clean
.SUFFIXES: .c .s .S .o .img 

build: $(DISKIMG)

run: $(DISKIMG)
	$(VM) -bios $(VMBIOS) -drive file=$<,if=ide -monitor stdio

log: $(DISKIMG)
	$(VM) -bios $(VMBIOS) -serial file:$(VMLOG) -drive file=$<,if=ide
clean:
	rm -f $(foreach OBJ, $(EFIOBJS), $(BUILDDIR)/$(OBJ))
	rm -f $(DISKIMG)
	rm -f $(ESPIMG)
	rm -f $(MBRIMG)

$(DISKIMG): $(ESPIMG) $(MBRIMG) $(PARTITIONFILE)
	tools/gpt_creator -o $@ -m $(MBRIMG) -s 5000 -b 512 -p $(PARTITIONFILE)

$(ESPIMG): $(EFIBIN) $(wildcard $(SKELETONDIR)/**/*)
	dd if=/dev/zero of=$@ count=4096 bs=512 >& /dev/null
	hdiutil attach -nomount $@ | awk '{print $$1}' > .loopback
	newfs_msdos `cat .loopback` >& /dev/null
	mount -t msdos `cat .loopback` $(ESPMOUNTPOINT)
	cp -R $(SKELETONDIR)/* $(ESPMOUNTPOINT)
	mkdir -p $(ESPMOUNTPOINT)/efi/boot
	cp $(EFIBIN) $(ESPMOUNTPOINT)/efi/boot
	umount $(ESPMOUNTPOINT)
	hdiutil detach `cat .loopback` >& /dev/null
	rm .loopback

$(EFIBIN): $(EFIOBJS) $(LINKERSCRIPT)
	$(LD) $(LDFLAGS) $(EFIOBJS) -o $@

$(BUILDDIR)/%.o: $(SRCDIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<
$(BUILDDIR)/%.o: $(SRCDIR)/%.s
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) -c -o $@ $<
$(BUILDDIR)/%.o: $(SRCDIR)/%.S
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) -c -o $@ $<

$(BUILDDIR)/%.img: $(SRCDIR)/%.s
	nasm -f bin $< -o $@
