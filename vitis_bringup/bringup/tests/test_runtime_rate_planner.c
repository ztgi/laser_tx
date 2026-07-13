#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "laser_rate_decimal_parser.h"
#include "laser_runtime_rate_planner.h"

static RuntimeRatePlan plan_one(const char *text)
{
    RuntimeRatePlanRequest request;
    RuntimeRatePlan plan;
    RuntimeRatePlanDiagnostics diagnostics;
    uint64_t bps = 0U;
    assert(laser_rate_decimal_mbps_to_bps(text, &bps) == LASER_RATE_DECIMAL_OK);
    memset(&request, 0, sizeof(request));
    request.requested_line_rate_bps = bps;
    request.preferred_error_ppm = LASER_RUNTIME_RATE_DEFAULT_PREFERRED_PPM;
    request.maximum_error_ppm = LASER_RUNTIME_RATE_DEFAULT_MAXIMUM_PPM;
    request.allowed_pll_type = LASER_RUNTIME_PLL_BOTH;
    request.allowed_implementation_path = LASER_RUNTIME_PATH_AD9528_OUT0;
    assert(laser_runtime_rate_plan(&request, NULL, &plan, &diagnostics) == LASER_RUNTIME_PLAN_OK);
    assert(plan.plan_executable == 1U);
    assert(plan.ad9528_write_count == LASER_RUNTIME_AD9528_WRITE_COUNT);
    assert(plan.mmcm_write_count == RUNTIME_MMCM_WRITE_COUNT);
    assert(diagnostics.gt_tuples_considered == 240U);
    assert(diagnostics.executable_qualified != 0U);
    return plan;
}

static void test_parser(void)
{
    uint64_t value = 0U;
    assert(laser_rate_decimal_mbps_to_bps("3000", &value) == 0 && value == 3000000000ULL);
    assert(laser_rate_decimal_mbps_to_bps("2999.5", &value) == 0 && value == 2999500000ULL);
    assert(laser_rate_decimal_mbps_to_bps("3000.125", &value) == 0 && value == 3000125000ULL);
    assert(laser_rate_decimal_mbps_to_bps("", &value) != 0);
    assert(laser_rate_decimal_mbps_to_bps("-1", &value) != 0);
    assert(laser_rate_decimal_mbps_to_bps("1e3", &value) != 0);
    assert(laser_rate_decimal_mbps_to_bps("1.0000", &value) != 0);
    assert(laser_rate_decimal_mbps_to_bps("10x", &value) != 0);
    assert(laser_rate_decimal_mbps_to_bps("0", &value) != 0);
    assert(laser_rate_decimal_mbps_to_bps("18446744073709551615", &value) != 0);
    assert(laser_rate_decimal_mbps_to_bps("10312.501", &value) != 0);
}

static void test_golden_vectors(void)
{
    static const char *vectors[] = {
        "500", "625", "1000", "1250", "2000", "2500",
        "2999.5", "3000", "3125", "4000", "5000", "6250", "10000"
    };
    size_t i;
    for (i = 0U; i < sizeof(vectors) / sizeof(vectors[0]); ++i) {
        RuntimeRatePlan first = plan_one(vectors[i]);
        RuntimeRatePlan second = plan_one(vectors[i]);
        assert(memcmp(&first, &second, sizeof(first)) == 0);
        assert(first.rejected_reason != NULL);
        assert(strcmp(first.rejected_reason, "NONE") == 0);
    }
}

static void test_gap_is_not_executable(void)
{
    RuntimeRatePlanRequest request = {0};
    RuntimeRatePlan plan;
    RuntimeRatePlanDiagnostics diagnostics;
    request.requested_line_rate_bps = 9000000000ULL;
    request.preferred_error_ppm = 100U;
    request.maximum_error_ppm = 100U;
    request.allowed_pll_type = LASER_RUNTIME_PLL_BOTH;
    request.allowed_implementation_path = LASER_RUNTIME_PATH_AD9528_OUT0;
    assert(laser_runtime_rate_plan(&request, NULL, &plan, &diagnostics) == LASER_RUNTIME_PLAN_NO_SOLUTION);
    assert(plan.plan_executable == 0U);
}

int main(void)
{
    test_parser();
    test_golden_vectors();
    test_gap_is_not_executable();
    puts("PASS: runtime rate planner host tests");
    return 0;
}
