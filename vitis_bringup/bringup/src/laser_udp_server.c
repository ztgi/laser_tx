#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sleep.h"
#include "gt_rate_plan.h"
#include "laser_bram.h"
#include "laser_gpio.h"
#include "laser_gt.h"
#include "laser_hw.h"
#include "laser_status.h"
#include "laser_udp_server.h"
#include "xil_printf.h"
#include "xstatus.h"

#if LASER_HAS_LWIP
#include "lwip/init.h"
#include "lwip/ip_addr.h"
#include "lwip/netif.h"
#include "lwip/udp.h"
#include "netif/xadapter.h"
#include "xil_exception.h"
#include "xparameters.h"
#include "xscugic.h"
#endif

#define LASER_UDP_PORT 5005U
#define LASER_UDP_IP0 192U
#define LASER_UDP_IP1 168U
#define LASER_UDP_IP2 1U
#define LASER_UDP_IP3 10U
#define LASER_UDP_NETMASK0 255U
#define LASER_UDP_NETMASK1 255U
#define LASER_UDP_NETMASK2 255U
#define LASER_UDP_NETMASK3 0U
#define LASER_UDP_GATEWAY0 192U
#define LASER_UDP_GATEWAY1 168U
#define LASER_UDP_GATEWAY2 1U
#define LASER_UDP_GATEWAY3 1U
#define LASER_UDP_MAX_PAYLOAD 384U
#define LASER_UDP_MAX_RESPONSE 512U
#define LASER_UDP_INPUT_HEARTBEAT_LOOPS 1000000U
#define LASER_RATE_QUIESCE_WAIT_ITERATIONS 1000U
#define LASER_RATE_SWITCH_POLL_ITERATIONS 200000U

#ifndef LASER_STATIC_RATE_MBPS
#define LASER_STATIC_RATE_MBPS 500U
#endif

#if LASER_HAS_LWIP
static void laser_lwip_platform_setup_interrupts(void)
{
    Xil_ExceptionInit();
    XScuGic_DeviceInitialize(XPAR_SCUGIC_0_DEVICE_ID);
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_IRQ_INT,
                                 (Xil_ExceptionHandler)XScuGic_DeviceInterruptHandler,
                                 (void *)XPAR_SCUGIC_0_DEVICE_ID);
    Xil_ExceptionEnableMask(XIL_EXCEPTION_IRQ);
#if LASER_UDP_DEBUG
    xil_printf("lwIP IRQ platform setup done: scugic_device_id=%u\r\n",
               (unsigned int)XPAR_SCUGIC_0_DEVICE_ID);
#endif
}

static uint32_t laser_rate_id_from_mbps(uint32_t target_mbps)
{
    if (target_mbps == 500U) {
        return LASER_RATE_ID_500M;
    }
    if (target_mbps == 1000U) {
        return LASER_RATE_ID_1000M;
    }
    if (target_mbps == 1250U) {
        return LASER_RATE_ID_1250M;
    }
    if (target_mbps == 2500U) {
        return LASER_RATE_ID_2500M;
    }
    if (target_mbps == 5000U) {
        return LASER_RATE_ID_5000M;
    }
    if (target_mbps == 3125U) {
        return LASER_RATE_ID_3125M;
    }
    if (target_mbps == 6250U) {
        return LASER_RATE_ID_6250M;
    }
    if (target_mbps == 10000U) {
        return LASER_RATE_ID_10000M;
    }
    if (target_mbps == 2000U) {
        return LASER_RATE_ID_2000M;
    }
    return LASER_RATE_ID_NONE;
}

static int laser_rate_wait_tx_idle(LaserGpio *gpio)
{
    uint32_t i;
    uint32_t status;

    for (i = 0U; i < LASER_RATE_QUIESCE_WAIT_ITERATIONS; ++i) {
        status = laser_gpio_read_status(gpio);
        if (((status & LASER_STATUS_BUSY) == 0U) ||
            ((status & LASER_STATUS_DONE) != 0U)) {
            return XST_SUCCESS;
        }
        usleep(100U);
    }

    return XST_FAILURE;
}

