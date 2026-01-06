/*
 * Copyright (C) 2020 ETH Zurich and University of Bologna
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 * Authors:  Francesco Conti <f.conti@unibo.it>
 */

#include <stdio.h>

#ifndef __HAL_DATAMOVER_H__
#define __HAL_DATAMOVER_H__

/* REGISTER MAP */

// global address map + event IDs
#define DATAMOVER_ADDR_BASE      0x00201000
#define CLUS_CTRL_ADDR_BASE      0x00200000
#define DATAMOVER_EVT0           12
#define DATAMOVER_EVT1           13

// commands
#define DATAMOVER_COMMIT_AND_TRIGGER 0x00
#define DATAMOVER_ACQUIRE            0x04
#define DATAMOVER_FINISHED           0x08
#define DATAMOVER_STATUS             0x0c
#define DATAMOVER_RUNNING_JOB        0x10
#define DATAMOVER_SOFT_CLEAR         0x14
#define DATAMOVER_SWSYNC             0x18
#define DATAMOVER_URISCY_IMEM        0x1c

// job configuration    ToDo(cdurrer): OUTDATED! Use HAL from Konark-cluster repo!
#define DATAMOVER_REGISTER_OFFS       0x40
#define DATAMOVER_REGISTER_CXT0_OFFS  0x80
#define DATAMOVER_REGISTER_CXT1_OFFS  0x120
#define DATAMOVER_REG_IN_PTR          0x00
#define DATAMOVER_REG_OUT_PTR         0x04
#define DATAMOVER_REG_TOT_LEN         0x08
#define DATAMOVER_REG_IN_D0_LEN       0x0c
#define DATAMOVER_REG_IN_D0_STRIDE    0x10
#define DATAMOVER_REG_IN_D1_LEN       0x14
#define DATAMOVER_REG_IN_D1_STRIDE    0x18
#define DATAMOVER_REG_IN_D2_STRIDE    0x1c
#define DATAMOVER_REG_OUT_D0_LEN      0x20
#define DATAMOVER_REG_OUT_D0_STRIDE   0x24
#define DATAMOVER_REG_OUT_D1_LEN      0x28
#define DATAMOVER_REG_OUT_D1_STRIDE   0x2c
#define DATAMOVER_REG_OUT_D2_STRIDE   0x30

// cluster controller register offset and bits
#define CLUS_CTRL_DATAMOVER_OFFS              0x18
#define CLUS_CTRL_DATAMOVER_CG_EN_MASK        0x800
#define CLUS_CTRL_DATAMOVER_HCI_PRIO_MASK     0x100
#define CLUS_CTRL_DATAMOVER_HCI_MAXSTALL_MASK 0xff

// others
#define DATAMOVER_COMMIT_CMD  1
#define DATAMOVER_TRIGGER_CMD 0
#define DATAMOVER_SOFT_CLEAR_ALL   0
#define DATAMOVER_SOFT_CLEAR_STATE 1

/* LOW-LEVEL HAL */
// For all the following functions we use __builtin_pulp_OffsetedWrite and __builtin_pulp_OffsetedRead
// instead of classic load/store because otherwise the compiler is not able to correctly factorize
// the DATAMOVER base in case several accesses are done, ending up with twice more code
#if defined(__riscv__) && !defined(RV_ISA_RV32)
  #define DATAMOVER_WRITE_CMD(offset, value)        __builtin_pulp_OffsetedWrite(value, (int volatile *)(DATAMOVER_ADDR_BASE), offset)
  #define DATAMOVER_WRITE_CMD_BE(offset, value, be) *(char volatile *)(DATAMOVER_ADDR_BASE + offset + be) = value
  // #define DATAMOVER_READ_CMD(offset)                (__builtin_pulp_OffsetedRead(*(int volatile *)(DATAMOVER_ADDR_BASE), offset))
  #define DATAMOVER_READ_CMD(ret, offset)           ret = (*(int volatile *)(DATAMOVER_ADDR_BASE + offset))

  #define DATAMOVER_WRITE_REG(offset, value)        __builtin_pulp_OffsetedWrite(value, (int volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_REGISTER_OFFS), offset)
  #define DATAMOVER_WRITE_REG_BE(offset, value, be) *(char volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_REGISTER_OFFS + offset + be) = value
  // #define DATAMOVER_READ_REG(offset)                (__builtin_pulp_OffsetedRead(*(int volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_REGISTER_OFFS), offset))
  #define DATAMOVER_READ_REG(ret, offset)           ret = (*(int volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_REGISTER_OFFS + offset))

  #define DATAMOVER_WRITE_REG_CXT0(offset, value)        __builtin_pulp_OffsetedWrite(value, (int volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_REGISTER_CXT0_OFFS), offset)
  #define DATAMOVER_WRITE_REG_CXT0_BE(offset, value, be) *(char volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_REGISTER_CXT0_OFFS + offset + be) = value
  #define DATAMOVER_READ_REG_CXT0(offset)                (__builtin_pulp_OffsetedRead(*(int volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_REGISTER_CXT0_OFFS), offset))

  #define DATAMOVER_WRITE_REG_CXT1(offset, value)        __builtin_pulp_OffsetedWrite(value, (int volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_REGISTER_CXT1_OFFS), offset)
  #define DATAMOVER_WRITE_REG_CXT1_BE(offset, value, be) *(char volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_REGISTER_CXT1_OFFS + offset + be) = value
  #define DATAMOVER_READ_REG_CXT1(offset)                (__builtin_pulp_OffsetedRead(*(int volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_REGISTER_CXT1_OFFS), offset))
