/**
 * @file    main.c
 * @brief   FM/DMB Repeater Main Firmware
 *
 * STM32F429 @ 180 MHz, FPGA Kintex-7 over SPI
 *
 * Init sequence:
 *   1. HAL, System Clock (HSE 8 MHz → PLL → 180 MHz)
 *   2. SPI2 → FPGA configuration (frequencies, AGC params)
 *   3. UART3 → CLI
 *   4. TIM6 → Sensor polling (100 ms)
 *   5. Main loop: CLI task
 */

#include "stm32f4xx_hal.h"
#include "fpga_regs.h"
#include "spi_driver.h"
#include "cli.h"
#include "sensor.h"
#include <string.h>

/*============================================================================
 * Private defines
 *============================================================================*/
#define LED_GPIO_PORT           GPIOG
#define LED_PIN                 GPIO_PIN_13  /* STM32F429 DISCOVERY green LED */

/* Default AGC parameters (Q15 fixed-point) */
#define AGC_ATTACK_DEFAULT      100     /* Fast attack */
#define AGC_RELEASE_DEFAULT     1000    /* Slow release */
#define AGC_REF_DEFAULT         0x4000  /* Reference = 0.5 */
#define AGC_MU_DEFAULT          328     /* Step = 0.01 */
#define AGC_GAIN_MIN_DEFAULT    0x0080  /* Min gain ~0.0025 */
#define AGC_GAIN_MAX_DEFAULT    0x7FFF  /* Max gain ~1.0 */

/* Default FM frequencies (MHz) — Korea FM broadcast band */
static const uint32_t fm_freq_khz[] = {
    88100, 88300, 88500, 88700, 88900, 89100, 89300, 89500,
    89700, 89900, 90100, 90300, 90500, 90700, 90900, 91100,
    91300, 91500, 91700, 91900, 92100, 92300, 92500, 92700,
    92900, 93100, 93300, 93500, 93700, 93900, 94100, 94300,
    94500, 94700, 94900, 95100, 95300, 95500, 95700, 95900
};
#define FM_FREQ_COUNT   (sizeof(fm_freq_khz) / sizeof(fm_freq_khz[0]))

/* Default DMB frequencies (MHz) — Korea T-DMB Band-III */
static const uint32_t dmb_freq_khz[] = {
    180000, 182000, 184000, 186000, 188000, 190000
};
#define DMB_FREQ_COUNT  (sizeof(dmb_freq_khz) / sizeof(dmb_freq_khz[0]))

/*============================================================================
 * Private variables
 *============================================================================*/
static UART_HandleTypeDef huart1;   /* Debug UART (optional) */
static uint8_t rx_byte;

/*============================================================================
 * System Clock Configuration
 *   HSE 8 MHz → PLL → 180 MHz HCLK
 *============================================================================*/
static void system_clock_init(void)
{
    RCC_OscInitTypeDef osc = {0};
    RCC_ClkInitTypeDef clk = {0};

    /* HSE oscillator enable */
    osc.OscillatorType = RCC_OSCILLATORTYPE_HSE;
    osc.HSEState       = RCC_HSE_ON;
    osc.PLL.PLLState   = RCC_PLL_ON;
    osc.PLL.PLLSource  = RCC_PLLSOURCE_HSE;
    osc.PLL.PLLM       = 8;        /* 8 MHz / 8 = 1 MHz */
    osc.PLL.PLLN       = 360;      /* 1 MHz × 360 = 360 MHz */
    osc.PLL.PLLP       = RCC_PLLP_DIV2; /* 360 / 2 = 180 MHz (HCLK) */
    osc.PLL.PLLQ       = 7;        /* 360 / 7 ≈ 51.4 MHz (USB OTG FS/SDIO) */
    HAL_RCC_OscConfig(&osc);

    /* HCLK = 180 MHz, APB1 = 45 MHz, APB2 = 90 MHz */
    clk.ClockType      = RCC_CLOCKTYPE_HCLK | RCC_CLOCKTYPE_SYSCLK
                       | RCC_CLOCKTYPE_PCLK1 | RCC_CLOCKTYPE_PCLK2;
    clk.SYSCLKSource   = RCC_SYSCLKSOURCE_PLLCLK;
    clk.AHBCLKDivider  = RCC_SYSCLK_DIV1;
    clk.APB1CLKDivider = RCC_HCLK_DIV4;    /* 180 / 4 = 45 MHz */
    clk.APB2CLKDivider = RCC_HCLK_DIV2;    /* 180 / 2 = 90 MHz */
    HAL_RCC_ClockConfig(&clk, FLASH_LATENCY_5);

    /* Update HAL tick */
    HAL_SYSTICK_Config(HAL_RCC_GetHCLKFreq() / 1000);
}