static void print_netif_debug_once(const struct netif *netif,
                                   const unsigned char *mac_address)
{
#if LASER_UDP_DEBUG
    xil_printf("MAC = %02x:%02x:%02x:%02x:%02x:%02x\r\n",
               mac_address[0], mac_address[1], mac_address[2],
               mac_address[3], mac_address[4], mac_address[5]);
    xil_printf("netif ip      = %u.%u.%u.%u\r\n",
               ip4_addr1(netif_ip4_addr(netif)), ip4_addr2(netif_ip4_addr(netif)),
               ip4_addr3(netif_ip4_addr(netif)), ip4_addr4(netif_ip4_addr(netif)));
    xil_printf("netif netmask = %u.%u.%u.%u\r\n",
               ip4_addr1(netif_ip4_netmask(netif)), ip4_addr2(netif_ip4_netmask(netif)),
               ip4_addr3(netif_ip4_netmask(netif)), ip4_addr4(netif_ip4_netmask(netif)));
    xil_printf("netif gateway = %u.%u.%u.%u\r\n",
               ip4_addr1(netif_ip4_gw(netif)), ip4_addr2(netif_ip4_gw(netif)),
               ip4_addr3(netif_ip4_gw(netif)), ip4_addr4(netif_ip4_gw(netif)));
    xil_printf("netif flags   = 0x%02x\r\n", netif->flags);
    xil_printf("netif is up   = %u\r\n", (unsigned int)netif_is_up(netif));
    xil_printf("netif link up = %u\r\n", (unsigned int)netif_is_link_up(netif));
    xil_printf("netif name    = %c%c\r\n", netif->name[0], netif->name[1]);
#else
    (void)netif;
    (void)mac_address;
#endif
}
#endif

static int laser_udp_init_control_hw(LaserGpio *gpio)
{
    uint32_t gt_status;
    int status;

    xil_printf("GPIO ctrl/status : 0x%08lx\r\n", (unsigned long)LASER_GPIO_BASEADDR);
    xil_printf("BRAM             : 0x%08lx\r\n", (unsigned long)LASER_BRAM_BASEADDR);
    xil_printf("GT status GPIO   : 0x%08lx\r\n", (unsigned long)LASER_GT_STATUS_GPIO_BASEADDR);
    xil_printf("Runtime rate set : CPLL/QPLL_DYNAMIC_500M_1000M_1250M_2000M_2500M_3125M_5000M_6250M_10000M, no AD9528/refclk/wide-range rate change\r\n");

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

#if LASER_HAS_LWIP
static char ascii_upper(char c)
{
    if (c >= 'a' && c <= 'z') {
        return (char)(c - ('a' - 'A'));
    }
    return c;
}

static int token_equals(const char *left, const char *right)
{
    while (*left != '\0' && *right != '\0') {
        if (ascii_upper(*left) != ascii_upper(*right)) {
            return 0;
        }
        ++left;
        ++right;
    }
    return *left == '\0' && *right == '\0';
}

static char *next_token(char **cursor)
{
    char *p = *cursor;
    char *start;

    while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') {
        ++p;
    }
    if (*p == '\0') {
        *cursor = p;
        return NULL;
    }

    start = p;
    while (*p != '\0' && *p != ' ' && *p != '\t' &&
           *p != '\r' && *p != '\n') {
        ++p;
    }
    if (*p != '\0') {
        *p = '\0';
        ++p;
    }
    *cursor = p;
    return start;
}

static int parse_u32_arg(char **cursor, uint32_t *value)
{
    char *token = next_token(cursor);
    char *end = NULL;
    unsigned long parsed;

    if (token == NULL || token[0] == '\0') {
        return XST_FAILURE;
    }
    parsed = strtoul(token, &end, 0);
    if (end == token || *end != '\0') {
        return XST_FAILURE;
    }
    *value = (uint32_t)parsed;
    return XST_SUCCESS;
}

static int command_has_extra_arg(char **cursor)
{
    return next_token(cursor) != NULL;
}

