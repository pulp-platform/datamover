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
  DATAMOVER_FOLD                 = 0x5,
  DATAMOVER_IM2COL               = 0x6
} datamover_mode_t;

typedef enum {
  DATAMOVER_TRANSP_NONE  = 0x0,
  DATAMOVER_TRANSP_1ELEM = 0x1,
  DATAMOVER_TRANSP_2ELEM = 0x2,
  DATAMOVER_TRANSP_4ELEM = 0x4
} datamover_transp_mode_t;

// Tensor layouts. CHW is row-major. CIM is the 64-column block layout of mode 2: an
// activation is the (C, pixels) matrix, a token matrix is (4N, C).
typedef enum {
  DATAMOVER_LAYOUT_CHW = 0,
  DATAMOVER_LAYOUT_CIM = 1
} datamover_layout_t;

// im2col output: COL makes each patch a column (torch unfold, Surya operand B), ROW makes
// each patch a row (im2row, Surya operand A), *_CIM is the same in 64-column blocks.
typedef enum {
  DATAMOVER_IM2COL_IN_CHW = 0,
  DATAMOVER_IM2COL_IN_HWC = 1,
  DATAMOVER_IM2COL_IN_CIM = 2   // (C, pixels) in 64-pixel blocks
} datamover_im2col_in_t;

typedef enum {
  DATAMOVER_IM2COL_OUT_COL     = 0,  // (Kh*Kw*C, pixels)
  DATAMOVER_IM2COL_OUT_ROW     = 1,  // (pixels, C*Kh*Kw)
  DATAMOVER_IM2COL_OUT_ROW_CIM = 2,  // (pixels, C*Kh*Kw) in 64-column blocks
  DATAMOVER_IM2COL_OUT_COL_CIM = 3   // (Kh*Kw*C, pixels) in 64-pixel blocks
} datamover_im2col_out_t;

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
  uint32_t                size_c;
  uint32_t                size_m;
  uint32_t                size_n;
  uint32_t                kernel_h;
  uint32_t                kernel_w;
  uint32_t                conv_stride;
  uint32_t                conv_pad;
  datamover_layout_t      layout;         // unfold and fold
  datamover_im2col_in_t   im2col_in;
  datamover_im2col_out_t  im2col_out;
} datamover_task_config_t;

//==========================================================================
// Field packing
//==========================================================================

