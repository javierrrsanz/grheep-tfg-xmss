#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "gr_heep.h"
#include "x-heep.h"
#include "hart.h"
#include "csr.h"
#include "w25q128jw.h"

#include "params.h"
#include "xmss.h"
#include "xmss_commons.h"
#include "sha256.h"

// ============================================================================
// MAPA DE MEMORIA Y OFFSETS
// ============================================================================
#define SRAM_FSBL_ADDR       0x00000000   /* Destino directo del payload FSBL */
#define SRAM_AUTH_META_ADDR  0x00010000   /* Buffer temporal en RAM bank 2 (PK 68B + Sig 2500B) */
#define SRAM_MOUT_ADDR       0x00018000   /* Buffer temporal salida de mensaje autenticado */
#define BENCHMARK_MEM_ADDR   0x00024000   /* Banco 4 de SRAM: métricas compartidas con FSBL */

static inline uint32_t get_mcycle(void) {
    uint32_t cycles;
    __asm__ volatile ("csrr %0, mcycle" : "=r" (cycles));
    return cycles;
}

void secure_halt(void) {
    while (1) {
        __asm__ volatile ("wfi");
    }
}

// ============================================================================
// ZERO-STAGE BOOTLOADER (ZSBL - ETAPA 0 EN BOOT ROM @ 0x20010000)
// ============================================================================
int main(void) {
    // Habilitar contadores de rendimiento (mcycle, minstret) limpiando mcountinhibit (CSR 0x320)
    __asm__ volatile ("csrw 0x320, zero");

    // 0. Inicio de medición de ZSBL
    uint32_t zsbl_start = get_mcycle();

    // 1. Inicializar bus Quad SPI Flash
    if (w25q128jw_init(spi_flash) != FLASH_OK) {
        secure_halt();
    }
    uint32_t zsbl_spi_init_end = get_mcycle();

    // 2. Leer cabecera de 4 bytes (tamaño total FSBL firmado) en offset 0x000000
    uint32_t fsbl_total_size = 0;
    if (w25q128jw_read_quad(0x000000, &fsbl_total_size, 4) != FLASH_OK) {
        secure_halt();
    }
    uint32_t zsbl_spi_hdr_end = get_mcycle();

    uint32_t fsbl_payload_size = fsbl_total_size - 68 - 2500;

    // 3. Leer metadatos de autenticación del FSBL (PK 68B + Firma RFC 8391 Nativa 2500B)
    if (w25q128jw_read_quad(0x000004, (uint32_t*)SRAM_AUTH_META_ADDR, 68 + 2500) != FLASH_OK) {
        secure_halt();
    }
    uint32_t zsbl_spi_meta_end = get_mcycle();

    // 4. Leer Payload del FSBL directamente a SRAM (0x00000000) y preparar sm_buf
    uint8_t *rotpk_ptr = (uint8_t *)SRAM_AUTH_META_ADDR;
    uint8_t *sm_buf    = (uint8_t *)(SRAM_AUTH_META_ADDR + 68);
    uint8_t *mout_buf  = (uint8_t *)SRAM_MOUT_ADDR;
    uint8_t *fsbl_pay  = (uint8_t *)SRAM_FSBL_ADDR;

    if (w25q128jw_read_quad(0x000004 + 68 + 2500, (uint32_t*)SRAM_FSBL_ADDR, fsbl_payload_size) != FLASH_OK) {
        secure_halt();
    }
    memcpy(sm_buf + 2500, fsbl_pay, fsbl_payload_size);
    uint32_t zsbl_spi_end = get_mcycle();

    // 5. Autenticación de la RoTPK contra el hash OTP mediante SHA-256 en Software
    SHA256_CTX sha_ctx;
    uint8_t rotpk_hash[32];
    sha256_init(&sha_ctx);
    sha256_update(&sha_ctx, rotpk_ptr, 68);
    sha256_final(&sha_ctx, rotpk_hash);

    // Hash SHA-256 real de rot_key.pk (Root of Trust)
    const uint32_t bootrom_rotpk_ptr[8] = {
        0x510B0134, 0xB52F106B, 0xFCA82441, 0xB4B78483,
        0xFCAE5891, 0x2C4B4520, 0xD8695793, 0xF3C17AA5
    };
    uint8_t expected_rotpk_hash[32];
    for (int i = 0; i < 8; i++) {
        uint32_t w = bootrom_rotpk_ptr[i];
        expected_rotpk_hash[i*4 + 0] = (w >> 24) & 0xFF;
        expected_rotpk_hash[i*4 + 1] = (w >> 16) & 0xFF;
        expected_rotpk_hash[i*4 + 2] = (w >> 8) & 0xFF;
        expected_rotpk_hash[i*4 + 3] = w & 0xFF;
    }

    if (memcmp(rotpk_hash, expected_rotpk_hash, 32) != 0) {
        secure_halt(); // RoTPK inválida
    }
    uint32_t zsbl_rotpk_end = get_mcycle();

    // 6. Verificación Criptográfica XMSS del FSBL en CPU (Zero-Unpack RFC 8391)
    unsigned long long smlen_fsbl = 2500 + fsbl_payload_size;
    unsigned long long mlen_out_fsbl = 0;
    xmss_stage_cycles_t zsbl_stages;

    int status_fsbl = xmss_sign_open_profiled(mout_buf, &mlen_out_fsbl, sm_buf, smlen_fsbl, rotpk_ptr, &zsbl_stages);
    if (status_fsbl != 0 || mlen_out_fsbl != fsbl_payload_size) {
        secure_halt(); // Firma FSBL inválida
    }
    uint32_t zsbl_xmss_end = get_mcycle();

    // 8. Escribir métricas en BENCHMARK_MEM_ADDR (0x00024000)
    volatile uint32_t *bench = (volatile uint32_t *)BENCHMARK_MEM_ADDR;
    bench[0]  = zsbl_start;
    bench[1]  = zsbl_spi_init_end;
    bench[2]  = zsbl_spi_hdr_end;
    bench[3]  = zsbl_spi_meta_end;
    bench[4]  = zsbl_spi_end;
    bench[5]  = zsbl_rotpk_end;
    bench[6]  = zsbl_xmss_end;
    bench[7]  = 0; // DMA Wait overhead (0 en Software)
    bench[8]  = zsbl_stages.hash_cycles;
    bench[9]  = zsbl_stages.wots_cycles;
    bench[10] = zsbl_stages.tree_cycles;
    bench[11] = get_mcycle(); // zsbl_end

    // 9. Salto a FSBL (0x00000180)
    __asm__ volatile ("fence.i");
    typedef void (*fsbl_entry_t)(void);
    fsbl_entry_t fsbl_entry = (fsbl_entry_t)(SRAM_FSBL_ADDR + 0x180);
    fsbl_entry();

    while (1) {
        __asm__ volatile ("wfi");
    }
    return 0;
}