static int laser_rate_wait_done_or_error(uint32_t expected_rate_id,
                                         uint32_t *final_status)
{
    uint32_t i;
    uint32_t status;
    uint32_t rate_state;
    uint32_t current_rate_id;
    uint32_t error_code;

    for (i = 0U; i < LASER_RATE_SWITCH_POLL_ITERATIONS; ++i) {
        status = laser_gt_read_status();
        rate_state = LASER_GT_STATUS_RATE_STATE(status);
        current_rate_id = LASER_GT_STATUS_CURRENT_RATE_ID(status);
        error_code = LASER_GT_STATUS_RATE_ERROR_CODE(status);
        if ((status & LASER_GT_STATUS_RATE_ERROR) != 0U ||
            rate_state == LASER_RATE_STATE_ERROR ||
            error_code != LASER_RATE_ERR_NONE) {
            if (final_status != NULL) {
                *final_status = status;
            }
            return XST_SUCCESS;
        }
        if (rate_state == LASER_RATE_STATE_DONE &&
            current_rate_id == expected_rate_id &&
            error_code == LASER_RATE_ERR_NONE) {
            if (final_status != NULL) {
                *final_status = status;
            }
            return XST_SUCCESS;
        }
        usleep(100U);
    }

    if (final_status != NULL) {
        *final_status = laser_gt_read_status();
    }
    return XST_FAILURE;
}

