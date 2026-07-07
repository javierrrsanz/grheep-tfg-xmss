#include <stdio.h>
#include <stdint.h>
#include "spi_sdk.h"
#include "core_v_mini_mcu.h"
#include "bitfield.h"
#include "fast_intr_ctrl.h"
#include "csr.h"
#include "csr_registers.h"

#define FC_RD 0x03

int main(void) {
    printf("\n--- SPI TEST: LECTURA BASICA ---\n");

    // Habilitar interrupciones para que el SPI no bloquee la CPU
    enable_fast_interrupt(kExt_peri_fic_e, true);
    CSR_SET_BITS(CSR_REG_MSTATUS, 0x8);
    CSR_SET_BITS(CSR_REG_MIE, (1u << 21)); // FIC_FLASH_MEIE

    spi_slave_t slave = SPI_SLAVE(0, 1000000);
    spi_t spi = spi_init(SPI_IDX_FLASH, slave);

    if (!spi.init) {
        printf("Error inicializando SPI\n");
        return 1;
    }

    uint32_t buffer[4] = {0}; // Vamos a leer 16 bytes (La primera parte de la Clave)
    
    spi_segment_t segments[2] = { SPI_SEG_TX(4), SPI_SEG_RX(16) };
    uint32_t addr = 0x000000;
    uint32_t cmd = (((addr >> 24) | (((addr) & 0x00FF0000) >> 8) | (((addr) & 0x0000FF00) << 8) | ((addr) << 24)) | FC_RD);

    if (spi_execute(&spi, segments, 2, &cmd, buffer) == SPI_CODE_OK) {
        printf("Lectura exitosa. Datos:\n");
        uint8_t *bytes = (uint8_t*)buffer;
        for(int i=0; i<16; i++) {
            printf("%02X ", bytes[i]);
        }
        printf("\n");
    } else {
        printf("Error en la lectura SPI\n");
    }

    // Terminar simulación
    while(1) { __asm__ volatile ("wfi"); }
    return 0;
}