#define DATAMOVER_FIELD(reg, field, val) \
  (((uint32_t)(val) << DATAMOVER_REGIF__##reg##__##field##_bp) & DATAMOVER_REGIF__##reg##__##field##_bm)

static inline uint32_t dm_ceil_div(uint32_t a, uint32_t b) {
  return (a + b - 1) / b;
}

// Stride and length of source dimension d (d4 has no length).
static inline void dm_in(datamover_cfg_t *cfg, uint32_t d, uint32_t stride, uint32_t len) {
  switch (d) {
    case 0: cfg->in_stride0 = stride; cfg->in_len_d0_d1 = (cfg->in_len_d0_d1 & ~DATAMOVER_REGIF__DM_LEN_D0_D1__D0_bm) | DATAMOVER_FIELD(DM_LEN_D0_D1, D0, len); break;
    case 1: cfg->in_stride1 = stride; cfg->in_len_d0_d1 = (cfg->in_len_d0_d1 & ~DATAMOVER_REGIF__DM_LEN_D0_D1__D1_bm) | DATAMOVER_FIELD(DM_LEN_D0_D1, D1, len); break;
    case 2: cfg->in_stride2 = stride; cfg->in_len_d2_d3 = (cfg->in_len_d2_d3 & ~DATAMOVER_REGIF__DM_LEN_D2_D3__D2_bm) | DATAMOVER_FIELD(DM_LEN_D2_D3, D2, len); break;
    case 3: cfg->in_stride3 = stride; cfg->in_len_d2_d3 = (cfg->in_len_d2_d3 & ~DATAMOVER_REGIF__DM_LEN_D2_D3__D3_bm) | DATAMOVER_FIELD(DM_LEN_D2_D3, D3, len); break;
    default: cfg->in_stride4 = stride; break;
  }
}

static inline void dm_out(datamover_cfg_t *cfg, uint32_t d, uint32_t stride, uint32_t len) {
  switch (d) {
    case 0: cfg->out_stride0 = stride; cfg->out_len_d0_d1 = (cfg->out_len_d0_d1 & ~DATAMOVER_REGIF__DM_LEN_D0_D1__D0_bm) | DATAMOVER_FIELD(DM_LEN_D0_D1, D0, len); break;
    case 1: cfg->out_stride1 = stride; cfg->out_len_d0_d1 = (cfg->out_len_d0_d1 & ~DATAMOVER_REGIF__DM_LEN_D0_D1__D1_bm) | DATAMOVER_FIELD(DM_LEN_D0_D1, D1, len); break;
    case 2: cfg->out_stride2 = stride; cfg->out_len_d2_d3 = (cfg->out_len_d2_d3 & ~DATAMOVER_REGIF__DM_LEN_D2_D3__D2_bm) | DATAMOVER_FIELD(DM_LEN_D2_D3, D2, len); break;
    case 3: cfg->out_stride3 = stride; cfg->out_len_d2_d3 = (cfg->out_len_d2_d3 & ~DATAMOVER_REGIF__DM_LEN_D2_D3__D3_bm) | DATAMOVER_FIELD(DM_LEN_D2_D3, D3, len); break;
    default: cfg->out_stride4 = stride; break;
  }
}

static inline uint32_t dm_matrix_dim(uint32_t tensor_size_n, uint32_t tensor_size_m) {
  return DATAMOVER_FIELD(DM_MATRIX_DIM, TENSOR_SIZE_N, tensor_size_n) | DATAMOVER_FIELD(DM_MATRIX_DIM, TENSOR_SIZE_M, tensor_size_m);
}

static inline void dm_channels(datamover_cfg_t *cfg, uint32_t total_elements, uint32_t num_channels) {
  cfg->channels = DATAMOVER_FIELD(DM_CHANNELS, TOTAL_ELEMENTS, total_elements)
                | DATAMOVER_FIELD(DM_CHANNELS, NUM_CHANNELS, num_channels);
}

static inline uint32_t dm_log2(uint32_t v) {
  uint32_t l = 0;
  while ((1u << l) < v) l++;
  return l;
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
  dm_in(cfg, 0, DATAMOVER_BANDWIDTH_ELEMS, total_accesses);
  dm_in(cfg, 1, 0, 0);
  dm_in(cfg, 2, 0, 0);
  dm_in(cfg, 3, 0, 0);
  dm_out(cfg, 0, DATAMOVER_BANDWIDTH_ELEMS, total_accesses);
  dm_out(cfg, 1, 0, 0);
  dm_out(cfg, 2, 0, 0);
  dm_out(cfg, 3, 0, 0);
  dm_out(cfg, 4, 0, 0);
  dm_in(cfg, 4, 0, 0);
  cfg->matrix_dim = dm_matrix_dim(size_n, size_m);
  dm_channels(cfg, size_m * size_n, 1);
  cfg->ctrl_engine      = dm_ctrl_engine(DATAMOVER_COPY, 0, 0, DATAMOVER_TRANSP_NONE);
}

// Transpose columns [col_start, col_start+band_cols) into output rows [col_start, ...).
static inline __attribute__((always_inline)) void datamover_build_transpose(datamover_cfg_t *cfg, const void *in, const void *out,
                                             uint32_t size_m, uint32_t size_n, uint32_t col_start,
                                             uint32_t band_cols, datamover_transp_mode_t transp_mode) {
  uint32_t t = (uint32_t)transp_mode;
  uint32_t BWE = DATAMOVER_BANDWIDTH_ELEMS;
  uint32_t m_tiles = dm_ceil_div(size_m, BWE);
  uint32_t n_tiles = dm_ceil_div(band_cols, BWE);
  uint32_t cols_per_tile = (band_cols >= BWE) ? BWE : band_cols;

  cfg->in_ptr           = (uint32_t)(uintptr_t)in + col_start;
  cfg->out_ptr          = (uint32_t)(uintptr_t)out + col_start * size_m;
  cfg->tot_len          = size_m * n_tiles;
  cfg->out_tot_len      = band_cols * m_tiles;
  dm_in(cfg, 0, size_n, size_m);
  dm_in(cfg, 1, BWE, n_tiles);
  dm_in(cfg, 2, 0, 0);
  dm_in(cfg, 3, 0, 0);
  dm_out(cfg, 0, size_m * t, cols_per_tile / t);
  dm_out(cfg, 1, BWE, m_tiles * t);
  dm_out(cfg, 2, size_m * BWE, 0);
  dm_out(cfg, 3, 0, 0);
  dm_out(cfg, 4, 0, 0);
  dm_in(cfg, 4, 0, 0);
  cfg->matrix_dim = dm_matrix_dim(band_cols, size_m);
  dm_channels(cfg, size_m * size_n, 1);
  cfg->ctrl_engine      = dm_ctrl_engine(DATAMOVER_TRANSP, 0x3, 0x1, transp_mode);
}

// CIM-layout forward (row-major -> CIM), the complete column blocks of one beat each.
static inline __attribute__((always_inline)) void datamover_build_cim_complete(datamover_cfg_t *cfg, const void *in, const void *out,
                                                uint32_t size_m, uint32_t size_n) {
  const uint32_t BWE = DATAMOVER_BANDWIDTH_ELEMS;
  uint32_t m_tiles  = dm_ceil_div(size_m, BWE);
  uint32_t n_blocks = size_n / BWE;

  cfg->in_ptr  = (uint32_t)(uintptr_t)in;
  cfg->out_ptr = (uint32_t)(uintptr_t)out;
  cfg->tot_len = m_tiles * n_blocks * BWE;
  dm_in(cfg, 0, BWE, 1);
  dm_in(cfg, 1, size_n, m_tiles * BWE);
  dm_in(cfg, 2, BWE, 0);
  dm_in(cfg, 3, 0, 0);
  dm_in(cfg, 4, 0, 0);
  dm_out(cfg, 0, BWE, m_tiles * BWE);
  dm_out(cfg, 1, BWE * size_m, n_blocks);
  dm_out(cfg, 2, 0, 0);
  dm_out(cfg, 3, 0, 0);
  dm_out(cfg, 4, 0, 0);
  cfg->matrix_dim = dm_matrix_dim(n_blocks * BWE, size_m);
  dm_channels(cfg, n_blocks * BWE * size_m, 1);
  cfg->ctrl_engine = dm_ctrl_engine(DATAMOVER_CIM_LAYOUT, 0x1, 0x3, DATAMOVER_TRANSP_NONE);
}

// CIM-layout forward, the leftover columns after the complete blocks.
static inline __attribute__((always_inline)) void datamover_build_cim_leftover(datamover_cfg_t *cfg, const void *in, const void *out,
                                                uint32_t size_m, uint32_t size_n) {
  const uint32_t BWE = DATAMOVER_BANDWIDTH_ELEMS;
  uint32_t m_tiles  = dm_ceil_div(size_m, BWE);
  uint32_t n_blocks = size_n / BWE;
  uint32_t leftover = size_n % BWE;

  cfg->in_ptr  = (uint32_t)(uintptr_t)in  + n_blocks * BWE;
  cfg->out_ptr = (uint32_t)(uintptr_t)out + n_blocks * size_m * BWE;
  cfg->tot_len = m_tiles * BWE;
  dm_in(cfg, 0, BWE, 1);
  dm_in(cfg, 1, size_n, m_tiles * BWE);
  dm_in(cfg, 2, 0, 0);
  dm_in(cfg, 3, 0, 0);
  dm_in(cfg, 4, 0, 0);
  dm_out(cfg, 0, leftover, m_tiles * BWE);
  dm_out(cfg, 1, 0, 0);
  dm_out(cfg, 2, 0, 0);
  dm_out(cfg, 3, 0, 0);
  dm_out(cfg, 4, 0, 0);
  cfg->matrix_dim = dm_matrix_dim(leftover, size_m);
  dm_channels(cfg, leftover * size_m, 1);
  cfg->ctrl_engine = dm_ctrl_engine(DATAMOVER_CIM_LAYOUT, 0x0, 0x1, DATAMOVER_TRANSP_NONE);
}

// CIM-layout reverse (CIM -> row-major), the complete column blocks.
static inline __attribute__((always_inline)) void datamover_build_cim_rev_complete(datamover_cfg_t *cfg, const void *in, const void *out,
                                                    uint32_t size_m, uint32_t size_n) {
  const uint32_t BWE = DATAMOVER_BANDWIDTH_ELEMS;
  uint32_t n_blocks = size_n / BWE;
  uint32_t m_tiles  = dm_ceil_div(size_m * n_blocks, BWE);

  cfg->in_ptr  = (uint32_t)(uintptr_t)in;
  cfg->out_ptr = (uint32_t)(uintptr_t)out;
  cfg->tot_len = m_tiles * BWE;
  dm_in(cfg, 0, BWE, size_m * n_blocks);
  dm_in(cfg, 1, 0, 0);
  dm_in(cfg, 2, 0, 0);
  dm_in(cfg, 3, 0, 0);
  dm_in(cfg, 4, 0, 0);
  dm_out(cfg, 0, size_n, size_m);
  dm_out(cfg, 1, BWE, n_blocks);
  dm_out(cfg, 2, 0, 0);
  dm_out(cfg, 3, 0, 0);
  dm_out(cfg, 4, 0, 0);
  cfg->matrix_dim = dm_matrix_dim(BWE, size_m * n_blocks);
  dm_channels(cfg, BWE * size_m * n_blocks, 1);
  cfg->ctrl_engine = dm_ctrl_engine(DATAMOVER_CIM_LAYOUT, 0x1, 0x0, DATAMOVER_TRANSP_NONE);
}

// CIM-layout reverse, the leftover columns after the complete blocks.
static inline __attribute__((always_inline)) void datamover_build_cim_rev_leftover(datamover_cfg_t *cfg, const void *in, const void *out,
                                                    uint32_t size_m, uint32_t size_n) {
  const uint32_t BWE = DATAMOVER_BANDWIDTH_ELEMS;
  uint32_t m_tiles  = dm_ceil_div(size_m, BWE);
  uint32_t n_blocks = size_n / BWE;
  uint32_t leftover = size_n % BWE;

  cfg->in_ptr  = (uint32_t)(uintptr_t)in  + n_blocks * size_m * BWE;
  cfg->out_ptr = (uint32_t)(uintptr_t)out + n_blocks * BWE;
  cfg->tot_len = m_tiles * BWE;
  dm_in(cfg, 0, leftover, m_tiles * BWE);
  dm_in(cfg, 1, 0, 0);
  dm_in(cfg, 2, 0, 0);
  dm_in(cfg, 3, 0, 0);
  dm_in(cfg, 4, 0, 0);
  dm_out(cfg, 0, size_n, m_tiles * BWE);
  dm_out(cfg, 1, 0, 0);
  dm_out(cfg, 2, 0, 0);
  dm_out(cfg, 3, 0, 0);
  dm_out(cfg, 4, 0, 0);
  cfg->matrix_dim = dm_matrix_dim(leftover, size_m);
  dm_channels(cfg, leftover * size_m, 1);
  cfg->ctrl_engine = dm_ctrl_engine(DATAMOVER_CIM_LAYOUT, 0x0, 0x0, DATAMOVER_TRANSP_NONE);
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
  dm_in(cfg, 0, size_h * size_w, c_tiles * DATAMOVER_BANDWIDTH_ELEMS);
  dm_in(cfg, 1, DATAMOVER_BANDWIDTH_ELEMS, w_tiles);
  dm_in(cfg, 2, size_w, size_h);
  dm_in(cfg, 3, 0, 0);
  dm_out(cfg, 0, size_c * size_h * size_w / P, side_P);
  dm_out(cfg, 1, size_c, (w_tiles * DATAMOVER_BANDWIDTH_ELEMS) / side_P);
  dm_out(cfg, 2, DATAMOVER_BANDWIDTH_ELEMS, c_tiles);
  dm_out(cfg, 3, size_c * size_h * size_w / side_P, side_P);
  dm_out(cfg, 4, size_c * size_w / side_P, 0);
  dm_in(cfg, 4, 0, 0);
  cfg->matrix_dim = dm_matrix_dim(size_w, size_h);
  dm_channels(cfg, size_c * size_h * size_w, size_c);
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
  dm_in(cfg, 0, size_c * size_h * size_w / P, side_P);
  dm_in(cfg, 1, size_c, (w_tiles * DATAMOVER_BANDWIDTH_ELEMS) / side_P);
  dm_in(cfg, 2, DATAMOVER_BANDWIDTH_ELEMS, c_tiles);
  dm_in(cfg, 3, size_c * size_h * size_w / side_P, side_P);
  dm_out(cfg, 0, size_h * size_w, c_tiles * DATAMOVER_BANDWIDTH_ELEMS);
  dm_out(cfg, 1, DATAMOVER_BANDWIDTH_ELEMS, w_tiles);
  dm_out(cfg, 2, size_w, size_h);
  dm_out(cfg, 3, 0, 0);
  dm_out(cfg, 4, 0, 0);
  dm_in(cfg, 4, size_c * size_w / side_P, 0);
  cfg->matrix_dim = dm_matrix_dim(size_w, size_h);
  dm_channels(cfg, size_c * size_h * size_w, size_c);
  cfg->ctrl_engine      = dm_ctrl_engine(DATAMOVER_FOLD, 0x3, 0xF, DATAMOVER_TRANSP_1ELEM);
}

// CIM layout: (C, pixels) in 64-pixel blocks -> (4N, C) in 64-column blocks, channels
// [c_off, c_off + c_len). c_len is a multiple of BANDWIDTH_ELEMS, or the leftover below it:
// the last block then has a row pitch of c_len.
static inline __attribute__((always_inline)) void datamover_build_unfold_cim(datamover_cfg_t *cfg, const void *in, const void *out,
                                              uint32_t size_c, uint32_t size_h, uint32_t size_w,
                                              uint32_t c_off, uint32_t c_len) {
  const uint32_t BWE = DATAMOVER_BANDWIDTH_ELEMS;
  uint32_t n_tok  = size_h * size_w / DATAMOVER_UNFOLD_PATCH;
  uint32_t blocks = size_h * size_w / BWE;
  uint32_t tiles  = dm_ceil_div(c_len, BWE);
  uint32_t pitch  = (c_len < BWE) ? c_len : BWE;

  cfg->in_ptr           = (uint32_t)(uintptr_t)in + c_off * BWE;
  cfg->out_ptr          = (uint32_t)(uintptr_t)out + c_off * n_tok * DATAMOVER_UNFOLD_PATCH;
  cfg->tot_len          = tiles * blocks * BWE;
  dm_in(cfg, 0, BWE, BWE);
  dm_in(cfg, 1, size_c * BWE, blocks);
  dm_in(cfg, 2, BWE * BWE, tiles);
  dm_in(cfg, 3, 0, 0);
  dm_out(cfg, 0, n_tok * pitch, 2);
  dm_out(cfg, 1, pitch, size_w / 2);
  dm_out(cfg, 2, 2 * n_tok * pitch, 2);
  dm_out(cfg, 3, (size_w / 2) * pitch, size_h / 2);
  dm_out(cfg, 4, DATAMOVER_UNFOLD_PATCH * n_tok * BWE, 0);
  dm_in(cfg, 4, 0, 0);
  cfg->matrix_dim = dm_matrix_dim(BWE, tiles * blocks);
  dm_channels(cfg, pitch * size_h * size_w, pitch);
  cfg->ctrl_engine      = dm_ctrl_engine(DATAMOVER_UNFOLD, 0xF, 0x3, DATAMOVER_TRANSP_1ELEM);
}

// Inverse of datamover_build_unfold_cim.
static inline __attribute__((always_inline)) void datamover_build_fold_cim(datamover_cfg_t *cfg, const void *in, const void *out,
                                            uint32_t size_c, uint32_t size_h, uint32_t size_w,
                                            uint32_t c_off, uint32_t c_len) {
  const uint32_t BWE = DATAMOVER_BANDWIDTH_ELEMS;
  uint32_t n_tok  = size_h * size_w / DATAMOVER_UNFOLD_PATCH;
  uint32_t blocks = size_h * size_w / BWE;
  uint32_t tiles  = dm_ceil_div(c_len, BWE);
  uint32_t pitch  = (c_len < BWE) ? c_len : BWE;

  cfg->in_ptr           = (uint32_t)(uintptr_t)in + c_off * n_tok * DATAMOVER_UNFOLD_PATCH;
  cfg->out_ptr          = (uint32_t)(uintptr_t)out + c_off * BWE;
  cfg->tot_len          = tiles * blocks * BWE;
  dm_in(cfg, 0, n_tok * pitch, 2);
  dm_in(cfg, 1, pitch, size_w / 2);
  dm_in(cfg, 2, 2 * n_tok * pitch, 2);
  dm_in(cfg, 3, (size_w / 2) * pitch, size_h / 2);
  dm_out(cfg, 0, BWE, BWE);
  dm_out(cfg, 1, size_c * BWE, blocks);
  dm_out(cfg, 2, BWE * BWE, tiles);
  dm_out(cfg, 3, 0, 0);
  dm_out(cfg, 4, 0, 0);
  dm_in(cfg, 4, DATAMOVER_UNFOLD_PATCH * n_tok * BWE, 0);
  cfg->matrix_dim = dm_matrix_dim(BWE, tiles * blocks);
  dm_channels(cfg, pitch * size_h * size_w, pitch);
  cfg->ctrl_engine      = dm_ctrl_engine(DATAMOVER_FOLD, 0x3, 0xF, DATAMOVER_TRANSP_1ELEM);
}

// Tensor (C,H,W) -> im2col matrix (Kh*Kw*C, H_out*W_out); row = ci*Kh*Kw+kh*Kw+kw, col = oh*W_out+ow.
// conv_stride applies to both spatial dims. Three paths:
// - CIM in, COL_CIM out: the im2col unit, 3x3 with a 1-pixel border, stride 1, W in 8..64.
// - CHW in, stride 2, w_out above 32: the im2col unit merges two half beats; COL_CIM needs
//   w_out a multiple of 64, COL takes the leftover columns in a second job.
// - CHW in, COL out: pass-through, beats of w_out pixels, no pad.
static inline __attribute__((always_inline)) void datamover_build_im2col(datamover_cfg_t *cfg, const void *in, const void *out,
                                          uint32_t size_c, uint32_t size_h, uint32_t size_w,
                                          uint32_t kernel_h, uint32_t kernel_w, uint32_t conv_stride, uint32_t pad,
                                          datamover_im2col_in_t in_layout, datamover_im2col_out_t out_layout) {
  const uint32_t Kh = kernel_h;
  const uint32_t Kw = kernel_w;
  const uint32_t S = conv_stride;
  const uint32_t BWE = DATAMOVER_BANDWIDTH_ELEMS;
  uint32_t h_out = (size_h + 2 * pad - Kh) / S + 1;
  uint32_t w_out = (size_w + 2 * pad - Kw) / S + 1;
  uint32_t row_bytes = h_out * w_out;

  cfg->in_ptr     = (uint32_t)(uintptr_t)in;
  cfg->out_ptr    = (uint32_t)(uintptr_t)out;
  cfg->matrix_dim = dm_matrix_dim(w_out, h_out);

  if (in_layout == DATAMOVER_IM2COL_IN_CIM) {
    uint32_t blocks = size_h * size_w / BWE;
    cfg->tot_len          = size_c * blocks;
    cfg->out_tot_len      = Kh * Kw * size_c * blocks;
    dm_in(cfg, 0, size_c * BWE, blocks);
    dm_in(cfg, 1, BWE, size_c);
    dm_in(cfg, 2, 0, 0);
    dm_in(cfg, 3, 0, 0);
    dm_out(cfg, 0, BWE, Kw);
    dm_out(cfg, 1, Kw * BWE, Kh);
    dm_out(cfg, 2, 0, 1);
    dm_out(cfg, 3, Kh * Kw * size_c * BWE, blocks);
    dm_out(cfg, 4, Kh * Kw * BWE, 0);
  dm_in(cfg, 4, 0, 0);
    dm_channels(cfg, Kh * Kw * size_c * blocks * BWE, size_c);
    cfg->ctrl_engine      = dm_ctrl_engine(DATAMOVER_IM2COL, 0xF, 0x1, DATAMOVER_TRANSP_NONE)
                          | DATAMOVER_FIELD(DM_CTRL_ENGINE, CONV_STRIDE, 1)
                          | DATAMOVER_FIELD(DM_CTRL_ENGINE, IM2COL_PACK, 1)
                          | DATAMOVER_FIELD(DM_CTRL_ENGINE, IM2COL_LOG2W, dm_log2(size_w));
    return;
  }

  if (S == 2 && w_out > BWE / 2) {
    uint32_t w_blocks = (w_out < BWE) ? 1 : w_out / BWE;
    cfg->tot_len          = 2 * w_blocks * h_out * Kh * Kw * size_c;
    cfg->out_tot_len      = w_blocks * h_out * Kh * Kw * size_c;
    dm_in(cfg, 0, BWE, 2 * w_blocks);
    dm_in(cfg, 1, S * size_w, h_out);
    dm_in(cfg, 2, 1, Kw);
    dm_in(cfg, 3, size_w, Kh);
    if (out_layout == DATAMOVER_IM2COL_OUT_COL_CIM) {
      dm_out(cfg, 0, Kh * Kw * size_c * BWE, w_blocks);
      dm_out(cfg, 1, Kh * Kw * size_c * BWE * w_blocks, h_out);
      dm_out(cfg, 2, BWE, Kw);
      dm_out(cfg, 3, Kw * BWE, Kh);
      dm_out(cfg, 4, Kh * Kw * BWE, 0);
  dm_in(cfg, 4, size_h * size_w, 0);
    } else {
      dm_out(cfg, 0, BWE, w_blocks);
      dm_out(cfg, 1, w_out, h_out);
      dm_out(cfg, 2, row_bytes, Kw);
      dm_out(cfg, 3, Kw * row_bytes, Kh);
      dm_out(cfg, 4, Kh * Kw * row_bytes, 0);
  dm_in(cfg, 4, size_h * size_w, 0);
    }
    dm_channels(cfg, Kh * Kw * size_c * BWE * w_blocks * h_out, size_c);
    cfg->ctrl_engine      = dm_ctrl_engine(DATAMOVER_IM2COL, 0xF, 0xF, DATAMOVER_TRANSP_NONE)
                          | DATAMOVER_FIELD(DM_CTRL_ENGINE, CONV_STRIDE, S)
                          | DATAMOVER_FIELD(DM_CTRL_ENGINE, IM2COL_PACK, 1);
    return;
  }

  if (w_out < BWE) {
    uint32_t tot_len      = h_out * Kh * Kw * size_c;
    cfg->tot_len          = tot_len;
    dm_in(cfg, 0, S * size_w, h_out);
    dm_in(cfg, 1, 1, Kw);
    dm_in(cfg, 2, size_w, Kh);
    dm_in(cfg, 3, size_h * size_w, size_c);
    dm_out(cfg, 0, w_out, h_out);
    dm_out(cfg, 1, row_bytes, Kw);
    dm_out(cfg, 2, Kw * row_bytes, Kh);
    dm_out(cfg, 3, Kh * Kw * row_bytes, size_c);
    dm_out(cfg, 4, 0, 0);
  dm_in(cfg, 4, 0, 0);
    dm_channels(cfg, tot_len * BWE, size_c);
    cfg->ctrl_engine      = dm_ctrl_engine(DATAMOVER_IM2COL, 0x7, 0x7, DATAMOVER_TRANSP_NONE)
                          | DATAMOVER_FIELD(DM_CTRL_ENGINE, CONV_STRIDE, S);
  } else {
    uint32_t w_tiles      = w_out / BWE;
    uint32_t tot_len      = w_tiles * h_out * Kh * Kw * size_c;
    cfg->tot_len          = tot_len;
    dm_in(cfg, 0, BWE, w_tiles);
    dm_in(cfg, 1, S * size_w, h_out);
    dm_in(cfg, 2, 1, Kw);
    dm_in(cfg, 3, size_w, Kh);
    dm_out(cfg, 0, BWE, w_tiles);
    dm_out(cfg, 1, w_out, h_out);
    dm_out(cfg, 2, row_bytes, Kw);
    dm_out(cfg, 3, Kw * row_bytes, Kh);
    dm_out(cfg, 4, Kh * Kw * row_bytes, 0);
  dm_in(cfg, 4, size_h * size_w, 0);
    dm_channels(cfg, Kh * Kw * size_c * row_bytes, size_c);
    cfg->ctrl_engine      = dm_ctrl_engine(DATAMOVER_IM2COL, 0xF, 0xF, DATAMOVER_TRANSP_NONE)
                          | DATAMOVER_FIELD(DM_CTRL_ENGINE, CONV_STRIDE, S);
  }
}

static inline __attribute__((always_inline)) uint32_t datamover_build_im2col_leftover(datamover_cfg_t *cfg, const void *in, const void *out,
                                          uint32_t size_c, uint32_t size_h, uint32_t size_w,
                                          uint32_t kernel_h, uint32_t kernel_w, uint32_t conv_stride, uint32_t pad) {
  const uint32_t Kh = kernel_h;
  const uint32_t Kw = kernel_w;
  const uint32_t S = conv_stride;
  const uint32_t BWE = DATAMOVER_BANDWIDTH_ELEMS;
  uint32_t h_out = (size_h + 2 * pad - Kh) / S + 1;
  uint32_t w_out = (size_w + 2 * pad - Kw) / S + 1;
  if (pad != 0 || w_out < BWE) return 0;
  uint32_t w_full = (w_out / BWE) * BWE;
  uint32_t w_len  = w_out - w_full;
  if (w_len == 0) return 0;
  uint32_t row_bytes = h_out * w_out;
  uint32_t tot_len   = h_out * Kh * Kw * size_c;

  cfg->in_ptr           = (uint32_t)(uintptr_t)in  + w_full * S;
  cfg->out_ptr          = (uint32_t)(uintptr_t)out + w_full;
  if (S == 2 && w_len > BWE / 2) {
    cfg->tot_len          = 2 * tot_len;
    cfg->out_tot_len      = tot_len;
    dm_in(cfg, 0, BWE, 2);
    dm_in(cfg, 1, S * size_w, h_out);
    dm_in(cfg, 2, 1, Kw);
    dm_in(cfg, 3, size_w, Kh);
    dm_out(cfg, 0, w_out, h_out);
    dm_out(cfg, 1, row_bytes, Kw);
    dm_out(cfg, 2, Kw * row_bytes, Kh);
    dm_out(cfg, 3, Kh * Kw * row_bytes, size_c);
    dm_out(cfg, 4, 0, 0);
  dm_in(cfg, 4, size_h * size_w, 0);
    cfg->matrix_dim = dm_matrix_dim(w_len, h_out);
    dm_channels(cfg, tot_len * BWE, size_c);
    cfg->ctrl_engine      = dm_ctrl_engine(DATAMOVER_IM2COL, 0xF, 0xF, DATAMOVER_TRANSP_NONE)
                          | DATAMOVER_FIELD(DM_CTRL_ENGINE, CONV_STRIDE, S)
                          | DATAMOVER_FIELD(DM_CTRL_ENGINE, IM2COL_PACK, 1);
    return 1;
  }
  cfg->tot_len          = tot_len;
  dm_in(cfg, 0, S * size_w, h_out);
  dm_in(cfg, 1, 1, Kw);
  dm_in(cfg, 2, size_w, Kh);
  dm_in(cfg, 3, size_h * size_w, size_c);
  dm_out(cfg, 0, w_out, h_out);
  dm_out(cfg, 1, row_bytes, Kw);
  dm_out(cfg, 2, Kw * row_bytes, Kh);
  dm_out(cfg, 3, Kh * Kw * row_bytes, size_c);
  dm_out(cfg, 4, 0, 0);
  dm_in(cfg, 4, 0, 0);
  cfg->matrix_dim = dm_matrix_dim(w_len, h_out);
  dm_channels(cfg, tot_len * BWE, size_c);
  cfg->ctrl_engine      = dm_ctrl_engine(DATAMOVER_IM2COL, 0x7, 0x7, DATAMOVER_TRANSP_NONE)
                        | DATAMOVER_FIELD(DM_CTRL_ENGINE, CONV_STRIDE, S);
  return 1;
}

// im2row for non-overlapping patches (stride == patch): one row per patch, in CIM layout.
// HWC with 48-byte patch rows takes three jobs: four rows span three blocks, so
// rows 1 and 2 split at the block boundary.
static inline __attribute__((always_inline)) void datamover_build_im2row(datamover_cfg_t *cfg, const void *in, const void *out,
                                          uint32_t size_c, uint32_t size_h, uint32_t size_w, uint32_t patch,
                                          datamover_im2col_in_t in_layout, uint32_t job) {
  const uint32_t BWE = DATAMOVER_BANDWIDTH_ELEMS;
  uint32_t n_w = size_w / patch, n_h = size_h / patch, n_tok = n_w * n_h;
  uint32_t blk = n_tok * BWE;

  if (in_layout == DATAMOVER_IM2COL_IN_CHW) {
    uint32_t rpb = BWE / patch;
    cfg->in_ptr      = (uint32_t)(uintptr_t)in;
    cfg->out_ptr     = (uint32_t)(uintptr_t)out;
    cfg->tot_len     = size_c * size_h * size_w / patch;
    dm_in(cfg, 0, size_w, rpb);
    dm_in(cfg, 1, rpb * size_w, patch / rpb);
    dm_in(cfg, 2, patch, n_w);
    dm_in(cfg, 3, patch * size_w, n_h);
    dm_out(cfg, 0, patch, rpb);
    dm_out(cfg, 1, blk, patch / rpb);
    dm_out(cfg, 2, BWE, n_w);
    dm_out(cfg, 3, BWE * n_w, n_h);
    dm_out(cfg, 4, (patch * patch / BWE) * blk, 0);
  dm_in(cfg, 4, size_h * size_w, 0);
    cfg->matrix_dim = dm_matrix_dim(patch, n_tok);
    cfg->ctrl_engine = dm_ctrl_engine(DATAMOVER_IM2COL, 0xF, 0xF, DATAMOVER_TRANSP_NONE);
  } else {
    uint32_t pitch = size_w * size_c;
    uint32_t run, in_off, out_off, d0_in, d0_out;
    switch (job) {
      case 0:  run = 48; in_off = 0;          out_off = 0;   d0_in = 3 * pitch;  d0_out = 2 * blk + 16; break;
      case 1:  run = 16; in_off = pitch;      out_off = 48;  d0_in = pitch + 32; d0_out = 2 * blk - 48; break;
      default: run = 32; in_off = pitch + 16; out_off = blk; d0_in = pitch - 16; d0_out = 32;           break;
    }
    cfg->in_ptr      = (uint32_t)(uintptr_t)in + in_off;
    cfg->out_ptr     = (uint32_t)(uintptr_t)out + out_off;
    cfg->tot_len     = 2 * (patch / 4) * n_tok;
    dm_in(cfg, 0, d0_in, 2);
    dm_in(cfg, 1, 4 * pitch, patch / 4);
    dm_in(cfg, 2, 48, n_w);
    dm_in(cfg, 3, patch * pitch, n_h);
    dm_out(cfg, 0, d0_out, 2);
    dm_out(cfg, 1, 3 * blk, patch / 4);
    dm_out(cfg, 2, BWE, n_w);
    dm_out(cfg, 3, BWE * n_w, n_h);
    dm_out(cfg, 4, 0, 0);
  dm_in(cfg, 4, 0, 0);
    cfg->matrix_dim = dm_matrix_dim(run, n_tok);
    cfg->ctrl_engine = dm_ctrl_engine(DATAMOVER_IM2COL, 0x7, 0x7, DATAMOVER_TRANSP_NONE);
  }
  dm_channels(cfg, cfg->tot_len * BWE, size_c);
  cfg->ctrl_engine |= DATAMOVER_FIELD(DM_CTRL_ENGINE, CONV_STRIDE, 1);
}

#endif // __DATAMOVER_CONFIG_H__
