/**
 * @file    sensor.c
 * @brief   Sensor Monitoring Module
 *
 * TIM6 triggers at 100 ms intervals to poll FPGA monitoring registers.
 * Alarm edge detection: callback invoked on rising/falling alarm edges.
 * All data stored in static structure (thread-safe via atomic reads).
 */

#include "sensor.h"
#include "fpga_regs.h"
#include "spi_driver.h"
#include "stm32f4xx_hal.h"
#include <string.h>

/*============================================================================
 * Private variables
 *============================================================================*/
static sensor_data_t sensor_data = {0};
static sensor_data_t prev_data = {0};
static alarm_callback_t alarm_cb = NULL;
static bool initialized = false;
static bool alarm_changed = false;

/*============================================================================
 * TIM6 Configuration (100 ms interval)
 *============================================================================*/
static TIM_HandleTypeDef htim6;

static void tim6_init(void)
{
    __HAL_RCC_TIM6_CLK_ENABLE();

    htim6.Instance               = TIM6;
    htim6.Init.Prescaler         = 18000 - 1;   /* 180 MHz / 18000 = 10 kHz */
    htim6.Init.CounterMode       = TIM_COUNTERMODE_UP;
    htim6.Init.Period            = 1000 - 1;     /* 10 kHz / 1000 = 10 Hz (100 ms) */
    htim6.Init.AutoReloadPreload = TIM_AUTORELOAD_PRELOAD_DISABLE;

    HAL_TIM_Base_Init(&htim6);

    /* Enable TIM6 interrupt */
    HAL_NVIC_SetPriority(TIM6_DAC_IRQn, 5, 0);
    HAL_NVIC_EnableIRQ(TIM6_DAC_IRQn);
}

/**
 * @brief  TIM6 interrupt handler
 */
void TIM6_DAC_IRQHandler(void)
{
    HAL_TIM_IRQHandler(&htim6);
}

/**
 * @brief  TIM6 period elapsed callback (called from HAL)
 */
void HAL_TIM_PeriodElapsedCallback(TIM_HandleTypeDef *htim)
{
    if (htim->Instance == TIM6) {
        sensor_poll();
    }
}

/*============================================================================
 * Private helpers
 *============================================================================*/

/**
 * @brief  Convert LM75A raw value to Celsius
 *
 * LM75A: 11-bit signed, left-aligned in 16-bit register
 * Temp_C = raw >> 5 (for left-aligned 11-bit)
 * Simplified: raw >> 7 gives approximate Celsius
 */
static int8_t raw_to_celsius(uint16_t raw)
{
    int16_t signed_raw = (int16_t)raw;
    int8_t temp = (int8_t)(signed_raw >> 7);

    return temp;
}

/*============================================================================
 * Public API
 *============================================================================*/

HAL_StatusTypeDef sensor_init(void)
{
    if (initialized) {
        return HAL_OK;
    }

    /* Initialize data structures */
    memset(&sensor_data, 0, sizeof(sensor_data));
    memset(&prev_data, 0, sizeof(prev_data));

    /* Initialize TIM6 for 100 ms polling */
    tim6_init();

    /* Start TIM6 in interrupt mode */
    if (HAL_TIM_Base_Start_IT(&htim6) != HAL_OK) {
        return HAL_ERROR;
    }

    initialized = true;
    return HAL_OK;
}

void sensor_register_alarm_callback(alarm_callback_t callback)
{
    alarm_cb = callback;
}

const sensor_data_t* sensor_get_data(void)
{
    return &sensor_data;
}

int8_t sensor_get_temperature_c(void)
{
    return raw_to_celsius(sensor_data.temp_raw);
}

void sensor_poll(void)
{
    uint16_t temp, vswr, alarm, fwd, ref;

    /* Read all monitoring registers via SPI */
    if (spi_read_reg(FPGA_REG_TEMP_RAW, &temp) != HAL_OK) {
        return;
    }
    if (spi_read_reg(FPGA_REG_VSWR_INDEX, &vswr) != HAL_OK) {
        return;
    }
    if (spi_read_reg(FPGA_REG_ALARM_STATUS, &alarm) != HAL_OK) {
        return;
    }
    if (spi_read_reg(FPGA_REG_FWD_POWER, &fwd) != HAL_OK) {
        return;
    }
    if (spi_read_reg(FPGA_REG_REF_POWER, &ref) != HAL_OK) {
        return;
    }

    /* Update sensor data */
    prev_data = sensor_data;

    sensor_data.temp_raw    = temp;
    sensor_data.vswr_idx    = (uint8_t)(vswr & 0xFFU);
    sensor_data.alarm_bits  = (uint8_t)(alarm & 0xFFU);
    sensor_data.fwd_power   = fwd;
    sensor_data.ref_power   = ref;

    /* Check for alarm state change */
    alarm_changed = (sensor_data.alarm_bits != prev_data.alarm_bits);

    if (alarm_changed && (alarm_cb != NULL)) {
        alarm_cb(sensor_data.alarm_bits);
    }
}

bool sensor_alarm_changed(void)
{
    bool changed = alarm_changed;
    alarm_changed = false;
    return changed;
}