static void handle_rate_command(LaserGpio *gpio, char **cursor, char *response,
                                size_t response_size)
{
    char *subcommand = next_token(cursor);
    uint32_t target_mbps;
    uint32_t rate_id;
    uint32_t gt_status;
    uint32_t current_rate_id;
    uint32_t current_rate_mbps;
    uint32_t rate_state;
    uint32_t error_code;
    GtRatePlan plan;
    int plan_status;

    if (subcommand == NULL) {
        (void)snprintf(response, response_size, "ERR RATE_COMMAND_ARGS");
        return;
    }

    if (token_equals(subcommand, "STATUS")) {
        if (command_has_extra_arg(cursor)) {
            (void)snprintf(response, response_size, "ERR RATE_STATUS_ARGS");
            return;
        }
        gt_status = laser_gt_read_status();
        current_rate_id = LASER_GT_STATUS_CURRENT_RATE_ID(gt_status);
        current_rate_mbps = laser_gt_rate_id_to_mbps(current_rate_id);
        rate_state = LASER_GT_STATUS_RATE_STATE(gt_status);
        error_code = LASER_GT_STATUS_RATE_ERROR_CODE(gt_status);
        (void)snprintf(response, response_size,
                       "OK RATE_STATUS mode=dynamic_500m_1000m_1250m_2000m_2500m_3125m_5000m_6250m_10000m_qpll current_rate=%lu current_rate_id=%lu rate_state=%s error_code=%s gt_drp_written=%lu mmcm_drp_written=%lu gt_drp_done=%lu mmcm_drp_done=%lu gt_ready=%lu raw=0x%08lx",
                       (unsigned long)current_rate_mbps,
                       (unsigned long)current_rate_id,
                       laser_gt_rate_state_name(rate_state),
                       laser_gt_rate_error_name(error_code),
                       (unsigned long)((gt_status & LASER_GT_STATUS_GT_DRP_WRITTEN) != 0U),
                       (unsigned long)((gt_status & LASER_GT_STATUS_MMCM_DRP_WRITTEN) != 0U),
                       (unsigned long)((gt_status & LASER_GT_STATUS_GT_DRP_DONE) != 0U),
                       (unsigned long)((gt_status & LASER_GT_STATUS_MMCM_DRP_DONE) != 0U),
                       (unsigned long)laser_gt_is_ready(gt_status),
                       (unsigned long)gt_status);
        return;
    }

    if (token_equals(subcommand, "LIST")) {
        if (command_has_extra_arg(cursor)) {
            (void)snprintf(response, response_size, "ERR RATE_LIST_ARGS");
            return;
        }
        (void)snprintf(response, response_size,
                       "OK RATE_LIST supported=500,1000,1250,2000,2500,3125,5000,6250,10000 refclk=125MHz pll=CPLL/QPLL ad9528_dynamic=0 qpll=1");
        return;
    }

    if (token_equals(subcommand, "PLAN")) {
        if (parse_u32_arg(cursor, &target_mbps) != XST_SUCCESS ||
            command_has_extra_arg(cursor)) {
            (void)snprintf(response, response_size, "ERR RATE_PLAN_ARGS");
            return;
        }

        plan_status = gt_rate_plan(target_mbps, &plan);
        if (plan_status == GT_RATE_PLAN_OK) {
            (void)snprintf(response, response_size,
                           "OK RATE_PLAN target_rate=%lu refclk=125MHz pll=%s QPLL_N=%lu TXOUT_DIV=%lu TXOUTCLK=%luHz TXUSRCLK=%luHz TXUSRCLK2=%luHz requires_gt_drp=1 requires_mmcm_drp=1 ad9528_dynamic=0 supported_dynamic=1",
                           (unsigned long)plan.target_mbps,
                           gt_rate_pll_source_name(plan.pll_source),
                           (unsigned long)plan.qpll_n,
                           (unsigned long)plan.txout_div,
                           (unsigned long)plan.txoutclk_hz,
                           (unsigned long)plan.txusrclk_hz,
                           (unsigned long)plan.txusrclk2_hz);
            return;
        }

        (void)snprintf(response, response_size,
                       "ERROR unsupported_rate target=%lu",
                       (unsigned long)target_mbps);
        return;
    }

    if (token_equals(subcommand, "SET")) {
        if (parse_u32_arg(cursor, &target_mbps) != XST_SUCCESS ||
            command_has_extra_arg(cursor)) {
            (void)snprintf(response, response_size, "ERR RATE_SET_ARGS");
            return;
        }

        plan_status = gt_rate_plan(target_mbps, &plan);
        rate_id = laser_rate_id_from_mbps(target_mbps);
        if (plan_status != GT_RATE_PLAN_OK || rate_id == LASER_RATE_ID_NONE) {
            (void)snprintf(response, response_size,
                           "ERROR unsupported_rate target=%lu",
                           (unsigned long)target_mbps);
            return;
        }

        gt_status = laser_gt_read_status();
        current_rate_id = LASER_GT_STATUS_CURRENT_RATE_ID(gt_status);
        current_rate_mbps = laser_gt_rate_id_to_mbps(current_rate_id);
        rate_state = LASER_GT_STATUS_RATE_STATE(gt_status);
        error_code = LASER_GT_STATUS_RATE_ERROR_CODE(gt_status);
        if (current_rate_id == rate_id &&
            rate_state == LASER_RATE_STATE_DONE &&
            (gt_status & LASER_GT_STATUS_RATE_ERROR) == 0U &&
            error_code == LASER_RATE_ERR_NONE &&
            laser_gt_is_ready(gt_status)) {
            (void)snprintf(response, response_size,
                           "OK RATE_SET target=%lu already_current_rate=1 current_rate=%lu",
                           (unsigned long)target_mbps,
                           (unsigned long)current_rate_mbps);
            return;
        }

        if (laser_rate_wait_tx_idle(gpio) != XST_SUCCESS) {
            (void)snprintf(response, response_size,
                           "ERROR RATE_SET_FAILED target=%lu state=SOFTWARE_QUIESCE error_code=TX_QUIESCE_TIMEOUT current_rate=%lu",
                           (unsigned long)target_mbps,
                           (unsigned long)current_rate_mbps);
            return;
        }

        gt_status = laser_gt_read_status();
        current_rate_id = LASER_GT_STATUS_CURRENT_RATE_ID(gt_status);
        current_rate_mbps = laser_gt_rate_id_to_mbps(current_rate_id);
        rate_state = LASER_GT_STATUS_RATE_STATE(gt_status);
        error_code = LASER_GT_STATUS_RATE_ERROR_CODE(gt_status);

        if ((gt_status & LASER_GT_STATUS_RATE_BUSY) != 0U) {
            (void)snprintf(response, response_size,
                           "ERROR RATE_SET_FAILED target=%lu state=%s error_code=RATE_BUSY current_rate=%lu",
                           (unsigned long)target_mbps,
                           laser_gt_rate_state_name(LASER_GT_STATUS_RATE_STATE(gt_status)),
                           (unsigned long)current_rate_mbps);
            return;
        }

        if (!laser_gt_is_ready(gt_status) &&
            rate_state != LASER_RATE_STATE_ERROR) {
            (void)snprintf(response, response_size,
                           "ERROR RATE_SET_FAILED target=%lu state=PRECHECK error_code=GT_NOT_READY current_rate=%lu",
                           (unsigned long)target_mbps,
                           (unsigned long)current_rate_mbps);
            return;
        }

        laser_gpio_rate_request(gpio, rate_id);
        if (laser_rate_wait_done_or_error(rate_id, &gt_status) != XST_SUCCESS) {
            rate_state = LASER_GT_STATUS_RATE_STATE(gt_status);
            error_code = LASER_GT_STATUS_RATE_ERROR_CODE(gt_status);
            current_rate_mbps = laser_gt_rate_id_to_mbps(
                LASER_GT_STATUS_CURRENT_RATE_ID(gt_status));
            (void)snprintf(response, response_size,
                           "ERROR RATE_SET_FAILED target=%lu state=%s error_code=TIMEOUT current_rate=%lu target_rate_id=%lu raw=0x%08lx",
                           (unsigned long)target_mbps,
                           laser_gt_rate_state_name(rate_state),
                           (unsigned long)current_rate_mbps,
                           (unsigned long)rate_id,
                           (unsigned long)gt_status);
            return;
        }

        rate_state = LASER_GT_STATUS_RATE_STATE(gt_status);
        error_code = LASER_GT_STATUS_RATE_ERROR_CODE(gt_status);
        current_rate_id = LASER_GT_STATUS_CURRENT_RATE_ID(gt_status);
        current_rate_mbps = laser_gt_rate_id_to_mbps(current_rate_id);
        if ((gt_status & LASER_GT_STATUS_RATE_ERROR) != 0U ||
            rate_state == LASER_RATE_STATE_ERROR ||
            error_code != LASER_RATE_ERR_NONE) {
            (void)snprintf(response, response_size,
                           "ERROR RATE_SET_FAILED target=%lu state=%s error_code=%s current_rate=%lu raw=0x%08lx",
                           (unsigned long)target_mbps,
                           laser_gt_rate_state_name(rate_state),
                           laser_gt_rate_error_name(error_code),
                           (unsigned long)current_rate_mbps,
                           (unsigned long)gt_status);
            return;
        }
        if (rate_state != LASER_RATE_STATE_DONE ||
            current_rate_id != rate_id) {
            (void)snprintf(response, response_size,
                           "ERROR RATE_SET_FAILED reason=CURRENT_RATE_MISMATCH target=%lu current=%lu state=%s error_code=%s raw=0x%08lx",
                           (unsigned long)target_mbps,
                           (unsigned long)current_rate_mbps,
                           laser_gt_rate_state_name(rate_state),
                           laser_gt_rate_error_name(error_code),
                           (unsigned long)gt_status);
            return;
        }

        (void)snprintf(response, response_size,
                       "OK RATE_SET target=%lu current_rate=%lu state=DONE gt_drp_written=%lu mmcm_drp_written=%lu",
                       (unsigned long)target_mbps,
                       (unsigned long)current_rate_mbps,
                       (unsigned long)((gt_status & LASER_GT_STATUS_GT_DRP_WRITTEN) != 0U),
                       (unsigned long)((gt_status & LASER_GT_STATUS_MMCM_DRP_WRITTEN) != 0U));
        return;
    }

    (void)snprintf(response, response_size, "ERR RATE_COMMAND");
}

