// Copyright 2023 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Authors: Cyrill Durrer <cdurrer@iis.ee.ethz.ch>
//          Daniel Keller <dankeller@iis.ee.ethz.ch>
//          Sergio Mazzola <smazzola@iis.ee.ethz.ch>

#include <stdint.h>
#include <stdio.h>
#include <inttypes.h>

#include "snrt.h"
#include "konark_cluster_raw_addrmap.h"

#include "konark/hal_datamover.h"
#include "konark/hal_konark.h"

#include "data.h"

#define VERBOSE 1
#if VERBOSE
#include "printf.h"
#endif

#define P 4   // Unfold patch size (number of elements in a patch) for datamover_unfold

static inline int datamover_compare_int (uint64_t *actual, uint64_t *golden, int total_bytes) {
  int errors = 0;
  int len = (int)(total_bytes / 8);  // Number of complete uint64_t words
  int remaining_elements = total_bytes % 8;

  printf("[DM-INFO] Comparing %d 64b-words + %d 8b-elements:\n", len, remaining_elements);
  for (int i=0; i<len; i++) {
    uint64_t actual_ = *(actual+i);
    uint64_t golden_ = *(golden+i);
    if (actual_ != golden_) {
      printf("ERROR! 0x%" PRIx64 " (golden) @ %p != 0x%" PRIx64 " (actual) @ %p (%d)\n", golden_, (void *)(golden+i), actual_, (void *)(actual+i), i);
      errors ++;
    }
    // else {
    //   printf("OK:    0x%" PRIx64 " (golden) @ %p <- 0x%" PRIx64 " (actual) @ %p (%d)\n", golden_, (void *)(golden+i), actual_, (void *)(actual+i), i);
    // }
    // #ifdef VERBOSE
    // printf("  0x%" PRIx64 " <- 0x%" PRIx64 " @ %p (%d)\n", golden_, actual_, (void *)(actual+i), i);
    // #endif
  }
  if (remaining_elements > 0) {
    for (int i=0; i<remaining_elements; i++) {
      uint8_t actual_ = *((uint8_t*)actual + len * 8 + i);
      uint8_t golden_ = *((uint8_t*)golden + len * 8 + i);
      // printf("  0x%" PRIx8 " (golden) @ %p <- 0x%" PRIx8 " (actual) @ %p (%d)\n", golden_, (void *)((uint8_t*)golden + len * 8 + i), actual_, (void *)((uint8_t*)actual + len * 8 + i), len * 8 + i);
      if (actual_ != golden_) {
        printf("ERROR! 0x%" PRIx8 " (golden) != 0x%" PRIx8 " (actual) @ %p (%d)\n", golden_, actual_, (void *)((uint8_t*)actual + len * 8 + i), len * 8 + i);
        errors ++;
      }
      // else {
      //   printf("OK:    0x%" PRIx8 " (golden) <- 0x%" PRIx8 " (actual) @ %p (%d)\n", golden_, actual_, (void *)((uint8_t*)actual + len * 8 + i), len * 8 + i);
      // }
      // #ifdef VERBOSE
      // printf("  0x%" PRIx8 " <- 0x%" PRIx8 " @ %p (%d)\n", golden_, actual_, (void *)((uint8_t*)actual + len * 8 + i), len * 8 + i);
      // #endif
    }
  }
  return errors;
}


