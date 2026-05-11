/**
 * @file    spi_driver.c
 * @brief   SPI Communication Driver for FPGA Control
 *
 * STM32F429: SPI2 (Mode 0, 12.5 MHz), CS on PD7
 * Protocol: 32-bit frame [CMD:8][ADDR:8][DATA:16], MSB first
 *   CMD 0x01 = READ, CMD 0x02 = WRITE
 */

#include "spi_driver.h"
#include "fpga_regs.h"
#include "stm32f4xx_hal.h"

/*============================================================================
 * Private variables
 *============================================================================*/
static SPI_HandleTypeDef hspi2;
static bool initialized = false;

/*============================================================================
 * SPI2 GPIO Configuration
 *============================================================================*/
static void spi_gpio_init(void)
{
    GPIO_InitTypeDef gpio = {0};

    /* SPI2: SCK=PB13, MISO=PB14, MOSI=PB15 */
    __HAL_RCC_SPI2_CLK_ENABLE();
    __HAL_RCC_GPIOB_CLK_ENABLE();

    gpio.Pin       = GPIO_PIN_13 | GPIO_PIN_14 | GPIO_PIN_15;
    gpio.Mode      = GPIO_MODE_AF_PP;
    gpio.Pull      = GPIO_PULLUP;
    gpio.Speed     = GPIO_SPEED_FREQ_VERY_HIGH;
    gpio.Alternate = GPIO_AF5_SPI2;
    HAL_GPIO_Init(GPIOB, &gpio);

    /* CS: PD7 (software controlled) */
    __HAL_RCC_GPIOD_CLK_ENABLE();
    gpio.Pin       = GPIO_PIN_7;
    gpio.Mode      = GPIO_MODE_OUTPUT_PP;
    gpio.Pull      = GPIO_PULLUP;
    gpio.Speed     = GPIO_SPEED_FREQ_HIGH;
    gpio.Alternate = 0;
    HAL_GPIO_Init(GPIOD, &gpio);

    /* CS de-asserted */
    HAL_GPIO_WritePin(SPI_CS_PORT, SPI_CS_PIN, GPIO_PIN_SET);
}

/*============================================================================
 * Public API
 *============================================================================*/

HAL_StatusTypeDef spi_init(void)
{
    HAL_StatusTypeDef status;

    if (initialized) {
        return HAL_OK;
    }

    spi_gpio_init();

    hspi2.Instance               = SPI2;
    hspi2.Init.Mode              = SPI_MODE_MASTER;
    hspi2.Init.Direction         = SPI_DIRECTION_2LINES;
    hspi2.Init.DataSize          = SPI_DATASIZE_8BIT;
    hspi2.Init.CLKPolarity       = SPI_POLARITY_LOW;     /* CPOL = 0 */
    hspi2.Init.CLKPhase          = SPI_PHASE_1EDGE;      /* CPHA = 0 */
    hspi2.Init.NSS               = SPI_NSS_SOFT;
    hspi2.Init.BaudRatePrescaler = SPI_BAUDRATEPRESCALER_4; /* 45 MHz / 4 = 11.25 MHz */
    hspi2.Init.FirstBit          = SPI_FIRSTBIT_MSB;
    hspi2.Init.TIMode            = SPI_TIMODE_DISABLE;
    hspi2.Init.CRCCalculation    = SPI_CRCCALCULATION_DISABLE;
    hspi2.Init.CRCPolynomial     = 7;

    status = HAL_SPI_Init(&hspi2);

    if (status == HAL_OK) {
        initialized = true;
    }

    return status;
}

HAL_StatusTypeDef spi_read_reg(uint8_t addr, uint16_t *value)
{
    uint8_t tx_buf[4];
    uint8_t rx_buf[4];
    HAL_StatusTypeDef status;

    if (!initialized || (value == NULL)) {
        return HAL_ERROR;
    }

    tx_buf[0] = SPI_CMD_READ;   /* READ command */
    tx_buf[1] = addr;           /* Address */
    tx_buf[2] = 0x00;           /* Dummy byte */
    tx_buf[3] = 0x00;           /* Dummy byte */

    HAL_GPIO_WritePin(SPI_CS_PORT, SPI_CS_PIN, GPIO_PIN_RESET);

    status = HAL_SPI_TransmitReceive(&hspi2, tx_buf, rx_buf, 4, SPI_TIMEOUT_MS);

    HAL_GPIO_WritePin(SPI_CS_PORT, SPI_CS_PIN, GPIO_PIN_SET);

    if (status == HAL_OK) {
        *value = ((uint16_t)rx_buf[2] << 8) | rx_buf[3];
    }

    return status;
}

HAL_StatusTypeDef spi_write_reg(uint8_t addr, uint16_t value)
{
    uint8_t tx_buf[4];
    HAL_StatusTypeDef status;

    if (!initialized) {
        return HAL_ERROR;
    }

    tx_buf[0] = SPI_CMD_WRITE;       /* WRITE command */
    tx_buf[1] = addr;                /* Address */
    tx_buf[2] = (uint8_t)(value >> 8);  /* Data high byte */
    tx_buf[3] = (uint8_t)(value);       /* Data low byte */

    HAL_GPIO_WritePin(SPI_CS_PORT, SPI_CS_PIN, GPIO_PIN_RESET);

    status = HAL_SPI_Transmit(&hspi2, tx_buf, 4, SPI_TIMEOUT_MS);

    HAL_GPIO_WritePin(SPI_CS_PORT, SPI_CS_PIN, GPIO_PIN_SET);

    return status;
}

HAL_StatusTypeDef spi_burst_read(uint8_t start_addr, uint16_t *buffer, uint8_t count)
{
    HAL_StatusTypeDef status = HAL_OK;

    for (uint8_t i = 0; i < count; i++) {
        status = spi_read_reg(start_addr + i, &buffer[i]);
        if (status != HAL_OK) {
            break;
        }
    }

    return status;
}

HAL_StatusTypeDef spi_burst_write(uint8_t start_addr, const uint16_t *buffer, uint8_t count)
{
    HAL_StatusTypeDef status = HAL_OK;

    for (uint8_t i = 0; i < count; i++) {
        status = spi_write_reg(start_addr + i, buffer[i]);
        if (status != HAL_OK) {
            break;
        }
    }

    return status;
}

HAL_StatusTypeDef spi_set_frequency(bool is_dmb, uint8_t channel, uint32_t freq_hz)
{
    uint32_t phase_inc;
    uint8_t addr_l, addr_h;
    HAL_StatusTypeDef status;

    phase_inc = FPGA_NCO_FREQ(freq_hz);

    if (is_dmb) {
        addr_l = FPGA_DMB_CH_NCO_L(channel);
        addr_h = FPGA_DMB_CH_NCO_H(channel);
    } else {
        addr_l = FPGA_FM_CH_NCO_L(channel);
        addr_h = FPGA_FM_CH_NCO_H(channel);
    }

    status = spi_write_reg(addr_l, (uint16_t)(phase_inc & 0xFFFFU));
    if (status != HAL_OK) {
        return status;
    }

    status = spi_write_reg(addr_h, (uint16_t)(phase_inc >> 16));

    return status;
}

HAL_StatusTypeDef spi_set_agc_param(uint8_t reg_addr, uint16_t value)
{
    return spi_write_reg(reg_addr, value);
}

bool spi_check_mmcm_lock(void)
{
    uint16_t status = 0;

    if (spi_read_reg(FPGA_REG_SYS_STATUS, &status) != HAL_OK) {
        return false;
    }

    return (status & 0x01U) != 0U;  /* Bit 0 = MMCM lock */
}
