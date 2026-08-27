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

#define SRAM_FSBL_ADDR       0x000000 // Base de la SRAM donde cargaremos el FSBL
#define SRAM_AUTH_META_ADDR  0x024000 // Buffer temporal en ram4

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
    PRINTF("\n[ZSBL ERROR CRITICO] %s\n", reason);
    PRINTF("[ZSBL] Sistema bloqueado permanentemente.\n");
    while(1) { __asm__ volatile ("wfi"); }
}

// Exception handlers para depuración
void handler_exception(void) {
    uint32_t mcause, mepc, mtval;
    CSR_READ(CSR_REG_MCAUSE, &mcause);
    CSR_READ(CSR_REG_MEPC, &mepc);
    CSR_READ(CSR_REG_MTVAL, &mtval);
    PRINTF("\n[ZSBL TRAP] Excepcion detectada! mcause=0x%08X, mepc=0x%08X, mtval=0x%08X\n", mcause, mepc, mtval);
    secure_halt("Excepcion no controlada en ZSBL.");
}

void handler_bkpt(void) {
    uint32_t mepc, mtval;
    CSR_READ(CSR_REG_MEPC, &mepc);
    CSR_READ(CSR_REG_MTVAL, &mtval);
    PRINTF("\n[ZSBL TRAP] Breakpoint (ebreak) detectado! mepc=0x%08X, mtval=0x%08X\n", mepc, mtval);
    secure_halt("Trap ebreak.");
}

