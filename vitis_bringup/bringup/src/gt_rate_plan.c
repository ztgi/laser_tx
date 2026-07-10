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
#endif

#define GT_RATE_PROFILE_COUNT 9U

/* Sorted by rate_mbps. Values are copied from the active RTL profile accessors:
 * FREQ_*_COUNT is a roughly 1 ms counter window, not hertz. */
static const GtRateProfile gt_rate_profile_table[GT_RATE_PROFILE_COUNT] = {
    {500U,   LASER_RATE_ID_500M,   GT_RATE_PLL_CPLL, 125000000U,   7812500U,   7700U,   7950U, 0x1002U, 8U, 1U,  0U, 0U, 0U, 1U},
    {1000U,  LASER_RATE_ID_1000M,  GT_RATE_PLL_CPLL, 125000000U,  15625000U,  15400U,  15900U, 0x1002U, 4U, 2U,  0U, 0U, 0U, 1U},
    {1250U,  LASER_RATE_ID_1250M,  GT_RATE_PLL_CPLL, 125000000U,  19531250U,  19200U,  19850U, 0x1003U, 4U, 4U,  0U, 0U, 0U, 1U},
    {2000U,  LASER_RATE_ID_2000M,  GT_RATE_PLL_CPLL, 125000000U,  31250000U,  30800U,  31800U, 0x1002U, 2U, 3U,  0U, 0U, 0U, 1U},
    {2500U,  LASER_RATE_ID_2500M,  GT_RATE_PLL_CPLL, 125000000U,  39062500U,  38400U,  39750U, 0x1003U, 2U, 5U,  0U, 0U, 0U, 1U},
    {3125U,  LASER_RATE_ID_3125M,  GT_RATE_PLL_CPLL, 125000000U,  48828125U,  48000U,  49700U, 0x1083U, 2U, 7U,  0U, 0U, 0U, 1U},
    {5000U,  LASER_RATE_ID_5000M,  GT_RATE_PLL_CPLL, 125000000U,  78125000U,  76800U,  79500U, 0x1003U, 1U, 6U,  0U, 0U, 0U, 1U},
    {6250U,  LASER_RATE_ID_6250M,  GT_RATE_PLL_CPLL, 125000000U,  97656250U,  96000U,  99500U, 0x1083U, 1U, 8U,  0U, 0U, 0U, 1U},
    {10000U, LASER_RATE_ID_10000M, GT_RATE_PLL_QPLL, 125000000U, 156250000U, 153000U, 159500U, 0x0000U, 1U, 9U, 80U, 1U, 0U, 1U}
};

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
    if (requested_rate_mbps == 3000U) {
        plan->reason = "NO_LEGAL_VERIFIED_125M_CPLL_PROFILE";
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
    return (pll_source == GT_RATE_PLL_QPLL) ? "QPLL" : "CPLL";
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
