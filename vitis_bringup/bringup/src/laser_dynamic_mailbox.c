#include "laser_dynamic_mailbox.h"

#include "laser_dynamic_rate_descriptor.h"
#include "laser_hw.h"
#include "sleep.h"
#include "xil_io.h"
#include "xstatus.h"

#include <string.h>

#define MAILBOX_GPIO_DATA_OFFSET 0x00U
#define MAILBOX_GPIO_TRI_OFFSET  0x04U
#define MAILBOX_STATUS_OFFSET    0x08U
#define MAILBOX_STATUS_TRI       0x0cU

#define MAILBOX_TOGGLE_PREPARE        0x01U
#define MAILBOX_TOGGLE_REFCLK_READY   0x02U
#define MAILBOX_TOGGLE_ABORT          0x04U
#define MAILBOX_TOGGLE_ROLLBACK_READY 0x08U

static uint32_t mailbox_control;
static uint8_t mailbox_initialized;

static uint32_t descriptor_cpll_image(const RuntimeRatePlan *plan)
{
    return (plan->gt_pll_type == LASER_RUNTIME_PLL_CPLL) ?
        (uint32_t)plan->gt_cpll_drp_value : 0U;
}

static int build_descriptor(const RuntimeRatePlan *plan, uint32_t sequence,
                            uint32_t *words)
{
    uint32_t i;
    if (plan == NULL || words == NULL || !plan->plan_executable ||
        plan->mmcm_write_count > LASER_DYN_DESC_MAX_MMCM_WRITES ||
        !plan->gt_drp_encoding_confirmed) {
        return XST_INVALID_PARAM;
    }
    memset(words, 0, LASER_DYN_DESC_WORDS * sizeof(words[0]));
    words[LASER_DYN_WORD_MAGIC] = LASER_DYN_DESC_MAGIC;
    words[LASER_DYN_WORD_VERSION_COUNT] = LASER_DYN_DESC_VERSION_COUNT;
    words[LASER_DYN_WORD_SEQUENCE] = sequence;
    words[LASER_DYN_WORD_FLAGS] = 1U; /* AD9528 OUT0 / GTNORTHREFCLK0 */
    words[LASER_DYN_WORD_REQUESTED_RATE_LO] =
        (uint32_t)plan->requested_line_rate_bps;
    words[LASER_DYN_WORD_REQUESTED_RATE_HI] =
        (uint32_t)(plan->requested_line_rate_bps >> 32);
    words[LASER_DYN_WORD_ACTUAL_RATE_LO] =
        (uint32_t)plan->actual_line_rate_bps;
    words[LASER_DYN_WORD_ACTUAL_RATE_HI] =
        (uint32_t)(plan->actual_line_rate_bps >> 32);
    words[LASER_DYN_WORD_ERROR_PPM] = (uint32_t)plan->line_rate_error_ppm;
    words[LASER_DYN_WORD_GT_PLL] =
        (descriptor_cpll_image(plan) << 2) | (plan->gt_pll_type & 0x3U);
    words[LASER_DYN_WORD_GT_TXOUT] = plan->gt_txout_div_encoding & 0x7U;
    words[LASER_DYN_WORD_VERIFY_EXPECTED] = plan->verify_expected_count;
    words[LASER_DYN_WORD_VERIFY_TOLERANCE] = plan->verify_tolerance;
    words[LASER_DYN_WORD_MMCM_COUNT] = plan->mmcm_write_count;
    words[LASER_DYN_WORD_EOM_CONFIG] = plan->eom_subdiv_log2 & 0x7U;
    for (i = 0U; i < plan->mmcm_write_count; ++i) {
        words[LASER_DYN_WORD_MMCM_BASE + i * 2U] =
            plan->mmcm_writes[i].address;
        words[LASER_DYN_WORD_MMCM_BASE + i * 2U + 1U] =
            plan->mmcm_writes[i].value;
    }
    words[LASER_DYN_WORD_CRC32] = laser_dyn_descriptor_crc32(words);
    return XST_SUCCESS;
}

static void toggle_control(uint32_t mask)
{
    mailbox_control ^= mask;
    Xil_Out32(LASER_DYNAMIC_MAILBOX_GPIO_BASEADDR +
              MAILBOX_GPIO_DATA_OFFSET, mailbox_control);
}

static int sequence_matches(uint32_t sequence,
                            const LaserDynamicMailboxStatus *status)
{
    return status->sequence == (uint16_t)sequence;
}

int laser_dynamic_mailbox_init(void)
{
    Xil_Out32(LASER_DYNAMIC_MAILBOX_GPIO_BASEADDR + MAILBOX_GPIO_TRI_OFFSET,
              0x00000000U);
    Xil_Out32(LASER_DYNAMIC_MAILBOX_GPIO_BASEADDR + MAILBOX_STATUS_TRI,
              0xffffffffU);
    mailbox_control = Xil_In32(LASER_DYNAMIC_MAILBOX_GPIO_BASEADDR +
                               MAILBOX_GPIO_DATA_OFFSET) & 0x0fU;
    mailbox_initialized = 1U;
    return XST_SUCCESS;
}