// ============================================================================
// ZERO-STAGE BOOTLOADER (ZSBL - ETAPA 0)
// ============================================================================
int main(void) {

    PRINTF("\n==============================================\n");
    PRINTF("---   X-HEEP ZSBL (ETAPA 0 - BOOT ROM)     ---\n");
    PRINTF("==============================================\n");

    // 1. CONFIGURACIÓN DE INTERRUPCIONES
    enable_fast_interrupt(kExt_peri_fic_e, true);
    CSR_SET_BITS(CSR_REG_MSTATUS, 0x8);
    
    // Habilitamos solo la interrupción del XMSS (bit 31)
    uint32_t intr_mask = (1u << 31);
    CSR_SET_BITS(CSR_REG_MIE, intr_mask);

    // ========================================================================
    // 2. LECTURA FÍSICA DESDE LA SPI FLASH A LA SRAM
    // ========================================================================
    PRINTF("[ZSBL] Inicializando bus SPI Flash...\n");
    
    if (w25q128jw_init(spi_flash) != FLASH_OK) {
        secure_halt("Fallo critico al inicializar SPI Flash.");
    }

    uint32_t firmware_total_size = 0;
    
    // Leemos los primeros 4 bytes de la cabecera (offset 0x000000)
    if (w25q128jw_read_quad(0x000000, &firmware_total_size, 4) != FLASH_OK) {
        secure_halt("Error de hardware al leer la cabecera del FSBL de la Flash.");
    }

    PRINTF("[ZSBL] Cabecera leida. Tamaño total FSBL: %d bytes.\n", firmware_total_size);
    
    uint32_t payload_size = firmware_total_size - 68 - 4768;
    
    uint32_t pk_ptr  = SRAM_AUTH_META_ADDR;              // 68 bytes
    uint32_t sig_ptr = SRAM_AUTH_META_ADDR + 68;         // 4768 bytes
    uint32_t fsbl_ptr = SRAM_FSBL_ADDR;                  // payload_size bytes (destino final directo en 0x00000000)

    PRINTF("[ZSBL] Leyendo metadatos de autenticacion (PK + Firma, 4836 bytes)...\n");
    if (w25q128jw_read_quad(0x000004, (uint32_t*)SRAM_AUTH_META_ADDR, 68 + 4768) != FLASH_OK) {
        secure_halt("Error de hardware al leer metadatos de autenticacion.");
    }

    PRINTF("[ZSBL] Leyendo Payload directamente a 0x%08X (%d bytes)...\n", SRAM_FSBL_ADDR, payload_size);
    if (w25q128jw_read_quad(0x000004 + 68 + 4768, (uint32_t*)SRAM_FSBL_ADDR, payload_size) != FLASH_OK) {
        secure_halt("Error de hardware al leer payload del FSBL de la Flash.");
    }
    
    PRINTF("[ZSBL] Descarga completada.\n");

    // --- BLOQUE DE DEPURACIÓN ---
    PRINTF("\n[DEBUG] Volcado de los primeros 16 bytes (Clave Publica RoT):\n");
    uint8_t *mem_ptr = (uint8_t *)pk_ptr;
    for(int i = 0; i < 16; i++) {
        PRINTF("%02X ", mem_ptr[i]);
    }
    PRINTF("\n\n");

    // ========================================================================
    // 3. VALIDACIÓN DE LA CLAVE PÚBLICA (ROOT OF TRUST) POR HARDWARE
    // ========================================================================
    PRINTF("[ZSBL] Validando Clave Publica (RoTPK) contra eFuses por Hardware...\n");
    
    xmss_write32(XMSS_PK_ADDR_OFFSET, pk_ptr);
    xmss_write32(XMSS_MLEN_OFFSET, 68 * 8); // 544 bits
    
    xmss_finished = false;
    xmss_write32(XMSS_CTRL_OFFSET, 0x04); // Start HASH_ONLY
    
    while (!xmss_finished) {
        CSR_CLEAR_BITS(CSR_REG_MSTATUS, 0x8);
        if (!xmss_finished) {
            wait_for_interrupt();
        }
        CSR_SET_BITS(CSR_REG_MSTATUS, 0x8);
    }
    
    uint8_t calculated_pk_hash[32];
    for (int i = 0; i < 8; i++) {
        uint32_t word = xmss_read32(0x20 + (i * 4));
        calculated_pk_hash[i*4 + 0] = (word >> 24) & 0xFF;
        calculated_pk_hash[i*4 + 1] = (word >> 16) & 0xFF;
        calculated_pk_hash[i*4 + 2] = (word >> 8) & 0xFF;
        calculated_pk_hash[i*4 + 3] = word & 0xFF;
    }
    
    // Hash SHA-256 de rot_key.pk
    const uint32_t bootrom_rotpk_ptr[8] = {
        0x46AA3916, 0x8FF90E7D, 0x27A38210, 0x881991E3,
        0x7F641135, 0xDBA9D5B7, 0x91E6581A, 0x95C1DDDA
    };
    
    uint8_t expected_pk_hash[32];
    PRINTF("[DEBUG] Volcado de la ROM RoTPK:\n");
    for (int i = 0; i < 8; i++) {
        uint32_t expected_word = bootrom_rotpk_ptr[i];
        PRINTF("%08X ", expected_word);
        expected_pk_hash[i*4 + 0] = (expected_word >> 24) & 0xFF;
        expected_pk_hash[i*4 + 1] = (expected_word >> 16) & 0xFF;
        expected_pk_hash[i*4 + 2] = (expected_word >> 8) & 0xFF;
        expected_pk_hash[i*4 + 3] = expected_word & 0xFF;
    }
    PRINTF("\n");
    
    if (memcmp(calculated_pk_hash, expected_pk_hash, 32) != 0) {
        secure_halt("RoTPK Invalida: La clave publica de la Flash no coincide con el Root of Trust (OTP).");
    }
    
    PRINTF("[ZSBL] Clave Publica de RoT AUTENTICADA con exito.\n");

    // ========================================================================
    // 4. PARSEO Y CONFIGURACIÓN DEL ACELERADOR XMSS PARA VERIFICACIÓN DEL FSBL
    // ========================================================================
    PRINTF("[ZSBL] Configurando Acelerador Hardware para verificacion de firma...\n");
    xmss_write32(XMSS_SIG_ADDR_OFFSET, sig_ptr);
    xmss_write32(XMSS_MSG_ADDR_OFFSET, fsbl_ptr);
    xmss_write32(XMSS_MLEN_OFFSET,     payload_size * 8);

    // 5. LANZAR VERIFICACIÓN
    PRINTF("[ZSBL] Ejecutando verificacion criptografica XMSS del FSBL por Hardware...\n");
    xmss_finished = false;
    xmss_write32(XMSS_CTRL_OFFSET, 1u);

    while (!xmss_finished) {
        CSR_CLEAR_BITS(CSR_REG_MSTATUS, 0x8);
        if (!xmss_finished) {
            wait_for_interrupt();
        }
        CSR_SET_BITS(CSR_REG_MSTATUS, 0x8);
    }

    // 6. TOMA DE DECISIÓN CRÍTICA
    uint32_t status = xmss_read32(XMSS_STATUS_OFFSET);
    uint16_t valid_code = (uint16_t)(status & 0xFFFFu);
    PRINTF("[DEBUG] Codigo de estado devuelto por HW: 0x%08X (valid_code=0x%04X)\n", status, valid_code);

    if (valid_code != SECURE_VALID_CODE) {
        secure_halt("Firma XMSS del FSBL Invalida o Binario Corrupto.");
    }

    PRINTF("[ZSBL] Exito: Firma del FSBL validada correctamente por HW.\n");

    // Limpieza de interrupciones de forma inmediata
    CSR_CLEAR_BITS(CSR_REG_MSTATUS, 0x8);
    CSR_CLEAR_BITS(CSR_REG_MIE, intr_mask);
    enable_fast_interrupt(kExt_peri_fic_e, false);

    PRINTF("[ZSBL] Preparando salto a FSBL (Etapa 1)...\n");
    
    // Sincronizar memoria de instrucciones
    __asm__ volatile ("fence.i");

    PRINTF("[ZSBL] === SALTANDO A FSBL (0x00000180) ===\n\n");
    
    typedef void (*fsbl_entry_t)(void);
    fsbl_entry_t fsbl_entry = (fsbl_entry_t)(SRAM_FSBL_ADDR + 0x180);
    fsbl_entry();

    while(1) { __asm__ volatile("wfi"); }
    return 0;
}