static void handle_udp_command(LaserGpio *gpio,
                               char *request,
                               char *response,
                               size_t response_size)
{
    char *cursor = request;
    char *command = next_token(&cursor);
    uint32_t value;

    if (command == NULL) {
        (void)snprintf(response, response_size, "ERR EMPTY_COMMAND");
        return;
    }

    if (token_equals(command, "PING")) {
        (void)snprintf(response, response_size, "OK PONG");
        return;
    }

    if (token_equals(command, "READ_STATUS")) {
        value = laser_gpio_read_status(gpio);
        (void)snprintf(response, response_size, "OK STATUS 0x%08lx",
                       (unsigned long)value);
        return;
    }

    if (token_equals(command, "READ_GT_STATUS")) {
        value = laser_gt_read_status();
        (void)snprintf(response, response_size, "OK GT_STATUS 0x%08lx",
                       (unsigned long)value);
        return;
    }

    if (token_equals(command, "RATE")) {
        handle_rate_command(gpio, &cursor, response, response_size);
        return;
    }

    if (token_equals(command, "WRITE_CONFIG")) {
        LaserConfig config;
        uint32_t index;
        uint32_t gap_len_bits;
        uint32_t insert_after;
        uint32_t prbs_order;
        uint32_t phase_shift_en;
        uint32_t loop_en;

        if (parse_u32_arg(&cursor, &index) != XST_SUCCESS ||
            parse_u32_arg(&cursor, &config.seed) != XST_SUCCESS ||
            parse_u32_arg(&cursor, &config.repeat_cycles) != XST_SUCCESS ||
            parse_u32_arg(&cursor, &gap_len_bits) != XST_SUCCESS ||
            parse_u32_arg(&cursor, &insert_after) != XST_SUCCESS ||
            parse_u32_arg(&cursor, &prbs_order) != XST_SUCCESS ||
            parse_u32_arg(&cursor, &phase_shift_en) != XST_SUCCESS ||
            parse_u32_arg(&cursor, &loop_en) != XST_SUCCESS ||
            parse_u32_arg(&cursor, &config.pattern_low) != XST_SUCCESS ||
            parse_u32_arg(&cursor, &config.pattern_mid) != XST_SUCCESS ||
            parse_u32_arg(&cursor, &config.pattern_high) != XST_SUCCESS ||
            parse_u32_arg(&cursor, &config.pattern_top) != XST_SUCCESS ||
            command_has_extra_arg(&cursor)) {
            (void)snprintf(response, response_size,
                           "ERR WRITE_CONFIG_ARGS");
            return;
        }

        if (index > 255U || gap_len_bits > 255U ||
            insert_after > 65535U || prbs_order > 255U ||
            phase_shift_en > 1U || loop_en > 1U) {
            (void)snprintf(response, response_size,
                           "ERR WRITE_CONFIG_RANGE");
            return;
        }

        config.gap_len_bits = (uint8_t)gap_len_bits;
        config.insert_after = (uint16_t)insert_after;
        config.prbs_order = (uint8_t)prbs_order;
        config.phase_shift_en = (uint8_t)phase_shift_en;
        config.loop_en = (uint8_t)loop_en;

        if (laser_bram_write_config((uint8_t)index, &config) != XST_SUCCESS ||
            laser_bram_verify_config((uint8_t)index, &config) != XST_SUCCESS) {
            (void)snprintf(response, response_size,
                           "ERR WRITE_CONFIG_VERIFY");
            return;
        }

        (void)snprintf(response, response_size, "OK WRITE_CONFIG %lu",
                       (unsigned long)index);
        return;
    }

    if (token_equals(command, "SELECT_CONFIG")) {
        uint32_t index;
        uint32_t direct_source;
        uint32_t direct_len_127;

        if (parse_u32_arg(&cursor, &index) != XST_SUCCESS ||
            parse_u32_arg(&cursor, &direct_source) != XST_SUCCESS ||
            parse_u32_arg(&cursor, &direct_len_127) != XST_SUCCESS ||
            command_has_extra_arg(&cursor)) {
            (void)snprintf(response, response_size,
                           "ERR SELECT_CONFIG_ARGS");
            return;
        }
        if (index > 255U || direct_source > 1U || direct_len_127 > 1U) {
            (void)snprintf(response, response_size,
                           "ERR SELECT_CONFIG_RANGE");
            return;
        }
        laser_gpio_select_config(gpio, (uint8_t)index,
                                 direct_source != 0U,
                                 direct_len_127 != 0U);
        (void)snprintf(response, response_size, "OK SELECT_CONFIG %lu %lu %lu",
                       (unsigned long)index,
                       (unsigned long)direct_source,
                       (unsigned long)direct_len_127);
        return;
    }

    if (token_equals(command, "APPLY")) {
        laser_gpio_toggle_apply(gpio);
        (void)snprintf(response, response_size, "OK APPLY");
        return;
    }

    if (token_equals(command, "ENABLE")) {
        laser_gpio_set_enable(gpio, 1);
        (void)snprintf(response, response_size, "OK ENABLE");
        return;
    }

    if (token_equals(command, "DISABLE")) {
        laser_gpio_set_enable(gpio, 0);
        (void)snprintf(response, response_size, "OK DISABLE");
        return;
    }

    if (token_equals(command, "SOFT_RESET")) {
        laser_gpio_soft_reset(gpio);
        (void)snprintf(response, response_size, "OK SOFT_RESET");
        return;
    }

    (void)snprintf(response, response_size, "ERR UNKNOWN_COMMAND");
}

