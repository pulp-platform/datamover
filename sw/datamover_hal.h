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
// Datamover HWPE Hardware Abstraction Layer.
//
// Three access levels over the SystemRDL-generated datamover_regif map:
//   L0  commands  : datamover_{soft_clear,acquire,trigger,status}()
//   L1  program   : datamover_program() -- write a built register image
//   L2  operations: datamover_{copy,transpose,cim_layout,...}() and
//                   datamover_run() -- build, acquire, program, and trigger a job
//
// DATAMOVER_BASE_ADDR must be defined before including.

#ifndef __DATAMOVER_HAL_H__
#define __DATAMOVER_HAL_H__

#include <stdint.h>

#include "datamover_config.h"

#ifndef DATAMOVER_BASE_ADDR
#error "DATAMOVER_BASE_ADDR must be defined"
#endif

#define DATAMOVER_REGS ((volatile datamover_regif_t *)DATAMOVER_BASE_ADDR)

//==========================================================================
// Commands
//==========================================================================

static inline void     datamover_soft_clear(void) { DATAMOVER_REGS->hwpe_ctrl.soft_clear     = 0; }
static inline int32_t  datamover_acquire(void)    { return (int32_t)DATAMOVER_REGS->hwpe_ctrl.acquire; }
static inline void     datamover_trigger(void)    { DATAMOVER_REGS->hwpe_ctrl.commit_trigger = 0; }
static inline uint32_t datamover_status(void)     { return DATAMOVER_REGS->hwpe_ctrl.status; }

// Spin until a job slot is free.
static inline void datamover_acquire_wait(void) { while (datamover_acquire() < 0) {} }

static inline void datamover_wait(void) { while (datamover_status() != 0) {} }

//==========================================================================
// Program
//==========================================================================

static inline __attribute__((always_inline)) void datamover_program(const datamover_cfg_t *cfg) {
  volatile datamover_cfg_t *r = &DATAMOVER_REGS->hwpe_job_dep;
  r->in_ptr           = cfg->in_ptr;
  r->out_ptr          = cfg->out_ptr;
  r->tot_len          = cfg->tot_len;
  r->in_d0            = cfg->in_d0;
  r->in_d1            = cfg->in_d1;
  r->in_d2            = cfg->in_d2;
  r->in_d3            = cfg->in_d3;
  r->out_d0           = cfg->out_d0;
  r->out_d1           = cfg->out_d1;
  r->out_d2           = cfg->out_d2;
  r->out_d3           = cfg->out_d3;
  r->in_out_d4_stride = cfg->in_out_d4_stride;
  r->matrix_dim       = cfg->matrix_dim;
  r->channels         = cfg->channels;
  r->ctrl_engine      = cfg->ctrl_engine;
}

// Acquire a free slot, program the built image, and trigger the job.
static inline __attribute__((always_inline)) void datamover_launch(const datamover_cfg_t *cfg) {
  datamover_acquire_wait();
  datamover_program(cfg);
  datamover_trigger();
}

//==========================================================================
// Operations
//==========================================================================

static inline __attribute__((always_inline)) void datamover_copy(uint8_t *src, uint8_t *dst, uint32_t size_m, uint32_t size_n) {
  datamover_cfg_t cfg;
  datamover_build_copy(&cfg, src, dst, size_m, size_n);
  datamover_launch(&cfg);
}

static inline __attribute__((always_inline)) void datamover_transpose(uint8_t *matrix_in, uint8_t *matrix_out, uint32_t size_m,
                                       uint32_t size_n, datamover_transp_mode_t transp_mode) {
  datamover_cfg_t cfg;
  datamover_build_transpose(&cfg, matrix_in, matrix_out, size_m, size_n, transp_mode);
  datamover_launch(&cfg);
}

static inline __attribute__((always_inline)) void datamover_cim_layout(uint8_t *matrix_in, uint8_t *matrix_out, uint32_t size_m,
                                        uint32_t size_n, uint32_t row_tile_size) {
  // row_tile_size = CIM inner dim (A-layout) or outer dim (B-layout). Must be a
  // multiple of BANDWIDTH_ELEMS; the leftover-column path assumes == BANDWIDTH_ELEMS.
  datamover_cfg_t cfg;
  uint32_t leftover_columns = size_n % DATAMOVER_BANDWIDTH_ELEMS;

  if (leftover_columns == 0 || size_n > DATAMOVER_BANDWIDTH_ELEMS) {
    datamover_build_cim_complete(&cfg, matrix_in, matrix_out, size_m, size_n, row_tile_size);
    datamover_launch(&cfg);
  }
  if (leftover_columns != 0) {
    datamover_build_cim_leftover(&cfg, matrix_in, matrix_out, size_m, size_n, row_tile_size);
    datamover_launch(&cfg);
  }
}

