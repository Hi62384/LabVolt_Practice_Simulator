ENTRY(Reset_Handler)
MEMORY { FLASH (rx) : ORIGIN = 0x10000000, LENGTH = 2048K
         RAM (rwx) : ORIGIN = 0x20000000, LENGTH = 264K }
SECTIONS {
 .boot : { BYTE(0); . = 0x100; } > FLASH
 .vectors : { KEEP(*(.vectors)) } > FLASH
 .text : { *(.text*) *(.rodata*)
   . = ALIGN(4); __preinit_array_start = .; KEEP(*(.preinit_array*)) __preinit_array_end = .;
   __init_array_start = .; KEEP(*(SORT(.init_array.*))) KEEP(*(.init_array)) __init_array_end = .;
 } > FLASH
 .data : { . = ALIGN(4); _sdata = .; *(.data*) . = ALIGN(4); _edata = .; } > RAM AT> FLASH
 _sidata = LOADADDR(.data);
 .bss (NOLOAD) : { . = ALIGN(4); _sbss = .; *(.bss*) *(COMMON) . = ALIGN(4); _ebss = .; } > RAM
 /DISCARD/ : { *(.comment*) *(.ARM.exidx*) *(.ARM.extab*) }
}
