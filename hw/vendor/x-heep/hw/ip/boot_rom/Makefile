# See LICENSE.SiFive for license details

boot_rom = boot_rom.sv

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

boot_rom.bin: ../../../sw/build/main.bin
	cp $< $@

clean:
	rm -f *.img *.bin *.sv .*dump