static void copy_udp_payload(struct pbuf *packet, char *buffer, size_t size)
{
    struct pbuf *fragment = packet;
    size_t copied = 0U;

    while (fragment != NULL && copied + 1U < size) {
        size_t fragment_len = fragment->len;
        if (fragment_len > size - copied - 1U) {
            fragment_len = size - copied - 1U;
        }
        (void)memcpy(&buffer[copied], fragment->payload, fragment_len);
        copied += fragment_len;
        fragment = fragment->next;
    }
    buffer[copied] = '\0';
}

static void send_udp_response(struct udp_pcb *pcb, const ip_addr_t *addr,
                              u16_t port, const char *text)
{
    size_t len = strlen(text);
    struct pbuf *response = pbuf_alloc(PBUF_TRANSPORT, (u16_t)len, PBUF_RAM);
    err_t err;

#if LASER_UDP_DEBUG
    xil_printf("UDP TX response=%s\r\n", text);
#endif
    if (response == NULL) {
        xil_printf("UDP TX pbuf_alloc failed\r\n");
        return;
    }
    (void)memcpy(response->payload, text, len);
    err = udp_sendto(pcb, response, addr, port);
    if (err != ERR_OK) {
        xil_printf("UDP TX send err=%d\r\n", (int)err);
    }
    pbuf_free(response);
}

