#include <stdint.h>
#include "laser_ad9528.h"
#include "laser_bram.h"
#include "laser_config_cases.h"
#include "laser_gpio.h"
#include "laser_gt.h"
#include "laser_hw.h"
#include "laser_status.h"
#include "laser_udp_server.h"
#include "sleep.h"
#include "xil_printf.h"
#include "xstatus.h"

#define LASER_APP_MODE_UART_TEST 0
#define LASER_APP_MODE_UDP_SERVER 1

#ifndef LASER_APP_MODE
#define LASER_APP_MODE LASER_APP_MODE_UDP_SERVER
#endif


#define CONFIG_INDEX 0U
#define CONFIG_WAIT_ITERATIONS 1000U
#define UART_TEST_CASE LASER_TEST_DIRECT63

#if defined(__GNUC__)
#define LASER_MAYBE_UNUSED __attribute__((unused))
#else
#define LASER_MAYBE_UNUSED
#endif

static int wait_for_config_result(LaserGpio *gpio, int expect_error,
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
            if ((status & LASER_STATUS_CFG_VALID) != 0U) {
                *last_status = status;
                return XST_FAILURE;
            }
        } else {
            if ((status & LASER_STATUS_CFG_VALID) != 0U &&
                (status & LASER_STATUS_CFG_ERROR) == 0U) {
                *last_status = status;
                return XST_SUCCESS;
            }
        }
        usleep(1000U);
    }
    *last_status = status;
    return XST_FAILURE;
}

static int laser_init_control_hw(LaserGpio *gpio)
{
    uint32_t gt_status;
    int status;

    xil_printf("GPIO ctrl/status : 0x%08lx\r\n", (unsigned long)LASER_GPIO_BASEADDR);
    xil_printf("BRAM             : 0x%08lx\r\n", (unsigned long)LASER_BRAM_BASEADDR);
    xil_printf("GT status GPIO   : 0x%08lx\r\n", (unsigned long)LASER_GT_STATUS_GPIO_BASEADDR);
    xil_printf("Runtime rate set : CPLL_DYNAMIC_500M_1000M_1250M_2000M in UDP mode; no AD9528/QPLL/wide-range rate change\r\n");

    status = laser_gpio_init(gpio);
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: laser GPIO init failed: %d\r\n", status);
        return XST_FAILURE;
    }
    status = laser_gt_init();
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: GT status GPIO init failed: %d\r\n", status);
        return XST_FAILURE;
    }

    laser_gpio_set_enable(gpio, 0);
    laser_gpio_soft_reset(gpio);

    gt_status = laser_gt_read_status();
    laser_gt_print_status(gt_status);
    laser_print_status(laser_gpio_read_status(gpio));
    return XST_SUCCESS;
}

static int LASER_MAYBE_UNUSED run_uart_test(void)
{
    LaserGpio gpio;
    LaserConfig config;
    uint32_t laser_status;
    uint32_t gt_status;
    int direct_source;
    int direct_len_127;
    int expect_config_error;
    int status;

    xil_printf("\r\n=== laser_tx UART_TEST / GT Profile 0 ===\r\n");
    xil_printf("PS SPI1 device   : %lu, AD9528 SS%u\r\n",
               (unsigned long)LASER_SPI_DEVICE_ID, LASER_AD9528_SPI_SLAVE);
    xil_printf("Test case        : %s\r\n", laser_test_case_name(UART_TEST_CASE));

    status = laser_init_control_hw(&gpio);
    if (status != XST_SUCCESS) {
        return status;
    }

    status = laser_ad9528_spi_init();
    if (status == XST_SUCCESS) {
        (void)laser_ad9528_basic_check();
    } else {
        xil_printf("AD9528 SPI init : failed (%d)\r\n", status);
    }

    gt_status = laser_gt_read_status();
    laser_gt_print_status(gt_status);

    laser_gpio_set_enable(&gpio, 0);
    laser_gpio_soft_reset(&gpio);
    status = laser_make_test_config(UART_TEST_CASE, &config,
                                    &direct_source, &direct_len_127);
    if (status != XST_SUCCESS ||
        laser_bram_write_config(CONFIG_INDEX, &config) != XST_SUCCESS ||
        laser_bram_verify_config(CONFIG_INDEX, &config) != XST_SUCCESS) {
        xil_printf("ERROR: test config BRAM write/readback failed\r\n");
        return XST_FAILURE;
    }

    laser_gpio_select_config(&gpio, CONFIG_INDEX, direct_source, direct_len_127);
    laser_gpio_toggle_apply(&gpio);
    expect_config_error = laser_test_case_expects_config_error(UART_TEST_CASE);
    status = wait_for_config_result(&gpio, expect_config_error, &laser_status);
    laser_print_status(laser_status);
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: unexpected configuration result; TX remains disabled\r\n");
        return XST_FAILURE;
    }
    if (expect_config_error) {
        xil_printf("PASS: invalid config was rejected for %s; TX remains disabled\r\n",
                   laser_test_case_name(UART_TEST_CASE));
        while (1) {
            laser_print_status(laser_gpio_read_status(&gpio));
            laser_gt_print_status(laser_gt_read_status());
            usleep(1000000U);
        }
    }

    gt_status = laser_gt_read_status();
    laser_gt_print_status(gt_status);
    if (!laser_gt_is_ready(gt_status)) {
        xil_printf("GT_NOT_READY: TX remains disabled\r\n");
        return XST_FAILURE;
    }

    laser_gpio_set_enable(&gpio, 1);
    xil_printf("TX enabled for %s\r\n", laser_test_case_name(UART_TEST_CASE));
    while (1) {
        laser_print_status(laser_gpio_read_status(&gpio));
        laser_gt_print_status(laser_gt_read_status());
        usleep(1000000U);
    }
}

static int run_udp_server(void)
{
    return laser_udp_server_run();
}

int main(void)
{
    xil_printf("LASER_APP_MODE=%d\r\n", LASER_APP_MODE);
    xil_printf("LASER_HAS_LWIP=%d\r\n", LASER_HAS_LWIP);

#if LASER_APP_MODE == LASER_APP_MODE_UDP_SERVER
    return run_udp_server();
#else
    return run_uart_test();
#endif
}
