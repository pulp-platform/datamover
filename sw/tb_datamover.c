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

#include "hal_datamover.h"
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
 * datamover's word-width accesses are aligned. */
#define DM_TASK_OUT_BUF(i) \
  static uint8_t task##i##_out[TASK##i##_OUT_SIZE] __attribute__((aligned(8)));
DATAMOVER_TASKS(DM_TASK_OUT_BUF)
#undef DM_TASK_OUT_BUF

typedef struct {
  uint8_t  *in_ptr;
  uint8_t  *out_ptr;
  uint8_t  *gold_ptr;
  uint32_t  out_size;
  uint32_t  mode;
  uint32_t  transp_mode;
  uint32_t  cim_mode;
  uint32_t  row_tile_size;
  uint32_t  size_c;
  uint32_t  size_m;
  uint32_t  size_n;
} dm_task_t;

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
  },

static const dm_task_t dm_tasks[NUM_TASKS] = {
  DATAMOVER_TASKS(DM_TASK_INIT)
};
#undef DM_TASK_INIT

static datamover_transp_mode_t resolve_transp_mode(uint32_t t) {
  switch (t) {
    case 1: return DATAMOVER_TRANSP_1ELEM;
    case 2: return DATAMOVER_TRANSP_2ELEM;
    case 4: return DATAMOVER_TRANSP_4ELEM;
    default: return DATAMOVER_TRANSP_NONE;
  }
}

static int run_task(const dm_task_t *t, int idx) {
  const uint64_t timeout = 5000000;
  datamover_status_t st = DATAMOVER_OK;
  datamover_transp_mode_t tm = resolve_transp_mode(t->transp_mode);

  /* Pre-fill the output buffer with a sentinel so any unwritten bytes show up
   * in the verify pass instead of accidentally matching golden. */
  for (uint32_t i = 0; i < t->out_size; i++) t->out_ptr[i] = 0xA5;

  switch (t->mode) {
    case 0:
      tfp_printf("[RISCV] Task %d: COPY %ux%u\n", idx, t->size_m, t->size_n);
      st = datamover_copy_blocking(t->in_ptr, t->out_ptr, t->size_m, t->size_n, timeout);
      break;
    case 1:
      tfp_printf("[RISCV] Task %d: TRANSPOSE %ux%u (t=%u)\n", idx, t->size_m, t->size_n, t->transp_mode);
      st = datamover_transpose_blocking(t->in_ptr, t->out_ptr, t->size_m, t->size_n, tm, timeout);
      break;
    case 2:
      if (t->cim_mode == 0) {
        tfp_printf("[RISCV] Task %d: CIM_LAYOUT_FWD %ux%u rt=%u\n", idx, t->size_m, t->size_n, t->row_tile_size);
        st = datamover_cim_layout_blocking(t->in_ptr, t->out_ptr, t->size_m, t->size_n, t->row_tile_size, timeout);
      } else {
        tfp_printf("[RISCV] Task %d: CIM_LAYOUT_REV %ux%u rt=%u\n", idx, t->size_m, t->size_n, t->row_tile_size);
        st = datamover_cim_layout_reverse_blocking(t->in_ptr, t->out_ptr, t->size_m, t->size_n, t->row_tile_size, timeout);
      }
      break;
    case 3:
      tfp_printf("[RISCV] Task %d: CIM_LAYOUT_TRANSPOSE %ux%u rt=%u t=%u\n",
                 idx, t->size_m, t->size_n, t->row_tile_size, t->transp_mode);
      st = datamover_cim_layout_transpose_blocking(t->in_ptr, t->out_ptr, t->size_m, t->size_n,
                                                   t->row_tile_size, tm, timeout);
      break;
    case 4:
      tfp_printf("[RISCV] Task %d: UNFOLD C=%u %ux%u\n", idx, t->size_c, t->size_m, t->size_n);
      st = datamover_unfold_blocking(t->in_ptr, t->out_ptr, t->size_c, t->size_m, t->size_n, timeout);
      break;
    case 5:
      tfp_printf("[RISCV] Task %d: FOLD C=%u %ux%u\n", idx, t->size_c, t->size_m, t->size_n);
      st = datamover_fold_blocking(t->in_ptr, t->out_ptr, t->size_c, t->size_m, t->size_n, timeout);
      break;
    default:
      tfp_printf("[RISCV] Task %d: ERROR unknown mode %u\n", idx, t->mode);
      return 1;
  }

  if (st != DATAMOVER_OK) {
    tfp_printf("[RISCV] Task %d: HAL returned status %d\n", idx, (int)st);
    return 1;
  }
  return 0;
}

int main(void) {
  init_printf(NULL, tb_putc);
  tfp_printf("[RISCV] Datamover HWPE Test (%d task%s)\n",
             NUM_TASKS, NUM_TASKS > 1 ? "s" : "");

  datamover_soft_clear();
  for (volatile int kk = 0; kk < 10; kk++);

  int hal_errors = 0;
  for (int i = 0; i < NUM_TASKS; i++) {
    hal_errors += run_task(&dm_tasks[i], i);
  }

  uint32_t hwpe_cycles = *(volatile uint32_t *)TB_MBOX_CYCLES_ADDR;

  int total_errors = 0;
  for (int i = 0; i < NUM_TASKS; i++) {
    const dm_task_t *t = &dm_tasks[i];
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