static inline __attribute__((always_inline)) void datamover_cim_layout_reverse(uint8_t *matrix_in, uint8_t *matrix_out, uint32_t size_m,
                                                uint32_t size_n, uint32_t row_tile_size) {
  datamover_cfg_t cfg;
  uint32_t leftover_columns = size_n % DATAMOVER_BANDWIDTH_ELEMS;

  if (leftover_columns == 0 || size_n > DATAMOVER_BANDWIDTH_ELEMS) {
    datamover_build_cim_rev_complete(&cfg, matrix_in, matrix_out, size_m, size_n, row_tile_size);
    datamover_launch(&cfg);
  }
  if (leftover_columns != 0) {
    datamover_build_cim_rev_leftover(&cfg, matrix_in, matrix_out, size_m, size_n, row_tile_size);
    datamover_launch(&cfg);
  }
}

static inline __attribute__((always_inline)) void datamover_unfold(uint8_t *matrix_in, uint8_t *matrix_out,
                                    uint32_t size_c, uint32_t size_h, uint32_t size_w) {
  datamover_cfg_t cfg;
  datamover_build_unfold(&cfg, matrix_in, matrix_out, size_c, size_h, size_w);
  datamover_launch(&cfg);
}

static inline __attribute__((always_inline)) void datamover_fold(uint8_t *matrix_in, uint8_t *matrix_out,
                                  uint32_t size_c, uint32_t size_h, uint32_t size_w) {
  datamover_cfg_t cfg;
  datamover_build_fold(&cfg, matrix_in, matrix_out, size_c, size_h, size_w);
  datamover_launch(&cfg);
}

static inline __attribute__((always_inline)) void datamover_im2col(uint8_t *tensor_in, uint8_t *matrix_out,
                                    uint32_t size_c, uint32_t size_h, uint32_t size_w,
                                    uint32_t kernel_size, uint32_t conv_stride) {
  datamover_cfg_t cfg;
  datamover_build_im2col(&cfg, tensor_in, matrix_out, size_c, size_h, size_w, kernel_size, conv_stride);
  datamover_launch(&cfg);
}

// Transpose a CIM-layout matrix via row-major: reverse -> transpose -> forward.
// Each phase reads the buffer the previous one wrote; the engine runs committed
// jobs in order, so the phases stay correctly sequenced without explicit waits.
// IMPORTANT: the input buffer is used as scratch and is overwritten.
static inline __attribute__((always_inline)) void datamover_cim_layout_transpose(uint8_t *matrix_in, uint8_t *matrix_out, uint32_t size_m,
                                                  uint32_t size_n, uint32_t row_tile_size,
                                                  datamover_transp_mode_t transp_mode) {
  if (size_n <= row_tile_size && size_m <= row_tile_size) {
    // Single tile in N and M: CIM layout equals row-major, so transpose directly.
    datamover_transpose(matrix_in, matrix_out, size_m, size_n, transp_mode);
    return;
  }
  datamover_cim_layout_reverse(matrix_in, matrix_out, size_m, size_n, row_tile_size);
  datamover_transpose(matrix_out, matrix_in, size_m, size_n, transp_mode);
  datamover_cim_layout(matrix_in, matrix_out, size_n, size_m, row_tile_size);
}

//==========================================================================
// Run
//==========================================================================

static inline __attribute__((always_inline)) datamover_status_t datamover_run(const datamover_task_config_t *t) {
  switch (t->mode) {
    case DATAMOVER_COPY:
      datamover_copy(t->in_ptr, t->out_ptr, t->size_m, t->size_n);
      return DATAMOVER_OK;
    case DATAMOVER_TRANSP:
      datamover_transpose(t->in_ptr, t->out_ptr, t->size_m, t->size_n, t->transp_mode);
      return DATAMOVER_OK;
    case DATAMOVER_CIM_LAYOUT:
      if (t->cim_mode == 0)
        datamover_cim_layout(t->in_ptr, t->out_ptr, t->size_m, t->size_n, t->row_tile_size);
      else
        datamover_cim_layout_reverse(t->in_ptr, t->out_ptr, t->size_m, t->size_n, t->row_tile_size);
      return DATAMOVER_OK;
    case DATAMOVER_CIM_LAYOUT_TRANSPOSE:
      datamover_cim_layout_transpose(t->in_ptr, t->out_ptr, t->size_m, t->size_n,
                                     t->row_tile_size, t->transp_mode);
      return DATAMOVER_OK;
    case DATAMOVER_UNFOLD:
      datamover_unfold(t->in_ptr, t->out_ptr, t->size_c, t->size_m, t->size_n);
      return DATAMOVER_OK;
    case DATAMOVER_FOLD:
      datamover_fold(t->in_ptr, t->out_ptr, t->size_c, t->size_m, t->size_n);
      return DATAMOVER_OK;
    case DATAMOVER_IM2COL:
      datamover_im2col(t->in_ptr, t->out_ptr, t->size_c, t->size_m, t->size_n,
                       t->kernel_size, t->conv_stride);
      return DATAMOVER_OK;
    default:
      return DATAMOVER_ERR;
  }
}

#endif // __DATAMOVER_HAL_H__
