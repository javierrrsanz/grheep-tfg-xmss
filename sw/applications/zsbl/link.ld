/* Linker script for ZSBL running from BOOTROM with Stack/Data at high SRAM (0x020000) */

ENTRY(_start)

MEMORY
{
    BOOTROM (rx)    : ORIGIN = 0x20010000, LENGTH = 0x00010000
    /* ZSBL uses high RAM (ram4 @ 0x020000) so downloading FSBL to 0x000000 does not overwrite stack/bss */
    RAM (xrw)       : ORIGIN = 0x00020000, LENGTH = 0x00008000
}

SECTIONS {

    /* fixed entry point in BOOTROM */
    PROVIDE(__boot_address = 0x20010180);

    /* stack and heap settings */
    __stack_size = DEFINED(__stack_size) ? __stack_size : 0x800;
    PROVIDE(__stack_size = __stack_size);
    __heap_size = DEFINED(__heap_size) ? __heap_size : 0x800;

    /* crt0 init code */
    .init (ORIGIN(BOOTROM)):
    {
        KEEP (*(SORT_NONE(.init)))
        KEEP (*(.text.start))
    } >BOOTROM

    .vectors : ALIGN(256)
    {
      PROVIDE(__vector_start = .);
      KEEP(*(.vectors));
    } >BOOTROM

    /* The program code and constants go into BOOTROM */
    .text :
    {
        . = ALIGN(4);
        *(.text)
        *(.text*)
        *(.rodata)
        *(.rodata*)
        *(.srodata)
        *(.srodata*)
        . = ALIGN(4);
        _etext = .;
    } >BOOTROM

    /* Initialized data placed in RAM, loaded from BOOTROM */
    .data :
    {
        . = ALIGN(4);
        _sidata = LOADADDR(.data);
        _sdata = .;
        _ram_start = .;
        __data_start__ = .;
        __DATA_BEGIN__ = .;
        *(.data)
        *(.data*)
        __SDATA_BEGIN__ = .;
        *(.sdata)
        *(.sdata*)
        . = ALIGN(4);
        _edata = .;
        __data_end__ = .;
    } >RAM AT>BOOTROM

    _lma_vma_data_offset = 0x0;

    /* Power manager state */
    .power_manager (NOLOAD) :
    {
       PROVIDE(__power_manager_start = .);
       . += 256;
    } >RAM

    /* Uninitialized data (BSS) in RAM */
    .bss :
    {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss)
        *(.bss*)
        *(.sbss)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
        __BSS_END__ = .;
    } >RAM

    __global_pointer$ = MIN(__SDATA_BEGIN__ + 0x800,
			    MAX(__DATA_BEGIN__ + 0x800, __BSS_END__ - 0x800));

    .heap :
    {
     PROVIDE(__heap_start = .);
     . = __heap_size;
     PROVIDE(__heap_end = .);
    } >RAM

    .stack : ALIGN(16)
    {
     PROVIDE(__stack_start = .);
     . = __stack_size;
     PROVIDE(_sp = .);
    } >RAM
}
