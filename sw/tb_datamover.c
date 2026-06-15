/*
 * Copyright (C) 2025-2026 ETH Zurich and University of Bologna
 * Licensed under the Apache License, Version 2.0, see LICENSE for details.
 * SPDX-License-Identifier: Apache-2.0
 *
 * Authors: Lionnus Kesting <lkesting@iis.ee.ethz.ch>
 *          Cyrill Durrer <cdurrer@iis.ee.ethz.ch>
 *
 * Datamover HWPE standalone test program. Runs on the Ibex core in
 * tb_datamover.sv. The unified workload header (datamover_workload.h) is
 * generated from a JSON test entry and pulls in the per-task golden
 * stimuli/output as static byte arrays placed in TCDM by the linker.
 */

#include <stdint.h>
#include <stddef.h>

#define DATAMOVER_BASE_ADDR 0x10000000  /* HWPE region (addr[31:24]==0x10) in standalone TB */
#include "datamover_hal.h"
#include "tinyprintf.h"
#include "datamover_workload.h"

#ifndef TB_MBOX_ERRORS_ADDR
#define TB_MBOX_ERRORS_ADDR 0x80000000
#endif
#ifndef TB_MBOX_PUTC_ADDR
#define TB_MBOX_PUTC_ADDR 0x80000004
#endif
#ifndef TB_MBOX_CYCLES_ADDR
#define TB_MBOX_CYCLES_ADDR 0x80000008
#endif
#ifndef TB_MBOX_VERIFY_PTR_ADDR
#define TB_MBOX_VERIFY_PTR_ADDR  0x80000010
#endif
#ifndef TB_MBOX_VERIFY_GOLD_ADDR
#define TB_MBOX_VERIFY_GOLD_ADDR 0x80000018
#endif
#ifndef TB_MBOX_VERIFY_SIZE_ADDR
#define TB_MBOX_VERIFY_SIZE_ADDR 0x80000020
#endif

/* Putc stub for tinyprintf. */
static void tb_putc(void *p, char c) {
  (void)p;
  *(volatile uint8_t *)TB_MBOX_PUTC_ADDR = (uint8_t)c;
}

/* Output buffers, sized at compile time per task. Aligned to 8 bytes so the
 * datamover's word-width accesses are aligned. In a chain, task i reads the
 * output buffer of an earlier task (TASK<i>_IN_PTR resolves to it). */
#define DM_TASK_OUT_BUF(i) \
  static uint8_t task##i##_out[TASK##i##_OUT_SIZE] __attribute__((aligned(8)));
DATAMOVER_TASKS(DM_TASK_OUT_BUF)
#undef DM_TASK_OUT_BUF

#define DM_TASK_INIT(i)                                  \
  {                                                      \
    .in_ptr        = TASK##i##_IN_PTR,                   \
    .out_ptr       = task##i##_out,                      \
    .gold_ptr      = TASK##i##_OUT_GOLDEN,               \
    .out_size      = TASK##i##_OUT_SIZE,                 \
    .mode          = TASK##i##_DATAMOVER_MODE,           \
    .transp_mode   = TASK##i##_TRANSP_MODE,              \
    .cim_mode      = TASK##i##_CIM_MODE,                 \
    .row_tile_size = TASK##i##_ROW_TILE_SIZE,            \
    .size_c        = TASK##i##_SIZE_C,                   \
    .size_m        = TASK##i##_SIZE_M,                   \
    .size_n        = TASK##i##_SIZE_N,                   \
    .kernel_size   = TASK##i##_KERNEL_SIZE,              \
    .conv_stride   = TASK##i##_CONV_STRIDE,              \
  },

static const datamover_task_config_t dm_tasks[NUM_TASKS] = {
  DATAMOVER_TASKS(DM_TASK_INIT)
};
#undef DM_TASK_INIT

/* Per-task verify flag: 1 to check against the golden, 0 for chain intermediates. */
#define DM_TASK_VERIFY(i) TASK##i##_VERIFY,
static const int dm_task_verify[NUM_TASKS] = { DATAMOVER_TASKS(DM_TASK_VERIFY) };
#undef DM_TASK_VERIFY

int main(void) {
  init_printf(NULL, tb_putc);
  tfp_printf("[RISCV] Datamover HWPE Test (%d task%s)\n",
             NUM_TASKS, NUM_TASKS > 1 ? "s" : "");

  datamover_soft_clear();
  for (volatile int kk = 0; kk < 10; kk++);

  /* Pre-fill output buffers with a sentinel so unwritten bytes show up in the
   * verify pass instead of accidentally matching golden. */
  for (int i = 0; i < NUM_TASKS; i++) {
    const datamover_task_config_t *t = &dm_tasks[i];
    for (uint32_t b = 0; b < t->out_size; b++) t->out_ptr[b] = 0xA5;
  }

  /* Trigger all jobs back-to-back. The 2-deep job queue lets each be programmed
   * while the previous one runs; acquire spins when the queue is full. */
  int hal_errors = 0;
  for (int i = 0; i < NUM_TASKS; i++) {
    if (datamover_run(&dm_tasks[i]) != DATAMOVER_OK) hal_errors++;
  }

  /* Wait for the datamover to drain, then (idle) read metrics and verify. */
  datamover_wait();

  uint32_t hwpe_cycles = *(volatile uint32_t *)TB_MBOX_CYCLES_ADDR;

  int total_errors = 0;
  for (int i = 0; i < NUM_TASKS; i++) {
    if (!dm_task_verify[i]) continue;
    const datamover_task_config_t *t = &dm_tasks[i];
    *(volatile uint32_t *)TB_MBOX_VERIFY_PTR_ADDR  = (uint32_t)t->out_ptr;
    *(volatile uint32_t *)TB_MBOX_VERIFY_GOLD_ADDR = (uint32_t)t->gold_ptr;
    *(volatile uint32_t *)TB_MBOX_VERIFY_SIZE_ADDR = t->out_size;
    int task_errors = *(volatile int *)TB_MBOX_VERIFY_SIZE_ADDR;

    if (task_errors != 0) {
      tfp_printf("[RISCV] Task %d: FAIL %d/%d errors\n", i, task_errors, (int)t->out_size);
    } else {
      tfp_printf("[RISCV] Task %d: PASS (%d bytes)\n", i, (int)t->out_size);
    }
    total_errors += task_errors;
  }

  total_errors += hal_errors;

  if (total_errors == 0) {
    tfp_printf("[RISCV] PASS: All %d task%s correct\n",
               NUM_TASKS, NUM_TASKS > 1 ? "s" : "");
  } else {
    tfp_printf("[RISCV] FAIL: %d total errors\n", total_errors);
  }

  tfp_printf("[RISCV] hwpe_cycles = %d\n", (int)hwpe_cycles);

  *(volatile int *)TB_MBOX_ERRORS_ADDR = total_errors;
  asm volatile("wfi" ::: "memory");
  return 0;
}
