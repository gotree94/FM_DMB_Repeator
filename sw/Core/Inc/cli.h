/**
 * @file    cli.h
 * @brief   Command-Line Interface for UART Debug Console
 *
 * UART3 (115200 8N1) based CLI with 9 built-in commands.
 * Command table driven: add commands by extending cmd_table[].
 */

#ifndef CLI_H
#define CLI_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/*============================================================================
 * Constants
 *============================================================================*/
#define CLI_LINE_BUF_SIZE       128U    /* Maximum input line length */
#define CLI_MAX_ARGS            8U      /* Maximum arguments per command */
#define CLI_MAX_CMD_NAME        16U     /* Maximum command name length */
#define CLI_PROMPT              "repeater> "

/*============================================================================
 * Command handler type
 *============================================================================*/
typedef void (*cli_handler_t)(int argc, char **argv);

/**
 * @brief  Command table entry structure
 */
typedef struct {
    const char      *name;          /* Command name (e.g., "rd") */
    const char      *help;          /* Help text (e.g., "rd <addr> - Read register") */
    cli_handler_t   handler;        /* Handler function */
} cli_cmd_t;

/*============================================================================
 * Public API
 *============================================================================*/

/**
 * @brief  Initialize CLI (UART3 at 115200 baud)
 * @retval HAL_StatusTypeDef
 */
HAL_StatusTypeDef cli_init(void);

/**
 * @brief  Process one character from UART (call from ISR or poll)
 * @param  c  Received character
 */
void cli_process_char(char c);

/**
 * @brief  Main CLI processing task (call in main loop)
 */
void cli_task(void);

/**
 * @brief  Print a string over the CLI UART
 * @param  str  Null-terminated string
 */
void cli_puts(const char *str);

/**
 * @brief  Print formatted string (printf-like, limited)
 * @param  fmt  Format string
 * @param  ...  Arguments
 */
void cli_printf(const char *fmt, ...);

/**
 * @brief  Register a user-defined command
 * @param  cmd  Pointer to command entry
 * @retval true if registered successfully
 */
bool cli_register_command(const cli_cmd_t *cmd);

#ifdef __cplusplus
}
#endif

#endif /* CLI_H */
