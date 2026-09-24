#include "core_v_mini_mcu.h"
#include "gpio.h"
#include <stdio.h>


// Pines de LEDs de usuario (mapeados a led[4..7] en Genesys 2 y Nexys A7)
static const int leds[] = {5, 6, 7, 8};
#define NUM_LEDS 4

// Retardo de visualización (~100 ms @ 15 MHz de reloj FPGA)
static void delay_step(void) {
    for (volatile int d = 0; d < 400000; d++) {
        __asm__ volatile ("nop");
    }
}

int main(void) {
    
    printf("Hello World from app_dummy\n");

    // 1. Configurar pines GPIO 5 a 8 como salidas Push-Pull y apagarlos
    for (int i = 0; i < NUM_LEDS; i++) {
        gpio_cfg_t pin_cfg = {
            .pin = leds[i],
            .mode = GpioModeOutPushPull
        };
        gpio_config(pin_cfg);
        gpio_write(leds[i], false);
    }

    // 2. Bucle infinito: Efecto "Coche Fantástico" (KITT Scanner)
    // Recorre los LEDs hacia delante (4 -> 5 -> 6 -> 7) y hacia atrás (7 -> 6 -> 5 -> 4)
    while (1) {
        // Barrido de izquierda a derecha (leds 0 a 3)
        for (int i = 0; i < NUM_LEDS; i++) {
            gpio_write(leds[i], true);
            delay_step();
            gpio_write(leds[i], false);
        }
        
        // Barrido de regreso (leds 2 y 1, evitando repetir los extremos)
        for (int i = NUM_LEDS - 2; i > 0; i--) {
            gpio_write(leds[i], true);
            delay_step();
            gpio_write(leds[i], false);
        }
    }
    
    return 0;
}