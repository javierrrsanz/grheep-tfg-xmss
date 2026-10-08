#include <stdint.h>
#include <stdbool.h>

#include "gr_heep.h"
#include "x-heep.h"
#include "hart.h"
#include "csr.h"
#include "fast_intr_ctrl.h"
#include "w25q128jw.h"
#include "uart.h"

#define PRINTF_IN_FPGA  0
#define PRINTF_IN_SIM   0

#if (TARGET_SIM && PRINTF_IN_SIM) || (PRINTF_IN_FPGA && !TARGET_SIM)
    #include <stdio.h>
    #define PRINTF(fmt, ...)    printf(fmt, ## __VA_ARGS__)
#else
    #define PRINTF(...)
#endif

// ============================================================================
// DEFINICIONES DE SEGURIDAD, REGISTROS Y MAPA DE MEMORIA
// ============================================================================
#define SECURE_VALID_CODE    0x3C5A       /* Código multibit seguro para firma válida */
#define XMSS_CTRL_OFFSET     0x0000u      /* Control: bit 0=Start, 1=Ack, 2=Hash, 3=Reset, 31=Lock */
#define XMSS_STATUS_OFFSET   0x0004u      /* Estado: bits [15:0]=código validación, bit 16=done */
#define XMSS_SIG_ADDR_OFFSET 0x0008u      /* Puntero DMA a la firma XMSS en SRAM */
#define XMSS_MSG_ADDR_OFFSET 0x0010u      /* Puntero DMA al mensaje/payload en SRAM */
#define XMSS_MLEN_OFFSET     0x0014u      /* Longitud del mensaje en bits */
#define XMSS_PK_ADDR_OFFSET  0x0018u      /* Puntero DMA a la clave pública (68 bytes) */

#define SRAM_APP_ADDR        0x018000     /* Destino de ejecución del firmware de usuario */
#define SRAM_AUTH_META_ADDR  0x010000     /* Búfer temporal de autenticación (PK + Firma) */

#define FLASH_APP_OFFSET     0x010000     /* Offset de la aplicación en la memoria SPI Flash */

#define BENCHMARK_MEM_ADDR   0x00024000   /* Banco 4 de SRAM: métricas compartidas con ZSBL */

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

void secure_halt(void) {
    while (1) {
        __asm__ volatile ("wfi");
    }
}

static inline uint32_t get_mcycle(void) {
    uint32_t cycles;
    __asm__ volatile ("csrr %0, mcycle" : "=r" (cycles));
    return cycles;
}

