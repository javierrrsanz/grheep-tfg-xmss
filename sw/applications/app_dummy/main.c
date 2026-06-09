#include <stdio.h>
#include <stdint.h>

int main(void) {
    printf("\n");
    printf("===================================================\n");
    printf("   ¡HOLA DESDE LA APP SEGURA! (Ejecucion exitosa)  \n");
    printf("   El Bootloader ha confiado en este firmware.     \n");
    printf("===================================================\n");

    // Bucle infinito para atrapar la CPU. 
    // Un firmware real aquí tendría su RTOS o su bucle principal (while(1) { leer_sensores(); }).
    while (1) {
        __asm__ volatile ("wfi");
    }
    
    return 0;
}