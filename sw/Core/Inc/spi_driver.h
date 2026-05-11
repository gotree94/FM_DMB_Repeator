/**
 * @file    spi_driver.h
 * @brief   SPI Communication Driver for FPGA Control
 *
 * HAL-based SPI2 driver (Mode 0, CPOL=0, CPHA=0, 12.5 MHz)
 * 32-bit frame protocol: [CMD:8][ADDR:8][DATA:16]
 */

#ifndef SPI_DRIVER_H
#define SPI_DRIVER_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/*============================================================================
 * SPI Protocol Definitions
 *============================================================================*/
#define SPI_CMD_READ        0x01U   /* Read FPGA register */
#define SPI_CMD_WRITE       0x02U   /* Write FPGA register */
#define SPI_FRAME_SIZE      4U      /* 32-bit frame (4 bytes) */
#define SPI_TIMEOUT_MS      100U    /* SPI transaction timeout */

/* SPI chip select (software controlled) */
#define SPI_CS_PORT         GPIOD
#define SPI_CS_PIN          GPIO_PIN_7

/*============================================================================
 * Public API
 *============================================================================*/

/**
 * @brief  Initialize SPI2 peripheral and GPIO
 * @note   Configures SPI2: Master, Mode 0, 12.5 MHz, 8-bit
 *         Configures CS pin (PD7) as push-pull output
 * @retval HAL_StatusTypeDef: HAL_OK on success
 */
HAL_StatusTypeDef spi_init(void);

/**
 * @brief  Read a 16-bit FPGA register
 * @param  addr  Register address (8-bit)
 * @param  value Pointer to store read value
 * @retval HAL_OK on success, HAL_ERROR/HAL_TIMEOUT on failure
 */
HAL_StatusTypeDef spi_read_reg(uint8_t addr, uint16_t *value);

/**
 * @brief  Write a 16-bit FPGA register
 * @param  addr  Register address (8-bit)
 * @param  value Data to write (16-bit)
 * @retval HAL_OK on success, HAL_ERROR/HAL_TIMEOUT on failure
 */
HAL_StatusTypeDef spi_write_reg(uint8_t addr, uint16_t value);

/**
 * @brief  Burst read consecutive FPGA registers
 * @param  start_addr  Starting address
 * @param  buffer      Output buffer (16-bit words)
 * @param  count       Number of registers to read
 * @retval HAL_OK on success
 */
HAL_StatusTypeDef spi_burst_read(uint8_t start_addr, uint16_t *buffer, uint8_t count);

/**
 * @brief  Burst write consecutive FPGA registers
 * @param  start_addr  Starting address
 * @param  buffer      Input buffer (16-bit words)
 * @param  count       Number of registers to write
 * @retval HAL_OK on success
 */
HAL_StatusTypeDef spi_burst_write(uint8_t start_addr, const uint16_t *buffer, uint8_t count);

/**
 * @brief  Convenience: Set FPGA NCO frequency for FM/DMB channel
 * @param  is_dmb  false=FM, true=DMB
 * @param  channel Channel index (0~39 for FM, 0~5 for DMB)
 * @param  freq_hz NCO frequency in Hz
 * @retval HAL_OK on success
 */
HAL_StatusTypeDef spi_set_frequency(bool is_dmb, uint8_t channel, uint32_t freq_hz);

/**
 * @brief  Convenience: Set AGC parameter
 * @param  reg_addr  AGC register address (e.g., FPGA_REG_AGC_ATTACK)
 * @param  value     Parameter value (Q15 fixed-point)
 * @retval HAL_OK on success
 */
HAL_StatusTypeDef spi_set_agc_param(uint8_t reg_addr, uint16_t value);

/**
 * @brief  Check FPGA MMCM lock status
 * @retval true if MMCM is locked
 */
bool spi_check_mmcm_lock(void);

#ifdef __cplusplus
}
#endif

#endif /* SPI_DRIVER_H */