// ============================================================================
// SALIDA UART "LOW-COST" BARE-METAL PARA INFORME CONSOLIDADO (SIN LIBC/STDIO)
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
// FIRST-STAGE BOOTLOADER (FSBL - ETAPA 1)
// ============================================================================
int main(void) {
    // 0. MARCA INICIAL FSBL
    uint32_t fsbl_start = get_mcycle();

    PRINTF("\n==============================================\n");
    PRINTF("---    X-HEEP FSBL (ETAPA 1 - SRAM)        ---\n");
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
    PRINTF("[FSBL] Inicializando bus quad SPI Flash...\n");
    
    if (w25q128jw_init(spi_flash) != FLASH_OK) {
        secure_halt();
    }
    uint32_t fsbl_spi_init_end = get_mcycle();

    uint32_t firmware_total_size = 0;
    
    // Leemos los primeros 4 bytes de la cabecera (offset 0x010000)
    if (w25q128jw_read_quad(FLASH_APP_OFFSET, &firmware_total_size, 4) != FLASH_OK) {
        secure_halt();
    }
    uint32_t fsbl_spi_hdr_end = get_mcycle();

    PRINTF("[FSBL] Cabecera leida. Tamaño total App: %d bytes.\n", firmware_total_size);
    
    uint32_t payload_size = firmware_total_size - 68 - 4768;
    
    uint32_t pk_ptr  = SRAM_AUTH_META_ADDR;              // 68 bytes
    uint32_t sig_ptr = SRAM_AUTH_META_ADDR + 68;         // 4768 bytes
    uint32_t app_ptr = SRAM_APP_ADDR;                    // payload_size bytes (destino final directo en 0x018000)

    PRINTF("[FSBL] Leyendo metadatos de autenticacion (PK + Firma, 4836 bytes)...\n");
    if (w25q128jw_read_quad(FLASH_APP_OFFSET + 4, (uint32_t*)SRAM_AUTH_META_ADDR, 68 + 4768) != FLASH_OK) {
        secure_halt();
    }
    uint32_t fsbl_spi_meta_end = get_mcycle();

    PRINTF("[FSBL] Leyendo Payload directamente a 0x%08X (%d bytes)...\n", SRAM_APP_ADDR, payload_size);
    if (w25q128jw_read_quad(FLASH_APP_OFFSET + 4 + 68 + 4768, (uint32_t*)SRAM_APP_ADDR, payload_size) != FLASH_OK) {
        secure_halt();
    }
    uint32_t fsbl_spi_end = get_mcycle();
    
    PRINTF("[FSBL] Descarga completada.\n");

    // ========================================================================
    // 3. VALIDACIÓN DE LA CLAVE PÚBLICA DE LA APP POR HARDWARE (HASH_ONLY)
    // ========================================================================
    PRINTF("[FSBL] Validando Clave Publica de la App contra Hash esperado en FSBL...\n");
    
    // Reset del acelerador por software
    xmss_write32(XMSS_CTRL_OFFSET, 0x08);

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
    
    // Hash SHA-256 matemático real de la Clave Publica de la App (app_key.pk en Flash)
    const uint32_t expected_app_pk_hash[8] = {
        0x9030C723, 0x418B4D68, 0xD1EF98BD, 0xFD5F8152,
        0xFABA1F78, 0xB694865A, 0x8086CA14, 0xC41D7021
    };

    for (int i = 0; i < 8; i++) {
        if (xmss_read32(0x20 + (i * 4)) != expected_app_pk_hash[i]) {
            secure_halt();
        }
    }
    
    uint32_t fsbl_pk_end = get_mcycle();
    PRINTF("[FSBL] Clave Publica de la App AUTENTICADA con exito.\n");

    // Resetear acelerador tras HASH_ONLY para dejar DMA y FSMs en estado limpio
    xmss_write32(XMSS_CTRL_OFFSET, 0x08);

    // ========================================================================
    // 4. PARSEO Y CONFIGURACIÓN DEL ACELERADOR XMSS PARA VERIFICACIÓN DE LA APP
    // ========================================================================
    PRINTF("[FSBL] Configurando Acelerador Hardware para verificacion de firma...\n");
    xmss_write32(XMSS_SIG_ADDR_OFFSET, sig_ptr);
    xmss_write32(XMSS_MSG_ADDR_OFFSET, app_ptr);
    xmss_write32(XMSS_MLEN_OFFSET,     payload_size * 8);
    xmss_write32(XMSS_PK_ADDR_OFFSET, pk_ptr);

    uint32_t fsbl_xmss_setup_end = get_mcycle();

    // 5. LANZAR VERIFICACIÓN
    PRINTF("[FSBL] Ejecutando verificacion criptografica XMSS de la App por Hardware...\n");
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
    PRINTF("[FSBL] Resultado Verificacion HW: Status = 0x%08X (Codigo: 0x%04X)\n", status, (uint16_t)(status & 0xFFFFu));

    if ((status & 0xFFFFu) != SECURE_VALID_CODE) {
        secure_halt();
    }

    uint32_t fsbl_xmss_end = get_mcycle();
    uint32_t fsbl_hw_dma  = xmss_read32(0x40);
    uint32_t fsbl_hw_hash = xmss_read32(0x44);
    uint32_t fsbl_hw_wots = xmss_read32(0x48);
    uint32_t fsbl_hw_tree = xmss_read32(0x4C);

    PRINTF("[FSBL] Exito: Firma de la App validada correctamente por HW.\n");

    // Limpieza de interrupciones de forma inmediata
    CSR_CLEAR_BITS(CSR_REG_MSTATUS, 0x8);
    CSR_CLEAR_BITS(CSR_REG_MIE, intr_mask);
    enable_fast_interrupt(kExt_peri_fic_e, false);

    PRINTF("[FSBL] Preparando salto a Aplicacion de Usuario...\n");
    
    // Hardening: Limpieza de SRAM (Buffer Scrubbing seguro a 32 bits, anti dead-store elimination)
    volatile uint32_t *scrub_ptr = (volatile uint32_t *)SRAM_AUTH_META_ADDR;
    uint32_t scrub_words = (68 + 4768) / sizeof(uint32_t); // 1209 palabras
    uint32_t i = 0;
    for (; i + 3 < scrub_words; i += 4) {
        scrub_ptr[i]     = 0;
        scrub_ptr[i + 1] = 0;
        scrub_ptr[i + 2] = 0;
        scrub_ptr[i + 3] = 0;
    }
    for (; i < scrub_words; i++) {
        scrub_ptr[i] = 0;
    }

    // Hardening: Zeroization de registros MMIO del acelerador XMSS
    xmss_write32(XMSS_SIG_ADDR_OFFSET, 0u);
    xmss_write32(XMSS_MSG_ADDR_OFFSET, 0u);
    xmss_write32(XMSS_MLEN_OFFSET,     0u);
    xmss_write32(XMSS_PK_ADDR_OFFSET,  0u);

    // Hardening: Hardware Lockdown definitivo (Sticky Lock Bit 31 + Reset Bit 3)
    // El acelerador queda en reset continuo y el DMA queda físicamente aislado del bus.
    xmss_write32(XMSS_CTRL_OFFSET, 0x80000008u);

    // Sincronizar memoria de instrucciones y pipeline
    __asm__ volatile ("fence.i");

    uint32_t fsbl_scrub_end = get_mcycle();
    uint32_t fsbl_end = get_mcycle();

    // ========================================================================
    // 7. EMISIÓN DEL INFORME CONSOLIDADO (UART LOW-COST)
    // ========================================================================
    // Inicialización del hardware UART solo ahora, tras finalizar todas las mediciones
    uart_init_for_report();

    // Lectura de los contadores guardados por ZSBL en Banco 4 (0x00024000)
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

    // Cálculo de diferencias de ciclos: ZSBL
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

    // Cálculo de diferencias de ciclos: FSBL
    uint32_t f_spi_init = fsbl_spi_init_end - fsbl_start;
    uint32_t f_spi_hdr  = fsbl_spi_hdr_end  - fsbl_spi_init_end;
    uint32_t f_spi_meta = fsbl_spi_meta_end - fsbl_spi_hdr_end;
    uint32_t f_spi_pay  = fsbl_spi_end      - fsbl_spi_meta_end;
    uint32_t f_spi_tot  = fsbl_spi_end      - fsbl_start;
    uint32_t f_pk       = fsbl_pk_end       - fsbl_spi_end;
    uint32_t f_setup    = fsbl_xmss_setup_end - fsbl_pk_end;
    uint32_t f_xmss     = fsbl_xmss_end     - fsbl_xmss_setup_end;
    uint32_t f_scrub    = fsbl_scrub_end    - fsbl_xmss_end;
    uint32_t f_total    = fsbl_end          - fsbl_start;
    
    // Total Pipeline
    uint32_t total_pipeline = fsbl_end - zsbl_start;

    print_str("\n\n================================================================================\n");
    print_str("   X-HEEP POST-QUANTUM SECURE BOOT BENCHMARK REPORT (XMSS-SHA2_10_256)\n");
    print_str("================================================================================\n");
    print_str(" Accelerator Config : HASH_CORES = 4 | HASH_CHAINS = 4\n");
    print_str(" Target Frequencies : Sim = 100.0 MHz | FPGA = 15.0 MHz\n");
    print_str("--------------------------------------------------------------------------------\n");
    print_str(" BOOT STAGE / OPERATION           |      CYCLES |  TIME @ 100MHz |  TIME @ 15MHz\n");
    print_str("--------------------------------------------------------------------------------\n");
    print_str(" [STAGE 0: ZSBL - BOOT ROM]\n");
    print_row("   1. SPI Flash Subsystem (FSBL) ", z_spi_tot);
    print_row("      -> 1.1. QSPI Host Setup    ", z_spi_init);
    print_row("      -> 1.2. Read Header (4 B)  ", z_spi_hdr);
    print_row("      -> 1.3. Read Auth Metadata ", z_spi_meta);
    print_row("      -> 1.4. Read Payload (FSBL)", z_spi_pay);
    print_row("   2. RoTPK SHA-256 HW Check     ", z_rotpk);
    print_row("   3. XMSS FSBL HW Verify        ", z_xmss);
    print_row("      -> DMA Wait Overhead       ", zsbl_hw_dma);
    print_row("      -> Hash Message (Payload)  ", zsbl_hw_hash);
    print_row("      -> WOTS+ Chains            ", zsbl_hw_wots);
    print_row("      -> L-Tree & Root           ", zsbl_hw_tree);
    print_row(" -> Total ZSBL Execution         ", z_total);
    print_str("--------------------------------------------------------------------------------\n");
    print_row(" [INTER-STAGE HANDOFF]           ", handoff);
    print_str("--------------------------------------------------------------------------------\n");
    print_str(" [STAGE 1: FSBL - SRAM]\n");
    print_row("   1. SPI Flash Subsystem (App)  ", f_spi_tot);
    print_row("      -> 1.1. QSPI Driver Init   ", f_spi_init);
    print_row("      -> 1.2. Read Header (4 B)  ", f_spi_hdr);
    print_row("      -> 1.3. Read Auth Metadata ", f_spi_meta);
    print_row("      -> 1.4. Read Payload (App) ", f_spi_pay);
    print_row("   2. App PK SHA-256 HW Check    ", f_pk);
    print_row("   3. XMSS Accelerator Setup     ", f_setup);
    print_row("   4. XMSS App HW Verify         ", f_xmss);
    print_row("      -> DMA Wait Overhead       ", fsbl_hw_dma);
    print_row("      -> Hash Message (Payload)  ", fsbl_hw_hash);
    print_row("      -> WOTS+ Chains            ", fsbl_hw_wots);
    print_row("      -> L-Tree & Root           ", fsbl_hw_tree);
    print_row("   5. Limpieza & HW Lockdown     ", f_scrub);
    print_row(" -> Total FSBL Execution         ", f_total);
    print_str("--------------------------------------------------------------------------------\n");
    print_row(" TOTAL SECURE BOOT PIPELINE      ", total_pipeline);
    print_str("================================================================================\n\n");

    PRINTF("[FSBL] === INICIANDO APLICACION DE USUARIO (0x00018180) ===\n\n");
    
    // Salto a la aplicación de usuario (0x018180)
    ((void (*)(void))(SRAM_APP_ADDR + 0x180))();

    while(1) { __asm__ volatile("wfi"); }
    return 0;
}
