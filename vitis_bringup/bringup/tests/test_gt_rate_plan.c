#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "gt_rate_plan.h"

static void expect_exact(uint32_t rate_mbps, uint32_t rate_id,
                         GtRatePllSource pll_source)
{
    GtRatePlan plan;
    assert(gt_rate_plan_exact(rate_mbps, &plan) == GT_RATE_PLAN_OK);
    assert(plan.result == GT_RATE_PLAN_EXACT);
    assert(plan.selected_rate_mbps == rate_mbps);
    assert(plan.selected_rate_id == rate_id);
    assert(plan.profile != NULL);
    assert(plan.profile->pll_source == pll_source);
    assert(plan.profile->board_verified != 0U);
}

static void expect_unsupported(uint32_t rate_mbps, uint32_t lower,
                               uint32_t upper, const char *reason)
{
    GtRatePlan plan;
    assert(gt_rate_plan_exact(rate_mbps, &plan) == GT_RATE_PLAN_STATUS_UNSUPPORTED);
    assert(plan.result == GT_RATE_PLAN_UNSUPPORTED);
    assert(plan.selected_rate_id == 0U);
    assert(plan.profile == NULL);
    assert(plan.nearest_lower_mbps == lower);
    assert(plan.nearest_upper_mbps == upper);
    assert(strcmp(plan.reason, reason) == 0);
}

static void expect_nearest(uint32_t requested, uint32_t selected)
{
    GtRatePlan plan;
    assert(gt_rate_plan_nearest(requested, &plan) == GT_RATE_PLAN_OK);
    assert(plan.result == GT_RATE_PLAN_NEAREST || plan.result == GT_RATE_PLAN_EXACT);
    assert(plan.selected_rate_mbps == selected);
    assert(plan.profile != NULL);
}

static void expect_candidate(uint32_t rate_mbps, uint32_t rate_id,
                             uint32_t expected_txusrclk2_hz)
{
    GtRatePlan plan;

    assert(gt_rate_plan_exact(rate_mbps, &plan) == GT_RATE_PLAN_STATUS_UNSUPPORTED);
    assert(gt_rate_plan_lookup(rate_mbps, &plan) == GT_RATE_PLAN_OK);
    assert(plan.result == GT_RATE_PLAN_EXACT);
    assert(plan.selected_rate_id == rate_id);
    assert(plan.profile != NULL);
    assert(plan.profile->board_verified == 0U);
    assert(plan.profile->expected_txusrclk2_hz == expected_txusrclk2_hz);
    assert(strcmp(plan.reason, "CANDIDATE_PROFILE_BOARD_VALIDATION_REQUIRED") == 0);
}

int main(void)
{
    expect_exact(500U, 1U, GT_RATE_PLL_CPLL);
    expect_exact(1000U, 2U, GT_RATE_PLL_CPLL);
    expect_exact(1250U, 4U, GT_RATE_PLL_CPLL);
    expect_exact(2000U, 3U, GT_RATE_PLL_CPLL);
    expect_exact(2500U, 5U, GT_RATE_PLL_CPLL);
    expect_exact(3125U, 7U, GT_RATE_PLL_CPLL);
    expect_exact(5000U, 6U, GT_RATE_PLL_CPLL);
    expect_exact(6250U, 8U, GT_RATE_PLL_CPLL);
    expect_exact(10000U, 9U, GT_RATE_PLL_QPLL);
    expect_candidate(625U, 10U, 9765625U);
    expect_candidate(4000U, 11U, 62500000U);

    expect_unsupported(0U, 0U, 500U, "NO_VERIFIED_EXACT_PROFILE");
    expect_unsupported(499U, 0U, 500U, "NO_VERIFIED_EXACT_PROFILE");
    expect_unsupported(750U, 625U, 1000U, "NO_VERIFIED_EXACT_PROFILE");
    expect_unsupported(1500U, 1250U, 2000U, "NO_VERIFIED_EXACT_PROFILE");
    expect_unsupported(3000U, 2500U, 3125U, "NO_LEGAL_VERIFIED_125M_CPLL_PROFILE");
    expect_unsupported(3999U, 3125U, 4000U, "NO_VERIFIED_EXACT_PROFILE");
    expect_unsupported(7000U, 6250U, 10000U, "NO_VERIFIED_EXACT_PROFILE");
    expect_unsupported(9999U, 6250U, 10000U, "NO_VERIFIED_EXACT_PROFILE");
    expect_unsupported(10001U, 10000U, 0U, "NO_VERIFIED_EXACT_PROFILE");

    expect_nearest(3000U, 3125U);
    expect_nearest(2800U, 2500U);
    expect_nearest(7500U, 6250U);
    expect_nearest(9000U, 10000U);
    expect_nearest(750U, 500U);

    assert(gt_rate_profile_count() == 11U);
    assert(gt_rate_profile_rate_mbps_from_id(9U) == 10000U);
    assert(gt_rate_profile_rate_mbps_from_id(10U) == 625U);
    assert(gt_rate_profile_rate_mbps_from_id(11U) == 4000U);
    assert(strcmp(gt_rate_pll_source_name((GtRatePllSource)99), "UNKNOWN_PLL") == 0);
    puts("PASS: discrete rate planner tests");
    return 0;
}
