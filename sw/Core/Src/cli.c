/**
 * @file    cli.c
 * @brief   Command-Line Interface for UART Debug Console
 *
 * UART3 (115200 8N1), line buffered, strtok-based parser.
 * Built-in commands: help, rd, wr, status, reset, gain, mode, version, echo
 */

#include "cli.h"
#include "fpga_regs.h"
#include "spi_driver.h"
#include "sensor.h"
#include "stm32f4xx_hal.h"
#include <string.h>
#include <stdio.h>
#include <stdarg.h>

/*============================================================================
 * Private variables
 *============================================================================*/
static UART_HandleTypeDef huart3;
static char line_buf[CLI_LINE_BUF_SIZE];
static uint16_t line_len = 0;
static bool cmd_pending = false;
static bool initialized = false;

/* Forward declarations for built-in commands */
static void cmd_help(int argc, char **argv);
static void cmd_read(int argc, char **argv);
static void cmd_write(int argc, char **argv);
static void cmd_status(int argc, char **argv);
static void cmd_reset(int argc, char **argv);
static void cmd_gain(int argc, char **argv);
static void cmd_mode(int argc, char **argv);
static void cmd_version(int argc, char **argv);
static void cmd_echo(int argc, char **argv);

/*============================================================================
 * Built-in command table
 *============================================================================*/
static const cli_cmd_t builtin_cmds[] = {
    {"help",    "help                    - Show this help",           cmd_help},
    {"rd",      "rd <addr>              - Read FPGA register",        cmd_read},
    {"wr",      "wr <addr> <val>        - Write FPGA register",       cmd_write},
    {"status",  "status                 - Show system status",        cmd_status},
    {"reset",   "reset                  - Reset FPGA (soft)",         cmd_reset},
    {"gain",    "gain <ch> <val>        - Set channel gain",          cmd_gain},
    {"mode",    "mode <fm|dmb|all>      - Select operating mode",     cmd_mode},
    {"version", "version                - Show firmware version",     cmd_version},
    {"echo",    "echo <text>            - Echo input text",           cmd_echo},
    {NULL, NULL, NULL}  /* Sentinel */
};

/* Maximum user-registered commands */
#define CLI_MAX_USER_CMDS   8U
static cli_cmd_t user_cmds[CLI_MAX_USER_CMDS];
static uint8_t num_user_cmds = 0;

/*============================================================================
 * UART GPIO Configuration
 *============================================================================*/
static void uart_gpio_init(void)
{
    GPIO_InitTypeDef gpio = {0};

    __HAL_RCC_USART3_CLK_ENABLE();
    __HAL_RCC_GPIOD_CLK_ENABLE();

    /* USART3: TX=PD8, RX=PD9 (STM32F429 DISCOVERY) */
    gpio.Pin       = GPIO_PIN_8 | GPIO_PIN_9;
    gpio.Mode      = GPIO_MODE_AF_PP;
    gpio.Pull      = GPIO_PULLUP;
    gpio.Speed     = GPIO_SPEED_FREQ_HIGH;
    gpio.Alternate = GPIO_AF7_USART3;
    HAL_GPIO_Init(GPIOD, &gpio);
}

/*============================================================================
 * Public API
 *============================================================================*/

HAL_StatusTypeDef cli_init(void)
{
    HAL_StatusTypeDef status;

    if (initialized) {
        return HAL_OK;
    }

    uart_gpio_init();

    huart3.Instance          = USART3;
    huart3.Init.BaudRate     = 115200;
    huart3.Init.WordLength   = UART_WORDLENGTH_8B;
    huart3.Init.StopBits     = UART_STOPBITS_1;
    huart3.Init.Parity       = UART_PARITY_NONE;
    huart3.Init.Mode         = UART_MODE_TX_RX;
    huart3.Init.HwFlowCtl    = UART_HWCONTROL_NONE;
    huart3.Init.OverSampling = UART_OVERSAMPLING_16;

    status = HAL_UART_Init(&huart3);

    if (status == HAL_OK) {
        initialized = true;
        line_len = 0;
        cmd_pending = false;
        memset(line_buf, 0, sizeof(line_buf));
        cli_printf("\r\nFM/DMB Repeater CLI v1.0\r\n");
        cli_printf("%s", CLI_PROMPT);
    }

    return status;
}

