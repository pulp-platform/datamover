// Copyright 2025 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Authors: Daniel Keller <dankeller@iis.ee.ethz.ch>
//          Cyrill Durrer <cdurrer@iis.ee.ethz.ch>
//          Sergio Mazzola <smazzola@iis.ee.ethz.ch>
//          Lionnus Kesting <lkesting@iis.ee.ethz.ch>
//

#ifndef __HAL_HWPE_H__
#define __HAL_HWPE_H__

#include <stdint.h>

// Register offsets of HWPE Ctrl (32-bit registers)
#define HWPE_TRIGGER_OFFSET     (0*4)
#define HWPE_ACQUIRE_OFFSET     (1*4)
#define HWPE_FINISHED_OFFSET    (2*4)
#define HWPE_STATUS_OFFSET      (3*4)
#define HWPE_RUNNING_JOB_OFFSET (4*4)
#define HWPE_SOFT_CLEAR_OFFSET  (5*4)

#define __HAL_HWPE_REG_WRITE(base, offset, value) \
    (*(volatile uint32_t *)((base) + (offset)) = (value))
#define __HAL_HWPE_REG_READ(base, offset) \
    (*(volatile uint32_t *)((base) + (offset)))

static inline void hwpe_task_queue_release_and_run(uint32_t hwpe_base_addr) {
  __HAL_HWPE_REG_WRITE(hwpe_base_addr, HWPE_TRIGGER_OFFSET, 0);
}

static inline int hwpe_task_queue_acquire_task(uint32_t hwpe_base_addr) {
  return (int)__HAL_HWPE_REG_READ(hwpe_base_addr, HWPE_ACQUIRE_OFFSET);
}

static inline uint32_t hwpe_finished(uint32_t hwpe_base_addr) {
  return __HAL_HWPE_REG_READ(hwpe_base_addr, HWPE_FINISHED_OFFSET);
}

static inline uint32_t hwpe_task_queue_status(uint32_t hwpe_base_addr) {
  return __HAL_HWPE_REG_READ(hwpe_base_addr, HWPE_STATUS_OFFSET);
}

static inline void hwpe_soft_clear(uint32_t hwpe_base_addr) {
  __HAL_HWPE_REG_WRITE(hwpe_base_addr, HWPE_SOFT_CLEAR_OFFSET, 0);
}

#endif // __HAL_HWPE_H__
