#include "gt_rate_plan.h"
#include "xil_printf.h"

#include <stddef.h>

static const GtRatePlan gt_rate_plan_table[] = {
    {
        500U, 500000U, 0,
        GT_RATE_REF_LOCAL_125, GT_RATE_PLL_CPLL,
        125000000U, 500000U, 15625000U, 15625000U, 7812500U,
        8U, 5U,
        1U, 4U, 4U,
        0U, 0U,
        12188U, 1U, 39U, 78U,
        7700000U, 7950000U,
        0U, 0U,
        "profile0_static_verified_dynamic_candidate"
    },
    {
        1000U, 1000000U, 0,
        GT_RATE_REF_LOCAL_125, GT_RATE_PLL_CPLL,
        125000000U, 1000000U, 31250000U, 31250000U, 15625000U,
        4U, 5U,
        1U, 4U, 4U,
        0U, 0U,
        20000U, 1U, 20U, 40U,
        15400000U, 15900000U,
        0U, 0U,
        "profile1_static_verified_dynamic_candidate"
    },
    {
        2000U, 2000000U, 0,
        GT_RATE_REF_LOCAL_125, GT_RATE_PLL_CPLL,
        125000000U, 2000000U, 62500000U, 62500000U, 31250000U,
        2U, 5U,
        1U, 4U, 4U,
        0U, 0U,
        10000U, 1U, 10U, 20U,
        30800000U, 31800000U,
        0U, 0U,
        "profile2_static_initial_bringup_dynamic_candidate"
    },
    {
        1250U, 1250000U, 0,
        GT_RATE_REF_LOCAL_125, GT_RATE_PLL_CPLL,
        125000000U, 1250000U, 39062500U, 39062500U, 19531250U,
        4U, 5U,
        1U, 4U, 5U,
        0U, 0U,
        16000U, 1U, 16U, 32U,
        19200000U, 19850000U,
        0U, 0U,
        "profile3_cpll_param_dynamic_candidate"
    },
    {
        2500U, 2500000U, 0,
        GT_RATE_REF_LOCAL_125, GT_RATE_PLL_CPLL,
        125000000U, 2500000U, 78125000U, 78125000U, 39062500U,
        2U, 5U,
        1U, 4U, 5U,
        0U, 0U,
        8000U, 1U, 8U, 16U,
        38400000U, 39750000U,
        0U, 0U,
        "profile4_cpll_param_dynamic_candidate"
    },
    {
        3125U, 3125000U, 0,
        GT_RATE_REF_LOCAL_125, GT_RATE_PLL_CPLL,
        125000000U, 3125000U, 97656250U, 97656250U, 48828125U,
        2U, 5U,
        1U, 5U, 5U,
        0U, 0U,
        8000U, 1U, 8U, 16U,
        48000000U, 49700000U,
        0U, 0U,
        "profile6_cpll_n1_n2_dynamic_candidate"
    },
    {
        5000U, 5000000U, 0,
        GT_RATE_REF_LOCAL_125, GT_RATE_PLL_CPLL,
        125000000U, 5000000U, 156250000U, 156250000U, 78125000U,
        1U, 5U,
        1U, 4U, 5U,
        0U, 0U,
        4000U, 1U, 4U, 8U,
        76800000U, 79500000U,
        0U, 0U,
        "profile5_cpll_param_dynamic_candidate"
    },
    {
        6250U, 6250000U, 0,
        GT_RATE_REF_LOCAL_125, GT_RATE_PLL_CPLL,
        125000000U, 6250000U, 195312500U, 195312500U, 97656250U,
        1U, 5U,
        1U, 5U, 5U,
        0U, 0U,
        4000U, 1U, 4U, 8U,
        96000000U, 99500000U,
        0U, 0U,
        "profile7_cpll_n1_n2_dynamic_candidate"
    }
};

const char *gt_rate_ref_source_name(GtRateRefSource ref_source)
{
    switch (ref_source) {
    case GT_RATE_REF_LOCAL_125:
        return "LOCAL_125";
    case GT_RATE_REF_LOCAL_15625:
        return "LOCAL_15625";
    case GT_RATE_REF_AD9528_OUT0:
        return "AD9528_OUT0";
    default:
        return "UNKNOWN_REF";
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

int gt_rate_plan(uint32_t target_mbps, GtRatePlan *plan)
{
    size_t i;

    if (plan == NULL) {
        return GT_RATE_PLAN_BAD_ARG;
    }

    for (i = 0U; i < sizeof(gt_rate_plan_table) / sizeof(gt_rate_plan_table[0]); ++i) {
        if (gt_rate_plan_table[i].target_mbps == target_mbps) {
            *plan = gt_rate_plan_table[i];
            return GT_RATE_PLAN_OK;
        }
    }

    return GT_RATE_PLAN_UNSUPPORTED;
}

void gt_rate_plan_print(const GtRatePlan *plan)
{
    if (plan == NULL) {
        xil_printf("GT rate plan: null\r\n");
        return;
    }

    xil_printf("GT rate plan target=%lu actual_kbps=%lu error_kbps=%ld\r\n",
               (unsigned long)plan->target_mbps,
               (unsigned long)plan->actual_kbps,
               (long)plan->error_kbps);
    xil_printf("  ref=%s refclk_hz=%lu pll=%s line_rate_kbps=%lu txoutclk_hz=%lu txusrclk_hz=%lu txusrclk2_hz=%lu\r\n",
               gt_rate_ref_source_name(plan->ref_source),
               (unsigned long)plan->refclk_hz,
               gt_rate_pll_source_name(plan->pll_source),
               (unsigned long)plan->line_rate_kbps,
               (unsigned long)plan->txoutclk_hz,
               (unsigned long)plan->txusrclk_hz,
               (unsigned long)plan->txusrclk2_hz);
    xil_printf("  txout_div=%lu tx_clk25_div=%lu cpll_m=%lu cpll_n1=%lu cpll_n2=%lu qpll_m=%lu qpll_n=%lu\r\n",
               (unsigned long)plan->txout_div,
               (unsigned long)plan->tx_clk25_div,
               (unsigned long)plan->cpll_m,
               (unsigned long)plan->cpll_n1,
               (unsigned long)plan->cpll_n2,
               (unsigned long)plan->qpll_m,
               (unsigned long)plan->qpll_n);
    xil_printf("  requires_ad9528=%lu ad9528_out_hz=%lu note=%s\r\n",
               (unsigned long)plan->requires_ad9528,
               (unsigned long)plan->ad9528_out_hz,
               plan->note);
    xil_printf("  mmcm_mult_x1000=%lu divclk=%lu clkout1_div=%lu clkout0_div=%lu txusrclk2_window=[%lu,%lu]\r\n",
               (unsigned long)plan->mmcm_clkfbout_mult_x1000,
               (unsigned long)plan->mmcm_divclk_divide,
               (unsigned long)plan->mmcm_clkout1_divide,
               (unsigned long)plan->mmcm_clkout0_divide,
               (unsigned long)plan->expected_txusrclk2_freq_min,
               (unsigned long)plan->expected_txusrclk2_freq_max);
}
