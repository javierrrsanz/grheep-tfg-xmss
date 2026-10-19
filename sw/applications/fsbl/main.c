#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "gr_heep.h"
#include "x-heep.h"
#include "hart.h"
#include "csr.h"
#include "w25q128jw.h"
#include "uart.h"

#include "params.h"
#include "xmss.h"
#include "xmss_commons.h"
#include "sha256.h"

// ============================================================================
// MAPA DE MEMORIA Y OFFSETS (IDÉNTICOS AL ARRANQUE HW EXP-1)
// ============================================================================
#define FLASH_APP_OFFSET     0x010000     /* Offset de la app en Flash SPI (64 KB) */

#define SRAM_AUTH_META_ADDR  0x010000     /* Buffer temporal de metadatos (PK 68B + Sig 2500B) */
#define SRAM_APP_ADDR        0x018000     /* Destino de ejecución de la App de usuario */
#define SRAM_MOUT_ADDR       0x020000     /* Buffer salida mensaje autenticado */

#define BENCHMARK_MEM_ADDR   0x00024000   /* Banco 4 de SRAM: métricas compartidas con ZSBL */

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
// DRIVER UART BARE-METAL LIGERO PARA EL INFORME CONSOLIDADO (SIN LIBC)
// ============================================================================
static uart_t g_uart;

static void uart_init_for_report(void) {
    g_uart.base_addr   = mmio_region_from_addr((uintptr_t)UART_START_ADDRESS);
    g_uart.baudrate    = UART_BAUDRATE;
    g_uart.clk_freq_hz = *(volatile uint32_t *)(SOC_CTRL_START_ADDRESS + 0x1c);
    #ifdef UART_NCO
    g_uart.nco         = UART_NCO;
    #else
    g_uart.nco         = ((uint64_t)g_uart.baudrate << (NCO_WIDTH + 4)) / g_uart.clk_freq_hz;
    #endif
    uart_init(&g_uart);
}

static inline void low_cost_putchar(char c) {
    uart_putchar(&g_uart, (uint8_t)c);
}

void print_str(const char *str) {
    while (*str) {
        if (*str == '\n') {
            low_cost_putchar('\r');
        }
        low_cost_putchar(*str++);
    }
}

void print_dec(uint32_t val, int width) {
    char buf[12];
    int i = 11;
    buf[i] = '\0';
    if (val == 0) {
        i--;
        buf[i] = '0';
    } else {
        while (val > 0) {
            i--;
            buf[i] = '0' + (val % 10);
            val /= 10;
        }
    }
    int len = 11 - i;
    while (width > len) {
        print_str(" ");
        width--;
    }
    print_str(&buf[i]);
}

void print_time_ms(uint32_t cycles, uint32_t freq_mhz, int width) {
    uint32_t divisor = freq_mhz * 1000;
    uint32_t ms_int = cycles / divisor;
    uint32_t remainder = cycles % divisor;
    uint32_t ms_frac = (remainder * 1000) / divisor;

    char buf[20];
    int i = 19;
    buf[i] = '\0';

    for (int d = 0; d < 3; d++) {
        i--;
        buf[i] = '0' + (ms_frac % 10);
        ms_frac /= 10;
    }
    i--;
    buf[i] = '.';

    if (ms_int == 0) {
        i--;
        buf[i] = '0';
    } else {
        while (ms_int > 0) {
            i--;
            buf[i] = '0' + (ms_int % 10);
            ms_int /= 10;
        }
    }

    int len = 19 - i;
    while (width > len) {
        print_str(" ");
        width--;
    }
    print_str(&buf[i]);
}

void print_row(const char *name, uint32_t cycles) {
    print_str(name);
    print_str(" |");
    print_dec(cycles, 12);
    print_str(" |");
    print_time_ms(cycles, 100, 14);
    print_str(" |");
    print_time_ms(cycles, 15, 14);
    print_str("\n");
}

