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
// Datamover HWPE architecture, task descriptor, and register-image builders.

#ifndef __DATAMOVER_CONFIG_H__
#define __DATAMOVER_CONFIG_H__

#include <stdint.h>
#include <stddef.h>

#include "datamover_regif.h"  // SystemRDL-generated register interface

//==========================================================================
// Archi
//==========================================================================

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

#define DATAMOVER_UNFOLD_PATCH      4  // 2x2 patch, only supported unfold/fold patch
#define DATAMOVER_UNFOLD_PATCH_SIDE 2

//==========================================================================
// Types
//==========================================================================

typedef enum {
  DATAMOVER_COPY                 = 0x0,
  DATAMOVER_TRANSP               = 0x1,
  DATAMOVER_CIM_LAYOUT           = 0x2,
  DATAMOVER_CIM_LAYOUT_TRANSPOSE = 0x3,
  DATAMOVER_UNFOLD               = 0x4,
  DATAMOVER_FOLD                 = 0x5
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

typedef datamover_regif__hwpe_ctrl_job_dep_t datamover_cfg_t;

typedef struct {
  uint8_t                *in_ptr;
  uint8_t                *out_ptr;
  uint8_t                *gold_ptr;
  uint32_t                out_size;
  datamover_mode_t        mode;
  datamover_transp_mode_t transp_mode;
  uint32_t                cim_mode;       // 0 = row-major->CIM, 1 = CIM->row-major
  uint32_t                row_tile_size;
  uint32_t                size_c;
  uint32_t                size_m;
  uint32_t                size_n;
} datamover_task_config_t;

//==========================================================================
// Field packing
//==========================================================================

#define DATAMOVER_FIELD(reg, field, val) \
  (((uint32_t)(val) << DATAMOVER_REGIF__##reg##__##field##_bp) & DATAMOVER_REGIF__##reg##__##field##_bm)

static inline uint32_t dm_ceil_div(uint32_t a, uint32_t b) {
  return (a + b - 1) / b;
}

static inline uint32_t dm_stride_len(uint32_t stride, uint32_t len) {
  return DATAMOVER_FIELD(DM_STRIDE_LEN, STRIDE, stride) | DATAMOVER_FIELD(DM_STRIDE_LEN, LENGTH, len);
}

static inline uint32_t dm_d4_stride(uint32_t out_stride, uint32_t in_stride) {
  return DATAMOVER_FIELD(DM_D4_STRIDE, OUT_STRIDE, out_stride) | DATAMOVER_FIELD(DM_D4_STRIDE, IN_STRIDE, in_stride);
}

static inline uint32_t dm_matrix_dim(uint32_t tensor_size_n, uint32_t tensor_size_m) {
  return DATAMOVER_FIELD(DM_MATRIX_DIM, TENSOR_SIZE_N, tensor_size_n) | DATAMOVER_FIELD(DM_MATRIX_DIM, TENSOR_SIZE_M, tensor_size_m);
}

static inline uint32_t dm_channels(uint32_t total_elements, uint32_t num_channels) {
  return DATAMOVER_FIELD(DM_CHANNELS, TOTAL_ELEMENTS, total_elements) | DATAMOVER_FIELD(DM_CHANNELS, NUM_CHANNELS, num_channels);
}

static inline uint32_t dm_ctrl_engine(datamover_mode_t mode, uint32_t write_dim_en,
                                      uint32_t read_dim_en, datamover_transp_mode_t transp_mode) {
  return DATAMOVER_FIELD(DM_CTRL_ENGINE, WRITE_DIM_EN, write_dim_en)
       | DATAMOVER_FIELD(DM_CTRL_ENGINE, READ_DIM_EN, read_dim_en)
       | DATAMOVER_FIELD(DM_CTRL_ENGINE, DATAMOVER_MODE, mode)
       | DATAMOVER_FIELD(DM_CTRL_ENGINE, TRANSP_MODE, transp_mode);
}

//==========================================================================
// Register-image builders
//==========================================================================

static inline __attribute__((always_inline)) void datamover_build_copy(datamover_cfg_t *cfg, const void *in, const void *out,
                                        uint32_t size_m, uint32_t size_n) {
  uint32_t total_accesses = (size_m * size_n) / DATAMOVER_BANDWIDTH_ELEMS;
  if ((size_m * size_n) % DATAMOVER_BANDWIDTH_ELEMS != 0) total_accesses += 1;

  cfg->in_ptr           = (uint32_t)(uintptr_t)in;
  cfg->out_ptr          = (uint32_t)(uintptr_t)out;
  cfg->tot_len          = total_accesses;
  cfg->in_d0            = dm_stride_len(DATAMOVER_BANDWIDTH_ELEMS, total_accesses);
  cfg->in_d1            = dm_stride_len(0, 0);
  cfg->in_d2            = dm_stride_len(0, 0);
  cfg->in_d3            = dm_stride_len(0, 0);
  cfg->out_d0           = dm_stride_len(DATAMOVER_BANDWIDTH_ELEMS, total_accesses);
  cfg->out_d1           = dm_stride_len(0, 0);
  cfg->out_d2           = dm_stride_len(0, 0);
  cfg->out_d3           = dm_stride_len(0, 0);
  cfg->in_out_d4_stride = dm_d4_stride(0, 0);
  cfg->matrix_dim       = dm_matrix_dim(size_n, size_m);
  cfg->channels         = dm_channels(size_m * size_n, 1);
  cfg->ctrl_engine      = dm_ctrl_engine(DATAMOVER_COPY, 0, 0, DATAMOVER_TRANSP_NONE);
}

static inline __attribute__((always_inline)) void datamover_build_transpose(datamover_cfg_t *cfg, const void *in, const void *out,
                                             uint32_t size_m, uint32_t size_n, datamover_transp_mode_t transp_mode) {
  uint32_t t = (uint32_t)transp_mode;
  uint32_t m_tiles = dm_ceil_div(size_m, DATAMOVER_BANDWIDTH_ELEMS);
  uint32_t n_tiles = dm_ceil_div(size_n, DATAMOVER_BANDWIDTH_ELEMS);

  cfg->in_ptr           = (uint32_t)(uintptr_t)in;
  cfg->out_ptr          = (uint32_t)(uintptr_t)out;
  cfg->tot_len          = m_tiles * n_tiles * DATAMOVER_BANDWIDTH_ELEMS;
  cfg->in_d0            = dm_stride_len(size_n, m_tiles * DATAMOVER_BANDWIDTH_ELEMS);
  cfg->in_d1            = dm_stride_len(DATAMOVER_BANDWIDTH_ELEMS, n_tiles);
  cfg->in_d2            = dm_stride_len(0, 0);
  cfg->in_d3            = dm_stride_len(0, 0);
  cfg->out_d0           = dm_stride_len(size_m * t, DATAMOVER_BANDWIDTH_ELEMS / t);
  cfg->out_d1           = dm_stride_len(DATAMOVER_BANDWIDTH_ELEMS, m_tiles * t);
  cfg->out_d2           = dm_stride_len(size_m * DATAMOVER_BANDWIDTH_ELEMS, 0);
  cfg->out_d3           = dm_stride_len(0, 0);
  cfg->in_out_d4_stride = dm_d4_stride(0, 0);
  cfg->matrix_dim       = dm_matrix_dim(size_n, size_m);
  cfg->channels         = dm_channels(size_m * size_n, 1);
  cfg->ctrl_engine      = dm_ctrl_engine(DATAMOVER_TRANSP, 0x3, 0x1, transp_mode);
}

// CIM-layout forward (row-major -> CIM), complete tiles in the N dimension.
static inline __attribute__((always_inline)) void datamover_build_cim_complete(datamover_cfg_t *cfg, const void *in, const void *out,
                                                uint32_t size_m, uint32_t size_n, uint32_t row_tile_size) {
  uint32_t m_tiles          = dm_ceil_div(size_m, DATAMOVER_BANDWIDTH_ELEMS);
  uint32_t complete_n_tiles = size_n / row_tile_size;
  uint32_t beats_per_row    = row_tile_size / DATAMOVER_BANDWIDTH_ELEMS;

  cfg->in_ptr  = (uint32_t)(uintptr_t)in;
  cfg->out_ptr = (uint32_t)(uintptr_t)out;
  cfg->tot_len = m_tiles * complete_n_tiles * row_tile_size;
  cfg->in_d0   = dm_stride_len(DATAMOVER_BANDWIDTH_ELEMS, beats_per_row);
  cfg->in_d1   = dm_stride_len(size_n, m_tiles * DATAMOVER_BANDWIDTH_ELEMS);
  cfg->in_d2   = dm_stride_len(row_tile_size, 0);
  cfg->in_d3   = dm_stride_len(0, 0);
  if (beats_per_row > 1) {
    cfg->out_d0      = dm_stride_len(DATAMOVER_BANDWIDTH_ELEMS, beats_per_row);
    cfg->out_d1      = dm_stride_len(row_tile_size, m_tiles * DATAMOVER_BANDWIDTH_ELEMS);
    cfg->out_d2      = dm_stride_len(row_tile_size * size_m, complete_n_tiles);
    cfg->out_d3      = dm_stride_len(0, 0);
    cfg->ctrl_engine = dm_ctrl_engine(DATAMOVER_CIM_LAYOUT, 0x3, 0x3, DATAMOVER_TRANSP_NONE);
  } else {
    cfg->out_d0      = dm_stride_len(DATAMOVER_BANDWIDTH_ELEMS, m_tiles * DATAMOVER_BANDWIDTH_ELEMS);
    cfg->out_d1      = dm_stride_len(row_tile_size * size_m, complete_n_tiles);
    cfg->out_d2      = dm_stride_len(0, 0);
    cfg->out_d3      = dm_stride_len(0, 0);
    cfg->ctrl_engine = dm_ctrl_engine(DATAMOVER_CIM_LAYOUT, 0x1, 0x3, DATAMOVER_TRANSP_NONE);
  }
  cfg->in_out_d4_stride = dm_d4_stride(0, 0);
  cfg->matrix_dim       = dm_matrix_dim(complete_n_tiles * row_tile_size, size_m);
  cfg->channels         = dm_channels(complete_n_tiles * row_tile_size * size_m, 1);
}

// CIM-layout forward, leftover columns (assumes row_tile_size == BANDWIDTH_ELEMS).
static inline __attribute__((always_inline)) void datamover_build_cim_leftover(datamover_cfg_t *cfg, const void *in, const void *out,
                                                uint32_t size_m, uint32_t size_n, uint32_t row_tile_size) {
  uint32_t m_tiles          = dm_ceil_div(size_m, DATAMOVER_BANDWIDTH_ELEMS);
  uint32_t complete_n_tiles = size_n / row_tile_size;
  uint32_t leftover_columns = size_n % DATAMOVER_BANDWIDTH_ELEMS;
  const uint8_t *in_shifted  = (const uint8_t *)in  + complete_n_tiles * DATAMOVER_BANDWIDTH_ELEMS;
  const uint8_t *out_shifted = (const uint8_t *)out + complete_n_tiles * size_m * DATAMOVER_BANDWIDTH_ELEMS;

  cfg->in_ptr           = (uint32_t)(uintptr_t)in_shifted;
  cfg->out_ptr          = (uint32_t)(uintptr_t)out_shifted;
  cfg->tot_len          = m_tiles * DATAMOVER_BANDWIDTH_ELEMS;
  cfg->in_d0            = dm_stride_len(DATAMOVER_BANDWIDTH_ELEMS, row_tile_size / DATAMOVER_BANDWIDTH_ELEMS);
  cfg->in_d1            = dm_stride_len(size_n, m_tiles * DATAMOVER_BANDWIDTH_ELEMS);
  cfg->in_d2            = dm_stride_len(0, 0);
  cfg->in_d3            = dm_stride_len(0, 0);
  cfg->out_d0           = dm_stride_len(leftover_columns, m_tiles * DATAMOVER_BANDWIDTH_ELEMS);
  cfg->out_d1           = dm_stride_len(0, 0);
  cfg->out_d2           = dm_stride_len(0, 0);
  cfg->out_d3           = dm_stride_len(0, 0);
  cfg->in_out_d4_stride = dm_d4_stride(0, 0);
  cfg->matrix_dim       = dm_matrix_dim(leftover_columns, size_m);
  cfg->channels         = dm_channels(leftover_columns * size_m, 1);
  cfg->ctrl_engine      = dm_ctrl_engine(DATAMOVER_CIM_LAYOUT, 0x0, 0x1, DATAMOVER_TRANSP_NONE);
}

// CIM-layout reverse (CIM -> row-major), complete tiles in the N dimension.
static inline __attribute__((always_inline)) void datamover_build_cim_rev_complete(datamover_cfg_t *cfg, const void *in, const void *out,
                                                    uint32_t size_m, uint32_t size_n, uint32_t row_tile_size) {
  uint32_t complete_n_tiles   = size_n / row_tile_size;
  uint32_t cim_layout_m_tiles = dm_ceil_div(size_m * complete_n_tiles, DATAMOVER_BANDWIDTH_ELEMS);
  uint32_t beats_per_row      = row_tile_size / DATAMOVER_BANDWIDTH_ELEMS;

  cfg->in_ptr  = (uint32_t)(uintptr_t)in;
  cfg->out_ptr = (uint32_t)(uintptr_t)out;
  cfg->tot_len = cim_layout_m_tiles * row_tile_size;
  cfg->in_d0   = dm_stride_len(DATAMOVER_BANDWIDTH_ELEMS, size_m * complete_n_tiles * beats_per_row);
  cfg->in_d1   = dm_stride_len(0, 0);
  cfg->in_d2   = dm_stride_len(0, 0);
  cfg->in_d3   = dm_stride_len(0, 0);
  if (beats_per_row > 1) {
    cfg->out_d0      = dm_stride_len(DATAMOVER_BANDWIDTH_ELEMS, beats_per_row);
    cfg->out_d1      = dm_stride_len(size_n, size_m);
    cfg->out_d2      = dm_stride_len(row_tile_size, complete_n_tiles);
    cfg->out_d3      = dm_stride_len(0, 0);
    cfg->ctrl_engine = dm_ctrl_engine(DATAMOVER_CIM_LAYOUT, 0x3, 0x0, DATAMOVER_TRANSP_NONE);
  } else {
    cfg->out_d0      = dm_stride_len(size_n, size_m);
    cfg->out_d1      = dm_stride_len(DATAMOVER_BANDWIDTH_ELEMS, complete_n_tiles);
    cfg->out_d2      = dm_stride_len(0, 0);
    cfg->out_d3      = dm_stride_len(0, 0);
    cfg->ctrl_engine = dm_ctrl_engine(DATAMOVER_CIM_LAYOUT, 0x1, 0x0, DATAMOVER_TRANSP_NONE);
  }
  cfg->in_out_d4_stride = dm_d4_stride(0, 0);
  cfg->matrix_dim       = dm_matrix_dim(row_tile_size, size_m * complete_n_tiles);
  cfg->channels         = dm_channels(row_tile_size * size_m * complete_n_tiles, 1);
}

// CIM-layout reverse, leftover columns (assumes row_tile_size == BANDWIDTH_ELEMS).
static inline __attribute__((always_inline)) void datamover_build_cim_rev_leftover(datamover_cfg_t *cfg, const void *in, const void *out,
                                                    uint32_t size_m, uint32_t size_n, uint32_t row_tile_size) {
  uint32_t m_tiles          = dm_ceil_div(size_m, DATAMOVER_BANDWIDTH_ELEMS);
  uint32_t complete_n_tiles = size_n / row_tile_size;
  uint32_t leftover_columns = size_n % DATAMOVER_BANDWIDTH_ELEMS;
  const uint8_t *in_shifted  = (const uint8_t *)in  + complete_n_tiles * size_m * DATAMOVER_BANDWIDTH_ELEMS;
  const uint8_t *out_shifted = (const uint8_t *)out + complete_n_tiles * DATAMOVER_BANDWIDTH_ELEMS;

  cfg->in_ptr           = (uint32_t)(uintptr_t)in_shifted;
  cfg->out_ptr          = (uint32_t)(uintptr_t)out_shifted;
  cfg->tot_len          = m_tiles * DATAMOVER_BANDWIDTH_ELEMS;
  cfg->in_d0            = dm_stride_len(leftover_columns, m_tiles * DATAMOVER_BANDWIDTH_ELEMS);
  cfg->in_d1            = dm_stride_len(0, 0);
  cfg->in_d2            = dm_stride_len(0, 0);
  cfg->in_d3            = dm_stride_len(0, 0);
  cfg->out_d0           = dm_stride_len(size_n, m_tiles * DATAMOVER_BANDWIDTH_ELEMS);
  cfg->out_d1           = dm_stride_len(0, 0);
  cfg->out_d2           = dm_stride_len(0, 0);
  cfg->out_d3           = dm_stride_len(0, 0);
  cfg->in_out_d4_stride = dm_d4_stride(0, 0);
  cfg->matrix_dim       = dm_matrix_dim(leftover_columns, size_m);
  cfg->channels         = dm_channels(leftover_columns * size_m, 1);
  cfg->ctrl_engine      = dm_ctrl_engine(DATAMOVER_CIM_LAYOUT, 0x0, 0x0, DATAMOVER_TRANSP_NONE);
}

// Tensor (C,H,W) -> unfolded (P, N=(H*W)/P, C); H=size_m, W=size_n.
static inline __attribute__((always_inline)) void datamover_build_unfold(datamover_cfg_t *cfg, const void *in, const void *out,
                                          uint32_t size_c, uint32_t size_h, uint32_t size_w) {
  const uint32_t P = DATAMOVER_UNFOLD_PATCH;
  const uint32_t side_P = DATAMOVER_UNFOLD_PATCH_SIDE;
  uint32_t c_tiles = dm_ceil_div(size_c, DATAMOVER_BANDWIDTH_ELEMS);
  uint32_t w_tiles = dm_ceil_div(size_w, DATAMOVER_BANDWIDTH_ELEMS);

  cfg->in_ptr           = (uint32_t)(uintptr_t)in;
  cfg->out_ptr          = (uint32_t)(uintptr_t)out;
  cfg->tot_len          = c_tiles * w_tiles * DATAMOVER_BANDWIDTH_ELEMS * size_h;
  cfg->in_d0            = dm_stride_len(size_h * size_w, c_tiles * DATAMOVER_BANDWIDTH_ELEMS);
  cfg->in_d1            = dm_stride_len(DATAMOVER_BANDWIDTH_ELEMS, w_tiles);
  cfg->in_d2            = dm_stride_len(size_w, size_h);
  cfg->in_d3            = dm_stride_len(0, 0);
  cfg->out_d0           = dm_stride_len(size_c * size_h * size_w / P, side_P);
  cfg->out_d1           = dm_stride_len(size_c, (w_tiles * DATAMOVER_BANDWIDTH_ELEMS) / side_P);
  cfg->out_d2           = dm_stride_len(DATAMOVER_BANDWIDTH_ELEMS, c_tiles);
  cfg->out_d3           = dm_stride_len(size_c * size_h * size_w / side_P, side_P);
  cfg->in_out_d4_stride = dm_d4_stride(size_c * size_w / side_P, 0);
  cfg->matrix_dim       = dm_matrix_dim(size_w, size_h);
  cfg->channels         = dm_channels(size_c * size_h * size_w, size_c);
  cfg->ctrl_engine      = dm_ctrl_engine(DATAMOVER_UNFOLD, 0xF, 0x3, DATAMOVER_TRANSP_1ELEM);
}

// Unfolded (P,N,C) -> folded (C,H,W); H=size_m, W=size_n of the folded output.
static inline __attribute__((always_inline)) void datamover_build_fold(datamover_cfg_t *cfg, const void *in, const void *out,
                                        uint32_t size_c, uint32_t size_h, uint32_t size_w) {
  const uint32_t P = DATAMOVER_UNFOLD_PATCH;
  const uint32_t side_P = DATAMOVER_UNFOLD_PATCH_SIDE;
  uint32_t c_tiles = dm_ceil_div(size_c, DATAMOVER_BANDWIDTH_ELEMS);
  uint32_t w_tiles = dm_ceil_div(size_w, DATAMOVER_BANDWIDTH_ELEMS);

  cfg->in_ptr           = (uint32_t)(uintptr_t)in;
  cfg->out_ptr          = (uint32_t)(uintptr_t)out;
  cfg->tot_len          = c_tiles * w_tiles * DATAMOVER_BANDWIDTH_ELEMS * size_h;
  cfg->in_d0            = dm_stride_len(size_c * size_h * size_w / P, side_P);
  cfg->in_d1            = dm_stride_len(size_c, (w_tiles * DATAMOVER_BANDWIDTH_ELEMS) / side_P);
  cfg->in_d2            = dm_stride_len(DATAMOVER_BANDWIDTH_ELEMS, c_tiles);
  cfg->in_d3            = dm_stride_len(size_c * size_h * size_w / side_P, side_P);
  cfg->out_d0           = dm_stride_len(size_h * size_w, c_tiles * DATAMOVER_BANDWIDTH_ELEMS);
  cfg->out_d1           = dm_stride_len(DATAMOVER_BANDWIDTH_ELEMS, w_tiles);
  cfg->out_d2           = dm_stride_len(size_w, size_h);
  cfg->out_d3           = dm_stride_len(0, 0);
  cfg->in_out_d4_stride = dm_d4_stride(0, size_c * size_w / side_P);
  cfg->matrix_dim       = dm_matrix_dim(size_w, size_h);
  cfg->channels         = dm_channels(size_c * size_h * size_w, size_c);
  cfg->ctrl_engine      = dm_ctrl_engine(DATAMOVER_FOLD, 0x3, 0xF, DATAMOVER_TRANSP_1ELEM);
}

#endif // __DATAMOVER_CONFIG_H__