#else
  #define DATAMOVER_WRITE_CMD(offset, value)        *(int volatile *)(DATAMOVER_ADDR_BASE + offset) = value
  #define DATAMOVER_WRITE_CMD_BE(offset, value, be) *(char volatile *)(DATAMOVER_ADDR_BASE + offset + be) = value
  #define DATAMOVER_READ_CMD(ret, offset)           ret = (*(int volatile *)(DATAMOVER_ADDR_BASE + offset))

  #define DATAMOVER_WRITE_REG(offset, value)        *(int volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_REGISTER_OFFS + offset) = value
  #define DATAMOVER_WRITE_REG_BE(offset, value, be) *(char volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_REGISTER_OFFS + offset + be) = value
  #define DATAMOVER_READ_REG(ret, offset)           ret = (*(int volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_REGISTER_OFFS + offset))

  #define DATAMOVER_WRITE_REG_CXT0(offset, value)        __builtin_pulp_OffsetedWrite(value, (int volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_REGISTER_CXT0_OFFS), offset)
  #define DATAMOVER_WRITE_REG_CXT0_BE(offset, value, be) *(char volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_REGISTER_CXT0_OFFS + offset + be) = value
  #define DATAMOVER_READ_REG_CXT0(offset)                (__builtin_pulp_OffsetedRead(*(int volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_REGISTER_CXT0_OFFS), offset))

  #define DATAMOVER_WRITE_REG_CXT1(offset, value)        __builtin_pulp_OffsetedWrite(value, (int volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_REGISTER_CXT1_OFFS), offset)
  #define DATAMOVER_WRITE_REG_CXT1_BE(offset, value, be) *(char volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_REGISTER_CXT1_OFFS + offset + be) = value
  #define DATAMOVER_READ_REG_CXT1(offset)                (__builtin_pulp_OffsetedRead(*(int volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_REGISTER_CXT1_OFFS), offset))
#endif

#define DATAMOVER_CG_ENABLE()  *(volatile int*) (CLUS_CTRL_ADDR_BASE + CLUS_CTRL_DATAMOVER_OFFS) |=  CLUS_CTRL_DATAMOVER_CG_EN_MASK
#define DATAMOVER_CG_DISABLE() *(volatile int*) (CLUS_CTRL_ADDR_BASE + CLUS_CTRL_DATAMOVER_OFFS) &= ~CLUS_CTRL_DATAMOVER_CG_EN_MASK

#define DATAMOVER_SETPRIORITY_CORE() *(volatile int*) (CLUS_CTRL_ADDR_BASE + CLUS_CTRL_DATAMOVER_OFFS) &= ~CLUS_CTRL_DATAMOVER_HCI_PRIO_MASK
#define DATAMOVER_SETPRIORITY_DATAMOVER() *(volatile int*) (CLUS_CTRL_ADDR_BASE + CLUS_CTRL_DATAMOVER_OFFS) |=  CLUS_CTRL_DATAMOVER_HCI_PRIO_MASK

#define DATAMOVER_RESET_MAXSTALL()  *(volatile int*) (CLUS_CTRL_ADDR_BASE + CLUS_CTRL_DATAMOVER_OFFS) &= ~CLUS_CTRL_DATAMOVER_HCI_MAXSTALL_MASK
#define DATAMOVER_SET_MAXSTALL(val) *(volatile int*) (CLUS_CTRL_ADDR_BASE + CLUS_CTRL_DATAMOVER_OFFS) |=  (val & CLUS_CTRL_DATAMOVER_HCI_MAXSTALL_MASK)

#define DATAMOVER_BARRIER_NOSTATUS()      eu_evt_maskWaitAndClr (1 << DATAMOVER_EVT0)
#define DATAMOVER_BARRIER()               do { eu_evt_maskWaitAndClr (1 << DATAMOVER_EVT0); } while((*(int volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_STATUS)) != 0)
#define DATAMOVER_BUSYWAIT()              do {                                         } while((*(int volatile *)(DATAMOVER_ADDR_BASE + DATAMOVER_STATUS)) != 0)
#define DATAMOVER_BARRIER_ACQUIRE(job_id) job_id = DATAMOVER_READ_CMD(job_id, DATAMOVER_ACQUIRE); \
                                     while(job_id < 0) { eu_evt_maskWaitAndClr (1 << DATAMOVER_EVT0); DATAMOVER_READ_CMD(job_id, DATAMOVER_ACQUIRE); };

/* UTILITY FUNCTIONS */
int DATAMOVER_compare_int(uint32_t *actual_y, uint32_t *golden_y, int len) {
  uint32_t actual_word = 0;
  uint32_t golden_word = 0;
  uint32_t actual = 0;
  uint32_t golden = 0;

  int errors = 0;
  int non_zero_values = 0;

  for (int i=0; i<len; i++) {
    actual_word = *(actual_y+i);
    golden_word = *(golden_y+i);

    int error = (int) (actual_word != golden_word);
    errors += (int) (actual_word != golden_word);
#ifndef NVERBOSE
    if(error) {
      if(errors==1) printf("  golden     <- actual     @ address    @ index\n");
      printf("  0x%08x <- 0x%08x @ 0x%08x @ 0x%08x\n", golden_word, actual_word, (actual_y+i), i*4);
    }
#endif /* NVERBOSE */
  }
  return errors;
}

#endif /* __HAL_DATAMOVER_H__ */
