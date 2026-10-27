/*
 * Compile-time check that the C header matches the documented register map
 * (docs/register_map.md) and the RTL decode: four word registers, 16 bytes.
 * Run with `make check-sw`. Nothing here touches hardware.
 */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>

#define AXI4L_REGS_BASE 0x1000u
#include "axi4l_regs.h"

_Static_assert(REG0_CTRL_OFFSET == 0x00u, "CTRL offset");
_Static_assert(REG1_CFG_OFFSET  == 0x04u, "CFG offset");
_Static_assert(REG2_DATA_OFFSET == 0x08u, "DATA offset");
_Static_assert(REG3_GP_OFFSET   == 0x0Cu, "GP offset");
_Static_assert(AXI4L_REGS_SIZE  == 0x10u, "block size");

int main(void)
{
    /* Only addresses are taken; no register is dereferenced. */
    int ok = ((uintptr_t)&REG0_CTRL == 0x1000u) && ((uintptr_t)&REG1_CFG == 0x1004u) &&
             ((uintptr_t)&REG2_DATA == 0x1008u) && ((uintptr_t)&REG3_GP  == 0x100Cu);
    puts(ok ? "PASS: header offsets" : "FAIL: header offsets");
    return ok ? 0 : 1;
}
