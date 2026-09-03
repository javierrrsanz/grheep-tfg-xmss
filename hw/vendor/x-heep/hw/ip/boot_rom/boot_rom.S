// See LICENSE.SiFive for license details.

#include "core_v_mini_mcu.h"
#include "soc_ctrl_regs.h"
#include "spi_memio_regs.h"
#include "power_manager_regs.h"
#include "spi_host_regs.h"

#define SOC_CTRL_START_ADDRESS_20bit       (SOC_CTRL_START_ADDRESS >> 12)
#define FLASH_MEM_START_ADDRESS_20bit      (FLASH_MEM_START_ADDRESS >> 12)
#define SPI_MEMIO_START_ADDRESS_20bit      (SPI_MEMIO_START_ADDRESS >> 12)
#define POWER_MANAGER_START_ADDRESS_20bit  (POWER_MANAGER_START_ADDRESS >> 12)
#define SPI_FLASH_START_ADDRESS_20bit      (SPI_FLASH_START_ADDRESS >> 12)
#define XMSS_PERIPH_START_ADDRESS_20bit    (0x20070000 >> 12)

#define SRAM_FSBL_ADDR                     0x00000000
#define SRAM_AUTH_META_ADDR                0x00008000
#define SRAM_PK_ADDR                       (SRAM_AUTH_META_ADDR)        /* 0x00008000, 68B */
#define SRAM_SIG_ADDR                      (SRAM_AUTH_META_ADDR + 68)   /* 0x00008044, 4768B */

#define XMSS_CTRL_OFFSET                   0x00
#define XMSS_STATUS_OFFSET                 0x04
#define XMSS_SIG_ADDR_OFFSET               0x08
#define XMSS_MSG_ADDR_OFFSET               0x10
#define XMSS_MLEN_OFFSET                   0x14
#define XMSS_PK_ADDR_OFFSET                0x18
#define XMSS_HASH_RES_OFFSET               0x20

#define SECURE_VALID_CODE                  0x3C5A

#define SEXT_IMM(x) ((x) | (-(((x) >> 11) & 1) << 11))

       .global entry

entry:
       // Check if recovering from sleep state
       lui     a1, POWER_MANAGER_START_ADDRESS_20bit
       lbu     a0, POWER_MANAGER_WAKEUP_STATE_REG_OFFSET(a1)
       beqz    a0, boot
       // Restoring
       lw      a0, POWER_MANAGER_RESTORE_ADDRESS_REG_OFFSET(a1)
       jalr    a0

boot:
       // Read boot sel register
       lui     a1, SOC_CTRL_START_ADDRESS_20bit
       lbu     a0, SOC_CTRL_BOOT_SELECT_REG_OFFSET(a1)
       bnez    a0, _jump_to_flash

_jump_to_debug_rom:
       lbu     a0, SOC_CTRL_BOOT_EXIT_LOOP_REG_OFFSET(a1)
       // Check whether exit_loop flag is 1, otherwise jump back to entry
       beqz    a0, entry
       lw      a1, SOC_CTRL_BOOT_ADDRESS_REG_OFFSET(a1)
       jalr    a1

_jump_to_flash:
       lbu     a0, SOC_CTRL_USE_SPIMEMIO_REG_OFFSET(a1)
       beqz    a0, _copy_from_flash

_execute_from_flash:
       lui     a1, SPI_MEMIO_START_ADDRESS_20bit
       addi    a0, zero, 1
       sw      a0, OBI_SPIMEMIO_START_SPIMEM_REG_OFFSET(a1)
       lui     a1, FLASH_MEM_START_ADDRESS_20bit
       addi    a1, a1, SEXT_IMM(0x180)
       jalr    a1

_copy_from_flash:
       lui     a1, SPI_FLASH_START_ADDRESS_20bit
       // Enable spi
       lui     a0, 0xa0000
       lw      a4, SPI_HOST_CONTROL_REG_OFFSET(a1)
       or      a4, a4, a0
       sw      a4, SPI_HOST_CONTROL_REG_OFFSET(a1)
       // Create config_opt: 0x0FFF0001
       lui     a4, 0xfff0
       addi    a4, a4, 1
       sw      a4, SPI_HOST_CONFIGOPTS_0_REG_OFFSET(a1)
       // Set spi csid
       li      a0, 0
       sw      a0, SPI_HOST_CSID_REG_OFFSET(a1)
       // Set spi receiver watermark to 8
       lw      a4, SPI_HOST_CONTROL_REG_OFFSET(a1)
       andi    a4, a4, -256 # ~SPI_HOST_CONTROL_RX_WATERMARK_MASK
       ori     a4, a4, 8
       sw      a4, SPI_HOST_CONTROL_REG_OFFSET(a1)

       // Power up flash (0xab flash command)
       li      a4, 0xab
       sw      a4, SPI_HOST_TXDATA_REG_OFFSET(a1)
       // Power up command: 0x10000003 (transmit 4 words)
       lui     a4, 0x10000
       addi    a4, a4, 3
       sw      a4, SPI_HOST_COMMAND_REG_OFFSET(a1)

