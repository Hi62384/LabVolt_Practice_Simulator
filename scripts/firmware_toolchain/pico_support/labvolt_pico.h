#pragma once
#include <stdint.h>
/* Minimal bare-metal RP2040 addresses, not a Pico SDK compatibility layer. */
#define LV_REG(address) (*(volatile uint32_t *)(address))
#define LV_GPIO_CTRL(pin) LV_REG(0x40014004u + (pin)*8u)
#define LV_GPIO_OUT_SET LV_REG(0xd0000014u)
#define LV_GPIO_OUT_CLR LV_REG(0xd0000018u)
#define LV_GPIO_OE_SET LV_REG(0xd0000024u)
#define LV_GPIO_IN LV_REG(0xd0000004u)
static inline void lv_gpio_output(unsigned pin) { LV_GPIO_CTRL(pin)=5; LV_GPIO_OE_SET=1u<<pin; }
static inline void lv_gpio_write(unsigned pin,unsigned high) { if(high)LV_GPIO_OUT_SET=1u<<pin;else LV_GPIO_OUT_CLR=1u<<pin; }
