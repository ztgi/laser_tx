#include "gt_rate_plan.h"

#ifndef GT_RATE_PLAN_HOST_TEST
#include "laser_gpio.h"
#include "xil_printf.h"
#else
#define LASER_RATE_ID_500M   1U
#define LASER_RATE_ID_1000M  2U
#define LASER_RATE_ID_2000M  3U
#define LASER_RATE_ID_1250M  4U
#define LASER_RATE_ID_2500M  5U
#define LASER_RATE_ID_5000M  6U
#define LASER_RATE_ID_3125M  7U
#define LASER_RATE_ID_6250M  8U
#define LASER_RATE_ID_10000M 9U
#define LASER_RATE_ID_625M   10U
#define LASER_RATE_ID_4000M  11U
#endif

typedef struct {
    uint32_t rate_mbps;
    const char *reason;
} GtBlockedRate;

static const GtBlockedRate gt_blocked_rate_table[] = {
    {3000U, "NO_LEGAL_VERIFIED_125M_CPLL_PROFILE"}
};

/* Sorted by rate_mbps. Values are copied from the active RTL profile accessors:
 * FREQ_*_COUNT is a roughly 1 ms counter window, not hertz. */
static const GtRateProfile gt_rate_profile_table[] = {
    { .rate_mbps = 500U,   .rate_id = LASER_RATE_ID_500M,   .pll_source = GT_RATE_PLL_CPLL, .refclk_hz = 125000000U, .expected_txusrclk2_hz = 7812500U,   .freq_counter_min = 7700U,   .freq_counter_max = 7950U,   .cpll_drp_value = 0x1002U, .txout_div = 8U, .mmcm_profile_id = 1U, .qpll_n = 0U,  .qpll_required = 0U, .ad9528_dynamic_required = 0U, .board_verified = 1U },
    { .rate_mbps = 625U,   .rate_id = LASER_RATE_ID_625M,   .pll_source = GT_RATE_PLL_CPLL, .refclk_hz = 125000000U, .expected_txusrclk2_hz = 9765625U,   .freq_counter_min = 9600U,   .freq_counter_max = 9950U,   .cpll_drp_value = 0x1003U, .txout_div = 8U, .mmcm_profile_id = 10U, .qpll_n = 0U,  .qpll_required = 0U, .ad9528_dynamic_required = 0U, .board_verified = 0U },
    { .rate_mbps = 1000U,  .rate_id = LASER_RATE_ID_1000M,  .pll_source = GT_RATE_PLL_CPLL, .refclk_hz = 125000000U, .expected_txusrclk2_hz = 15625000U,  .freq_counter_min = 15400U,  .freq_counter_max = 15900U,  .cpll_drp_value = 0x1002U, .txout_div = 4U, .mmcm_profile_id = 2U, .qpll_n = 0U,  .qpll_required = 0U, .ad9528_dynamic_required = 0U, .board_verified = 1U },
    { .rate_mbps = 1250U,  .rate_id = LASER_RATE_ID_1250M,  .pll_source = GT_RATE_PLL_CPLL, .refclk_hz = 125000000U, .expected_txusrclk2_hz = 19531250U,  .freq_counter_min = 19200U,  .freq_counter_max = 19850U,  .cpll_drp_value = 0x1003U, .txout_div = 4U, .mmcm_profile_id = 4U, .qpll_n = 0U,  .qpll_required = 0U, .ad9528_dynamic_required = 0U, .board_verified = 1U },
    { .rate_mbps = 2000U,  .rate_id = LASER_RATE_ID_2000M,  .pll_source = GT_RATE_PLL_CPLL, .refclk_hz = 125000000U, .expected_txusrclk2_hz = 31250000U,  .freq_counter_min = 30800U,  .freq_counter_max = 31800U,  .cpll_drp_value = 0x1002U, .txout_div = 2U, .mmcm_profile_id = 3U, .qpll_n = 0U,  .qpll_required = 0U, .ad9528_dynamic_required = 0U, .board_verified = 1U },
    { .rate_mbps = 2500U,  .rate_id = LASER_RATE_ID_2500M,  .pll_source = GT_RATE_PLL_CPLL, .refclk_hz = 125000000U, .expected_txusrclk2_hz = 39062500U,  .freq_counter_min = 38400U,  .freq_counter_max = 39750U,  .cpll_drp_value = 0x1003U, .txout_div = 2U, .mmcm_profile_id = 5U, .qpll_n = 0U,  .qpll_required = 0U, .ad9528_dynamic_required = 0U, .board_verified = 1U },
    { .rate_mbps = 3125U,  .rate_id = LASER_RATE_ID_3125M,  .pll_source = GT_RATE_PLL_CPLL, .refclk_hz = 125000000U, .expected_txusrclk2_hz = 48828125U,  .freq_counter_min = 48000U,  .freq_counter_max = 49700U,  .cpll_drp_value = 0x1083U, .txout_div = 2U, .mmcm_profile_id = 7U, .qpll_n = 0U,  .qpll_required = 0U, .ad9528_dynamic_required = 0U, .board_verified = 1U },
    { .rate_mbps = 4000U,  .rate_id = LASER_RATE_ID_4000M,  .pll_source = GT_RATE_PLL_CPLL, .refclk_hz = 125000000U, .expected_txusrclk2_hz = 62500000U,  .freq_counter_min = 61400U,  .freq_counter_max = 63600U,  .cpll_drp_value = 0x1002U, .txout_div = 1U, .mmcm_profile_id = 11U, .qpll_n = 0U,  .qpll_required = 0U, .ad9528_dynamic_required = 0U, .board_verified = 0U },
    { .rate_mbps = 5000U,  .rate_id = LASER_RATE_ID_5000M,  .pll_source = GT_RATE_PLL_CPLL, .refclk_hz = 125000000U, .expected_txusrclk2_hz = 78125000U,  .freq_counter_min = 76800U,  .freq_counter_max = 79500U,  .cpll_drp_value = 0x1003U, .txout_div = 1U, .mmcm_profile_id = 6U, .qpll_n = 0U,  .qpll_required = 0U, .ad9528_dynamic_required = 0U, .board_verified = 1U },
    { .rate_mbps = 6250U,  .rate_id = LASER_RATE_ID_6250M,  .pll_source = GT_RATE_PLL_CPLL, .refclk_hz = 125000000U, .expected_txusrclk2_hz = 97656250U,  .freq_counter_min = 96000U,  .freq_counter_max = 99500U,  .cpll_drp_value = 0x1083U, .txout_div = 1U, .mmcm_profile_id = 8U, .qpll_n = 0U,  .qpll_required = 0U, .ad9528_dynamic_required = 0U, .board_verified = 1U },
    { .rate_mbps = 10000U, .rate_id = LASER_RATE_ID_10000M, .pll_source = GT_RATE_PLL_QPLL, .refclk_hz = 125000000U, .expected_txusrclk2_hz = 156250000U, .freq_counter_min = 153000U, .freq_counter_max = 159500U, .cpll_drp_value = 0x0000U, .txout_div = 1U, .mmcm_profile_id = 9U, .qpll_n = 80U, .qpll_required = 1U, .ad9528_dynamic_required = 0U, .board_verified = 1U }
};

