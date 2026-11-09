#include <stdint.h>
extern uint32_t _sidata, _sdata, _edata, _sbss, _ebss;
extern int main(void);
typedef void (*init_fn)(void);
extern init_fn __preinit_array_start[],__preinit_array_end[],__init_array_start[],__init_array_end[];
void Reset_Handler(void) {
  uint32_t *src=&_sidata,*dst=&_sdata;
  while(dst<&_edata)*dst++=*src++;
  for(dst=&_sbss;dst<&_ebss;dst++)*dst=0;
  for(init_fn *fn=__preinit_array_start;fn<__preinit_array_end;fn++)(*fn)();
  for(init_fn *fn=__init_array_start;fn<__init_array_end;fn++)(*fn)();
  main(); for(;;){}
}
void Default_Handler(void) { for(;;){} }
/* Minimal vector table: application can define its own strong named handlers. */
#define HANDLER(name) void name(void) __attribute__((weak,alias("Default_Handler")))
HANDLER(lv_nmi); HANDLER(lv_hardfault); HANDLER(lv_svcall); HANDLER(lv_pendsv); HANDLER(lv_systick);
HANDLER(lv_irq0); HANDLER(lv_irq1); HANDLER(lv_irq2); HANDLER(lv_irq3); HANDLER(lv_irq4); HANDLER(lv_irq5);
HANDLER(lv_irq6); HANDLER(lv_irq7); HANDLER(lv_irq8); HANDLER(lv_irq9); HANDLER(lv_irq10); HANDLER(lv_irq11);
HANDLER(lv_irq12); HANDLER(lv_irq13); HANDLER(lv_irq14); HANDLER(lv_irq15); HANDLER(lv_irq16); HANDLER(lv_irq17);
HANDLER(lv_irq18); HANDLER(lv_irq19); HANDLER(lv_irq20); HANDLER(lv_irq21); HANDLER(lv_irq22); HANDLER(lv_irq23);
HANDLER(lv_irq24); HANDLER(lv_irq25);
__attribute__((section(".vectors"),used)) const uintptr_t vectors[48]={
  0x20042000,(uintptr_t)Reset_Handler,(uintptr_t)lv_nmi,(uintptr_t)lv_hardfault,
  0,0,0,0,0,0,0,(uintptr_t)lv_svcall,0,0,(uintptr_t)lv_pendsv,(uintptr_t)lv_systick,
  (uintptr_t)lv_irq0,(uintptr_t)lv_irq1,(uintptr_t)lv_irq2,(uintptr_t)lv_irq3,(uintptr_t)lv_irq4,(uintptr_t)lv_irq5,
  (uintptr_t)lv_irq6,(uintptr_t)lv_irq7,(uintptr_t)lv_irq8,(uintptr_t)lv_irq9,(uintptr_t)lv_irq10,(uintptr_t)lv_irq11,
  (uintptr_t)lv_irq12,(uintptr_t)lv_irq13,(uintptr_t)lv_irq14,(uintptr_t)lv_irq15,(uintptr_t)lv_irq16,(uintptr_t)lv_irq17,
  (uintptr_t)lv_irq18,(uintptr_t)lv_irq19,(uintptr_t)lv_irq20,(uintptr_t)lv_irq21,(uintptr_t)lv_irq22,(uintptr_t)lv_irq23,
  (uintptr_t)lv_irq24,(uintptr_t)lv_irq25,0,0,0,0,0,0};