/*============================================================================
 * GPIO Initialization (LED, button, etc.)
 *============================================================================*/
static void gpio_init(void)
{
    GPIO_InitTypeDef gpio = {0};

    __HAL_RCC_GPIOG_CLK_ENABLE();

    /* Green LED (PG13) */
    gpio.Pin   = LED_PIN;
    gpio.Mode  = GPIO_MODE_OUTPUT_PP;
    gpio.Pull  = GPIO_NOPULL;
    gpio.Speed = GPIO_SPEED_FREQ_LOW;
    HAL_GPIO_Init(LED_GPIO_PORT, &gpio);

    HAL_GPIO_WritePin(LED_GPIO_PORT, LED_PIN, GPIO_PIN_RESET);
}

/*============================================================================
 * FPGA Initialization Sequence
 *============================================================================*/
static void fpga_init(void)
{
    uint16_t scratch_val;
    uint16_t mmcm_check;

    cli_puts("Initializing FPGA...\r\n");

    /* Check SPI communication via scratch register */
    if (spi_write_reg(FPGA_REG_SCRATCH, 0xA5A5) != HAL_OK) {
        cli_puts("  SPI write failed!\r\n");
        return;
    }

    /* Verify scratch readback */
    if (spi_read_reg(FPGA_REG_SCRATCH, &scratch_val) != HAL_OK) {
        cli_puts("  SPI read failed!\r\n");
        return;
    }

    if (scratch_val == 0xA5A5) {
        cli_puts("  SPI communication: OK\r\n");
    } else {
        cli_puts("  SPI communication: FAIL (unexpected value)\r\n");
        return;
    }

    /* Wait for MMCM lock */
    HAL_Delay(10);
    for (uint32_t retry = 0; retry < 100; retry++) {
        if (spi_check_mmcm_lock()) {
            cli_puts("  MMCM lock: OK\r\n");
            break;
        }
        HAL_Delay(10);
    }

    /* Configure FM channel frequencies */
    cli_printf("  Configuring %u FM channels...\r\n", FM_FREQ_COUNT);
    for (uint8_t ch = 0; ch < FM_FREQ_COUNT; ch++) {
        if (spi_set_frequency(false, ch, fm_freq_khz[ch] * 1000) != HAL_OK) {
            cli_printf("  FM CH%u frequency set failed!\r\n", ch);
            break;
        }
    }

    /* Configure DMB channel frequencies */
    cli_printf("  Configuring %u DMB channels...\r\n", DMB_FREQ_COUNT);
    for (uint8_t ch = 0; ch < DMB_FREQ_COUNT; ch++) {
        if (spi_set_frequency(true, ch, dmb_freq_khz[ch] * 1000) != HAL_OK) {
            cli_printf("  DMB CH%u frequency set failed!\r\n", ch);
            break;
        }
    }

    /* Configure AGC parameters */
    spi_set_agc_param(FPGA_REG_AGC_ATTACK, AGC_ATTACK_DEFAULT);
    spi_set_agc_param(FPGA_REG_AGC_RELEASE, AGC_RELEASE_DEFAULT);
    spi_set_agc_param(FPGA_REG_AGC_REF, AGC_REF_DEFAULT);
    spi_set_agc_param(FPGA_REG_AGC_MU, AGC_MU_DEFAULT);
    spi_set_agc_param(FPGA_REG_AGC_GAIN_MIN, AGC_GAIN_MIN_DEFAULT);
    spi_set_agc_param(FPGA_REG_AGC_GAIN_MAX, AGC_GAIN_MAX_DEFAULT);

    /* Enable FM + DMB operation */
    spi_write_reg(FPGA_REG_SYS_CTRL,
                  SYS_CTRL_ENABLE_FM | SYS_CTRL_ENABLE_DMB | SYS_CTRL_DAC_ENABLE);

    cli_puts("FPGA initialization complete!\r\n");

    /* Turn on LED to indicate ready */
    HAL_GPIO_WritePin(LED_GPIO_PORT, LED_PIN, GPIO_PIN_SET);
}

