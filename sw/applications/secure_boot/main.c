#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdbool.h>
#include "gr_heep.h"
#include "hart.h"
#include "csr.h"
#include "fast_intr_ctrl.h"

#include "firmware_image.h" // ¡Aquí vienen los arrays generados por el script C!

// ============================================================================
// DEFINICIONES DE SEGURIDAD Y MEMORIA
// ============================================================================
#define SECURE_VALID_CODE    0x3C5A
#define XMSS_CTRL_OFFSET     0x0000u
#define XMSS_STATUS_OFFSET   0x0004u
#define XMSS_SIG_ADDR_OFFSET 0x0008u
#define XMSS_MSG_ADDR_OFFSET 0x0010u
#define XMSS_MLEN_OFFSET     0x0014u
#define XMSS_PK_ADDR_OFFSET  0x0018u

#define SRAM_APP_ADDR        0x018000 

volatile bool xmss_finished = false;

// ============================================================================
// RUTINAS AUXILIARES Y DE INTERRUPCIÓN
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
    while(1) {
        __asm__ volatile ("wfi"); // Bloqueo total intencionado
    }
}

// ============================================================================
// ZERO-STAGE BOOTLOADER
// ============================================================================
int main(void) {
    printf("\n====================================\n");
    printf("--- X-HEEP XMSS SECURE BOOT ROM  ---\n");
    printf("====================================\n");

    // 1. CONFIGURACIÓN DEL SISTEMA Y ENERGÍA


    enable_fast_interrupt(kExt_peri_fic_e, true);
    CSR_SET_BITS(CSR_REG_MSTATUS, 0x8);
    CSR_SET_BITS(CSR_REG_MIE, (1u << 31));

    // 2. VOLCADO DEL FIRMWARE A LA SRAM (La zona de ejecución)
    printf("[SECURE BOOT] Copiando Firmware (%lu bytes) a SRAM en 0x%08x...\n", fw_payload_size, SRAM_APP_ADDR);
    memcpy((void*)SRAM_APP_ADDR, fw_payload, fw_payload_size);    
    
    // 3. CONFIGURACIÓN DEL ACELERADOR XMSS
    printf("[SECURE BOOT] Configurando Acelerador Hardware XMSS...\n");
    xmss_write32(XMSS_SIG_ADDR_OFFSET, (uint32_t)fw_hw_ready_signature);
    xmss_write32(XMSS_MSG_ADDR_OFFSET, SRAM_APP_ADDR); 
    xmss_write32(XMSS_PK_ADDR_OFFSET,  (uint32_t)fw_public_key);
    xmss_write32(XMSS_MLEN_OFFSET,     fw_payload_size * 8);

    // 4. LANZAR VERIFICACIÓN
    printf("[SECURE BOOT] Ejecutando verificacion de firma en HW...\n");
    xmss_finished = false;
    xmss_write32(XMSS_CTRL_OFFSET, 1u);

    // --- NUEVO: WFI SEGURO ---
    while (!xmss_finished) {
        CSR_CLEAR_BITS(CSR_REG_MSTATUS, 0x8);
        if (!xmss_finished) {
            wait_for_interrupt();
        }
        CSR_SET_BITS(CSR_REG_MSTATUS, 0x8);
    }

    // 5. TOMA DE DECISIÓN CRÍTICA
    uint32_t status = xmss_read32(XMSS_STATUS_OFFSET);
    uint16_t valid_code = (uint16_t)(status & 0xFFFFu);

    if (valid_code != SECURE_VALID_CODE) {
        secure_halt("Firma XMSS Invalida o corrupta.");
    }

    printf("[SECURE BOOT] Firma validada correctamente.\n");

    // 6. LIMPIEZA DE SEGURIDAD (Lockdown local)
    printf("[SECURE BOOT] Limpiando registros y preparando Handoff...\n");
    CSR_CLEAR_BITS(CSR_REG_MSTATUS, 0x8);
    CSR_CLEAR_BITS(CSR_REG_MIE, (1u << 31));
    enable_fast_interrupt(kExt_peri_fic_e, false);

    // 7. HANDOFF (SALTO A LA APLICACIÓN DE USUARIO) 
    printf("[SECURE BOOT] === INICIANDO APLICACION DE USUARIO ===\n\n");
    
    typedef void (*app_entry_t)(void);
    app_entry_t app_entry = (app_entry_t)(SRAM_APP_ADDR + 0x180); // Salto a 0x18180

    // ¡El gran salto!
    app_entry(); 

    // Si la app retorna por error:
    while(1) { __asm__ volatile("wfi"); }
    return 0;
}