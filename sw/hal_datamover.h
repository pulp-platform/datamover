// Copyright 2025-2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Authors: Sergio Mazzola <smazzola@iis.ee.ethz.ch>
//          Cyrill Durrer <cdurrer@iis.ee.ethz.ch>
//          Daniel Keller <dankeller@iis.ee.ethz.ch>
//          Francesco Conti <f.conti@unibo.it>
//          Lionnus Kesting <lkesting@iis.ee.ethz.ch>
//

#ifndef __HAL_DATAMOVER_H__
#define __HAL_DATAMOVER_H__

#include <stdint.h>
#include <stddef.h>

#include "datamover_regif.h"  // SystemRDL-generated register interface (datamover_regif_t)

///////////
// Archi //
///////////

#ifndef DATAMOVER_BASE_ADDR
#define DATAMOVER_BASE_ADDR 0x10000000  /* matches HWPE region (addr[31:24]==0x10) in standalone TB */
#endif

#define DATAMOVER_REGS ((volatile datamover_regif_t *)DATAMOVER_BASE_ADDR)

/* Architecture */

#ifndef DATAMOVER_BANDWIDTH
#define DATAMOVER_BANDWIDTH  512
#endif
#ifndef DATAMOVER_WORD_WIDTH
#define DATAMOVER_WORD_WIDTH 64
#endif
#ifndef DATAMOVER_ELEM_WIDTH
#define DATAMOVER_ELEM_WIDTH 8
#endif
#ifndef DATAMOVER_MISALIGNED_ACCESSES
#define DATAMOVER_MISALIGNED_ACCESSES 0
#endif

#if DATAMOVER_MISALIGNED_ACCESSES
  #define DATAMOVER_BANDWIDTH_ALIGNED (DATAMOVER_BANDWIDTH - DATAMOVER_WORD_WIDTH)
#else
  #define DATAMOVER_BANDWIDTH_ALIGNED (DATAMOVER_BANDWIDTH)
#endif
#define DATAMOVER_BANDWIDTH_ELEMS (DATAMOVER_BANDWIDTH_ALIGNED / DATAMOVER_ELEM_WIDTH)
#define DATAMOVER_WORD_ELEMS      (DATAMOVER_WORD_WIDTH / DATAMOVER_ELEM_WIDTH)

///////////
// Types //
///////////
typedef enum {
  DATAMOVER_COPY  = 0x0,
  DATAMOVER_TRANSP = 0x1,
  DATAMOVER_CIM_LAYOUT = 0x2,
  DATAMOVER_CIM_LAYOUT_TRANSPOSE = 0x3,
  DATAMOVER_UNFOLD = 0x4,
  DATAMOVER_FOLD = 0x5
} datamover_mode_t;
typedef enum {
  DATAMOVER_TRANSP_NONE  = 0x0,
  DATAMOVER_TRANSP_1ELEM = 0x1,
  DATAMOVER_TRANSP_2ELEM = 0x2,
  DATAMOVER_TRANSP_4ELEM = 0x4
} datamover_transp_mode_t;

typedef enum {
    DATAMOVER_OK = 0,
    DATAMOVER_TO,
    DATAMOVER_ERR
} datamover_status_t;

/////////////
// Defines //
/////////////

// Write a job-dependent register field (logs the field name when VERBOSE).
#if VERBOSE
#define DATAMOVER_JOB_REG_WRITE(field, value) do { \
    DATAMOVER_REGS->hwpe_job_dep.field = (value); \
    printf("__HAL_DATAMOVER_REG_WRITE: %s <= 0x%08x\n", #field, (uint32_t)(value)); \
  } while(0)
#else
#define DATAMOVER_JOB_REG_WRITE(field, value) (DATAMOVER_REGS->hwpe_job_dep.field = (value))
#endif

/////////////////////////////
// Mandatory HWPE controls //
/////////////////////////////

static inline int datamover_acquire_task(void) {
  return (int)DATAMOVER_REGS->hwpe_ctrl.acquire;
}

static inline void datamover_trigger_task(void) {
  DATAMOVER_REGS->hwpe_ctrl.commit_trigger = 0;
}

static inline uint32_t datamover_get_status(void) {
  return DATAMOVER_REGS->hwpe_ctrl.status;
}

