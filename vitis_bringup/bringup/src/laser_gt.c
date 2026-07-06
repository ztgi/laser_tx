#include "laser_gt.h"
#include "laser_hw.h"
#include "xgpio.h"
#include "xil_printf.h"
#include "xstatus.h"

static XGpio gt_status_gpio;
static int gt_status_initialized;

int laser_gt_init(void)
{
    int status = XGpio_Initialize(&gt_status_gpio, LASER_GT_STATUS_GPIO_DEVICE_ID);
    if (status != XST_SUCCESS) {
        return status;
    }
    XGpio_SetDataDirection(&gt_status_gpio, LASER_GT_STATUS_CHANNEL, 0xffffffffU);
    gt_status_initialized = 1;
    return XST_SUCCESS;
}

uint32_t laser_gt_read_status(void)
{
    if (!gt_status_initialized) {
        return 0U;
    }
    return XGpio_DiscreteRead(&gt_status_gpio, LASER_GT_STATUS_CHANNEL);
}

int laser_gt_is_ready(uint32_t status)
{
    return (status & LASER_GT_STATUS_READY) != 0U;
}

uint32_t laser_gt_rate_id_to_mbps(uint32_t rate_id)
{
    switch (rate_id) {
    case 1U:
        return 500U;
    case 2U:
        return 1000U;
    case 3U:
        return 2000U;
    case 4U:
        return 1250U;
    case 5U:
        return 2500U;
    case 6U:
        return 5000U;
    case 7U:
        return 3125U;
    case 8U:
        return 6250U;
    default:
        return 0U;
    }
}

const char *laser_gt_rate_state_name(uint32_t state)
{
    switch (state) {
    case LASER_RATE_STATE_IDLE:
        return "RATE_IDLE";
    case LASER_RATE_STATE_REQUEST:
        return "RATE_REQUEST";
    case LASER_RATE_STATE_VALIDATE:
        return "RATE_VALIDATE";
    case LASER_RATE_STATE_QUIESCE_TX:
        return "RATE_QUIESCE_TX";
    case LASER_RATE_STATE_ASSERT_RESET:
        return "RATE_ASSERT_RESET";
    case LASER_RATE_STATE_PROGRAM_GT_DRP:
        return "RATE_PROGRAM_GT_DRP";
    case LASER_RATE_STATE_PROGRAM_MMCM_DRP:
        return "RATE_PROGRAM_MMCM_DRP";
    case LASER_RATE_STATE_RELEASE_RESET:
        return "RATE_RELEASE_RESET";
    case LASER_RATE_STATE_WAIT_LOCK:
        return "RATE_WAIT_LOCK";
    case LASER_RATE_STATE_VERIFY_RATE:
        return "RATE_VERIFY_RATE";
    case LASER_RATE_STATE_DONE:
        return "RATE_DONE";
    case LASER_RATE_STATE_WAIT_MMCM_RESET_RELEASE:
        return "RATE_WAIT_MMCM_RESET_RELEASE";
    case LASER_RATE_STATE_ERROR:
        return "RATE_ERROR";
    default:
        return "RATE_UNKNOWN";
    }
}

const char *laser_gt_rate_error_name(uint32_t error_code)
{
    switch (error_code) {
    case LASER_RATE_ERR_NONE:
        return "NONE";
    case LASER_RATE_ERR_UNSUPPORTED_RATE:
        return "UNSUPPORTED_RATE";
    case LASER_RATE_ERR_TX_QUIESCE_TIMEOUT:
        return "TX_QUIESCE_TIMEOUT";
    case LASER_RATE_ERR_GT_DRP_TIMEOUT:
        return "GT_DRP_TIMEOUT";
    case LASER_RATE_ERR_GT_DRP_READBACK_MISMATCH:
        return "GT_DRP_READBACK_MISMATCH";
    case LASER_RATE_ERR_MMCM_DRP_TIMEOUT:
        return "MMCM_DRP_TIMEOUT";
    case LASER_RATE_ERR_MMCM_LOCK_TIMEOUT:
        return "MMCM_LOCK_TIMEOUT";
    case LASER_RATE_ERR_TX_RESETDONE_TIMEOUT:
        return "TX_RESETDONE_TIMEOUT";
    case LASER_RATE_ERR_GT_READY_TIMEOUT:
        return "GT_READY_TIMEOUT";
    case LASER_RATE_ERR_TXUSRCLK2_NOT_ALIVE:
        return "TXUSRCLK2_NOT_ALIVE";
    case LASER_RATE_ERR_TXUSRCLK2_FREQ_OUT_OF_WINDOW:
        return "TXUSRCLK2_FREQ_OUT_OF_WINDOW";
    case LASER_RATE_ERR_CPLL_LOCK_TIMEOUT:
        return "CPLL_LOCK_TIMEOUT";
    default:
        return "UNKNOWN";
    }
}

void laser_gt_print_status(uint32_t status)
{
    uint32_t rate_id = LASER_GT_STATUS_CURRENT_RATE_ID(status);
    uint32_t rate_state = LASER_GT_STATUS_RATE_STATE(status);
    uint32_t error_code = LASER_GT_STATUS_RATE_ERROR_CODE(status);

    xil_printf("GT status       : 0x%08lx\r\n", (unsigned long)status);
    xil_printf("  cpll_lock     : %lu\r\n", (unsigned long)((status & LASER_GT_STATUS_CPLL_LOCK) != 0U));
    xil_printf("  tx_reset_done : %lu\r\n", (unsigned long)((status & LASER_GT_STATUS_TX_RESET_DONE) != 0U));
    xil_printf("  gt_ready      : %lu\r\n", (unsigned long)laser_gt_is_ready(status));
    xil_printf("  ctrl_reset    : %lu\r\n", (unsigned long)((status & LASER_GT_STATUS_CTRL_RESET) != 0U));
    xil_printf("  current_rate  : id=%lu mbps=%lu\r\n",
               (unsigned long)rate_id,
               (unsigned long)laser_gt_rate_id_to_mbps(rate_id));
    xil_printf("  rate_state    : %s (0x%02lx)\r\n",
               laser_gt_rate_state_name(rate_state),
               (unsigned long)rate_state);
    xil_printf("  rate_error    : %lu code=%s (0x%02lx)\r\n",
               (unsigned long)((status & LASER_GT_STATUS_RATE_ERROR) != 0U),
               laser_gt_rate_error_name(error_code),
               (unsigned long)error_code);
    xil_printf("  gt_drp        : written=%lu done=%lu\r\n",
               (unsigned long)((status & LASER_GT_STATUS_GT_DRP_WRITTEN) != 0U),
               (unsigned long)((status & LASER_GT_STATUS_GT_DRP_DONE) != 0U));
    xil_printf("  mmcm_drp      : written=%lu done=%lu\r\n",
               (unsigned long)((status & LASER_GT_STATUS_MMCM_DRP_WRITTEN) != 0U),
               (unsigned long)((status & LASER_GT_STATUS_MMCM_DRP_DONE) != 0U));
}
