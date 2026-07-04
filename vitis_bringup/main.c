#include <stdint.h>
#include "laser_bram.h"
#include "laser_gpio.h"
#include "laser_status.h"
#include "sleep.h"
#include "xil_printf.h"
#include "xstatus.h"

#define LASER_TEST_DIRECT63       1
#define LASER_TEST_DIRECT63_GAP   2
#define LASER_TEST_PRBS6          3
#define LASER_TEST_INVALID        4

#ifndef LASER_TEST_CASE
#define LASER_TEST_CASE LASER_TEST_DIRECT63
#endif

#define CONFIG_INDEX 0U
#define CONFIG_WAIT_ITERATIONS 1000U

static void make_test_config(LaserConfig *config, int *direct_source,
                             int *direct_len_127, int *expect_error)
{
    *direct_source = 0;
    *direct_len_127 = 0;
    *expect_error = 0;

    config->seed = 0x0000003fU;
    config->repeat_cycles = 2U;
    config->gap_len_bits = 0U;
    config->insert_after = 0U;
    config->prbs_order = 6U;
    config->phase_shift_en = 0U;
    config->loop_en = 0U;
    config->pattern_low = 0x55555555U;
    config->pattern_mid = 0x2aaaaaaaU;
    config->pattern_high = 0x00000000U;
    config->pattern_top = 0x00000000U;

#if LASER_TEST_CASE == LASER_TEST_DIRECT63
    *direct_source = 1;
#elif LASER_TEST_CASE == LASER_TEST_DIRECT63_GAP
    *direct_source = 1;
    config->repeat_cycles = 4U;
    config->insert_after = 2U;
    config->gap_len_bits = 128U;
#elif LASER_TEST_CASE == LASER_TEST_PRBS6
    config->repeat_cycles = 4U;
    config->insert_after = 2U;
    config->gap_len_bits = 5U;
    config->phase_shift_en = 1U;
#elif LASER_TEST_CASE == LASER_TEST_INVALID
    config->repeat_cycles = 0U;
    *expect_error = 1;
#else
#error "Unsupported LASER_TEST_CASE"
#endif
}

static int wait_for_config(LaserGpio *gpio, int expect_error,
                           uint32_t *last_status)
{
    uint32_t i;
    uint32_t status = 0U;

    for (i = 0U; i < CONFIG_WAIT_ITERATIONS; ++i) {
        status = laser_gpio_read_status(gpio);
        if (expect_error) {
            if ((status & LASER_STATUS_CFG_ERROR) != 0U) {
                *last_status = status;
                return XST_SUCCESS;
            }
        } else if (((status & LASER_STATUS_CFG_VALID) != 0U) &&
                   ((status & LASER_STATUS_CFG_ERROR) == 0U)) {
            *last_status = status;
            return XST_SUCCESS;
        }
        usleep(1000U);
    }

    *last_status = status;
    return XST_FAILURE;
}

int main(void)
{
    LaserGpio gpio;
    LaserConfig config;
    uint32_t status;
    uint32_t previous_status;
    int direct_source;
    int direct_len_127;
    int expect_error;
    int result;

    xil_printf("\r\nLaser TX PL-core bring-up, test case %d\r\n", LASER_TEST_CASE);

    result = laser_gpio_init(&gpio);
    if (result != XST_SUCCESS) {
        xil_printf("ERROR: XGpio initialization failed: %d\r\n", result);
        return XST_FAILURE;
    }

    make_test_config(&config, &direct_source, &direct_len_127, &expect_error);
    laser_gpio_set_enable(&gpio, 0);
    laser_gpio_soft_reset(&gpio);

    result = laser_bram_write_config(CONFIG_INDEX, &config);
    if (result != XST_SUCCESS) {
        xil_printf("ERROR: BRAM write failed: %d\r\n", result);
        return XST_FAILURE;
    }
    result = laser_bram_verify_config(CONFIG_INDEX, &config);
    if (result != XST_SUCCESS) {
        xil_printf("ERROR: BRAM readback mismatch; apply was not issued.\r\n");
        return XST_FAILURE;
    }
    xil_printf("BRAM: all 8 configuration words verified.\r\n");

    laser_gpio_select_config(&gpio, CONFIG_INDEX, direct_source, direct_len_127);
    laser_gpio_toggle_apply(&gpio);
    xil_printf("GPIO: apply_toggle changed; waiting for PL configuration status.\r\n");

    result = wait_for_config(&gpio, expect_error, &status);
    laser_print_status(status);
    if (result != XST_SUCCESS) {
        xil_printf("ERROR: timeout waiting for expected configuration result.\r\n");
        return XST_FAILURE;
    }

    if (expect_error) {
        if ((status & LASER_STATUS_BUSY) != 0U ||
            LASER_STATUS_ERROR_CODE(status) != 0x01U) {
            xil_printf("ERROR: illegal-config status is not as expected.\r\n");
            return XST_FAILURE;
        }
        xil_printf("PASS: illegal repeat_cycles=0 was rejected.\r\n");
    } else {
        laser_gpio_set_enable(&gpio, 1);
        xil_printf("GPIO: enable=1. Use ila_laser_tx for cycle-accurate checks.\r\n");
    }

    previous_status = ~status;
    while (1) {
        status = laser_gpio_read_status(&gpio);
        if (status != previous_status) {
            laser_print_status(status);
            previous_status = status;
        }
        usleep(100000U);
    }

    return XST_SUCCESS;
}