void cli_process_char(char c)
{
    if (!initialized) {
        return;
    }

    if (c == '\r' || c == '\n') {
        /* End of line */
        if (line_len > 0) {
            line_buf[line_len] = '\0';
            cmd_pending = true;
        }
        line_len = 0;
    } else if (c == '\b' || c == 0x7F) {
        /* Backspace */
        if (line_len > 0) {
            line_len--;
            HAL_UART_Transmit(&huart3, (uint8_t *)"\b \b", 3, 10);
        }
    } else if (line_len < (CLI_LINE_BUF_SIZE - 1)) {
        line_buf[line_len++] = c;
        HAL_UART_Transmit(&huart3, (uint8_t *)&c, 1, 10);
    }
}

void cli_puts(const char *str)
{
    if (initialized && (str != NULL)) {
        HAL_UART_Transmit(&huart3, (uint8_t *)str, strlen(str), 100);
    }
}

void cli_printf(const char *fmt, ...)
{
    char buf[256];
    va_list args;

    if (!initialized || (fmt == NULL)) {
        return;
    }

    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);

    cli_puts(buf);
}

bool cli_register_command(const cli_cmd_t *cmd)
{
    if ((cmd == NULL) || (cmd->name == NULL) || (num_user_cmds >= CLI_MAX_USER_CMDS)) {
        return false;
    }

    user_cmds[num_user_cmds++] = *cmd;
    return true;
}

/*============================================================================
 * Command Processing
 *============================================================================*/

static const cli_cmd_t* find_command(const char *name)
{
    /* Search built-in */
    for (const cli_cmd_t *cmd = builtin_cmds; cmd->name != NULL; cmd++) {
        if (strcmp(cmd->name, name) == 0) {
            return cmd;
        }
    }

    /* Search user-registered */
    for (uint8_t i = 0; i < num_user_cmds; i++) {
        if (strcmp(user_cmds[i].name, name) == 0) {
            return &user_cmds[i];
        }
    }

    return NULL;
}

void cli_task(void)
{
    char *argv[CLI_MAX_ARGS];
    int argc;
    const cli_cmd_t *cmd;

    if (!cmd_pending) {
        return;
    }

    cmd_pending = false;
    cli_puts("\r\n");

    /* Parse line into argv */
    argv[0] = strtok(line_buf, " \t");
    if (argv[0] == NULL) {
        cli_printf("%s", CLI_PROMPT);
        return;
    }

    argc = 1;
    while ((argc < CLI_MAX_ARGS) && ((argv[argc] = strtok(NULL, " \t")) != NULL)) {
        argc++;
    }

    /* Find and execute command */
    cmd = find_command(argv[0]);
    if (cmd != NULL) {
        cmd->handler(argc, argv);
    } else {
        cli_printf("Unknown command: %s\r\n", argv[0]);
        cli_printf("Type 'help' for available commands.\r\n");
    }

    cli_printf("%s", CLI_PROMPT);
}

/*============================================================================
 * Command Handlers
 *============================================================================*/

static void cmd_help(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    cli_puts("FM/DMB Repeater CLI Commands:\r\n");
    cli_puts("--------------------------------\r\n");

    for (const cli_cmd_t *c = builtin_cmds; c->name != NULL; c++) {
        cli_printf("  %s\r\n", c->help);
    }

    for (uint8_t i = 0; i < num_user_cmds; i++) {
        cli_printf("  %s\r\n", user_cmds[i].help);
    }
}

static void cmd_read(int argc, char **argv)
{
    uint16_t value;
    uint32_t addr;
    char *endptr;

    if (argc < 2) {
        cli_puts("Usage: rd <addr>\r\n");
        return;
    }

    addr = strtoul(argv[1], &endptr, 16);
    if (*endptr != '\0') {
        cli_puts("Invalid address (hex)\r\n");
        return;
    }

    if (spi_read_reg((uint8_t)addr, &value) == HAL_OK) {
        cli_printf("REG[0x%02X] = 0x%04X (%u)\r\n", (unsigned)addr,
                   (unsigned)value, (unsigned)value);
    } else {
        cli_printf("Error reading REG[0x%02X]\r\n", (unsigned)addr);
    }
}