#define GT_RATE_PROFILE_COUNT \
    (sizeof(gt_rate_profile_table) / sizeof(gt_rate_profile_table[0]))

static const char *gt_rate_blocked_reason(uint32_t rate_mbps)
{
    size_t i;
    for (i = 0U; i < sizeof(gt_blocked_rate_table) / sizeof(gt_blocked_rate_table[0]); ++i) {
        if (gt_blocked_rate_table[i].rate_mbps == rate_mbps) {
            return gt_blocked_rate_table[i].reason;
        }
    }
    return NULL;
}

static void gt_rate_plan_clear(GtRatePlan *plan, uint32_t requested_rate_mbps)
{
    plan->result = GT_RATE_PLAN_UNSUPPORTED;
    plan->requested_rate_mbps = requested_rate_mbps;
    plan->selected_rate_mbps = 0U;
    plan->selected_rate_id = 0U;
    plan->nearest_lower_mbps = 0U;
    plan->nearest_upper_mbps = 0U;
    plan->absolute_error_mbps = 0U;
    plan->profile = NULL;
    plan->reason = "NO_VERIFIED_EXACT_PROFILE";
}

static void gt_rate_plan_set_bounds(uint32_t requested_rate_mbps, GtRatePlan *plan)
{
    size_t i;

    for (i = 0U; i < GT_RATE_PROFILE_COUNT; ++i) {
        if (gt_rate_profile_table[i].rate_mbps < requested_rate_mbps) {
            plan->nearest_lower_mbps = gt_rate_profile_table[i].rate_mbps;
        } else if (gt_rate_profile_table[i].rate_mbps > requested_rate_mbps) {
            plan->nearest_upper_mbps = gt_rate_profile_table[i].rate_mbps;
            break;
        }
    }
}

