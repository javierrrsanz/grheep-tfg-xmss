#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdbool.h>

#include "gr_heep.h"
#include "x-heep.h"
#include "hart.h"
#include "csr.h"
#include "fast_intr_ctrl.h"

#include "spi_sdk.h"
#include "bitfield.h"
#include "w25q128jw.h"

/* Activar PRINTF en simulacion y desactivarlo en placas por rendimiento */
#define PRINTF_IN_FPGA  0
#define PRINTF_IN_SIM   1

#if TARGET_SIM && PRINTF_IN_SIM
    #define PRINTF(fmt, ...)    printf(fmt, ## __VA_ARGS__)
#elif PRINTF_IN_FPGA && !TARGET_SIM
    #define PRINTF(fmt, ...)    printf(fmt, ## __VA_ARGS__)
#else
    #define PRINTF(...)
#endif

// ============================================================================
// DEFINICIONES DE SEGURIDAD, MEMORIA Y SPI
// ============================================================================
#define SECURE_VALID_CODE    0x3C5A
#define XMSS_CTRL_OFFSET     0x0000u
#define XMSS_STATUS_OFFSET   0x0004u
#define XMSS_SIG_ADDR_OFFSET 0x0008u
#define XMSS_MSG_ADDR_OFFSET 0x0010u
#define XMSS_MLEN_OFFSET     0x0014u
#define XMSS_PK_ADDR_OFFSET  0x0018u

#define SRAM_APP_ADDR        0x018000 // Donde copiaremos y ejecutaremos el firmware
#define FIRMWARE_TOTAL_SIZE  38588    // El tamaño del .bin empaquetado
#define FLASH_MAX_FREQ       (133*1000*1000) 
#define FC_RD                0x03     // Read Data Command


volatile bool xmss_finished = false;

// ============================================================================
// RUTINAS DE HARDWARE (XMSS & Interrupciones)
// ============================================================================
static inline void xmss_write32(uint32_t offset, uint32_t value) {
    volatile uint32_t *ptr = (volatile uint32_t *)(XMSS_PERIPH_START_ADDRESS + offset);
    *ptr = value;
}

static inline uint32_t xmss_read32(uint32_t offset) {
    volatile uint32_t *ptr = (volatile uint32_t *)(XMSS_PERIPH_START_ADDRESS + offset);
    return *ptr;
}

void fic_irq_ext_peripheral(void) {
    xmss_finished = true;
    xmss_write32(XMSS_CTRL_OFFSET, 0x02); // ACK
}

void secure_halt(const char* reason) {
    PRINTF("\n[SECURE BOOT] !!! ALERTA DE SEGURIDAD !!!\n");
    PRINTF("[SECURE BOOT] Motivo: %s\n", reason);
    PRINTF("[SECURE BOOT] Sistema bloqueado permanentemente.\n");
    while(1) { __asm__ volatile ("wfi"); }
}