// ============================================================================
// FIRST-STAGE BOOTLOADER (FSBL - ETAPA 1 EN SRAM @ 0x00000000)
// ============================================================================
int main(void) {
    // Habilitar contadores de rendimiento (mcycle, minstret) limpiando mcountinhibit (CSR 0x320)
    __asm__ volatile ("csrw 0x320, zero");

    uint32_t fsbl_start = get_mcycle();

    // 1. Inicializar bus Quad SPI Flash
    if (w25q128jw_init(spi_flash) != FLASH_OK) {
        secure_halt();
    }
    uint32_t fsbl_spi_init_end = get_mcycle();

    // 2. Leer cabecera de tamaño de la App (4 bytes) desde FLASH_APP_OFFSET (0x010000)
    uint32_t app_total_size = 0;
    if (w25q128jw_read_quad(FLASH_APP_OFFSET, &app_total_size, 4) != FLASH_OK) {
        secure_halt();
    }
    uint32_t fsbl_spi_hdr_end = get_mcycle();

    uint32_t app_payload_size = app_total_size - 68 - 2500;

    // 3. Leer metadatos de autenticación de la App (PK 68B + Firma RFC 8391 Nativa 2500B)
    if (w25q128jw_read_quad(FLASH_APP_OFFSET + 4, (uint32_t*)SRAM_AUTH_META_ADDR, 68 + 2500) != FLASH_OK) {
        secure_halt();
    }
    uint32_t fsbl_spi_meta_end = get_mcycle();

    // 4. Leer Payload de la App directamente a SRAM_APP_ADDR (0x018000) y preparar sm_buf
    uint8_t *app_pk_ptr = (uint8_t *)SRAM_AUTH_META_ADDR;
    uint8_t *sm_buf     = (uint8_t *)(SRAM_AUTH_META_ADDR + 68);
    uint8_t *mout_buf   = (uint8_t *)SRAM_MOUT_ADDR;
    uint8_t *app_pay    = (uint8_t *)SRAM_APP_ADDR;

    if (w25q128jw_read_quad(FLASH_APP_OFFSET + 4 + 68 + 2500, (uint32_t*)SRAM_APP_ADDR, app_payload_size) != FLASH_OK) {
        secure_halt();
    }
    memcpy(sm_buf + 2500, app_pay, app_payload_size);
    uint32_t fsbl_spi_end = get_mcycle();

    // 5. Validación de la App PK mediante SHA-256 en Software
    SHA256_CTX sha_ctx;
    uint8_t app_pk_hash[32];
    sha256_init(&sha_ctx);
    sha256_update(&sha_ctx, app_pk_ptr, 68);
    sha256_final(&sha_ctx, app_pk_hash);

    // Hash esperado de app_key.pk
    const uint32_t expected_app_pk_hash[8] = {
        0x9030C723, 0x418B4D68, 0xD1EF98BD, 0xFD5F8152,
        0xFABA1F78, 0xB694865A, 0x8086CA14, 0xC41D7021
    };
    uint8_t expected_app_hash_bytes[32];
    for (int i = 0; i < 8; i++) {
        uint32_t w = expected_app_pk_hash[i];
        expected_app_hash_bytes[i*4 + 0] = (w >> 24) & 0xFF;
        expected_app_hash_bytes[i*4 + 1] = (w >> 16) & 0xFF;
        expected_app_hash_bytes[i*4 + 2] = (w >> 8) & 0xFF;
        expected_app_hash_bytes[i*4 + 3] = w & 0xFF;
    }

    if (memcmp(app_pk_hash, expected_app_hash_bytes, 32) != 0) {
        secure_halt(); // App PK inválida
    }
    uint32_t fsbl_pk_end = get_mcycle();

    // 6. Verificación Criptográfica XMSS de la App en CPU (Zero-Unpack RFC 8391)
    unsigned long long smlen_app = 2500 + app_payload_size;
    unsigned long long mlen_out_app = 0;
    xmss_stage_cycles_t fsbl_stages;

    int status_app = xmss_sign_open_profiled(mout_buf, &mlen_out_app, sm_buf, smlen_app, app_pk_ptr, &fsbl_stages);
    if (status_app != 0 || mlen_out_app != app_payload_size) {
        secure_halt(); // Firma App inválida
    }
    uint32_t fsbl_xmss_end = get_mcycle();

    // 7. Hardening: Scrubbing / Zeroization de SRAM de buffers temporales
    volatile uint32_t *scrub_ptr = (volatile uint32_t *)SRAM_AUTH_META_ADDR;
    uint32_t scrub_words = (68 + 2500 + app_payload_size + 3) / sizeof(uint32_t);
    for (uint32_t i = 0; i < scrub_words; i++) {
        scrub_ptr[i] = 0;
    }
    __asm__ volatile ("fence.i");
    uint32_t fsbl_scrub_end = get_mcycle();
    uint32_t fsbl_end = fsbl_scrub_end;

    // ========================================================================
    // 9. LECTURA DE MÉTRICAS ZSBL Y EMISIÓN DEL INFORME CONSOLIDADO (UART)
    // ========================================================================
    uart_init_for_report();

    volatile uint32_t *zsbl_bench = (volatile uint32_t *)BENCHMARK_MEM_ADDR;
    uint32_t zsbl_start        = zsbl_bench[0];
    uint32_t zsbl_spi_init_end = zsbl_bench[1];
    uint32_t zsbl_spi_hdr_end  = zsbl_bench[2];
    uint32_t zsbl_spi_meta_end = zsbl_bench[3];
    uint32_t zsbl_spi_end      = zsbl_bench[4];
    uint32_t zsbl_rotpk_end    = zsbl_bench[5];
    uint32_t zsbl_xmss_end     = zsbl_bench[6];
    uint32_t zsbl_hw_dma       = zsbl_bench[7];
    uint32_t zsbl_hw_hash      = zsbl_bench[8];
    uint32_t zsbl_hw_wots      = zsbl_bench[9];
    uint32_t zsbl_hw_tree      = zsbl_bench[10];
    uint32_t zsbl_end          = zsbl_bench[11];

    // Diferencias ZSBL
    uint32_t z_spi_init = zsbl_spi_init_end - zsbl_start;
    uint32_t z_spi_hdr  = zsbl_spi_hdr_end  - zsbl_spi_init_end;
    uint32_t z_spi_meta = zsbl_spi_meta_end - zsbl_spi_hdr_end;
    uint32_t z_spi_pay  = zsbl_spi_end      - zsbl_spi_meta_end;
    uint32_t z_spi_tot  = zsbl_spi_end      - zsbl_start;
    uint32_t z_rotpk    = zsbl_rotpk_end    - zsbl_spi_end;
    uint32_t z_xmss     = zsbl_xmss_end     - zsbl_rotpk_end;
    uint32_t z_total    = zsbl_end          - zsbl_start;

    // Inter-stage Handoff
    uint32_t handoff    = fsbl_start - zsbl_end;

    // Diferencias FSBL
    uint32_t f_spi_init = fsbl_spi_init_end - fsbl_start;
    uint32_t f_spi_hdr  = fsbl_spi_hdr_end  - fsbl_spi_init_end;
    uint32_t f_spi_meta = fsbl_spi_meta_end - fsbl_spi_hdr_end;
    uint32_t f_spi_pay  = fsbl_spi_end      - fsbl_spi_meta_end;
    uint32_t f_spi_tot  = fsbl_spi_end      - fsbl_start;
    uint32_t f_pk       = fsbl_pk_end       - fsbl_spi_end;
    uint32_t f_xmss     = fsbl_xmss_end     - fsbl_pk_end;
    uint32_t f_scrub    = fsbl_scrub_end    - fsbl_xmss_end;
    uint32_t f_total    = fsbl_end          - fsbl_start;

    // Total Pipeline
    uint32_t total_pipeline = fsbl_end - zsbl_start;

    print_str("\n\n================================================================================\n");
    print_str("   X-HEEP POST-QUANTUM SECURE BOOT BENCHMARK REPORT (100% SOFTWARE / CPU)\n");
    print_str("================================================================================\n");
    print_str(" Execution Mode     : 2-Stage Pure CPU Verification (ZSBL ROM + FSBL SRAM)\n");
    print_str(" Target Processor   : RISC-V 32-bit (cv32e40p) en Genesys 2 @ 15.0 MHz\n");
    print_str(" Target Frequencies : Sim = 100.0 MHz | FPGA = 15.0 MHz\n");
    print_str("--------------------------------------------------------------------------------\n");
    print_str(" BOOT STAGE / OPERATION           |      CYCLES |  TIME @ 100MHz |  TIME @ 15MHz\n");
    print_str("--------------------------------------------------------------------------------\n");
    print_str(" [STAGE 0: ZSBL - BOOT ROM (SW)]\n");
    print_row("   1. SPI Flash Subsystem (FSBL) ", z_spi_tot);
    print_row("      -> 1.1. QSPI Host Setup    ", z_spi_init);
    print_row("      -> 1.2. Read Header (4 B)  ", z_spi_hdr);
    print_row("      -> 1.3. Read Auth Metadata ", z_spi_meta);
    print_row("      -> 1.4. Read Payload (FSBL)", z_spi_pay);
    print_row("   2. RoTPK SHA-256 SW Check     ", z_rotpk);
    print_row("   3. XMSS FSBL SW Verify        ", z_xmss);
    print_row("      -> Hash Message (Payload)  ", zsbl_hw_hash);
    print_row("      -> WOTS+ Chains            ", zsbl_hw_wots);
    print_row("      -> L-Tree & Root           ", zsbl_hw_tree);
    print_row(" -> Total ZSBL Execution (SW)    ", z_total);
    print_str("--------------------------------------------------------------------------------\n");
    print_row(" [INTER-STAGE HANDOFF]           ", handoff);
    print_str("--------------------------------------------------------------------------------\n");
    print_str(" [STAGE 1: FSBL - SRAM (SW)]\n");
    print_row("   1. SPI Flash Subsystem (App)  ", f_spi_tot);
    print_row("      -> 1.1. QSPI Driver Init   ", f_spi_init);
    print_row("      -> 1.2. Read Header (4 B)  ", f_spi_hdr);
    print_row("      -> 1.3. Read Auth Metadata ", f_spi_meta);
    print_row("      -> 1.4. Read Payload (App) ", f_spi_pay);
    print_row("   2. App PK SHA-256 SW Check    ", f_pk);
    print_row("   3. XMSS App SW Verify         ", f_xmss);
    print_row("      -> Hash Message (Payload)  ", fsbl_stages.hash_cycles);
    print_row("      -> WOTS+ Chains            ", fsbl_stages.wots_cycles);
    print_row("      -> L-Tree & Root           ", fsbl_stages.tree_cycles);
    print_row("   4. Limpieza & Scrubbing SRAM  ", f_scrub);
    print_row(" -> Total FSBL Execution (SW)    ", f_total);
    print_str("--------------------------------------------------------------------------------\n");
    print_row(" TOTAL SECURE BOOT PIPELINE (SW) ", total_pipeline);
    print_str("================================================================================\n\n");

    // 10. Salto a la aplicación de usuario (0x018180)
    ((void (*)(void))(SRAM_APP_ADDR + 0x180))();

    while (1) {
        __asm__ volatile ("wfi");
    }
    return 0;
}
