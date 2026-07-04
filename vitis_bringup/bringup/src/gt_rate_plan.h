#ifndef GT_RATE_PLAN_H
#define GT_RATE_PLAN_H

#include <stdint.h>

#define GT_RATE_PLAN_OK           0
#define GT_RATE_PLAN_UNSUPPORTED -1
#define GT_RATE_PLAN_BAD_ARG     -2

typedef enum {
    GT_RATE_REF_LOCAL_125 = 0,
    GT_RATE_REF_LOCAL_15625 = 1,
    GT_RATE_REF_AD9528_OUT0 = 2
} GtRateRefSource;

typedef enum {
    GT_RATE_PLL_CPLL = 0,
    GT_RATE_PLL_QPLL = 1
} GtRatePllSource;

typedef struct {
    uint32_t target_mbps;
    uint32_t actual_kbps;
    int32_t error_kbps;

    GtRateRefSource ref_source;
    GtRatePllSource pll_source;

    uint32_t refclk_hz;
    uint32_t line_rate_kbps;
    uint32_t txoutclk_hz;
    uint32_t txusrclk_hz;
    uint32_t txusrclk2_hz;

    uint32_t txout_div;
    uint32_t tx_clk25_div;

    uint32_t cpll_m;
    uint32_t cpll_n1;
    uint32_t cpll_n2;

    uint32_t qpll_m;
    uint32_t qpll_n;

    uint32_t mmcm_clkfbout_mult_x1000;
    uint32_t mmcm_divclk_divide;
    uint32_t mmcm_clkout1_divide;
    uint32_t mmcm_clkout0_divide;

    uint32_t expected_txusrclk2_freq_min;
    uint32_t expected_txusrclk2_freq_max;

    uint32_t requires_ad9528;
    uint32_t ad9528_out_hz;

    const char *note;
} GtRatePlan;

int gt_rate_plan(uint32_t target_mbps, GtRatePlan *plan);
void gt_rate_plan_print(const GtRatePlan *plan);
const char *gt_rate_ref_source_name(GtRateRefSource ref_source);
const char *gt_rate_pll_source_name(GtRatePllSource pll_source);

#endif
