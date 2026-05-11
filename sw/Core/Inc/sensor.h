/**
 * @file    sensor.h
 * @brief   Sensor Monitoring Module
 *
 * Periodic polling of FPGA monitoring registers via SPI.
 * Alarm edge detection with callback notification.
 * Polling interval: 100 ms (TIM6)
 */

#ifndef SENSOR_H
#define SENSOR_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/*============================================================================
 * Constants
 *============================================================================*/
#define SENSOR_POLL_INTERVAL_MS     100U    /* 100 ms polling interval */
#define SENSOR_TEMP_ALARM_C          75U    /* Over-temperature threshold (°C) */
#define SENSOR_VSWR_ALARM_THRESH     3U     /* VSWR alarm threshold (band index) */

/*============================================================================
 * Data structures
 *============================================================================*/

/**
 * @brief  Sensor data snapshot from FPGA
 */
typedef struct {
    uint16_t    temp_raw;       /* LM75A raw temperature (12-bit left-aligned) */
    uint8_t     vswr_idx;       /* VSWR band index (0=OK..5=critical) */
    uint16_t    fwd_power;      /* Forward power magnitude */
    uint16_t    ref_power;      /* Reflected power magnitude */
    uint8_t     alarm_bits;     /* Alarm status bits (see fpga_regs.h) */
} sensor_data_t;

/**
 * @brief  Alarm event callback type
 * @param  alarm_mask  Bitmask of active alarms
 */
typedef void (*alarm_callback_t)(uint8_t alarm_mask);

/*============================================================================
 * Public API
 *============================================================================*/

/**
 * @brief  Initialize sensor module (start TIM6)
 * @retval HAL_StatusTypeDef
 */
HAL_StatusTypeDef sensor_init(void);

/**
 * @brief  Register alarm callback
 * @param  callback  Function to call on alarm state change
 */
void sensor_register_alarm_callback(alarm_callback_t callback);

/**
 * @brief  Get latest sensor data snapshot
 * @retval Pointer to current sensor_data_t
 */
const sensor_data_t* sensor_get_data(void);

/**
 * @brief  Get temperature in degrees Celsius
 * @retval Temperature (°C) or -128 on error
 */
int8_t sensor_get_temperature_c(void);

/**
 * @brief  Poll FPGA registers (call from TIM6 ISR or main loop)
 * @note   Reads TEMP_RAW, VSWR_INDEX, ALARM_STATUS, FWD_POWER, REF_POWER
 */
void sensor_poll(void);

/**
 * @brief  Check if alarm state changed since last poll
 * @retval true if alarm state changed
 */
bool sensor_alarm_changed(void);

#ifdef __cplusplus
}
#endif

#endif /* SENSOR_H */