static void cmd_write(int argc, char **argv)
{
    uint32_t addr, value;
    char *endptr;

    if (argc < 3) {
        cli_puts("Usage: wr <addr> <val>\r\n");
        return;
    }

    addr = strtoul(argv[1], &endptr, 16);
    if (*endptr != '\0') {
        cli_puts("Invalid address (hex)\r\n");
        return;
    }

    value = strtoul(argv[2], &endptr, 16);
    if (*endptr != '\0') {
        cli_puts("Invalid value (hex)\r\n");
        return;
    }

    if (spi_write_reg((uint8_t)addr, (uint16_t)value) == HAL_OK) {
        cli_printf("REG[0x%02X] <- 0x%04X OK\r\n", (unsigned)addr, (unsigned)value);
    } else {
        cli_printf("Error writing REG[0x%02X]\r\n", (unsigned)addr);
    }
}

static void cmd_status(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    const sensor_data_t *s = sensor_get_data();

    cli_puts("System Status:\r\n");
    cli_puts("--------------------------------\r\n");

    cli_printf("Temperature:   %d C  (raw=0x%04X)\r\n",
               sensor_get_temperature_c(), s->temp_raw);
    cli_printf("VSWR Index:    %u/5\r\n", s->vswr_idx);
    cli_printf("Forward Pwr:   %u\r\n", s->fwd_power);
    cli_printf("Reflected Pwr: %u\r\n", s->ref_power);
    cli_printf("Alarms:        0x%02X %s%s%s\r\n", s->alarm_bits,
               (s->alarm_bits & ALARM_OT)   ? "[OT] "   : "",
               (s->alarm_bits & ALARM_VSWR) ? "[VSWR] " : "",
               (s->alarm_bits & ALARM_PA_FAULT) ? "[PA]" : "");
}

static void cmd_reset(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    cli_puts("Resetting FPGA...\r\n");

    if (spi_write_reg(FPGA_REG_RESET, 0x0001) == HAL_OK) {
        HAL_Delay(10);
        spi_write_reg(FPGA_REG_RESET, 0x0000);
        cli_puts("FPGA reset complete.\r\n");
    } else {
        cli_puts("FPGA reset failed.\r\n");
    }
}

static void cmd_gain(int argc, char **argv)
{
    uint32_t ch, gain_val;
    char *endptr;

    if (argc < 3) {
        cli_puts("Usage: gain <ch> <val>\r\n");
        return;
    }

    ch = strtoul(argv[1], &endptr, 10);
    if (*endptr != '\0') {
        cli_puts("Invalid channel number\r\n");
        return;
    }

    gain_val = strtoul(argv[2], &endptr, 10);
    if (*endptr != '\0') {
        cli_puts("Invalid gain value\r\n");
        return;
    }

    cli_printf("Setting FM CH%lu gain to %lu\r\n", ch, gain_val);
}

static void cmd_mode(int argc, char **argv)
{
    uint16_t ctrl = 0;

    if (argc < 2) {
        cli_puts("Usage: mode <fm|dmb|all>\r\n");
        return;
    }

    if (strcmp(argv[1], "fm") == 0) {
        ctrl = SYS_CTRL_ENABLE_FM;
    } else if (strcmp(argv[1], "dmb") == 0) {
        ctrl = SYS_CTRL_ENABLE_DMB;
    } else if (strcmp(argv[1], "all") == 0) {
        ctrl = SYS_CTRL_ENABLE_FM | SYS_CTRL_ENABLE_DMB;
    } else {
        cli_puts("Invalid mode. Use: fm, dmb, or all\r\n");
        return;
    }

    if (spi_write_reg(FPGA_REG_SYS_CTRL, ctrl) == HAL_OK) {
        cli_printf("Mode set: %s\r\n", argv[1]);
    } else {
        cli_puts("Error setting mode\r\n");
    }
}

static void cmd_version(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    cli_puts("FM/DMB Repeater\r\n");
    cli_puts("Firmware: v1.0 (2026-05-12)\r\n");
    cli_printf("Build: %s %s\r\n", __DATE__, __TIME__);
}

static void cmd_echo(int argc, char **argv)
{
    for (int i = 1; i < argc; i++) {
        cli_printf("%s%c", argv[i], (i < argc - 1) ? ' ' : '\n');
    }

    if (argc < 2) {
        cli_puts("\r\n");
    }
}