int main() {
  if (snrt_cluster_idx() > 0) return 0;

  const uint32_t TOT_SIZE = SIZE_C * SIZE_M * SIZE_N;
  datamover_status_t datamover_status;
  int errors = 0;
  datamover_transp_mode_t transp_mode = DATAMOVER_TRANSP_NONE;

  switch (TRANSP_MODE) {
    case 1:
      transp_mode = DATAMOVER_TRANSP_1ELEM;
      break;
    case 2:
      transp_mode = DATAMOVER_TRANSP_2ELEM;
      break;
    case 4:
      transp_mode = DATAMOVER_TRANSP_4ELEM;
      break;
    default:
      if (DATAMOVER_MODE == 1 || DATAMOVER_MODE == 3) {
        printf("[DM-ERR] Unknown DATAMOVER_TRANSPOSE_MODE=%d: Must be 1, 2, or 4\n", TRANSP_MODE);
        return -1;
      }
  }

  #if VERBOSE
  printf("[INFO] cluster = %u, core(cluster) = %u, core(global) = %u\n", snrt_cluster_idx(), snrt_cluster_core_idx(), snrt_global_core_idx());
  #endif

  // Allocate and load buffers on DMA core
  static uint8_t *local_in;
  static uint8_t *local_out;
  static uint8_t *local_gold;
  if (snrt_is_dm_core()) {
    local_in      = (uint8_t *) snrt_l1_alloc_cluster_local(TOT_SIZE, 8);   // Alignment paramter: 64: bank-aligned, 8: word-aligned
    local_out     = (uint8_t *) snrt_l1_alloc_cluster_local(TOT_SIZE, 8);
    local_gold    = (uint8_t *) snrt_l1_alloc_cluster_local(TOT_SIZE, 8);

    printf("[DM-INFO] Allocated L1 buffers: local_in=%p, local_out=%p, local_gold=%p\n", local_in, local_out, local_gold);

    // Move DMA input and expected goldens into TCDM
    snrt_dma_start_1d(local_in,    golden_in,   TOT_SIZE);
    snrt_dma_start_1d(local_gold,  golden_out,  TOT_SIZE);
    snrt_dma_wait_all();

    // Initialize output buffer with dummy value
    for(int i=0; i<TOT_SIZE/8; i++) {
      ((uint64_t*)local_out)[i] = 0xDEADBEEFDEADBEEF;  // Initialize output buffer with dummy value (Functionally not necessary, but helps to identify issues with uninitialized buffers)
    }
  }
  // Sync all cores
  snrt_cluster_hw_barrier();

  // Configure HWPE Datamover (only from core 0)
  if (snrt_cluster_core_idx() == 0) {
    int timeout = 5000000;

    konark_datamover_init();

    switch (DATAMOVER_MODE) {
      case 0:
        printf("[DM-INFO] Starting Datamover COPY operation of %ux%u = %u elements\n", SIZE_M, SIZE_N, TOT_SIZE);
        datamover_status = datamover_copy_blocking(local_in, local_out, SIZE_M, SIZE_N, timeout);
        break;
      case 1:
        printf("[DM-INFO] Starting Datamover TRANSPOSE (%u elements) operation of %ux%u tensor\n", transp_mode, SIZE_M, SIZE_N);
        datamover_status = datamover_transpose_blocking(local_in, local_out, SIZE_M, SIZE_N, transp_mode, timeout);
        break;
      case 2:
        switch (CIM_MODE) {
          case 0:
            printf("[DM-INFO] Starting Datamover CIM LAYOUT operation of %ux%u tensor (row tile size = %u)\n", SIZE_M, SIZE_N, ROW_TILE_SIZE);
            datamover_status = datamover_cim_layout_blocking(local_in, local_out, SIZE_M, SIZE_N, ROW_TILE_SIZE, timeout);
            break;
          case 1:
            printf("[DM-INFO] Starting Datamover CIM REVERSE LAYOUT operation of %ux%u tensor (inner dimension = %u)\n", SIZE_M, SIZE_N, ROW_TILE_SIZE);
            datamover_status = datamover_cim_layout_reverse_blocking(local_in, local_out, SIZE_M, SIZE_N, ROW_TILE_SIZE, timeout);
            break;
          default:
            printf("[DM-ERR] Unknown CIM_MODE=%d: Must be 0 (CHW->CIM-layout) or 1 (CIM-layout->CHW)\n", CIM_MODE);
        }
        break;
      case 3:
        printf("[DM-INFO] Starting Datamover CIM LAYOUT + TRANSPOSE (%u elements) operation of %ux%u (CONVERTED DIMENSIONS) tensor (CIM inner dimension = %u)\n", transp_mode, SIZE_M, SIZE_N, ROW_TILE_SIZE);
        datamover_status = datamover_cim_layout_transpose_blocking(local_in, local_out, SIZE_M, SIZE_N, ROW_TILE_SIZE, transp_mode, timeout);
        break;
      case 4:
        printf("[DM-INFO] Starting Datamover UNFOLD operation of %ux%ux%u tensor (CHW) (unfolded dimension = %ux%ux%u)\n", SIZE_C, SIZE_M, SIZE_N, P, SIZE_M*SIZE_N / P, SIZE_C);
        datamover_status = datamover_unfold_blocking(local_in, local_out, SIZE_C, SIZE_M, SIZE_N, timeout);
        break;
      case 5:
        printf("[DM-INFO] Starting Datamover FOLD operation of %ux%ux%u tensor (unfolded PNC) (folded dimension = %ux%ux%u)\n", P, SIZE_M*SIZE_N / P, SIZE_C, SIZE_C, SIZE_M, SIZE_N);
        datamover_status = datamover_fold_blocking(local_in, local_out, SIZE_C, SIZE_M, SIZE_N, timeout);
        break;
      default:
        printf("[DM-ERR] Unknown DATAMOVER_MODE=%d: Must be 0 (COPY), 1 (TRANSPOSE), 2 (CIM LAYOUT), 3 (CIM LAYOUT TRANSPOSE), 4 (UNFOLD), or 5 (FOLD)\n", DATAMOVER_MODE);
        return -1;
    }

    // Disable all HWPE clocks
    konark_hwpe_disable_all_clk();

    // Verification
    #if VERBOSE
    printf("[INFO] Verifying result...\n");
    #endif
    errors  = datamover_compare_int((uint64_t*)local_out,  (uint64_t*)local_gold, TOT_SIZE);
    #if VERBOSE
    if (errors == 0) {
      printf("[DM-OK] ======= DATAMOVER TEST PASSED =======\n");
      printf("  ***    ***  \n");
      printf(" ** **  ** ** \n");
      printf("  ***    ***  \n");
      printf("      /_      \n");
      printf(" ,          , \n");
      printf("  '-......-'  \n\n");
    } else {
      printf("[DM-ERR] !!!!!!! DATAMOVER TEST FAILED !!!!!!!\n");
      printf("[DM-ERR] mismatches: %d (%ux%ux%u tensor)\n", errors, SIZE_C, SIZE_M, SIZE_N);
    }
    #endif
  }

  return errors;
}