// ============================================================================
// ZERO-STAGE BOOTLOADER
// ============================================================================
int main(void) {
    PRINTF("\n====================================\n");
    PRINTF("--- X-HEEP XMSS SECURE BOOT ROM  ---\n");
    PRINTF("====================================\n");

    // 1. CONFIGURACIÓN DE INTERRUPCIONES
    enable_fast_interrupt(kExt_peri_fic_e, true);
    CSR_SET_BITS(CSR_REG_MSTATUS, 0x8);
    
    // Habilitamos solo la interrupción del XMSS (bit 31)
    uint32_t intr_mask = (1u << 31);
    CSR_SET_BITS(CSR_REG_MIE, intr_mask);

    // ========================================================================
    // 3. LECTURA FÍSICA DESDE LA SPI FLASH A LA SRAM
    // ========================================================================
    PRINTF("[SECURE BOOT] Inicializando bus SPI Flash...\n");
    
    // We use the w25q128jw BSP driver instead of the interrupt-based spi_execute,
    // to avoid simulation hangs due to FIC interrupt issues or timeouts taking too long.
    if (w25q128jw_init(spi_flash) != FLASH_OK) {
        secure_halt("Fallo critico al inicializar SPI Flash");
    }

    PRINTF("[SECURE BOOT] Leyendo %d bytes desde la Flash externa...\n", FIRMWARE_TOTAL_SIZE);
    
    if (w25q128jw_read_quad(0x000000, (uint32_t*)SRAM_APP_ADDR, FIRMWARE_TOTAL_SIZE) != FLASH_OK) {
        secure_halt("Error de hardware al leer la memoria Flash.");
    }
    
    PRINTF("[SECURE BOOT] Descarga completada.\n");


    // --- BLOQUE DE DEPURACIÓN ---
    PRINTF("\n[DEBUG] Volcado de los primeros 16 bytes (Clave Publica):\n");
    uint8_t *mem_ptr = (uint8_t *)SRAM_APP_ADDR;
    for(int i = 0; i < 16; i++) {
        PRINTF("%02X ", mem_ptr[i]);
    }
    PRINTF("\n\n");

    // ========================================================================
    // 4. PARSEO Y CONFIGURACIÓN DEL ACELERADOR XMSS
    // ========================================================================
    uint32_t payload_size = FIRMWARE_TOTAL_SIZE - 68 - 4768;

    uint32_t pk_ptr  = SRAM_APP_ADDR;                   // 68 bytes
    uint32_t sig_ptr = SRAM_APP_ADDR + 68;              // 4768 bytes
    uint32_t app_ptr = SRAM_APP_ADDR + 68 + 4768;       // payload_size bytes

    PRINTF("[SECURE BOOT] Configurando Acelerador Hardware...\n");
    xmss_write32(XMSS_PK_ADDR_OFFSET,  pk_ptr);
    xmss_write32(XMSS_SIG_ADDR_OFFSET, sig_ptr);
    xmss_write32(XMSS_MSG_ADDR_OFFSET, app_ptr);
    xmss_write32(XMSS_MLEN_OFFSET,     payload_size * 8);

    // 5. LANZAR VERIFICACIÓN
    PRINTF("[SECURE BOOT] Ejecutando verificacion criptografica...\n");
    xmss_finished = false;
    xmss_write32(XMSS_CTRL_OFFSET, 1u);

    while (!xmss_finished) {
        // Deshabilitar interrupciones globalmente (solo a nivel de CPU)
        CSR_CLEAR_BITS(CSR_REG_MSTATUS, 0x8);
        if (!xmss_finished) {
            // Dormir CPU. El HW la despertará si la linea de interrupción sube, 
            // a pesar de que MSTATUS.MIE=0.
            wait_for_interrupt();
        }
        // Reactivar interrupciones. Si nos ha despertado el XMSS,
        // saltará instantáneamente a la ISR (fic_irq_ext_peripheral) en este punto.
        CSR_SET_BITS(CSR_REG_MSTATUS, 0x8);
    }

    // 6. TOMA DE DECISIÓN CRÍTICA
    uint32_t status = xmss_read32(XMSS_STATUS_OFFSET);
    uint16_t valid_code = (uint16_t)(status & 0xFFFFu);

    if (valid_code != SECURE_VALID_CODE) {
        secure_halt("Firma XMSS Invalida o Binario Corrupto.");
    }

    PRINTF("[SECURE BOOT] Exito: Firma validada correctamente.\n");

    // Limpieza de interrupciones de forma inmediata para evitar tormentas de interrupciones
    CSR_CLEAR_BITS(CSR_REG_MSTATUS, 0x8);
    CSR_CLEAR_BITS(CSR_REG_MIE, intr_mask);
    enable_fast_interrupt(kExt_peri_fic_e, false);

    // 7. REUBICACIÓN DEL PAYLOAD Y LIMPIEZA
    PRINTF("[SECURE BOOT] Reubicando la aplicacion a su direccion base (0x%08X)...\n", SRAM_APP_ADDR);
    
    // Copiamos el payload desde app_ptr hacia SRAM_APP_ADDR para que coincida con su link.ld
    memcpy((void*)SRAM_APP_ADDR, (void*)app_ptr, payload_size);
    
    PRINTF("[SECURE BOOT] Reubicacion completada exitosamente.\n");
    PRINTF("[SECURE BOOT] Preparando salto de Programa...\n");

    
    // Sincronizar memoria de instrucciones por si hay cache
    __asm__ volatile ("fence.i");

    PRINTF("[SECURE BOOT] === INICIANDO APLICACION DE USUARIO ===\n\n");
    
    typedef void (*app_entry_t)(void);
    // El punto de entrada será ahora 0x018000 + 0x180
    app_entry_t app_entry = (app_entry_t)(SRAM_APP_ADDR + 0x180); 
    app_entry(); 

    while(1) { __asm__ volatile("wfi"); }
    return 0;
}