size_t gt_rate_profile_count(void)
{
    return GT_RATE_PROFILE_COUNT;
}

const GtRateProfile *gt_rate_profile_at(size_t index)
{
    return (index < GT_RATE_PROFILE_COUNT) ? &gt_rate_profile_table[index] : NULL;
}

const GtRateProfile *gt_rate_profile_from_rate_id(uint32_t rate_id)
{
    size_t i;
    for (i = 0U; i < GT_RATE_PROFILE_COUNT; ++i) {
        if (gt_rate_profile_table[i].rate_id == rate_id) {
            return &gt_rate_profile_table[i];
        }
    }
    return NULL;
}

uint32_t gt_rate_profile_rate_mbps_from_id(uint32_t rate_id)
{
    const GtRateProfile *profile = gt_rate_profile_from_rate_id(rate_id);
    return (profile == NULL) ? 0U : profile->rate_mbps;
}

int gt_rate_plan_exact(uint32_t requested_rate_mbps, GtRatePlan *plan)
{
    size_t i;

    if (plan == NULL) {
        return GT_RATE_PLAN_STATUS_BAD_ARG;
    }
    gt_rate_plan_clear(plan, requested_rate_mbps);
    gt_rate_plan_set_bounds(requested_rate_mbps, plan);
    for (i = 0U; i < GT_RATE_PROFILE_COUNT; ++i) {
        if (gt_rate_profile_table[i].rate_mbps == requested_rate_mbps &&
            gt_rate_profile_table[i].board_verified != 0U) {
            plan->result = GT_RATE_PLAN_EXACT;
            plan->selected_rate_mbps = requested_rate_mbps;
            plan->selected_rate_id = gt_rate_profile_table[i].rate_id;
            plan->profile = &gt_rate_profile_table[i];
            plan->reason = "VERIFIED_EXACT_PROFILE";
            return GT_RATE_PLAN_OK;
        }
    }
    plan->reason = gt_rate_blocked_reason(requested_rate_mbps);
    if (plan->reason == NULL) {
        plan->reason = "NO_VERIFIED_EXACT_PROFILE";
    }
    return GT_RATE_PLAN_STATUS_UNSUPPORTED;
}

int gt_rate_plan_lookup(uint32_t requested_rate_mbps, GtRatePlan *plan)
{
    size_t i;

    if (plan == NULL) {
        return GT_RATE_PLAN_STATUS_BAD_ARG;
    }
    gt_rate_plan_clear(plan, requested_rate_mbps);
    gt_rate_plan_set_bounds(requested_rate_mbps, plan);
    for (i = 0U; i < GT_RATE_PROFILE_COUNT; ++i) {
        if (gt_rate_profile_table[i].rate_mbps == requested_rate_mbps) {
            plan->result = GT_RATE_PLAN_EXACT;
            plan->selected_rate_mbps = requested_rate_mbps;
            plan->selected_rate_id = gt_rate_profile_table[i].rate_id;
            plan->profile = &gt_rate_profile_table[i];
            plan->reason = (plan->profile->board_verified != 0U) ?
                           "VERIFIED_EXACT_PROFILE" :
                           "CANDIDATE_PROFILE_BOARD_VALIDATION_REQUIRED";
            return GT_RATE_PLAN_OK;
        }
    }
    plan->reason = gt_rate_blocked_reason(requested_rate_mbps);
    if (plan->reason == NULL) {
        plan->reason = "NO_VERIFIED_EXACT_PROFILE";
    }
    return GT_RATE_PLAN_STATUS_UNSUPPORTED;
}