_wait_spi_ready_cmd_pwr:
       // Wait spi is ready for next command
       lw      a4, SPI_HOST_STATUS_REG_OFFSET(a1)
       bgez    a4, _wait_spi_ready_cmd_pwr

       // Fill TX FIFO with TX data (read command 0x03 + 3B address 0x000)
       li      a4, 0x03
       sw      a4, SPI_HOST_TXDATA_REG_OFFSET(a1)
       nop    # otherwise ready bit check is too fast

_wait_spi_ready_tx_init:
       lw      a4, SPI_HOST_STATUS_REG_OFFSET(a1)
       bgez    a4, _wait_spi_ready_tx_init
       // Read command: 0x11000003 (txonly + stdspeed + csaat + 4B)
       lui     a4, 0x11000
       addi    a4, a4, 3
       sw      a4, SPI_HOST_COMMAND_REG_OFFSET(a1)
       nop    # otherwise ready bit check is too fast

_wait_spi_ready_read_prog:
       lw      a5, SPI_HOST_STATUS_REG_OFFSET(a1)
       bgez    a5, _wait_spi_ready_read_prog

       // -------------------------------------------------------------
       // 1. LEER CABECERA (4 bytes = Longitud Total del FSBL)
       // -------------------------------------------------------------
       // Comando RX de 4 bytes con csaat=1: 0x09000003
       lui     s0, 0x9000
       addi    tp, s0, 3
       sw      tp, SPI_HOST_COMMAND_REG_OFFSET(a1)
       nop

_wait_spi_hdr:
       lw      a5, SPI_HOST_STATUS_REG_OFFSET(a1)
       bgez    a5, _wait_spi_hdr

_wait_spi_hdr_data:
       lw      a5, SPI_HOST_STATUS_REG_OFFSET(a1)
       srli    a5, a5, 8
       andi    a5, a5, 0xff
       beqz    a5, _wait_spi_hdr_data

       // Leemos la palabra de cabecera: s2 = firmware_total_size
       lw      s2, SPI_HOST_RXDATA_REG_OFFSET(a1)

       // Calculamos tamaño del payload: s3 = s2 - 68 (PK) - 4768 (SIG) = s2 - 4836
       li      t0, 4836
       sub     s3, s2, t0

       // -------------------------------------------------------------
       // 2. LEER METADATOS (PK 68B + SIG 4768B = 4836 bytes) -> RAM 0x00008000
       // -------------------------------------------------------------
       li      s1, SRAM_AUTH_META_ADDR
       li      a3, 4836
       li      s4, 1                   // Mantener CS activo (csaat=1)
       jal     ra, _read_bytes_block

       // -------------------------------------------------------------
       // 3. LEER PAYLOAD FSBL -> RAM 0x00000000
       // -------------------------------------------------------------
       li      s1, SRAM_FSBL_ADDR
       mv      a3, s3                  // payload_size
       li      s4, 0                   // Fin de transacción SPI (csaat=0 en último chunk)
       jal     ra, _read_bytes_block

       // -------------------------------------------------------------
       // 4. AUTENTICACIÓN DE LA CLAVE PÚBLICA (RoTPK) EN HARDWARE
       // -------------------------------------------------------------
       lui     a2, XMSS_PERIPH_START_ADDRESS_20bit

       // Configurar dirección de la PK (SRAM_PK_ADDR = 0x00008000)
       li      t0, SRAM_PK_ADDR
       sw      t0, XMSS_PK_ADDR_OFFSET(a2)

       // Configurar longitud en bits (68 bytes * 8 = 544 bits)
       li      t0, 544
       sw      t0, XMSS_MLEN_OFFSET(a2)

       // Iniciar modo HASH_ONLY: CTRL = 0x04
       li      t0, 0x04
       sw      t0, XMSS_CTRL_OFFSET(a2)

_wait_hash_done:
       lw      t0, XMSS_STATUS_OFFSET(a2)
       srli    t0, t0, 16
       andi    t0, t0, 1
       beqz    t0, _wait_hash_done

       // Limpiar flag con ACK: CTRL = 0x02
       li      t0, 0x02
       sw      t0, XMSS_CTRL_OFFSET(a2)

       // Comparar los 8 registros de 32 bits contra expected_rotpk_hash
       la      t1, expected_rotpk_hash
       li      t2, 8
       addi    t3, a2, XMSS_HASH_RES_OFFSET

