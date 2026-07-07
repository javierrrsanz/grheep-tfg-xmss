#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdbool.h>

#include "gr_heep.h"
#include "hart.h"
#include "csr.h"
#include "fast_intr_ctrl.h"
#include "power_manager.h"
#include "spi_sdk.h"
#include "bitfield.h"

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

// --- NUEVO: Bit de interrupción para la memoria Flash ---
#define FIC_FLASH_MEIE       21       

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
    printf("\n[SECURE BOOT] !!! ALERTA DE SEGURIDAD !!!\n");
    printf("[SECURE BOOT] Motivo: %s\n", reason);
    printf("[SECURE BOOT] Sistema bloqueado permanentemente.\n");
    while(1) { __asm__ volatile ("wfi"); }
}

// ============================================================================
// RUTINA DE LECTURA SPI (Basada en el driver oficial)
// ============================================================================
bool flash_read(spi_t* spi, uint32_t addr, uint32_t* dest_buff, uint32_t len) {
    spi_segment_t segments[2] = { SPI_SEG_TX(4), SPI_SEG_RX(len) };
    uint32_t read_byte_cmd = ((bitfield_byteswap32(addr & 0x00ffffff)) | FC_RD);

    spi_codes_e error = spi_execute(spi, segments, 2, &read_byte_cmd, dest_buff);
    if (error != SPI_CODE_OK) {
        printf("[SPI] Error Code: %i\n", error);
        return false;
    }
    return true;
}

// ============================================================================
// ZERO-STAGE BOOTLOADER
// ============================================================================
int main(void) {
    printf("\n====================================\n");
    printf("--- X-HEEP XMSS SECURE BOOT ROM  ---\n");
    printf("====================================\n");

    // 1. CONFIGURACIÓN DEL SISTEMA (Energía y RAM)
    power_manager_t pm = { .base_addr = POWER_MANAGER_START_ADDRESS };
    power_manager_counters_t pm_counters;
    power_gate_counters_init(&pm_counters, 10, 10, 10, 10, 10, 10, 10, 10);
    power_gate_periph(&pm, kOn_e, &pm_counters);
    for (int i = 0; i < 5; i++) {
        power_gate_ram_block(&pm, i, kOn_e, &pm_counters);
    }

    // 2. CONFIGURACIÓN DE INTERRUPCIONES
    enable_fast_interrupt(kExt_peri_fic_e, true);
    CSR_SET_BITS(CSR_REG_MSTATUS, 0x8);
    
    // --- CORRECCIÓN CLAVE ---
    // Habilitamos tanto el XMSS (bit 31) como el SPI Flash (bit 21)
    uint32_t intr_mask = (1u << 31) | (1u << FIC_FLASH_MEIE);
    CSR_SET_BITS(CSR_REG_MIE, intr_mask);

    // ========================================================================
    // 3. LECTURA FÍSICA DESDE LA SPI FLASH A LA SRAM
    // ========================================================================
    printf("[SECURE BOOT] Inicializando bus SPI Flash...\n");
    
    spi_slave_t slave = SPI_SLAVE(0, FLASH_MAX_FREQ);
    spi_t spi = spi_init(SPI_IDX_FLASH, slave);
    if (!spi.init) secure_halt("Fallo critico al inicializar SPI");

    printf("[SECURE BOOT] Leyendo %d bytes desde la Flash externa...\n", FIRMWARE_TOTAL_SIZE);
    
    if (!flash_read(&spi, 0x000000, (uint32_t*)SRAM_APP_ADDR, FIRMWARE_TOTAL_SIZE)) {
        secure_halt("Error de hardware al leer la memoria Flash.");
    }
    
    printf("[SECURE BOOT] Descarga completada.\n");


    // --- BLOQUE DE DEPURACIÓN ---
    printf("\n[DEBUG] Volcado de los primeros 16 bytes (Clave Publica):\n");
    uint8_t *mem_ptr = (uint8_t *)SRAM_APP_ADDR;
    for(int i = 0; i < 16; i++) {
        printf("%02X ", mem_ptr[i]);
    }
    printf("\n\n");

    // ========================================================================
    // 4. PARSEO Y CONFIGURACIÓN DEL ACELERADOR XMSS
    // ========================================================================
    uint32_t payload_size = FIRMWARE_TOTAL_SIZE - 68 - 4768;

    uint32_t pk_ptr  = SRAM_APP_ADDR;                   // 68 bytes
    uint32_t sig_ptr = SRAM_APP_ADDR + 68;              // 4768 bytes
    uint32_t app_ptr = SRAM_APP_ADDR + 68 + 4768;       // payload_size bytes

    printf("[SECURE BOOT] Configurando Acelerador Hardware...\n");
    xmss_write32(XMSS_PK_ADDR_OFFSET,  pk_ptr);
    xmss_write32(XMSS_SIG_ADDR_OFFSET, sig_ptr);
    xmss_write32(XMSS_MSG_ADDR_OFFSET, app_ptr);
    xmss_write32(XMSS_MLEN_OFFSET,     payload_size * 8);

    // 5. LANZAR VERIFICACIÓN
    printf("[SECURE BOOT] Ejecutando verificacion criptografica...\n");
    xmss_finished = false;
    xmss_write32(XMSS_CTRL_OFFSET, 1u);

    while (!xmss_finished) {
        __asm__ volatile ("nop"); 
    }

    // 6. TOMA DE DECISIÓN CRÍTICA
    uint32_t status = xmss_read32(XMSS_STATUS_OFFSET);
    uint16_t valid_code = (uint16_t)(status & 0xFFFFu);

    if (valid_code != SECURE_VALID_CODE) {
        secure_halt("Firma XMSS Invalida o Binario Corrupto.");
    }

    printf("[SECURE BOOT] Exito: Firma validada correctamente.\n");

    // 7. LIMPIEZA Y HANDOFF
    printf("[SECURE BOOT] Preparando salto de Programa...\n");
    CSR_CLEAR_BITS(CSR_REG_MSTATUS, 0x8);
    CSR_CLEAR_BITS(CSR_REG_MIE, intr_mask);
    enable_fast_interrupt(kExt_peri_fic_e, false);
    
    spi_deinit(&spi);

    printf("[SECURE BOOT] === INICIANDO APLICACION DE USUARIO ===\n\n");
    
    typedef void (*app_entry_t)(void);
    app_entry_t app_entry = (app_entry_t)(app_ptr + 0x180); 
    app_entry(); 

    while(1) { __asm__ volatile("wfi"); }
    return 0;
}