int gt_rate_plan_nearest(uint32_t requested_rate_mbps, GtRatePlan *plan)
{
    const GtRateProfile *best = NULL;
    uint32_t best_delta = 0U;
    size_t i;

    if (plan == NULL) {
        return GT_RATE_PLAN_STATUS_BAD_ARG;
    }
    if (gt_rate_plan_exact(requested_rate_mbps, plan) == GT_RATE_PLAN_OK) {
        return GT_RATE_PLAN_OK;
    }
    for (i = 0U; i < GT_RATE_PROFILE_COUNT; ++i) {
        const GtRateProfile *candidate = &gt_rate_profile_table[i];
        uint32_t delta = (candidate->rate_mbps > requested_rate_mbps) ?
                         (candidate->rate_mbps - requested_rate_mbps) :
                         (requested_rate_mbps - candidate->rate_mbps);
        if (candidate->board_verified != 0U &&
            (best == NULL || delta < best_delta ||
             (delta == best_delta && candidate->rate_mbps < best->rate_mbps))) {
            best = candidate;
            best_delta = delta;
        }
    }
    if (best == NULL) {
        return GT_RATE_PLAN_STATUS_UNSUPPORTED;
    }
    plan->result = GT_RATE_PLAN_NEAREST;
    plan->selected_rate_mbps = best->rate_mbps;
    plan->selected_rate_id = best->rate_id;
    plan->absolute_error_mbps = best_delta;
    plan->profile = best;
    plan->reason = "NEAREST_VERIFIED_PROFILE_SUGGESTION_ONLY";
    return GT_RATE_PLAN_OK;
}

int gt_rate_plan(uint32_t requested_rate_mbps, GtRatePlan *plan)
{
    return gt_rate_plan_exact(requested_rate_mbps, plan);
}

const char *gt_rate_plan_result_name(GtRatePlanResult result)
{
    switch (result) {
    case GT_RATE_PLAN_EXACT: return "EXACT";
    case GT_RATE_PLAN_NEAREST: return "NEAREST";
    default: return "UNSUPPORTED";
    }
}

const char *gt_rate_ref_source_name(GtRateRefSource ref_source)
{
    switch (ref_source) {
    case GT_RATE_REF_LOCAL_125: return "LOCAL_125";
    case GT_RATE_REF_LOCAL_15625: return "LOCAL_15625";
    case GT_RATE_REF_AD9528_OUT0: return "AD9528_OUT0";
    default: return "UNKNOWN_REF";
    }
}

const char *gt_rate_pll_source_name(GtRatePllSource pll_source)
{
    switch (pll_source) {
    case GT_RATE_PLL_CPLL:
        return "CPLL";
    case GT_RATE_PLL_QPLL:
        return "QPLL";
    default:
        return "UNKNOWN_PLL";
    }
}

void gt_rate_plan_print(const GtRatePlan *plan)
{
#ifndef GT_RATE_PLAN_HOST_TEST
    if (plan == NULL) {
        xil_printf("GT rate plan: null\r\n");
        return;
    }
    xil_printf("GT rate plan result=%s requested=%lu selected=%lu id=%lu lower=%lu upper=%lu delta=%lu reason=%s\r\n",
               gt_rate_plan_result_name(plan->result),
               (unsigned long)plan->requested_rate_mbps,
               (unsigned long)plan->selected_rate_mbps,
               (unsigned long)plan->selected_rate_id,
               (unsigned long)plan->nearest_lower_mbps,
               (unsigned long)plan->nearest_upper_mbps,
               (unsigned long)plan->absolute_error_mbps,
               plan->reason);
#else
    (void)plan;
#endif
}
