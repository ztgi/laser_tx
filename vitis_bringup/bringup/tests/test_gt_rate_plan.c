#include <assert.h>
#include <stdio.h>

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
                               uint32_t upper)
{
    GtRatePlan plan;
    assert(gt_rate_plan_exact(rate_mbps, &plan) == GT_RATE_PLAN_STATUS_UNSUPPORTED);
    assert(plan.result == GT_RATE_PLAN_UNSUPPORTED);
    assert(plan.selected_rate_id == 0U);
    assert(plan.profile == NULL);
    assert(plan.nearest_lower_mbps == lower);
    assert(plan.nearest_upper_mbps == upper);
}

static void expect_nearest(uint32_t requested, uint32_t selected)
{
    GtRatePlan plan;
    assert(gt_rate_plan_nearest(requested, &plan) == GT_RATE_PLAN_OK);
    assert(plan.result == GT_RATE_PLAN_NEAREST || plan.result == GT_RATE_PLAN_EXACT);
    assert(plan.selected_rate_mbps == selected);
    assert(plan.profile != NULL);
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

    expect_unsupported(0U, 0U, 500U);
    expect_unsupported(499U, 0U, 500U);
    expect_unsupported(750U, 500U, 1000U);
    expect_unsupported(1500U, 1250U, 2000U);
    expect_unsupported(3000U, 2500U, 3125U);
    expect_unsupported(4000U, 3125U, 5000U);
    expect_unsupported(7000U, 6250U, 10000U);
    expect_unsupported(9999U, 6250U, 10000U);
    expect_unsupported(10001U, 10000U, 0U);

    expect_nearest(3000U, 3125U);
    expect_nearest(2800U, 2500U);
    expect_nearest(7500U, 6250U);
    expect_nearest(9000U, 10000U);
    expect_nearest(750U, 500U);

    assert(gt_rate_profile_count() == 9U);
    assert(gt_rate_profile_rate_mbps_from_id(9U) == 10000U);
    assert(gt_rate_profile_rate_mbps_from_id(10U) == 0U);
    puts("PASS: discrete rate planner tests");
    return 0;
}
