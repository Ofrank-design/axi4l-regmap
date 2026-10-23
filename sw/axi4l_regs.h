/*
 * Register map for the AXI4-Lite register block (rtl/axi4l_regs_core.sv).
 *
 * Keep this in step with docs/register_map.md and the address decode in the
 * RTL. AXI4_REGS_BASE is a placeholder: set it to wherever your interconnect
 * maps the block.
 */
#ifndef AXI4L_REGS_H
#define AXI4L_REGS_H

#include <stdint.h>

#ifndef AXI4L_REGS_BASE
#define AXI4L_REGS_BASE 0x40000000u
#endif

#define AXI4L_REGS_SIZE 0x10u

#define REG0_CTRL_OFFSET 0x00u
#define REG1_CFG_OFFSET  0x04u
#define REG2_DATA_OFFSET 0x08u
#define REG3_GP_OFFSET   0x0Cu

/* 32-bit register access; the hardware also accepts byte-strobed writes. */
#define AXI4L_REG(off) (*(volatile uint32_t *)(AXI4L_REGS_BASE + (off)))

#define REG0_CTRL AXI4L_REG(REG0_CTRL_OFFSET)
#define REG1_CFG  AXI4L_REG(REG1_CFG_OFFSET)
#define REG2_DATA AXI4L_REG(REG2_DATA_OFFSET)
#define REG3_GP   AXI4L_REG(REG3_GP_OFFSET)

/*
 * Accesses outside the 16-byte window, or not word-aligned, complete with
 * SLVERR (a bus error on most CPUs) and have no effect on the registers.
 */

#endif /* AXI4L_REGS_H */
