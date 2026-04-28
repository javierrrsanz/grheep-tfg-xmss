#include <stdint.h>
#include <stdio.h>

#include "gr_heep.h"

#define XMSS_CTRL_OFFSET   0x0000u
#define XMSS_STATUS_OFFSET 0x0004u
#define XMSS_MLEN_OFFSET   0x0008u
#define XMSS_BRAM_OFFSET   0x2000u

static inline void xmss_write32(uint32_t offset, uint32_t value)
{
  volatile uint32_t *ptr = (volatile uint32_t *)(XMSS_PERIPH_START_ADDRESS + offset);
  *ptr = value;
}

static inline uint32_t xmss_read32(uint32_t offset)
{
  volatile uint32_t *ptr = (volatile uint32_t *)(XMSS_PERIPH_START_ADDRESS + offset);
  return *ptr;
}

static inline void xmss_write8(uint32_t offset, uint8_t value)
{
  volatile uint8_t *ptr = (volatile uint8_t *)(XMSS_PERIPH_START_ADDRESS + offset);
  *ptr = value;
}

static void print_check(const char *name, uint32_t got, uint32_t expected, uint32_t *fails)
{
  if (got == expected) {
    //printf("[OK]   %s got=0x%08lx\n", name, (unsigned long)got);
  } else {
    //printf("[FAIL] %s got=0x%08lx exp=0x%08lx\n", name, (unsigned long)got, (unsigned long)expected);
    *fails = *fails + 1;
  }
}

int main(void)
{
  uint32_t fails = 0;
  uint32_t ctrl;
  uint32_t status;
  uint32_t mlen;
  uint32_t i;

  const uint32_t line_words[8] = {
    0x11223344u, 0x55667788u, 0x99AABBCCu, 0xDDEEFF00u,
    0x0BADF00Du, 0xCAFEBABEu, 0xDEADBEEFu, 0x12345678u
  };

  //printf("\n[XMSS_TEST] MMIO smoke start\n");
  //printf("[XMSS_TEST] BASE=0x%08lx\n", (unsigned long)XMSS_PERIPH_START_ADDRESS);

  status = xmss_read32(XMSS_STATUS_OFFSET);
  //printf("[XMSS_TEST] STATUS init = 0x%08lx (done=%lu valid=0x%04lx)\n",
  //     (unsigned long)status,
  //     (unsigned long)((status >> 16) & 0x1u),
  //     (unsigned long)(status & 0xFFFFu));

  xmss_write32(XMSS_MLEN_OFFSET, 1234u);
  mlen = xmss_read32(XMSS_MLEN_OFFSET);
  print_check("MLEN write/read", mlen, 1234u, &fails);

  xmss_write32(XMSS_MLEN_OFFSET, 5000u);
  mlen = xmss_read32(XMSS_MLEN_OFFSET);
  print_check("MLEN saturation", mlen, 2048u, &fails);

  xmss_write32(XMSS_CTRL_OFFSET, 1u);
  ctrl = xmss_read32(XMSS_CTRL_OFFSET) & 0x1u;
  print_check("CTRL full-word set", ctrl, 1u, &fails);

  xmss_write8(XMSS_CTRL_OFFSET, 0u);
  ctrl = xmss_read32(XMSS_CTRL_OFFSET) & 0x1u;
  print_check("CTRL byte-write ignored", ctrl, 1u, &fails);

  xmss_write32(XMSS_CTRL_OFFSET, 0u);
  ctrl = xmss_read32(XMSS_CTRL_OFFSET) & 0x1u;
  print_check("CTRL full-word clear", ctrl, 0u, &fails);

  for (i = 0; i < 8; ++i) {
    xmss_write32(XMSS_BRAM_OFFSET + (i * 4u), line_words[i]);
  }
  //printf("[OK]   BRAM line 0 write sequence issued\n");

  status = xmss_read32(XMSS_STATUS_OFFSET);
  //printf("[XMSS_TEST] STATUS end  = 0x%08lx (done=%lu valid=0x%04lx)\n",
  //     (unsigned long)status,
  //     (unsigned long)((status >> 16) & 0x1u),
  //     (unsigned long)(status & 0xFFFFu));

  if (fails == 0u) {
    //printf("[XMSS_TEST] RESULT: PASS\n");
  } else {
    //printf("[XMSS_TEST] RESULT: FAIL (%lu checks)\n", (unsigned long)fails);
  }

  return 0;
}