int laser_dynamic_mailbox_read_status(LaserDynamicMailboxStatus *status)
{
    uint32_t raw;
    if (status == NULL || !mailbox_initialized) return XST_FAILURE;
    raw = Xil_In32(LASER_DYNAMIC_MAILBOX_GPIO_BASEADDR +
                   MAILBOX_STATUS_OFFSET);
    memset(status, 0, sizeof(*status));
    status->raw = raw;
    status->busy = (uint8_t)(raw & 1U);
    status->prepared = (uint8_t)((raw >> 1) & 1U);
    status->switch_done = (uint8_t)((raw >> 2) & 1U);
    status->switch_error = (uint8_t)((raw >> 3) & 1U);
    status->rollback_done = (uint8_t)((raw >> 4) & 1U);
    status->descriptor_valid = (uint8_t)((raw >> 5) & 1U);
    status->verify_pass = (uint8_t)((raw >> 6) & 1U);
    status->sequence_error = (uint8_t)((raw >> 7) & 1U);
    status->failed_stage = (uint8_t)((raw >> 8) & 0xffU);
    status->sequence = (uint16_t)(raw >> 16);
    return XST_SUCCESS;
}

int laser_dynamic_mailbox_prepare(const RuntimeRatePlan *plan,
                                  uint32_t sequence)
{
    uint32_t words[LASER_DYN_DESC_WORDS];
    uint32_t i;
    int status;
    if (!mailbox_initialized) return XST_FAILURE;
    status = build_descriptor(plan, sequence, words);
    if (status != XST_SUCCESS) return status;
    for (i = 0U; i < LASER_DYN_DESC_WORDS; ++i) {
        Xil_Out32(LASER_DYNAMIC_DESCRIPTOR_BRAM_BASEADDR + i * 4U, words[i]);
    }
    toggle_control(MAILBOX_TOGGLE_PREPARE);
    return XST_SUCCESS;
}

int laser_dynamic_mailbox_wait_prepared(uint32_t sequence,
                                        uint32_t timeout_ms,
                                        LaserDynamicMailboxStatus *final_status)
{
    uint32_t elapsed;
    LaserDynamicMailboxStatus local;
    for (elapsed = 0U; elapsed < timeout_ms; ++elapsed) {
        if (laser_dynamic_mailbox_read_status(&local) != XST_SUCCESS)
            return XST_FAILURE;
        if (sequence_matches(sequence, &local) && local.prepared &&
            local.descriptor_valid) {
            if (final_status != NULL) *final_status = local;
            return XST_SUCCESS;
        }
        if (sequence_matches(sequence, &local) &&
            (local.switch_error || local.sequence_error)) break;
        usleep(1000U);
    }
    (void)laser_dynamic_mailbox_read_status(&local);
    if (final_status != NULL) *final_status = local;
    return XST_FAILURE;
}

int laser_dynamic_mailbox_signal_refclk_ready(void)
{
    if (!mailbox_initialized) return XST_FAILURE;
    toggle_control(MAILBOX_TOGGLE_REFCLK_READY);
    return XST_SUCCESS;
}

int laser_dynamic_mailbox_wait_switch(uint32_t sequence,
                                      uint32_t timeout_ms,
                                      LaserDynamicMailboxStatus *final_status)
{
    uint32_t elapsed;
    LaserDynamicMailboxStatus local;
    for (elapsed = 0U; elapsed < timeout_ms; ++elapsed) {
        if (laser_dynamic_mailbox_read_status(&local) != XST_SUCCESS)
            return XST_FAILURE;
        if (sequence_matches(sequence, &local) && local.switch_done &&
            local.verify_pass && !local.switch_error) {
            if (final_status != NULL) *final_status = local;
            return XST_SUCCESS;
        }
        if (sequence_matches(sequence, &local) &&
            (local.switch_error || local.sequence_error)) break;
        usleep(1000U);
    }
    (void)laser_dynamic_mailbox_read_status(&local);
    if (final_status != NULL) *final_status = local;
    return XST_FAILURE;
}

int laser_dynamic_mailbox_signal_abort(void)
{
    if (!mailbox_initialized) return XST_FAILURE;
    toggle_control(MAILBOX_TOGGLE_ABORT);
    return XST_SUCCESS;
}

int laser_dynamic_mailbox_signal_rollback_ready(void)
{
    if (!mailbox_initialized) return XST_FAILURE;
    toggle_control(MAILBOX_TOGGLE_ROLLBACK_READY);
    return XST_SUCCESS;
}

int laser_dynamic_mailbox_wait_rollback(uint32_t sequence,
                                        uint32_t timeout_ms,
                                        LaserDynamicMailboxStatus *final_status)
{
    uint32_t elapsed;
    LaserDynamicMailboxStatus local;
    for (elapsed = 0U; elapsed < timeout_ms; ++elapsed) {
        if (laser_dynamic_mailbox_read_status(&local) != XST_SUCCESS)
            return XST_FAILURE;
        if (sequence_matches(sequence, &local) && local.rollback_done &&
            !local.busy) {
            if (final_status != NULL) *final_status = local;
            return XST_SUCCESS;
        }
        usleep(1000U);
    }
    (void)laser_dynamic_mailbox_read_status(&local);
    if (final_status != NULL) *final_status = local;
    return XST_FAILURE;
}