_check_hash_word:
       lw      t4, 0(t3)
       lw      t5, 0(t1)
       bne     t4, t5, _secure_halt
       addi    t3, t3, 4
       addi    t1, t1, 4
       addi    t2, t2, -1
       bnez    t2, _check_hash_word

       // -------------------------------------------------------------
       // 5. VERIFICACIÓN COMPLETA DE FIRMA XMSS DEL FSBL
       // -------------------------------------------------------------
       // Dirección de la firma (SRAM_SIG_ADDR = 0x00008044)
       li      t0, SRAM_SIG_ADDR
       sw      t0, XMSS_SIG_ADDR_OFFSET(a2)

       // Dirección del mensaje/payload (SRAM_FSBL_ADDR = 0x00000000)
       li      t0, SRAM_FSBL_ADDR
       sw      t0, XMSS_MSG_ADDR_OFFSET(a2)

       // Longitud del mensaje en bits (payload_size * 8)
       slli    t0, s3, 3
       sw      t0, XMSS_MLEN_OFFSET(a2)

       // Dirección de la clave pública (SRAM_PK_ADDR = 0x00008000)
       li      t0, SRAM_PK_ADDR
       sw      t0, XMSS_PK_ADDR_OFFSET(a2)

       // Iniciar verificación XMSS completa: CTRL = 0x01
       li      t0, 0x01
       sw      t0, XMSS_CTRL_OFFSET(a2)

_wait_xmss_done:
       lw      t0, XMSS_STATUS_OFFSET(a2)
       srli    t1, t0, 16
       andi    t1, t1, 1
       beqz    t1, _wait_xmss_done

       // Verificar código de validez (bits 15:0 == 0x3C5A)
       li      t2, SECURE_VALID_CODE
       slli    t3, t0, 16
       srli    t3, t3, 16
       bne     t3, t2, _secure_halt

       // Limpiar flag con ACK: CTRL = 0x02
       li      t0, 0x02
       sw      t0, XMSS_CTRL_OFFSET(a2)

       // -------------------------------------------------------------
       // 6. SALTO A LA ETAPA 1 (FSBL @ 0x00000180)
       // -------------------------------------------------------------
       fence.i
       lui     a0, 0
       addi    a0, a0, 0x180
       jalr    a0

_secure_halt:
       wfi
       j       _secure_halt

// --------------------------------------------------------------------
// Subrutina: Leer a3 bytes de SPI Flash hacia s1 (RAM)
// s1: Puntero RAM destino
// a3: Cantidad de bytes a leer
// s4: 1 = mantener csaat=1 en todo momento, 0 = deassert csaat en último chunk
// --------------------------------------------------------------------
_read_bytes_block:
       beqz    a3, _read_block_ret
       li      t3, 256
       bge     a3, t3, _chunk_size_256
       mv      t3, a3

_chunk_size_256:
       sub     a3, a3, t3

       addi    t4, t3, -1              // len - 1
       bnez    a3, _set_csaat_1
       beqz    s4, _set_csaat_0

_set_csaat_1:
       lui     s0, 0x9000
       or      tp, s0, t4
       j       _exec_spi_cmd

_set_csaat_0:
       lui     s0, 0x8000
       or      tp, s0, t4

_exec_spi_cmd:
       sw      tp, SPI_HOST_COMMAND_REG_OFFSET(a1)
       nop

_wait_spi_chunk_ready:
       lw      a5, SPI_HOST_STATUS_REG_OFFSET(a1)
       bgez    a5, _wait_spi_chunk_ready

       // Cantidad de palabras de 32 bits a extraer: (t3 + 3) / 4
       addi    t5, t3, 3
       srli    t5, t5, 2

_drain_rx_word:
       // Esperar a que haya datos en la FIFO RX (RXQD > 0)
       lw      a5, SPI_HOST_STATUS_REG_OFFSET(a1)
       srli    a5, a5, 8
       andi    a5, a5, 0xff
       beqz    a5, _drain_rx_word

       lw      t0, SPI_HOST_RXDATA_REG_OFFSET(a1)
       sw      t0, 0(s1)
       addi    s1, s1, 4
       addi    t5, t5, -1
       bnez    t5, _drain_rx_word

       j       _read_bytes_block

_read_block_ret:
       ret

// --------------------------------------------------------------------
// Clave Pública Root of Trust esperada (Hash SHA-256 de rot_key.pk)
// --------------------------------------------------------------------
       .align 4
       .global expected_rotpk_hash
expected_rotpk_hash:
       .word 0x46AA3916
       .word 0x8FF90E7D
       .word 0x27A38210
       .word 0x881991E3
       .word 0x7F641135
       .word 0xDBA9D5B7
       .word 0x91E6581A
       .word 0x95C1DDDA
