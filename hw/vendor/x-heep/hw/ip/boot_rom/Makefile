# See LICENSE.SiFive for license details

boot_rom = boot_rom.sv

COMPILER_PREFIX?=riscv32-unknown-
GCC?=$(RISCV_XHEEP)/bin/$(COMPILER_PREFIX)elf-gcc
OBJCOPY?=$(RISCV_XHEEP)/bin/$(COMPILER_PREFIX)elf-objcopy
OBJDUMP?=$(RISCV_XHEEP)/bin/$(COMPILER_PREFIX)elf-objdump
PYTHON?=python

INC_FOLDERS                 = $(sort $(dir $(wildcard ../../../sw/device/lib/drivers/*/)))
INC_FOLDERS                += $(sort $(dir $(wildcard ../../../sw/device/lib/base/*/)))
INC_FOLDERS                += $(sort $(dir $(wildcard ../../../sw/device/lib/runtime/)))
INC_FOLDERS_GCC             = $(addprefix -I ,$(INC_FOLDERS))

all: $(boot_rom)

%.sv: %.img
	$(PYTHON) gen_rom.py $<

%.img: %.bin
	dd if=$< of=$@ bs=1024

boot_rom.elf: boot_rom.S link.ld
	$(GCC) $(INC_FOLDERS_GCC) -Tlink.ld $< -nostdlib -static -Wl,--no-gc-sections -o $@

boot_rom.bin: boot_rom.elf
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< --disassemble-all --disassemble-zeroes > boot_rom.dump

clean:
	rm -f *.img *.bin *.sv .*dump
