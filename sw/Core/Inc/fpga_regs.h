/**
 * @file    fpga_regs.h
 * @brief   FPGA Register Map and NCO Frequency Macros
 *
 * Register map for repeater_top.v (256 x 16-bit registers)
 * All addresses are 8-bit, data is 16-bit.
 */

#ifndef FPGA_REGS_H
#define FPGA_REGS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*============================================================================
 * System Control Registers (0x00 - 0x0F)
 *============================================================================*/
#define FPGA_REG_SYS_CTRL       0x00U   /* System control */
#define FPGA_REG_SYS_STATUS     0x01U   /* System status */
#define FPGA_REG_FW_VERSION     0x02U   /* Firmware version */
#define FPGA_REG_FPGA_VERSION   0x03U   /* FPGA bitstream version */
#define FPGA_REG_SCRATCH        0x04U   /* Scratch register (R/W test) */
#define FPGA_REG_RESET          0x05U   /* Soft reset control */

/* System control bits */
#define SYS_CTRL_ENABLE_FM      (1U << 0)   /* Enable FM channels */
#define SYS_CTRL_ENABLE_DMB     (1U << 1)   /* Enable DMB channels */
#define SYS_CTRL_AGC_ENABLE     (1U << 2)   /* Enable AGC globally */
#define SYS_CTRL_DAC_ENABLE     (1U << 3)   /* Enable DAC output */
#define SYS_CTRL_LOOPBACK       (1U << 4)   /* Digital loopback mode */

/*============================================================================
 * AGC Global Parameters (0x40 - 0x4F)
 *============================================================================*/
#define FPGA_REG_AGC_ATTACK     0x40U   /* FM AGC attack time constant (Q15) */
#define FPGA_REG_AGC_RELEASE    0x41U   /* FM AGC release time constant (Q15) */
#define FPGA_REG_AGC_REF        0x42U   /* FM AGC reference level (Q15) */
#define FPGA_REG_AGC_MU         0x43U   /* FM AGC step size (Q15) */
#define FPGA_REG_AGC_GAIN_MIN   0x44U   /* FM AGC minimum gain (Q15) */
#define FPGA_REG_AGC_GAIN_MAX   0x45U   /* FM AGC maximum gain (Q15) */
#define FPGA_REG_AGC_DMB_ATTACK 0x46U   /* DMB AGC attack (Q15) */
#define FPGA_REG_AGC_DMB_RELEASE 0x47U  /* DMB AGC release (Q15) */
#define FPGA_REG_AGC_DMB_REF    0x48U   /* DMB AGC ref (Q15) */
#define FPGA_REG_AGC_DMB_MU     0x49U   /* DMB AGC mu (Q15) */
#define FPGA_REG_AGC_DMB_GMIN   0x4AU   /* DMB AGC gain min (Q15) */
#define FPGA_REG_AGC_DMB_GMAX   0x4BU   /* DMB AGC gain max (Q15) */

/*============================================================================
 * FM Channel Frequency Registers (0x00 - 0x4F, ch0~ch39)
 * Each channel uses 2 registers: NCO_L (phase inc low), NCO_H (high)
 * Address = ch * 2
 *============================================================================*/
#define FPGA_FM_CH0_NCO_L       0x00U
#define FPGA_FM_CH0_NCO_H       0x01U
/* CH1: 0x02-0x03, CH2: 0x04-0x05, ... CH39: 0x4E-0x4F */

/*============================================================================
 * DMB Channel Frequency Registers (0x50 - 0x5B, ch0~ch5)
 * Each channel uses 2 registers: NCO_L, NCO_H
 *============================================================================*/
#define FPGA_DMB_CH0_NCO_L      0x50U
#define FPGA_DMB_CH0_NCO_H      0x51U
#define FPGA_DMB_CH1_NCO_L      0x52U
#define FPGA_DMB_CH1_NCO_H      0x53U
#define FPGA_DMB_CH2_NCO_L      0x54U
#define FPGA_DMB_CH2_NCO_H      0x55U
#define FPGA_DMB_CH3_NCO_L      0x56U
#define FPGA_DMB_CH3_NCO_H      0x57U
#define FPGA_DMB_CH4_NCO_L      0x58U
#define FPGA_DMB_CH4_NCO_H      0x59U
#define FPGA_DMB_CH5_NCO_L      0x5AU
#define FPGA_DMB_CH5_NCO_H      0x5BU

/*============================================================================
 * Monitoring Registers (0x60 - 0x66)
 *============================================================================*/
#define FPGA_REG_TEMP_RAW       0x60U   /* LM75A temperature raw (read-only) */
#define FPGA_REG_VSWR_INDEX     0x61U   /* VSWR band index (read-only) */
#define FPGA_REG_ALARM_STATUS   0x62U   /* Alarm status bits (read-only) */
#define FPGA_REG_FWD_POWER      0x63U   /* Forward power magnitude (read-only) */
#define FPGA_REG_REF_POWER      0x64U   /* Reflected power magnitude (read-only) */
#define FPGA_REG_ADC_FIFO_ST    0x65U   /* ADC FIFO status (read-only) */
#define FPGA_REG_DAC_UNDERRUN   0x66U   /* DAC underrun counters (read-only) */

/* Alarm status bits */
#define ALARM_OT                (1U << 0)   /* Over-temperature */
#define ALARM_VSWR              (1U << 1)   /* High VSWR */
#define ALARM_PA_FAULT          (1U << 2)   /* PA fault */
#define ALARM_FIFO_OVERFLOW     (1U << 3)   /* ADC FIFO overflow */
#define ALARM_DAC_UNDERRUN_FM   (1U << 4)   /* FM DAC underrun */
#define ALARM_DAC_UNDERRUN_DMB  (1U << 5)   /* DMB DAC underrun */

/*============================================================================
 * NCO Frequency Calculation Macro
 *
 * FPGA NCO: phase_increment = (freq_hz * 2^32) / clk_hz
 * Using 64-bit intermediate to avoid overflow.
 * clk_hz = 80,000,000 (system clock)
 *
 * Example:
 *   uint32_t inc = FPGA_NCO_FREQ(100000000);  // 100 MHz → 0x1999999A
 *============================================================================*/
#define FPGA_NCO_FREQ(freq_hz) \
    ((uint32_t)(((uint64_t)(freq_hz) << 32) / 80000000ULL))

/*============================================================================
 * Helper Macros
 *============================================================================*/
#define FPGA_FM_CH_NCO_L(ch)    ((uint8_t)((ch) * 2))
#define FPGA_FM_CH_NCO_H(ch)    ((uint8_t)((ch) * 2 + 1))
#define FPGA_DMB_CH_NCO_L(ch)   ((uint8_t)(0x50U + (ch) * 2))
#define FPGA_DMB_CH_NCO_H(ch)   ((uint8_t)(0x50U + (ch) * 2 + 1))

#ifdef __cplusplus
}
#endif

#endif /* FPGA_REGS_H */