static void laser_udp_recv(void *arg, struct udp_pcb *pcb, struct pbuf *packet,
                           const ip_addr_t *addr, u16_t port)
{
    LaserGpio *gpio = (LaserGpio *)arg;
    char request[LASER_UDP_MAX_PAYLOAD];
    char response[LASER_UDP_MAX_RESPONSE];

    if (packet == NULL) {
        return;
    }
#if LASER_UDP_DEBUG
    xil_printf("UDP RX callback fired\r\n");
    xil_printf("UDP RX len=%u\r\n", (unsigned int)packet->tot_len);
#endif
    copy_udp_payload(packet, request, sizeof(request));
    handle_udp_command(gpio, request, response, sizeof(response));
    send_udp_response(pcb, addr, port, response);
    pbuf_free(packet);
}

int laser_udp_server_run(void)
{
    static struct netif server_netif;
    static LaserGpio gpio;
    struct udp_pcb *pcb;
    ip_addr_t ipaddr;
    ip_addr_t netmask;
    ip_addr_t gateway;
    unsigned char mac_address[] = { 0x02U, 0x00U, 0x00U, 0x00U, 0x00U, 0x01U };
    int status;
    uint32_t input_called_count = 0U;
    uint32_t input_nonzero_count = 0U;
    uint32_t loop_count = 0U;

    xil_printf("\r\n=== laser_tx UDP_SERVER / 500M/1000M/1250M/2000M/2500M/3125M/5000M/6250M/10000M dynamic rate switch ===\r\n");
    xil_printf("UDP purpose      : control layer + real GTX TXOUT_DIV/CPLL/MMCM DRP switch for fixed 125MHz CPLL profiles only\r\n");
    xil_printf("UDP commands     : PING READ_STATUS READ_GT_STATUS WRITE_CONFIG SELECT_CONFIG APPLY ENABLE DISABLE SOFT_RESET rate status rate list rate plan <Mbps> rate set <Mbps>\r\n");
    xil_printf("UDP listen       : %u.%u.%u.%u:%u\r\n",
               LASER_UDP_IP0, LASER_UDP_IP1, LASER_UDP_IP2, LASER_UDP_IP3,
               LASER_UDP_PORT);
    xil_printf("Power-up rate    : %lu Mb/s\r\n", (unsigned long)LASER_STATIC_RATE_MBPS);
    xil_printf("AD9528 dynamic   : not configured in UDP mode\r\n");

    status = laser_udp_init_control_hw(&gpio);
    if (status != XST_SUCCESS) {
        return status;
    }

    lwip_init();
    laser_lwip_platform_setup_interrupts();
    IP4_ADDR(&ipaddr, LASER_UDP_IP0, LASER_UDP_IP1, LASER_UDP_IP2, LASER_UDP_IP3);
    IP4_ADDR(&netmask, LASER_UDP_NETMASK0, LASER_UDP_NETMASK1,
             LASER_UDP_NETMASK2, LASER_UDP_NETMASK3);
    IP4_ADDR(&gateway, LASER_UDP_GATEWAY0, LASER_UDP_GATEWAY1,
             LASER_UDP_GATEWAY2, LASER_UDP_GATEWAY3);

    if (xemac_add(&server_netif, &ipaddr, &netmask, &gateway,
                  mac_address, XPAR_XEMACPS_0_BASEADDR) == NULL) {
        xil_printf("ERROR: xemac_add failed\r\n");
        return XST_FAILURE;
    }

    netif_set_default(&server_netif);
    netif_set_up(&server_netif);
    netif_set_link_up(&server_netif);
    print_netif_debug_once(&server_netif, mac_address);

    pcb = udp_new();
    if (pcb == NULL) {
        xil_printf("ERROR: udp_new failed\r\n");
        return XST_FAILURE;
    }
    if (udp_bind(pcb, IP_ADDR_ANY, LASER_UDP_PORT) != ERR_OK) {
        xil_printf("ERROR: udp_bind failed\r\n");
        udp_remove(pcb);
        return XST_FAILURE;
    }

    udp_recv(pcb, laser_udp_recv, &gpio);
    xil_printf("UDP server ready. Dynamic rate switch supports fixed 500M, 1000M, 1250M, 2000M, 2500M, 3125M, 5000M, 6250M and 10000M profiles.\r\n");

    while (1) {
        int input_ret;

        input_ret = xemacif_input(&server_netif);
        ++input_called_count;
        if (input_ret != 0) {
            ++input_nonzero_count;
#if LASER_UDP_DEBUG
            xil_printf("xemacif_input ret=%d\r\n", input_ret);
#endif
        }
        ++loop_count;
        if (loop_count >= LASER_UDP_INPUT_HEARTBEAT_LOOPS) {
#if LASER_UDP_DEBUG
            xil_printf("UDP loop alive: xemacif_input_called_count=%u, xemacif_input_nonzero_count=%u\r\n",
                       (unsigned int)input_called_count,
                       (unsigned int)input_nonzero_count);
#endif
            loop_count = 0U;
        }
    }
}
#else
int laser_udp_server_run(void)
{
    xil_printf("\r\n=== laser_tx UDP_SERVER / fixed GT Profile 0 ===\r\n");
    xil_printf("ERROR: current BSP does not provide lwIP headers/libraries.\r\n");
    xil_printf("Searched by compile-time __has_include for lwip/init.h, lwip/udp.h and netif/xadapter.h.\r\n");
    xil_printf("Enable lwIP in the Vitis BSP/platform, then rebuild this app.\r\n");
    xil_printf("This build needs lwIP for the UDP-controlled 500M/1000M/1250M/2000M/2500M/3125M/5000M/6250M/10000M dynamic rate switch.\r\n");
    return XST_FAILURE;
}
#endif