static inline void datamover_soft_clear(void) {
  DATAMOVER_REGS->hwpe_ctrl.soft_clear = 0;
}

static inline uint32_t datamover_running_job(void) {
  return DATAMOVER_REGS->hwpe_ctrl.running_job;
}

////////////////
// Prototypes //
////////////////

// Job-dependent register drivers
void datamover_in_set(uint32_t value);
void datamover_out_set(uint32_t value);
void datamover_tot_len_set(uint32_t value);
void datamover_in_d0_set(uint32_t stride, uint32_t len);
void datamover_in_d1_set(uint32_t stride, uint32_t len);
void datamover_in_d2_set(uint32_t stride, uint32_t len);
void datamover_in_d3_set(uint32_t stride, uint32_t len);
void datamover_out_d0_set(uint32_t stride, uint32_t len);
void datamover_out_d1_set(uint32_t stride, uint32_t len);
void datamover_out_d2_set(uint32_t stride, uint32_t len);
void datamover_out_d3_set(uint32_t stride, uint32_t len);
void datamover_in_out_d4_stride_set(uint32_t out_stride, uint32_t in_stride);
void datamover_matrix_dim_set(uint32_t tensor_size_n, uint32_t tensor_size_m);
void datamover_channels_set(uint32_t total_elements, uint32_t num_channels);
void datamover_ctrl_engine_set(datamover_mode_t datamover_mode, uint32_t write_dim_en, uint32_t read_dim_en, datamover_transp_mode_t transp_mode);

// HAL
datamover_status_t datamover_wait_done(uint64_t timeout);
datamover_status_t datamover_copy(uint8_t *src, uint8_t *dst, uint32_t size_m, uint32_t size_n);
datamover_status_t datamover_copy_blocking(uint8_t *src, uint8_t *dst, uint32_t size_m, uint32_t size_n, uint64_t timeout);
datamover_status_t datamover_transpose(uint8_t *matrix_in, uint8_t *matrix_out, uint32_t size_m, uint32_t size_n, datamover_transp_mode_t transp_mode);
datamover_status_t datamover_transpose_blocking(uint8_t *matrix_in, uint8_t *matrix_out, uint32_t size_m, uint32_t size_n, datamover_transp_mode_t transp_mode, uint64_t timeout);
datamover_status_t datamover_cim_layout(uint8_t *matrix_in, uint8_t *matrix_out, uint32_t size_m, uint32_t size_n, uint32_t row_tile_size);
datamover_status_t datamover_cim_layout_blocking(uint8_t *matrix_in, uint8_t *matrix_out, uint32_t size_m, uint32_t size_n, uint32_t row_tile_size, uint64_t timeout);
datamover_status_t datamover_cim_layout_reverse(uint8_t *matrix_in, uint8_t *matrix_out, uint32_t size_m, uint32_t size_n, uint32_t row_tile_size);
datamover_status_t datamover_cim_layout_reverse_blocking(uint8_t *matrix_in, uint8_t *matrix_out, uint32_t size_m, uint32_t size_n, uint32_t row_tile_size, uint64_t timeout);
datamover_status_t datamover_cim_layout_transpose_blocking(uint8_t *matrix_in, uint8_t *matrix_out, uint32_t size_m, uint32_t size_n, uint32_t row_tile_size, datamover_transp_mode_t transp_mode, uint64_t timeout);
datamover_status_t datamover_unfold(uint8_t *matrix_in, uint8_t *matrix_out, uint32_t size_c, uint32_t size_h, uint32_t size_w);
datamover_status_t datamover_unfold_blocking(uint8_t *matrix_in, uint8_t *matrix_out, uint32_t size_c, uint32_t size_h, uint32_t size_w, uint64_t timeout);
datamover_status_t datamover_fold(uint8_t *matrix_in, uint8_t *matrix_out, uint32_t size_c, uint32_t size_h, uint32_t size_w);
datamover_status_t datamover_fold_blocking(uint8_t *matrix_in, uint8_t *matrix_out, uint32_t size_c, uint32_t size_h, uint32_t size_w, uint64_t timeout);

#endif // __HAL_DATAMOVER_H__
