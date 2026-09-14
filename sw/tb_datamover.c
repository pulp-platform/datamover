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

#ifndef DATAMOVER_CTRL_TEST
#define DATAMOVER_CTRL_TEST 0
#endif
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
  static uint8_t task##i##_out[TASK##i##_OUT_SIZE] __attribute__((aligned(8), section(".noinit")));
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
    .block_mode      = TASK##i##_BLOCK_MODE,                 \
    .size_c        = TASK##i##_SIZE_C,                   \
    .size_m        = TASK##i##_SIZE_M,                   \
    .size_n        = TASK##i##_SIZE_N,                   \
    .kernel_h      = TASK##i##_KERNEL_SIZE_H,            \
    .kernel_w      = TASK##i##_KERNEL_SIZE_W,            \
    .conv_stride   = TASK##i##_CONV_STRIDE,              \
    .conv_pad      = TASK##i##_CONV_PAD,                 \
    .layout        = TASK##i##_LAYOUT,                   \
    .im2col_in     = TASK##i##_IM2COL_IN,                \
    .im2col_out    = TASK##i##_IM2COL_OUT,               \
  },

static const datamover_task_config_t dm_tasks[NUM_TASKS] = {
  DATAMOVER_TASKS(DM_TASK_INIT)
};
#undef DM_TASK_INIT

/* Per-task verify flag: 1 to check against the golden, 0 for chain intermediates. */
#define DM_TASK_VERIFY(i) TASK##i##_VERIFY,
static const int dm_task_verify[NUM_TASKS] = { DATAMOVER_TASKS(DM_TASK_VERIFY) };
#undef DM_TASK_VERIFY

#if DATAMOVER_CTRL_TEST
/* Exercise the control target before the regular tasks: register read-back, writes to the
 * read-only registers, a byte-wide store, a commit without a trigger, autotrigger, and a soft
 * clear of each kind while a job runs. Task 0 must be a copy; the regular task 0 rewrites its output. */
static int datamover_ctrl_test(void) {
  const datamover_task_config_t *t = &dm_tasks[0];
  volatile datamover_regif_t *regs = DATAMOVER_REGS;
  datamover_cfg_t cfg = {0};
  const uint32_t words = sizeof(datamover_cfg_t) / sizeof(uint32_t);
  const uint32_t clears[3] = {1, 2, 0};
  int errors = 0;

  if (t->mode != DATAMOVER_COPY) {
    tfp_printf("[RISCV] Control test: task 0 is not a copy, skipped\n");
    return 0;
  }
  datamover_build_copy(&cfg, t->in_ptr, t->out_ptr, t->size_c * t->size_m, t->size_n);

  /* Read back the programmed job, then commit without a trigger and trigger alone. */
  datamover_acquire_wait();
  datamover_program(&cfg);
  for (uint32_t w = 0; w < words; w++) {
    if (((volatile uint32_t *)&regs->hwpe_job_dep)[w] != ((const uint32_t *)&cfg)[w]) errors++;
  }
  (void)regs->hwpe_ctrl.soft_clear;
  (void)regs->hwpe_ctrl.running_job;
  regs->hwpe_ctrl.status = 0;
  regs->hwpe_ctrl.running_job = 0;
  regs->hwpe_ctrl.commit_trigger = 1;
  regs->hwpe_ctrl.commit_trigger = 2;
  datamover_wait();

  /* Autotrigger starts a committed job once the previous job is done. */
  regs->hwpe_ctrl.autotrigger = 0;
  datamover_acquire_wait();
  datamover_program(&cfg);
  regs->hwpe_ctrl.commit_trigger = 1;
  for (volatile int k = 0; k < 2000 && datamover_status() != 0; k++);
  if (datamover_status() != 0) regs->hwpe_ctrl.commit_trigger = 2;
  datamover_wait();
  regs->hwpe_ctrl.autotrigger = 1;

  /* A byte-wide store changes one byte of a register. */
  *(volatile uint8_t *)&regs->hwpe_job_dep.tot_len = 0x5a;

  /* A soft clear of the engine state, of the register file, and of both, each while a job runs. */
  for (int c = 0; c < 3; c++) {
    datamover_launch(&cfg);
    for (volatile int k = 0; k < 20; k++);
    regs->hwpe_ctrl.soft_clear = clears[c];
    for (volatile int k = 0; k < 20; k++);
    datamover_soft_clear();
    for (volatile int k = 0; k < 20; k++);
    if (datamover_status() != 0) errors++;
  }
  tfp_printf("[RISCV] Control test: %d errors\n", errors);
  return errors;
}
#endif

int main(void) {
  init_printf(NULL, tb_putc);
  tfp_printf("[RISCV] Datamover HWPE Test (%d task%s)\n",
             NUM_TASKS, NUM_TASKS > 1 ? "s" : "");

  datamover_soft_clear();
  for (volatile int kk = 0; kk < 10; kk++);

#if DATAMOVER_CTRL_TEST
  int ctrl_errors = datamover_ctrl_test();
#else
  int ctrl_errors = 0;
#endif

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

  total_errors += hal_errors + ctrl_errors;

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