/*============================================================================
 * Alarm Callback
 *============================================================================*/
static void alarm_handler(uint8_t alarm_mask)
{
    cli_printf("[ALARM] 0x%02X: ", alarm_mask);

    if (alarm_mask & ALARM_OT) {
        cli_puts("OVER-TEMPERATURE ");
    }
    if (alarm_mask & ALARM_VSWR) {
        cli_puts("HIGH-VSWR ");
    }
    if (alarm_mask & ALARM_PA_FAULT) {
        cli_puts("PA-FAULT ");
    }
    if (alarm_mask & ALARM_FIFO_OVERFLOW) {
        cli_puts("FIFO-OVERFLOW ");
    }
    cli_puts("\r\n");
}

/*============================================================================
 * Error Recovery
 *============================================================================*/
static void error_recovery(void)
{
    const sensor_data_t *s = sensor_get_data();

    /* Check for critical alarms */
    if (s->alarm_bits & ALARM_OT) {
        cli_puts("[RECOVERY] Over-temperature — reducing power\r\n");
        spi_write_reg(FPGA_REG_SYS_CTRL, 0x0000);  /* Disable all */
    }

    if (s->alarm_bits & ALARM_VSWR) {
        cli_puts("[RECOVERY] High VSWR — disabling PA\r\n");
        spi_write_reg(FPGA_REG_SYS_CTRL, SYS_CTRL_AGC_ENABLE);  /* PA only */
    }

    if (s->alarm_bits & ALARM_PA_FAULT) {
        cli_puts("[RECOVERY] PA fault — cycling power\r\n");
        spi_write_reg(FPGA_REG_RESET, 0x0001);
        HAL_Delay(100);
        spi_write_reg(FPGA_REG_RESET, 0x0000);
    }
}

/*============================================================================
 * Main
 *============================================================================*/
int main(void)
{
    /* HAL Library initialization */
    HAL_Init();

    /* Configure system clock: 180 MHz */
    system_clock_init();

    /* Initialize peripherals */
    gpio_init();

    /* Initialize SPI first (FPGA communication) */
    if (spi_init() != HAL_OK) {
        /* Fatal: cannot communicate with FPGA */
        while (1) {
            HAL_GPIO_TogglePin(LED_GPIO_PORT, LED_PIN);
            HAL_Delay(100);
        }
    }

    /* Initialize CLI (UART3) */
    if (cli_init() != HAL_OK) {
        /* Fatal: cannot initialize debug console */
        while (1) {
            HAL_GPIO_TogglePin(LED_GPIO_PORT, LED_PIN);
            HAL_Delay(200);
        }
    }

    /* Initialize sensors (TIM6 polling) */
    if (sensor_init() != HAL_OK) {
        cli_puts("Sensor init failed!\r\n");
    }

    /* Register alarm callback */
    sensor_register_alarm_callback(alarm_handler);

    /* Initialize FPGA */
    fpga_init();

    /* Main loop */
    while (1) {
        /* Process CLI commands */
        cli_task();

        /* Check for alarms and recovery */
        if (sensor_alarm_changed()) {
            const sensor_data_t *s = sensor_get_data();
            if (s->alarm_bits != 0) {
                error_recovery();
            }
        }

        /* Toggle LED at 1 Hz to indicate alive */
        static uint32_t last_tick = 0;
        if (HAL_GetTick() - last_tick >= 1000) {
            last_tick = HAL_GetTick();
            HAL_GPIO_TogglePin(LED_GPIO_PORT, LED_PIN);
        }
    }
}
